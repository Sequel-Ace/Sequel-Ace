//
//  SPAppController+MCP.m
//  Sequel Ace
//
//  Created for Sequel Ace by contributors.
//  See https://github.com/Sequel-Ace/Sequel-Ace/issues/2314
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.

#import "SPAppController+MCP.h"
#import "SPDatabaseDocument.h"
#import "SPConstants.h"

#import <SPMySQL/SPMySQL.h>
#import <objc/runtime.h>

#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

#import "sequel-ace-Swift.h"

// Stable id attached to each open document for its lifetime, so the agent can
// target a specific tab. (processID is not reliably populated.)
static const void *kMCPDocIDKey = &kMCPDocIDKey;

static NSString *mcpDocumentID(SPDatabaseDocument *doc)
{
    if (!doc) return @"";
    NSString *docID = objc_getAssociatedObject(doc, kMCPDocIDKey);
    if (!docID) {
        docID = [[NSUUID UUID] UUIDString];
        objc_setAssociatedObject(doc, kMCPDocIDKey, docID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return docID;
}

static const NSInteger  kMCPDefaultPort   = 8765;
static const NSUInteger kMCPMaxResultRows = 10000;   // Safety cap for run_query.

// Dispatch queue used for all MCP database operations (serial, background).
static dispatch_queue_t sMCPDBQueue;

// Last MCP configuration we acted on, so we ignore the frequent
// NSUserDefaultsDidChangeNotification callbacks that do not touch our keys.
static BOOL     sMCPDesiredKnown   = NO;
static BOOL     sMCPDesiredEnabled = NO;
static uint16_t sMCPDesiredPort    = 0;

static uint16_t mcpClampedPort(NSUserDefaults *prefs)
{
    NSInteger port = [prefs integerForKey:SPMCPServerPort];
    if (port < 1024 || port > 65535) port = kMCPDefaultPort;
    return (uint16_t)port;
}

// Escape an identifier (database/table/routine name) for use inside backticks.
static NSString *mcpQuoteIdentifier(NSString *name)
{
    return [name stringByReplacingOccurrencesOfString:@"`" withString:@"``"];
}

// MySQL can return text columns as NSData; decode to a string so values are
// usable directly (not just at JSON-serialisation time). Non-data values pass through.
static id mcpDecode(id value)
{
    if ([value isKindOfClass:[NSData class]]) {
        NSString *s = [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
        return s ?: [value description];
    }
    return value;
}

@implementation SPAppController (MCP)

#pragma mark - Lifecycle

- (void)setupMCPServer
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sMCPDBQueue = dispatch_queue_create("com.sequel-ace.mcp.db", DISPATCH_QUEUE_SERIAL);
    });

    SPMCPServer.shared.dataSource = self;

    // Observe preference changes to start/stop the server dynamically.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(mcpDefaultsChanged:)
                                                 name:NSUserDefaultsDidChangeNotification
                                               object:nil];

    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    sMCPDesiredKnown   = YES;
    sMCPDesiredEnabled = [prefs boolForKey:SPMCPServerEnabled];
    sMCPDesiredPort    = mcpClampedPort(prefs);
    if (sMCPDesiredEnabled) {
        [self startMCPServerWithPrefs:prefs];
    }
}

- (void)mcpDefaultsChanged:(NSNotification *)notification
{
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    BOOL shouldRun       = [prefs boolForKey:SPMCPServerEnabled];
    uint16_t desiredPort = mcpClampedPort(prefs);

    // NSUserDefaultsDidChangeNotification fires for any pref change in the app;
    // only react when the MCP enable flag or port actually changed, otherwise a
    // failed start would be retried (and re-alert) on every unrelated change.
    if (sMCPDesiredKnown && shouldRun == sMCPDesiredEnabled && desiredPort == sMCPDesiredPort) {
        return;
    }
    sMCPDesiredKnown   = YES;
    sMCPDesiredEnabled = shouldRun;
    sMCPDesiredPort    = desiredPort;

    if (shouldRun) {
        // startWithPort: stops any existing listener first, so this covers both
        // a fresh enable and a port change.
        [self startMCPServerWithPrefs:prefs];
    } else if (SPMCPServer.shared.isRunning) {
        [SPMCPServer.shared stop];
        SPLog(@"MCP server stopped.");
    }
}

- (void)startMCPServerWithPrefs:(NSUserDefaults *)prefs
{
    uint16_t port = mcpClampedPort(prefs);

    [SPMCPServer.shared startWithPort:port completion:^(BOOL success, NSString *errorMsg) {
        if (success) {
            SPLog(@"MCP server started on port %u", port);
        } else {
            SPLog(@"MCP server failed to start: %@", errorMsg ?: @"unknown error");
            NSAlert *alert = [[NSAlert alloc] init];
            alert.alertStyle      = NSAlertStyleWarning;
            alert.messageText     = NSLocalizedString(@"MCP Server Error", @"MCP start error title");
            alert.informativeText = [NSString stringWithFormat:
                NSLocalizedString(@"The MCP server could not start on port %ld: %@\n\n"
                                  @"You can change the port in Preferences > MCP Server.",
                                  @"MCP start error message"),
                (long)port, errorMsg ?: @"unknown error"];
            [alert runModal];
        }
    }];
}

