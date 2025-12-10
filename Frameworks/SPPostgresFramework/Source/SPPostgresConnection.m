//
//  SPPostgresConnection.m
//  SPPostgresFramework
//
//  Created by Mehmet Karabulut (mehmetik@gmail.com) on November 30, 2025.
//  Copyright (c) 2025 Mehmet Karabulut.
//  This software is released under the GPL License.
//  This is an open-source project forked from Sequel Ace.
//

#import "SPPostgresConnection.h"
#import "/opt/homebrew/include/postgresql@17/libpq-fe.h"

@implementation SPPostgresConnection

- (instancetype)init {
    self = [super init];
    if (self) {
        connection = NULL;
        isConnected = NO;
        stringEncoding = NSUTF8StringEncoding;
    }
    return self;
}

- (void)setConnectionDetailsWithHost:(NSString *)theHost username:(NSString *)theUsername password:(NSString *)thePassword port:(NSUInteger)thePort database:(NSString *)theDatabase {
    host = [theHost copy];
    username = [theUsername copy];
    password = [thePassword copy];
    port = thePort;
    database = [theDatabase copy];
}

- (BOOL)connect {
    if (isConnected) [self disconnect];

    NSMutableString *connInfo = [NSMutableString string];
    if (host) [connInfo appendFormat:@"host='%@' ", host];
    if (port) [connInfo appendFormat:@"port='%lu' ", (unsigned long)port];
    if (database) [connInfo appendFormat:@"dbname='%@' ", database];
    if (username) [connInfo appendFormat:@"user='%@' ", username];
    if (password) [connInfo appendFormat:@"password='%@' ", password];
    
    // Set client encoding to UTF8 by default
    [connInfo appendString:@"client_encoding='UTF8'"];

    connection = PQconnectdb([connInfo UTF8String]);

    if (PQstatus(connection) != CONNECTION_OK) {
        lastErrorMessage = [NSString stringWithUTF8String:PQerrorMessage(connection)];
        PQfinish(connection);
        connection = NULL;
        isConnected = NO;
        return NO;
    }

    isConnected = YES;
    
    // Get server version
    int version = PQserverVersion(connection);
    serverMajorVersion = version / 10000;
    serverMinorVersion = (version % 10000) / 100;
    serverReleaseVersion = version % 100;
    serverVersion = [NSString stringWithFormat:@"%d.%d.%d", (int)serverMajorVersion, (int)serverMinorVersion, (int)serverReleaseVersion];

    return YES;
}

- (BOOL)reconnectWithNewDatabase:(NSString *)databaseName {
    if (!databaseName) return NO;
    
    // If we're already connected to this database, do nothing but return success
    if (isConnected && [database isEqualToString:databaseName]) {
        return YES;
    }
    
    [self disconnect];
    
    database = [databaseName copy];
    
    return [self connect];
}


- (void)disconnect {
    if (connection) {
        PQfinish(connection);
        connection = NULL;
    }
    isConnected = NO;
}

- (SPPostgresResult *)queryString:(NSString *)query {
    if (!isConnected || !connection) return nil;

    PGresult *res = PQexec(connection, [query UTF8String]);
    
    SPPostgresResult *result = [[SPPostgresResult alloc] initWithPGResult:res];
    
    if (PQresultStatus(res) != PGRES_TUPLES_OK && PQresultStatus(res) != PGRES_COMMAND_OK) {
        lastErrorMessage = [NSString stringWithUTF8String:PQresultErrorMessage(res)];
    } else {
        lastErrorMessage = nil;
    }
    
    return result;
}

- (SPPostgresStreamingResult *)streamingQueryString:(NSString *)query useLowMemoryBlockingStreaming:(BOOL)lowMemory {
    if (!isConnected || !connection) return nil;
    
    // 1. Send the query asynchronously
    if (!PQsendQuery(connection, [query UTF8String])) {
        lastErrorMessage = [NSString stringWithUTF8String:PQerrorMessage(connection)];
        return nil;
    }
    
    // 2. Enable single-row mode (Streaming)
    if (!PQsetSingleRowMode(connection)) {
         lastErrorMessage = @"Failed to enable single-row mode";
         // We might want to cancel/drain here?
         return nil;
    }
    
    // 3. Return the streaming wrapper, passing the connection so it can pump results
    //    Note: SPPostgresStreamingResult does NOT own the connection, but uses it.
    SPPostgresStreamingResult *result = [[SPPostgresStreamingResult alloc] initWithConnection:connection];
    
    return result;
}

