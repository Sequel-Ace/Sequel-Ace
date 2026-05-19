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
#import "SPFavoritesController.h"
#import "SPTreeNode.h"
#import "SPFavoriteNode.h"
#import "SPConstants.h"

#import <SPMySQL/SPMySQL.h>

#import "sequel-ace-Swift.h"

static const NSInteger kMCPDefaultPort   = 8765;
static const NSUInteger kMCPMaxResultRows = 10000;   // Safety cap for run_query.

// Dispatch queue used for all MCP database operations (serial, background).
static dispatch_queue_t sMCPDBQueue;

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
    if ([prefs boolForKey:SPMCPServerEnabled]) {
        [self startMCPServerWithPrefs:prefs];
    }
}

- (void)mcpDefaultsChanged:(NSNotification *)notification
{
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    BOOL shouldRun = [prefs boolForKey:SPMCPServerEnabled];
    BOOL isRunning = SPMCPServer.shared.isRunning;

    if (shouldRun && !isRunning) {
        [self startMCPServerWithPrefs:prefs];
    } else if (!shouldRun && isRunning) {
        [SPMCPServer.shared stop];
        SPLog(@"MCP server stopped.");
    }
}

#pragma mark - Private: start helper

- (void)startMCPServerWithPrefs:(NSUserDefaults *)prefs
{
    NSInteger port = [prefs integerForKey:SPMCPServerPort];
    if (port < 1024 || port > 65535) port = kMCPDefaultPort;

    [SPMCPServer.shared startWithPort:(uint16_t)port completion:^(BOOL success, NSString *errorMsg) {
        if (success) {
            SPLog(@"MCP server started on port %ld", (long)port);
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

#pragma mark - SPMCPDataSource

- (NSArray<NSDictionary<NSString *, NSString *> *> *)mcpListConnections
{
    // Walk the favourites tree and collect leaf (connection) nodes.
    NSMutableArray *result = [NSMutableArray array];
    SPTreeNode *root = [SPFavoritesController.sharedFavoritesController favoritesTree];
    [self appendFavoriteNodes:root toArray:result];
    return [result copy];
}

/// Recursive walk of the favourites tree; appends flattened dictionaries for each leaf node.
- (void)appendFavoriteNodes:(SPTreeNode *)node toArray:(NSMutableArray *)array
{
    for (SPTreeNode *child in node.childNodes) {
        if (child.isGroup) {
            [self appendFavoriteNodes:child toArray:array];
        } else {
            SPFavoriteNode *favNode = (SPFavoriteNode *)child.representedObject;
            NSDictionary *fav = favNode.nodeFavorite;
            if (!fav) continue;

            // Include only the keys relevant to an AI agent; omit credentials/passwords.
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            for (NSString *key in @[SPFavoriteNameKey, SPFavoriteHostKey, SPFavoritePortKey,
                                    SPFavoriteUserKey, SPFavoriteDatabaseKey, SPFavoriteTypeKey]) {
                NSString *val = fav[key];
                if (val.length) info[key] = val;
            }
            if (info.count) [array addObject:[info copy]];
        }
    }
}

- (NSDictionary *)mcpListDatabases
{
    SPMySQLConnection *conn = [self activeMySQLConnection];
    if (!conn) return @{@"error": @"No active database connection. Please connect in Sequel Ace first."};

    __block NSDictionary *result;
    dispatch_sync(sMCPDBQueue, ^{
        SPMySQLResult *res = [conn queryString:@"SHOW DATABASES"];
        if ([conn queryErrored]) {
            result = @{@"error": [conn lastErrorMessage] ?: @"Query error"};
            return;
        }
        NSMutableArray *dbs = [NSMutableArray array];
        for (NSArray *row in res) {
            if (row.firstObject && row.firstObject != [NSNull null]) {
                [dbs addObject:row.firstObject];
            }
        }
        result = @{@"databases": [dbs copy]};
    });
    return result;
}

- (NSDictionary *)mcpListTablesInDatabase:(NSString *)database
{
    if (!database.length) return @{@"error": @"database argument is required"};

    SPMySQLConnection *conn = [self activeMySQLConnection];
    if (!conn) return @{@"error": @"No active database connection. Please connect in Sequel Ace first."};

    __block NSDictionary *result;
    dispatch_sync(sMCPDBQueue, ^{
        NSString *useSQL = [NSString stringWithFormat:@"SHOW FULL TABLES IN `%@`",
                            [database stringByReplacingOccurrencesOfString:@"`" withString:@"``"]];
        SPMySQLResult *res = [conn queryString:useSQL];
        if ([conn queryErrored]) {
            result = @{@"error": [conn lastErrorMessage] ?: @"Query error"};
            return;
        }
        NSMutableArray *tables = [NSMutableArray array];
        for (NSArray *row in res) {
            if (row.firstObject && row.firstObject != [NSNull null]) {
                NSMutableDictionary *entry = [NSMutableDictionary dictionary];
                entry[@"name"] = row.firstObject;
                if (row.count > 1 && row[1] != [NSNull null]) entry[@"type"] = row[1];
                [tables addObject:[entry copy]];
            }
        }
        result = @{@"tables": [tables copy]};
    });
    return result;
}

- (NSDictionary *)mcpDescribeTable:(NSString *)table inDatabase:(NSString *)database
{
    if (!table.length || !database.length) {
        return @{@"error": @"Both database and table arguments are required"};
    }

    SPMySQLConnection *conn = [self activeMySQLConnection];
    if (!conn) return @{@"error": @"No active database connection. Please connect in Sequel Ace first."};

    __block NSDictionary *result;
    dispatch_sync(sMCPDBQueue, ^{
        NSString *qualifiedTable = [NSString stringWithFormat:@"`%@`.`%@`",
            [database stringByReplacingOccurrencesOfString:@"`" withString:@"``"],
            [table    stringByReplacingOccurrencesOfString:@"`" withString:@"``"]];

        // Columns
        NSMutableArray *columns = [NSMutableArray array];
        SPMySQLResult *colRes = [conn queryString:[NSString stringWithFormat:@"SHOW FULL COLUMNS FROM %@", qualifiedTable]];
        if ([conn queryErrored]) {
            result = @{@"error": [conn lastErrorMessage] ?: @"Could not describe table"};
            return;
        }
        for (NSDictionary *row in colRes) {
            NSMutableDictionary *col = [NSMutableDictionary dictionary];
            for (NSString *k in @[@"Field", @"Type", @"Null", @"Key", @"Default", @"Extra", @"Comment"]) {
                id v = row[k];
                if (v && v != [NSNull null]) col[k] = v;
            }
            [columns addObject:[col copy]];
        }

        // Indexes
        NSMutableArray *indexes = [NSMutableArray array];
        SPMySQLResult *idxRes = [conn queryString:[NSString stringWithFormat:@"SHOW INDEX FROM %@", qualifiedTable]];
        if (![conn queryErrored]) {
            for (NSDictionary *row in idxRes) {
                NSMutableDictionary *idx = [NSMutableDictionary dictionary];
                for (NSString *k in @[@"Key_name", @"Column_name", @"Non_unique", @"Index_type"]) {
                    id v = row[k];
                    if (v && v != [NSNull null]) idx[k] = v;
                }
                [indexes addObject:[idx copy]];
            }
        }

        result = @{@"columns": [columns copy], @"indexes": [indexes copy]};
    });
    return result;
}

- (NSDictionary *)mcpRunQuery:(NSString *)sql
{
    if (!sql.length) return @{@"error": @"sql argument is required"};

    SPMySQLConnection *conn = [self activeMySQLConnection];
    if (!conn) return @{@"error": @"No active database connection. Please connect in Sequel Ace first."};

    __block NSDictionary *result;
    dispatch_sync(sMCPDBQueue, ^{
        SPMySQLResult *res = [conn queryString:sql];

        if ([conn queryErrored]) {
            result = @{@"error": [conn lastErrorMessage] ?: @"Query error"};
            return;
        }

        // Non-SELECT statements (INSERT, UPDATE, DELETE, …) return nil result.
        if (!res) {
            result = @{
                @"columns": @[],
                @"rows":    @[],
                @"rowsAffected": @([conn rowsAffectedByLastQuery])
            };
            return;
        }

        NSArray<NSString *> *fieldNames = [res fieldNames];
        NSMutableArray *rows = [NSMutableArray array];
        unsigned long long rowCount = 0;

        for (NSDictionary *row in res) {
            if (rowCount >= kMCPMaxResultRows) break;
            NSMutableDictionary *safeRow = [NSMutableDictionary dictionaryWithCapacity:row.count];
            for (NSString *key in row) {
                id val = row[key];
                // Convert NSNull to nil (omit) and non-JSON-serialisable types to strings.
                if (val == [NSNull null] || val == nil) {
                    safeRow[key] = [NSNull null];
                } else if ([val isKindOfClass:[NSString class]] ||
                           [val isKindOfClass:[NSNumber class]] ||
                           [val isKindOfClass:[NSNull class]]) {
                    safeRow[key] = val;
                } else {
                    safeRow[key] = [val description];
                }
            }
            [rows addObject:[safeRow copy]];
            rowCount++;
        }

        NSMutableDictionary *r = [NSMutableDictionary dictionary];
        r[@"columns"] = fieldNames ?: @[];
        r[@"rows"]    = [rows copy];
        r[@"rowCount"] = @(rowCount);
        if (rowCount >= kMCPMaxResultRows) {
            r[@"truncated"] = @YES;
            r[@"truncatedAt"] = @(kMCPMaxResultRows);
        }
        result = [r copy];
    });
    return result;
}

- (NSDictionary *)mcpExportResults:(NSString *)sql format:(NSString *)format path:(NSString *)path
{
    if (!sql.length) return @{@"error": @"sql argument is required"};

    // Run the query first.
    NSDictionary *queryResult = [self mcpRunQuery:sql];
    if (queryResult[@"error"]) return queryResult;

    NSArray *columns = queryResult[@"columns"] ?: @[];
    NSArray *rows    = queryResult[@"rows"]    ?: @[];

    NSError *writeError = nil;
    NSString *content;

    if ([format.lowercaseString isEqualToString:@"csv"]) {
        content = [self csvStringFromColumns:columns rows:rows];
    } else {
        // Default: JSON
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:queryResult
                                                           options:NSJSONWritingPrettyPrinted
                                                             error:&writeError];
        if (writeError) return @{@"error": writeError.localizedDescription};
        content = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }

    // Ensure the parent directory exists.
    NSString *dir = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    BOOL written = [content writeToFile:path
                             atomically:YES
                               encoding:NSUTF8StringEncoding
                                  error:&writeError];
    if (!written) return @{@"error": writeError.localizedDescription ?: @"Could not write file"};

    return @{
        @"path":     path,
        @"rowCount": @(rows.count),
        @"format":   format ?: @"json"
    };
}

#pragma mark - Private helpers

/// Returns the mySQLConnection of the front document, or nil if not connected.
- (SPMySQLConnection *)activeMySQLConnection
{
    __block SPMySQLConnection *conn = nil;
    // Must read on main thread as frontDocument accesses UI state.
    if ([NSThread isMainThread]) {
        SPDatabaseDocument *doc = [self frontDocument];
        if (doc && !doc.isProcessing) conn = [doc getConnection];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            SPDatabaseDocument *doc = [self frontDocument];
            if (doc && !doc.isProcessing) conn = [doc getConnection];
        });
    }
    return conn;
}

/// Build a CSV string from column names and row dictionaries.
- (NSString *)csvStringFromColumns:(NSArray<NSString *> *)columns rows:(NSArray<NSDictionary *> *)rows
{
    NSMutableString *csv = [NSMutableString string];

    // Header row
    NSMutableArray *escapedHeaders = [NSMutableArray arrayWithCapacity:columns.count];
    for (NSString *col in columns) {
        [escapedHeaders addObject:[self csvEscape:col]];
    }
    [csv appendFormat:@"%@\n", [escapedHeaders componentsJoinedByString:@","]];

    // Data rows
    for (NSDictionary *row in rows) {
        NSMutableArray *vals = [NSMutableArray arrayWithCapacity:columns.count];
        for (NSString *col in columns) {
            id val = row[col];
            NSString *strVal;
            if (val == nil || val == [NSNull null]) {
                strVal = @"";
            } else if ([val isKindOfClass:[NSString class]]) {
                strVal = val;
            } else {
                strVal = [val description];
            }
            [vals addObject:[self csvEscape:strVal]];
        }
        [csv appendFormat:@"%@\n", [vals componentsJoinedByString:@","]];
    }
    return [csv copy];
}

- (NSString *)csvEscape:(NSString *)value
{
    // Quote fields that contain commas, quotes, or newlines.
    if ([value containsString:@","] || [value containsString:@"\""] ||
        [value containsString:@"\n"] || [value containsString:@"\r"]) {
        NSString *escaped = [value stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
        return [NSString stringWithFormat:@"\"%@\"", escaped];
    }
    return value;
}

@end