#pragma mark - Connection resolution

// Resolve a connection id (nil/empty -> front document) to its live connection.
// Returns @{@"conn", @"id", @"database", @"host"} or nil if not connected.
// Reads document state on the main thread.
- (NSDictionary *)mcpResolveConnection:(NSString *)connID
{
    __block NSDictionary *info = nil;
    void (^resolve)(void) = ^{
        NSArray *wcs = self.tabManager.windowControllers;
        SPDatabaseDocument *doc = nil;
        if (connID.length) {
            for (SPWindowController *wc in wcs) {
                if ([mcpDocumentID(wc.databaseDocument) isEqualToString:connID]) {
                    doc = wc.databaseDocument;
                    break;
                }
            }
        } else {
            doc = [self frontDocument];
            // frontDocument is nil when the app is not frontmost (it relies on the
            // active window), so fall back to the first connected tab.
            if (!(doc && !doc.isProcessing && [doc getConnection].isConnected)) {
                doc = nil;
                for (SPWindowController *wc in wcs) {
                    SPDatabaseDocument *d = wc.databaseDocument;
                    if (!d.isProcessing && [d getConnection].isConnected) { doc = d; break; }
                }
            }
        }
        if (doc && !doc.isProcessing) {
            SPMySQLConnection *c = [doc getConnection];
            if (c && c.isConnected) {
                info = @{@"conn": c,
                         @"id":   mcpDocumentID(doc),
                         @"database": (doc.database ?: @""),
                         @"host": (doc.host ?: @"")};
            }
        }
    };
    if ([NSThread isMainThread]) resolve(); else dispatch_sync(dispatch_get_main_queue(), resolve);
    return info;
}

- (NSDictionary *)mcpNoConnectionError
{
    return @{@"error": @"No matching database connection. Connect in Sequel Ace, or pass a valid connection id from list_connections."};
}

#pragma mark - SPMCPDataSource: connections

- (NSArray<NSDictionary *> *)mcpListConnections
{
    __block NSMutableArray *result = [NSMutableArray array];
    void (^collect)(void) = ^{
        SPDatabaseDocument *front = [self frontDocument];
        for (SPWindowController *wc in self.tabManager.windowControllers) {
            SPDatabaseDocument *doc = wc.databaseDocument;
            SPMySQLConnection *c = doc.isProcessing ? nil : [doc getConnection];
            if (!c || !c.isConnected) continue;
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[@"id"]       = mcpDocumentID(doc);
            info[@"name"]     = doc.displayName ?: (doc.host ?: @"");
            if (doc.host.length)     info[@"host"]     = doc.host;
            if (doc.database.length) info[@"database"] = doc.database;
            info[@"active"]   = @(front != nil && doc == front);
            [result addObject:[info copy]];
        }
    };
    if ([NSThread isMainThread]) collect(); else dispatch_sync(dispatch_get_main_queue(), collect);
    return [result copy];
}

#pragma mark - SPMCPDataSource: schema

- (NSDictionary *)mcpListDatabasesOnConnection:(NSString *)connID
{
    NSDictionary *ci = [self mcpResolveConnection:connID];
    if (!ci) return [self mcpNoConnectionError];
    SPMySQLConnection *conn = ci[@"conn"];

    __block NSDictionary *result;
    dispatch_sync(sMCPDBQueue, ^{
        SPMySQLResult *res = [conn queryString:@"SHOW DATABASES"];
        if ([conn queryErrored]) { result = @{@"error": [conn lastErrorMessage] ?: @"Query error"}; return; }
        [res setDefaultRowReturnType:SPMySQLResultRowAsArray];
        NSMutableArray *dbs = [NSMutableArray array];
        for (NSArray *row in res) {
            if (row.firstObject && row.firstObject != [NSNull null]) [dbs addObject:mcpDecode(row.firstObject)];
        }
        result = @{@"databases": [dbs copy], @"connection": ci[@"id"]};
    });
    return result;
}