- (void)setEncoding:(NSString *)encoding {
    if (!isConnected) return;
    // Map encoding name to Postgres encoding if needed
    PQsetClientEncoding(connection, [encoding UTF8String]);
}

- (NSStringEncoding)encoding {
    return stringEncoding;
}

- (NSString *)escapeAndQuoteString:(NSString *)string {
    if (!string) return @"NULL";
    if (!isConnected) return [NSString stringWithFormat:@"'%@'", string]; // Fallback
    
    char *escaped = malloc(string.length * 2 + 1);
    int error;
    PQescapeStringConn(connection, escaped, [string UTF8String], string.length, &error);
    NSString *result = [NSString stringWithFormat:@"'%s'", escaped];
    free(escaped);
    return result;
}

- (id)delegate { return nil; }
- (void)setDelegate:(id)delegate {}

- (BOOL)queryErrored {
    return lastErrorMessage != nil;
}

- (BOOL)lastQueryWasCancelled {
    return NO; // TODO
}

- (void)cancelCurrentQuery {
    // TODO
}

- (NSString *)database {
    return database;
}

- (void)selectDatabase:(NSString *)db {
    // Postgres doesn't support "USE db", need to reconnect.
    // For now, just update the property, assuming caller will reconnect or this is just for tracking.
    database = [db copy];
}

- (NSString *)host {
    return host;
}

- (NSArray *)databases {
    if (!isConnected || !connection) return @[];
    
    // Query pg_database system catalog for all non-template databases
    SPPostgresResult *result = [self queryString:@"SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname"];
    
    if (!result || [self queryErrored]) {
        return @[];
    }
    
    NSMutableArray *databaseList = [NSMutableArray array];
    NSDictionary *row;
    while ((row = [result getRowAsDictionary])) {
        NSString *dbName = [row objectForKey:@"datname"];
        if (dbName && ![dbName isKindOfClass:[NSNull class]]) {
            [databaseList addObject:dbName];
        }
    }
    
    return [NSArray arrayWithArray:databaseList];
}

- (void)storeEncodingForRestoration {
    if (!isConnected || !connection) return;
    
    // Get current encoding from libpq
    const char *enc = pg_encoding_to_char(PQclientEncoding(connection));
    if (enc) {
        storedEncoding = [NSString stringWithUTF8String:enc];
    }
}

- (void)restoreStoredEncoding {
    if (!isConnected || !storedEncoding) return;
    
    [self setEncoding:storedEncoding];
    storedEncoding = nil;
}

- (id)getFirstFieldFromQuery:(NSString *)query {
    if (!isConnected || !connection || !query) return nil;
    
    SPPostgresResult *result = [self queryString:query];
    
    if (!result || [result numberOfRows] == 0 || [result numberOfFields] == 0) {
        return nil;
    }
    
    NSArray *row = [result getRowAsArray];
    if (row && [row count] > 0) {
        id val = [row objectAtIndex:0];
        if ([val isKindOfClass:[NSNull class]]) {
            return nil;
        }
        return val;
    }
    
    return nil;
}

- (NSUInteger)lastErrorID {
    // PostgreSQL uses SQLSTATE codes (5-char strings) rather than numeric error IDs.
    // Return 0 as a placeholder since numeric IDs don't apply.
    // Callers should use lastErrorMessage for actual error information.
    return 0;
}

- (NSString *)escapeAndQuoteData:(NSData *)data {
    if (!data || [data length] == 0) return @"NULL";
    if (!isConnected || !connection) {
        // Fallback: hex encode the data
        const unsigned char *bytes = [data bytes];
        NSMutableString *hex = [NSMutableString stringWithString:@"E'\\\\x"];
        for (NSUInteger i = 0; i < [data length]; i++) {
            [hex appendFormat:@"%02x", bytes[i]];
        }
        [hex appendString:@"'"];
        return hex;
    }
    
    // Use PostgreSQL's escape function for bytea
    size_t escapedLen;
    unsigned char *escaped = PQescapeByteaConn(connection, [data bytes], [data length], &escapedLen);
    if (escaped) {
        NSString *result = [NSString stringWithFormat:@"E'%s'", escaped];
        PQfreemem(escaped);
        return result;
    }
    
    return @"NULL";
}

- (BOOL)isNotMariadb103 {
    // PostgreSQL is not MariaDB, so this always returns YES
    // This method exists for MySQL/MariaDB compatibility checks
    return YES;
}

- (BOOL)isMariaDB {
    // PostgreSQL is not MariaDB
    return NO;
}