- (NSDictionary *)mcpListTablesInDatabase:(NSString *)database connection:(NSString *)connID
{
    if (!database.length) return @{@"error": @"database argument is required"};
    NSDictionary *ci = [self mcpResolveConnection:connID];
    if (!ci) return [self mcpNoConnectionError];
    SPMySQLConnection *conn = ci[@"conn"];

    __block NSDictionary *result;
    dispatch_sync(sMCPDBQueue, ^{
        NSString *sql = [NSString stringWithFormat:@"SHOW FULL TABLES IN `%@`", mcpQuoteIdentifier(database)];
        SPMySQLResult *res = [conn queryString:sql];
        if ([conn queryErrored]) { result = @{@"error": [conn lastErrorMessage] ?: @"Query error"}; return; }
        [res setDefaultRowReturnType:SPMySQLResultRowAsArray];
        NSMutableArray *tables = [NSMutableArray array];
        for (NSArray *row in res) {
            if (row.firstObject && row.firstObject != [NSNull null]) {
                NSMutableDictionary *entry = [NSMutableDictionary dictionary];
                entry[@"name"] = mcpDecode(row.firstObject);
                if (row.count > 1 && row[1] != [NSNull null]) entry[@"type"] = mcpDecode(row[1]);
                [tables addObject:[entry copy]];
            }
        }
        result = @{@"tables": [tables copy], @"connection": ci[@"id"]};
    });
    return result;
}

- (NSDictionary *)mcpDescribeTable:(NSString *)table inDatabase:(NSString *)database connection:(NSString *)connID
{
    if (!table.length || !database.length) return @{@"error": @"Both database and table arguments are required"};
    NSDictionary *ci = [self mcpResolveConnection:connID];
    if (!ci) return [self mcpNoConnectionError];
    SPMySQLConnection *conn = ci[@"conn"];

    __block NSDictionary *result;
    dispatch_sync(sMCPDBQueue, ^{
        NSString *qualified = [NSString stringWithFormat:@"`%@`.`%@`",
                               mcpQuoteIdentifier(database), mcpQuoteIdentifier(table)];

        NSMutableArray *columns = [NSMutableArray array];
        SPMySQLResult *colRes = [conn queryString:[NSString stringWithFormat:@"SHOW FULL COLUMNS FROM %@", qualified]];
        if ([conn queryErrored]) { result = @{@"error": [conn lastErrorMessage] ?: @"Could not describe table"}; return; }
        for (NSDictionary *row in colRes) {
            NSMutableDictionary *col = [NSMutableDictionary dictionary];
            for (NSString *k in @[@"Field", @"Type", @"Null", @"Key", @"Default", @"Extra", @"Comment"]) {
                id v = row[k];
                if (v && v != [NSNull null]) col[k] = mcpDecode(v);
            }
            [columns addObject:[col copy]];
        }

        NSMutableArray *indexes = [NSMutableArray array];
        SPMySQLResult *idxRes = [conn queryString:[NSString stringWithFormat:@"SHOW INDEX FROM %@", qualified]];
        if (![conn queryErrored]) {
            for (NSDictionary *row in idxRes) {
                NSMutableDictionary *idx = [NSMutableDictionary dictionary];
                for (NSString *k in @[@"Key_name", @"Column_name", @"Non_unique", @"Index_type"]) {
                    id v = row[k];
                    if (v && v != [NSNull null]) idx[k] = mcpDecode(v);
                }
                [indexes addObject:[idx copy]];
            }
        }

        NSMutableArray *foreignKeys = [NSMutableArray array];
        NSString *fkSQL = [NSString stringWithFormat:
            @"SELECT COLUMN_NAME, CONSTRAINT_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME "
             "FROM information_schema.KEY_COLUMN_USAGE "
             "WHERE TABLE_SCHEMA = %@ AND TABLE_NAME = %@ AND REFERENCED_TABLE_NAME IS NOT NULL",
            [conn escapeAndQuoteString:database], [conn escapeAndQuoteString:table]];
        SPMySQLResult *fkRes = [conn queryString:fkSQL];
        if (![conn queryErrored]) {
            for (NSDictionary *row in fkRes) {
                NSMutableDictionary *fk = [NSMutableDictionary dictionary];
                for (NSString *k in @[@"COLUMN_NAME", @"CONSTRAINT_NAME", @"REFERENCED_TABLE_NAME", @"REFERENCED_COLUMN_NAME"]) {
                    id v = row[k];
                    if (v && v != [NSNull null]) fk[k] = mcpDecode(v);
                }
                [foreignKeys addObject:[fk copy]];
            }
        }

        result = @{@"columns": [columns copy], @"indexes": [indexes copy],
                   @"foreignKeys": [foreignKeys copy], @"connection": ci[@"id"]};
    });
    return result;
}

- (NSDictionary *)mcpTableDDL:(NSString *)table inDatabase:(NSString *)database connection:(NSString *)connID
{
    if (!table.length || !database.length) return @{@"error": @"Both database and table arguments are required"};
    NSDictionary *ci = [self mcpResolveConnection:connID];
    if (!ci) return [self mcpNoConnectionError];
    SPMySQLConnection *conn = ci[@"conn"];

    __block NSDictionary *result;
    dispatch_sync(sMCPDBQueue, ^{
        NSString *qualified = [NSString stringWithFormat:@"`%@`.`%@`",
                               mcpQuoteIdentifier(database), mcpQuoteIdentifier(table)];
        SPMySQLResult *res = [conn queryString:[NSString stringWithFormat:@"SHOW CREATE TABLE %@", qualified]];
        if ([conn queryErrored] || !res) { result = @{@"error": [conn lastErrorMessage] ?: @"Could not read table DDL"}; return; }
        NSString *ddl = nil;
        for (NSDictionary *row in res) {
            ddl = row[@"Create Table"] ?: row[@"Create View"];
            break;
        }
        result = @{@"ddl": ddl ?: @"", @"connection": ci[@"id"]};
    });
    return result;
}