- (BOOL)userTriggeredDisconnect {
    // Return NO as PostgreSQL connections don't track user-triggered disconnects the same way
    return NO;
}

#pragma mark - Additional Compatibility Methods

- (SPPostgresResult *)resultStoreFromQueryString:(NSString *)query {
    // For PostgreSQL, we just use the regular query method
    // The "result store" concept was MySQL-specific
    return [self queryString:query];
}

- (NSString *)lastSqlstate {
    if (!connection) return nil;
    char *sqlstate = PQresultErrorField(PQexec(connection, "SELECT 1"), PG_DIAG_SQLSTATE);
    if (sqlstate) {
        return [NSString stringWithUTF8String:sqlstate];
    }
    return @"00000"; // Success state
}

- (NSUInteger)rowsAffectedByLastQuery {
    if (!connection) return 0;
    // PostgreSQL tracks affected rows via PQcmdTuples
    PGresult *result = PQexec(connection, "SELECT 1"); // Get last result
    if (result) {
        char *affected = PQcmdTuples(result);
        if (affected && strlen(affected) > 0) {
            return (NSUInteger)atol(affected);
        }
        PQclear(result);
    }
    return 0;
}

- (NSString *)escapeString:(NSString *)string includingQuotes:(BOOL)includeQuotes {
    if (!string || !connection) return includeQuotes ? @"''" : @"";
    
    const char *utf8String = [string UTF8String];
    size_t length = strlen(utf8String);
    char *escaped = PQescapeLiteral(connection, utf8String, length);
    
    if (escaped) {
        NSString *result;
        if (includeQuotes) {
            result = [NSString stringWithUTF8String:escaped];
        } else {
            // Remove surrounding quotes
            NSString *temp = [NSString stringWithUTF8String:escaped];
            if ([temp hasPrefix:@"'"] && [temp hasSuffix:@"'"]) {
                result = [temp substringWithRange:NSMakeRange(1, temp.length - 2)];
            } else {
                result = temp;
            }
        }
        PQfreemem(escaped);
        return result;
    }
    
    return includeQuotes ? @"''" : @"";
}

- (NSString *)escapeData:(NSData *)data includingQuotes:(BOOL)includeQuotes {
    if (!data || !connection) return includeQuotes ? @"''" : @"";
    
    size_t escapedLen;
    unsigned char *escaped = PQescapeByteaConn(connection, [data bytes], [data length], &escapedLen);
    
    if (escaped) {
        NSString *escapedStr = [NSString stringWithUTF8String:(char *)escaped];
        PQfreemem(escaped);
        if (includeQuotes) {
            return [NSString stringWithFormat:@"E'%@'", escapedStr];
        }
        return escapedStr;
    }
    
    return includeQuotes ? @"''" : @"";
}

- (NSStringEncoding)stringEncoding {
    return stringEncoding;
}

- (unsigned long long)lastInsertID {
    // PostgreSQL doesn't have a global last insert ID like MySQL
    // Instead, use RETURNING clause or sequences
    // For compatibility, we try to get the last value from the default sequence
    if (!connection) return 0;
    
    PGresult *result = PQexec(connection, "SELECT lastval()");
    if (result && PQresultStatus(result) == PGRES_TUPLES_OK && PQntuples(result) > 0) {
        char *value = PQgetvalue(result, 0, 0);
        if (value) {
            unsigned long long lastId = strtoull(value, NULL, 10);
            PQclear(result);
            return lastId;
        }
        PQclear(result);
    }
    if (result) PQclear(result);
    return 0;
}

- (BOOL)isConnected {
    return isConnected && connection && PQstatus(connection) == CONNECTION_OK;
}

- (NSArray *)tablesFromDatabase:(NSString *)databaseName {
    if (!connection || !databaseName) return @[];
    
    // Query PostgreSQL information_schema for tables in the specified schema/database
    NSString *query = [NSString stringWithFormat:
        @"SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_catalog = '%@'",
        databaseName];
    
    SPPostgresResult *result = [self queryString:query];
    if (!result || [self queryErrored]) {
        return @[];
    }
    
    NSMutableArray *tables = [NSMutableArray array];
    NSUInteger rows = [result numberOfRows];
    for (NSUInteger i = 0; i < rows; i++) {
        NSArray *row = [result getRowAsArray];
        if (row && [row count] > 0) {
            [tables addObject:[row objectAtIndex:0]];
        }
    }
    
    return [NSArray arrayWithArray:tables];
}

@end