// type: "view" | "procedure" | "function" | "trigger" | "event"
- (NSDictionary *)mcpListRoutinesOfType:(NSString *)type inDatabase:(NSString *)database connection:(NSString *)connID
{
    if (!database.length) return @{@"error": @"database argument is required"};
    NSDictionary *ci = [self mcpResolveConnection:connID];
    if (!ci) return [self mcpNoConnectionError];
    SPMySQLConnection *conn = ci[@"conn"];
    NSString *t = type.lowercaseString;

    __block NSDictionary *result;
    dispatch_sync(sMCPDBQueue, ^{
        NSString *db = [conn escapeAndQuoteString:database];
        NSString *sql = nil;
        if ([t isEqualToString:@"view"]) {
            sql = [NSString stringWithFormat:@"SELECT TABLE_NAME AS name FROM information_schema.VIEWS WHERE TABLE_SCHEMA = %@ ORDER BY TABLE_NAME", db];
        } else if ([t isEqualToString:@"procedure"] || [t isEqualToString:@"function"]) {
            sql = [NSString stringWithFormat:@"SELECT ROUTINE_NAME AS name FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = %@ AND ROUTINE_TYPE = '%@' ORDER BY ROUTINE_NAME",
                   db, [t isEqualToString:@"procedure"] ? @"PROCEDURE" : @"FUNCTION"];
        } else if ([t isEqualToString:@"trigger"]) {
            sql = [NSString stringWithFormat:@"SELECT TRIGGER_NAME AS name, EVENT_OBJECT_TABLE AS table_name, EVENT_MANIPULATION AS event, ACTION_TIMING AS timing FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = %@ ORDER BY TRIGGER_NAME", db];
        } else if ([t isEqualToString:@"event"]) {
            sql = [NSString stringWithFormat:@"SELECT EVENT_NAME AS name, STATUS AS status FROM information_schema.EVENTS WHERE EVENT_SCHEMA = %@ ORDER BY EVENT_NAME", db];
        } else {
            result = @{@"error": @"type must be one of: view, procedure, function, trigger, event"};
            return;
        }
        SPMySQLResult *res = [conn queryString:sql];
        if ([conn queryErrored]) { result = @{@"error": [conn lastErrorMessage] ?: @"Query error"}; return; }
        NSMutableArray *items = [NSMutableArray array];
        for (NSDictionary *row in res) {
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            for (NSString *k in row) {
                id v = row[k];
                if (v && v != [NSNull null]) entry[k] = mcpDecode(v);
            }
            [items addObject:[entry copy]];
        }
        result = @{@"items": [items copy], @"connection": ci[@"id"]};
    });
    return result;
}

- (NSDictionary *)mcpRoutineDefinitionOfType:(NSString *)type name:(NSString *)name inDatabase:(NSString *)database connection:(NSString *)connID
{
    if (!type.length || !name.length || !database.length) return @{@"error": @"type, name and database arguments are required"};
    NSDictionary *ci = [self mcpResolveConnection:connID];
    if (!ci) return [self mcpNoConnectionError];
    SPMySQLConnection *conn = ci[@"conn"];
    NSString *t = type.uppercaseString;
    NSArray *allowed = @[@"PROCEDURE", @"FUNCTION", @"TRIGGER", @"VIEW", @"EVENT"];
    if (![allowed containsObject:t]) return @{@"error": @"type must be one of: procedure, function, trigger, view, event"};

    __block NSDictionary *result;
    dispatch_sync(sMCPDBQueue, ^{
        // SHOW CREATE TRIGGER does not accept a schema-qualified name and uses the
        // connection's current database. Rather than mutate the shared connection's
        // default DB, reconstruct the trigger from information_schema (schema-scoped).
        if ([t isEqualToString:@"TRIGGER"]) {
            NSString *sql = [NSString stringWithFormat:
                @"SELECT ACTION_TIMING, EVENT_MANIPULATION, EVENT_OBJECT_TABLE, ACTION_STATEMENT "
                 "FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = %@ AND TRIGGER_NAME = %@",
                [conn escapeAndQuoteString:database], [conn escapeAndQuoteString:name]];
            SPMySQLResult *res = [conn queryString:sql];
            if ([conn queryErrored] || !res) { result = @{@"error": [conn lastErrorMessage] ?: @"Could not read definition"}; return; }
            NSDictionary *row = nil;
            for (NSDictionary *r in res) { row = r; break; }
            if (!row) { result = @{@"error": @"Trigger not found"}; return; }
            NSString *def = [NSString stringWithFormat:@"CREATE TRIGGER `%@` %@ %@ ON `%@` FOR EACH ROW %@",
                             mcpQuoteIdentifier(name),
                             mcpDecode(row[@"ACTION_TIMING"]), mcpDecode(row[@"EVENT_MANIPULATION"]),
                             mcpQuoteIdentifier([mcpDecode(row[@"EVENT_OBJECT_TABLE"]) description]),
                             mcpDecode(row[@"ACTION_STATEMENT"])];
            result = @{@"definition": def, @"connection": ci[@"id"]};
            return;
        }

        NSString *qualified = [NSString stringWithFormat:@"`%@`.`%@`",
                               mcpQuoteIdentifier(database), mcpQuoteIdentifier(name)];
        SPMySQLResult *res = [conn queryString:[NSString stringWithFormat:@"SHOW CREATE %@ %@", t, qualified]];
        if ([conn queryErrored] || !res) { result = @{@"error": [conn lastErrorMessage] ?: @"Could not read definition"}; return; }
        NSString *def = nil;
        for (NSDictionary *row in res) {
            for (NSString *k in row) {
                if ([k hasPrefix:@"Create "] || [k isEqualToString:@"SQL Original Statement"]) {
                    id v = row[k];
                    if (v && v != [NSNull null]) { def = [v description]; break; }
                }
            }
            break;
        }
        result = @{@"definition": def ?: @"", @"connection": ci[@"id"]};
    });
    return result;
}

#pragma mark - SPMCPDataSource: queries

- (NSDictionary *)mcpRunQuery:(NSString *)sql params:(NSArray *)params limit:(NSInteger)limit offset:(NSInteger)offset connection:(NSString *)connID
{
    if (!sql.length) return @{@"error": @"sql argument is required"};
    NSDictionary *ci = [self mcpResolveConnection:connID];
    if (!ci) return [self mcpNoConnectionError];
    SPMySQLConnection *conn = ci[@"conn"];

    // Bind ? placeholders to escaped literals (injection-safe).
    NSString *bound = sql;
    if (params.count) {
        NSString *err = nil;
        bound = [self mcpBindParams:params intoSQL:sql connection:conn error:&err];
        if (!bound) return @{@"error": err ?: @"Parameter binding failed"};
    }

    // Paginate read queries by wrapping them in a derived table.
    NSString *finalSQL = bound;
    if (limit > 0) {
        NSString *t = [bound stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        while ([t hasSuffix:@";"]) t = [[t substringToIndex:t.length - 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *up = t.uppercaseString;
        // Only wrap plain SELECTs. A CTE (WITH ... SELECT) is invalid inside a
        // derived table, so leave those unpaginated (the caller can add LIMIT).
        if ([up hasPrefix:@"SELECT"] || [up hasPrefix:@"("]) {
            finalSQL = [NSString stringWithFormat:@"SELECT * FROM (%@) AS _mcp_page LIMIT %ld OFFSET %ld",
                        t, (long)limit, (long)MAX((NSInteger)0, offset)];
        }
    }

    __block NSDictionary *result;
    dispatch_sync(sMCPDBQueue, ^{
        result = [self mcpExecuteResultQuery:finalSQL onConnection:conn connectionID:ci[@"id"]];
    });
    return result;
}

/// Substitutes each unquoted ? in `sql` with the next param as an escaped SQL
/// literal. Returns nil (with *error) if the placeholder and param counts differ.
- (NSString *)mcpBindParams:(NSArray *)params intoSQL:(NSString *)sql connection:(SPMySQLConnection *)conn error:(NSString **)error
{
    NSMutableString *out = [NSMutableString stringWithCapacity:sql.length];
    NSUInteger pIndex = 0;
    unichar quote = 0;
    for (NSUInteger i = 0; i < sql.length; i++) {
        unichar c = [sql characterAtIndex:i];
        if (quote != 0) {
            [out appendFormat:@"%C", c];
            if (c == '\\' && quote != '`') {                       // backslash escape in a string literal
                if (i + 1 < sql.length) { [out appendFormat:@"%C", [sql characterAtIndex:i + 1]]; i++; }
            } else if (c == quote) {
                if (i + 1 < sql.length && [sql characterAtIndex:i + 1] == quote) {   // doubled-quote escape
                    [out appendFormat:@"%C", quote]; i++;
                } else {
                    quote = 0;
                }
            }
            continue;
        }
        if (c == '\'' || c == '"' || c == '`') { quote = c; [out appendFormat:@"%C", c]; continue; }
        if (c == '?') {
            if (pIndex >= params.count) { if (error) *error = @"More ? placeholders than params provided"; return nil; }
            [out appendString:[self mcpSQLLiteralForValue:params[pIndex] connection:conn]];
            pIndex++;
            continue;
        }
        [out appendFormat:@"%C", c];
    }
    if (pIndex != params.count) { if (error) *error = @"More params than ? placeholders provided"; return nil; }
    return [out copy];
}

- (NSString *)mcpSQLLiteralForValue:(id)value connection:(SPMySQLConnection *)conn
{
    if (!value || value == [NSNull null]) return @"NULL";
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    return [conn escapeAndQuoteString:[value description]];
}

- (NSDictionary *)mcpKillProcessID:(NSString *)processID connection:(NSString *)connID
{
    long long pid = processID.longLongValue;
    if (pid <= 0) return @{@"error": @"a positive numeric process id is required"};
    NSDictionary *ci = [self mcpResolveConnection:connID];
    if (!ci) return [self mcpNoConnectionError];
    SPMySQLConnection *conn = ci[@"conn"];

    __block NSDictionary *result;
    dispatch_sync(sMCPDBQueue, ^{
        [conn queryString:[NSString stringWithFormat:@"KILL %lld", pid]];
        if ([conn queryErrored]) { result = @{@"error": [conn lastErrorMessage] ?: @"Could not kill process"}; return; }
        result = @{@"killed": @(pid), @"connection": ci[@"id"]};
    });
    return result;
}

// Runs a result-returning query and packages rows/columns. Caller holds sMCPDBQueue.
- (NSDictionary *)mcpExecuteResultQuery:(NSString *)sql onConnection:(SPMySQLConnection *)conn connectionID:(NSString *)connID
{
    SPMySQLResult *res = [conn queryString:sql];
    if ([conn queryErrored]) return @{@"error": [conn lastErrorMessage] ?: @"Query error"};

    // Non-SELECT statements (INSERT, UPDATE, DELETE, ...) return nil result.
    if (!res) {
        return @{@"columns": @[], @"rows": @[],
                 @"rowsAffected": @([conn rowsAffectedByLastQuery]),
                 @"connection": connID ?: @""};
    }

    NSArray<NSString *> *fieldNames = [res fieldNames];
    NSMutableArray *rows = [NSMutableArray array];
    unsigned long long rowCount = 0;
    for (NSDictionary *row in res) {
        if (rowCount >= kMCPMaxResultRows) break;
        NSMutableDictionary *safeRow = [NSMutableDictionary dictionaryWithCapacity:row.count];
        for (NSString *key in row) {
            id val = row[key];
            if (val == [NSNull null] || val == nil) {
                safeRow[key] = [NSNull null];
            } else if ([val isKindOfClass:[NSString class]] || [val isKindOfClass:[NSNumber class]]) {
                safeRow[key] = val;
            } else if ([val isKindOfClass:[NSData class]]) {
                NSString *s = [[NSString alloc] initWithData:val encoding:NSUTF8StringEncoding];
                safeRow[key] = s ?: [val description];
            } else {
                safeRow[key] = [val description];
            }
        }
        [rows addObject:[safeRow copy]];
        rowCount++;
    }

    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    r[@"columns"]    = fieldNames ?: @[];
    r[@"rows"]       = [rows copy];
    r[@"rowCount"]   = @(rowCount);
    r[@"connection"] = connID ?: @"";
    if (rowCount >= kMCPMaxResultRows) {
        r[@"truncated"]   = @YES;
        r[@"truncatedAt"] = @(kMCPMaxResultRows);
    }
    return [r copy];
}

- (NSDictionary *)mcpExplainQuery:(NSString *)sql connection:(NSString *)connID
{
    if (!sql.length) return @{@"error": @"sql argument is required"};
    NSString *trimmed = [sql stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // Plain EXPLAIN never executes the statement, but EXPLAIN ANALYZE does, so
    // refuse a query that already starts with ANALYZE.
    if ([trimmed.uppercaseString hasPrefix:@"ANALYZE"]) {
        return @{@"error": @"ANALYZE is not allowed; it would execute the statement"};
    }
    NSDictionary *ci = [self mcpResolveConnection:connID];
    if (!ci) return [self mcpNoConnectionError];
    SPMySQLConnection *conn = ci[@"conn"];

    __block NSDictionary *result;
    dispatch_sync(sMCPDBQueue, ^{
        result = [self mcpExecuteResultQuery:[NSString stringWithFormat:@"EXPLAIN %@", trimmed]
                                onConnection:conn connectionID:ci[@"id"]];
    });
    return result;
}

- (NSDictionary *)mcpSampleTable:(NSString *)table inDatabase:(NSString *)database limit:(NSInteger)limit offset:(NSInteger)offset connection:(NSString *)connID
{
    if (!table.length || !database.length) return @{@"error": @"Both database and table arguments are required"};
    NSDictionary *ci = [self mcpResolveConnection:connID];
    if (!ci) return [self mcpNoConnectionError];
    SPMySQLConnection *conn = ci[@"conn"];
    NSInteger n = limit;
    if (n < 1) n = 10;
    if (n > 1000) n = 1000;
    NSInteger off = MAX((NSInteger)0, offset);

    __block NSDictionary *result;
    dispatch_sync(sMCPDBQueue, ^{
        NSString *sql = [NSString stringWithFormat:@"SELECT * FROM `%@`.`%@` LIMIT %ld OFFSET %ld",
                         mcpQuoteIdentifier(database), mcpQuoteIdentifier(table), (long)n, (long)off];
        result = [self mcpExecuteResultQuery:sql onConnection:conn connectionID:ci[@"id"]];
    });
    return result;
}

- (NSDictionary *)mcpCountRowsInTable:(NSString *)table inDatabase:(NSString *)database connection:(NSString *)connID
{
    if (!table.length || !database.length) return @{@"error": @"Both database and table arguments are required"};
    NSDictionary *ci = [self mcpResolveConnection:connID];
    if (!ci) return [self mcpNoConnectionError];
    SPMySQLConnection *conn = ci[@"conn"];

    __block NSDictionary *result;
    dispatch_sync(sMCPDBQueue, ^{
        NSString *sql = [NSString stringWithFormat:@"SELECT COUNT(*) AS count FROM `%@`.`%@`",
                         mcpQuoteIdentifier(database), mcpQuoteIdentifier(table)];
        SPMySQLResult *res = [conn queryString:sql];
        if ([conn queryErrored] || !res) { result = @{@"error": [conn lastErrorMessage] ?: @"Query error"}; return; }
        [res setDefaultRowReturnType:SPMySQLResultRowAsArray];
        NSString *count = @"0";
        for (NSArray *row in res) { if (row.firstObject) count = [row.firstObject description]; break; }
        result = @{@"count": @(count.longLongValue), @"connection": ci[@"id"]};
    });
    return result;
}

- (NSDictionary *)mcpExportResults:(NSString *)sql format:(NSString *)format path:(NSString *)path connection:(NSString *)connID
{
    if (!sql.length) return @{@"error": @"sql argument is required"};

    // Confine writes to the configured export folder. An MCP tool path is
    // attacker-influencable (prompt injection), so never write to an arbitrary path.
    // Resolve symlinks so a link inside the folder cannot redirect writes outside it.
    NSString *base = [[NSUserDefaults standardUserDefaults] stringForKey:SPMCPExportPath];
    if (!base.length) base = NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory, NSUserDomainMask, YES).firstObject ?: NSTemporaryDirectory();
    NSString *realBase = [[[base stringByStandardizingPath] stringByResolvingSymlinksInPath] stringByStandardizingPath];

    NSString *filename = [path lastPathComponent];
    if (!filename.length || [filename isEqualToString:@"."] || [filename isEqualToString:@".."]) {
        return @{@"error": @"Export path must include a filename"};
    }
    NSString *parent     = [[path stringByStandardizingPath] stringByDeletingLastPathComponent];
    NSString *realParent = [[[parent stringByResolvingSymlinksInPath] stringByStandardizingPath] copy];
    NSString *baseWithSlash = [realBase hasSuffix:@"/"] ? realBase : [realBase stringByAppendingString:@"/"];
    BOOL inside = [realParent isEqualToString:realBase] ||
                  [[realParent stringByAppendingString:@"/"] hasPrefix:baseWithSlash];
    if (!inside) {
        return @{@"error": [NSString stringWithFormat:@"Export path must be inside the configured export folder: %@", realBase]};
    }
    path = [realParent stringByAppendingPathComponent:filename];

    NSDictionary *queryResult = [self mcpRunQuery:sql params:nil limit:0 offset:0 connection:connID];
    if (queryResult[@"error"]) return queryResult;

    NSArray *columns = queryResult[@"columns"] ?: @[];
    NSArray *rows    = queryResult[@"rows"]    ?: @[];

    NSError *writeError = nil;
    NSString *content;
    if ([format.lowercaseString isEqualToString:@"csv"]) {
        content = [self csvStringFromColumns:columns rows:rows];
    } else {
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:queryResult options:NSJSONWritingPrettyPrinted error:&writeError];
        if (writeError) return @{@"error": writeError.localizedDescription};
        content = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }

    NSString *dir = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

    // Open the destination without following symlinks (O_NOFOLLOW). This closes the
    // TOCTOU race where the path is swapped for a symlink after a prior stat check;
    // opening a symlink or directory now fails instead of redirecting the write.
    NSData *outData = [content dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0644);
    if (fd < 0) {
        return @{@"error": [NSString stringWithFormat:@"Could not open export file (%s)", strerror(errno)]};
    }
    BOOL ok = YES;
    size_t total = 0;
    const char *bytes = outData.bytes;
    while (total < outData.length) {
        ssize_t w = write(fd, bytes + total, outData.length - total);
        if (w <= 0) { ok = NO; break; }
        total += (size_t)w;
    }
    close(fd);
    if (!ok) return @{@"error": @"Could not write export file"};

    return @{@"path": path, @"rowCount": @(rows.count), @"format": format ?: @"json", @"connection": connID ?: @""};
}

#pragma mark - SPMCPDataSource: diagnostics

- (NSDictionary *)mcpServerInfoOnConnection:(NSString *)connID
{
    NSDictionary *ci = [self mcpResolveConnection:connID];
    if (!ci) return [self mcpNoConnectionError];
    SPMySQLConnection *conn = ci[@"conn"];

    __block NSDictionary *result;
    dispatch_sync(sMCPDBQueue, ^{
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        SPMySQLResult *res = [conn queryString:
            @"SHOW VARIABLES WHERE Variable_name IN "
            @"('version','version_comment','version_compile_os','protocol_version','max_connections','sql_mode','time_zone','character_set_server')"];
        if (![conn queryErrored]) {
            [res setDefaultRowReturnType:SPMySQLResultRowAsArray];
            for (NSArray *row in res) {
                if (row.count >= 2 && row[0] != [NSNull null]) {
                    info[[row[0] description]] = (row[1] == [NSNull null]) ? @"" : [row[1] description];
                }
            }
        }
        result = @{@"variables": [info copy], @"connection": ci[@"id"], @"database": ci[@"database"], @"host": ci[@"host"]};
    });
    return result;
}

- (NSDictionary *)mcpTableSizesInDatabase:(NSString *)database connection:(NSString *)connID
{
    if (!database.length) return @{@"error": @"database argument is required"};
    NSDictionary *ci = [self mcpResolveConnection:connID];
    if (!ci) return [self mcpNoConnectionError];
    SPMySQLConnection *conn = ci[@"conn"];

    __block NSDictionary *result;
    dispatch_sync(sMCPDBQueue, ^{
        NSString *sql = [NSString stringWithFormat:
            @"SELECT TABLE_NAME AS name, TABLE_ROWS AS row_estimate, DATA_LENGTH AS data_bytes, INDEX_LENGTH AS index_bytes "
             "FROM information_schema.TABLES WHERE TABLE_SCHEMA = %@ ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC",
            [conn escapeAndQuoteString:database]];
        SPMySQLResult *res = [conn queryString:sql];
        if ([conn queryErrored]) { result = @{@"error": [conn lastErrorMessage] ?: @"Query error"}; return; }
        NSMutableArray *tables = [NSMutableArray array];
        for (NSDictionary *row in res) {
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            for (NSString *k in row) { id v = row[k]; if (v && v != [NSNull null]) entry[k] = mcpDecode(v); }
            [tables addObject:[entry copy]];
        }
        result = @{@"tables": [tables copy], @"connection": ci[@"id"]};
    });
    return result;
}

- (NSDictionary *)mcpProcessListOnConnection:(NSString *)connID
{
    NSDictionary *ci = [self mcpResolveConnection:connID];
    if (!ci) return [self mcpNoConnectionError];
    SPMySQLConnection *conn = ci[@"conn"];

    __block NSDictionary *result;
    dispatch_sync(sMCPDBQueue, ^{
        SPMySQLResult *res = [conn queryString:@"SHOW FULL PROCESSLIST"];
        if ([conn queryErrored] || !res) { result = @{@"error": [conn lastErrorMessage] ?: @"Query error"}; return; }
        NSMutableArray *procs = [NSMutableArray array];
        for (NSDictionary *row in res) {
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            for (NSString *k in row) { id v = row[k]; entry[k] = (v == [NSNull null] || !v) ? [NSNull null] : mcpDecode(v); }
            [procs addObject:[entry copy]];
        }
        result = @{@"processes": [procs copy], @"connection": ci[@"id"]};
    });
    return result;
}

#pragma mark - CSV helpers

- (NSString *)csvStringFromColumns:(NSArray<NSString *> *)columns rows:(NSArray<NSDictionary *> *)rows
{
    NSMutableString *csv = [NSMutableString string];
    NSMutableArray *escapedHeaders = [NSMutableArray arrayWithCapacity:columns.count];
    for (NSString *col in columns) [escapedHeaders addObject:[self csvEscape:col]];
    [csv appendFormat:@"%@\n", [escapedHeaders componentsJoinedByString:@","]];

    for (NSDictionary *row in rows) {
        NSMutableArray *vals = [NSMutableArray arrayWithCapacity:columns.count];
        for (NSString *col in columns) {
            id val = row[col];
            NSString *strVal;
            if (val == nil || val == [NSNull null]) strVal = @"";
            else if ([val isKindOfClass:[NSString class]]) strVal = val;
            else strVal = [val description];
            [vals addObject:[self csvEscape:strVal]];
        }
        [csv appendFormat:@"%@\n", [vals componentsJoinedByString:@","]];
    }
    return [csv copy];
}

- (NSString *)csvEscape:(NSString *)value
{
    if ([value containsString:@","] || [value containsString:@"\""] ||
        [value containsString:@"\n"] || [value containsString:@"\r"]) {
        NSString *escaped = [value stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
        return [NSString stringWithFormat:@"\"%@\"", escaped];
    }
    return value;
}

@end
