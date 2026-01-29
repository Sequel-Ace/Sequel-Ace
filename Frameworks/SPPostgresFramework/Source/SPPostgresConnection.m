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
#import "SPPostgresStreamingResultStore.h"
#import <libpq-fe.h>

@implementation SPPostgresConnection

@synthesize lastErrorMessage;

- (instancetype)init {
    self = [super init];
    if (self) {
        connection = NULL;
        isConnected = NO;
        stringEncoding = NSUTF8StringEncoding;
        queryWasCancelled = NO;
        lastAffectedRows = 0;
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

    // DEBUG: Log connection parameters (without password)
    NSLog(@"[PG-DEBUG] Connecting: host=%@, port=%lu, db=%@, user=%@",
          host, (unsigned long)port, database, username);

    NSMutableString *connInfo = [NSMutableString string];
    if (host) [connInfo appendFormat:@"host='%@' ", host];
    if (port) [connInfo appendFormat:@"port='%lu' ", (unsigned long)port];
    if (database) [connInfo appendFormat:@"dbname='%@' ", database];
    if (username) [connInfo appendFormat:@"user='%@' ", username];
    if (password) [connInfo appendFormat:@"password='%@' ", password];

    // Set client encoding to UTF8 by default
    [connInfo appendString:@"client_encoding='UTF8'"];

    connection = PQconnectdb([connInfo UTF8String]);

    // DEBUG: Log connection result
    NSLog(@"[PG-DEBUG] PQstatus=%d (CONNECTION_OK=%d)", PQstatus(connection), CONNECTION_OK);

    if (PQstatus(connection) != CONNECTION_OK) {
        NSLog(@"[PG-DEBUG] Connection failed: %s", PQerrorMessage(connection));
        lastErrorMessage = [NSString stringWithUTF8String:PQerrorMessage(connection)];
        PQfinish(connection);
        connection = NULL;
        isConnected = NO;
        return NO;
    }

    NSLog(@"[PG-DEBUG] Connection successful!");
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

- (SPPostgresStreamingResultStore *)queryString:(NSString *)query {
    if (!isConnected || !connection) return nil;

    queryWasCancelled = NO;  // Reset cancellation flag before new query
    PGresult *res = PQexec(connection, [query UTF8String]);

    // DEBUG: Log query type and affected rows
    ExecStatusType status = PQresultStatus(res);
    char *affected = PQcmdTuples(res);
    NSLog(@"[PG-AFFECTED] Query: %.60s...", [query UTF8String]);
    NSLog(@"[PG-AFFECTED] Status: %d, PQcmdTuples: '%s'", status, affected ? affected : "(null)");

    // Save affected rows count immediately (for UPDATE/INSERT/DELETE)
    if (affected && strlen(affected) > 0) {
        lastAffectedRows = (NSUInteger)atol(affected);
    } else {
        lastAffectedRows = 0;
    }
    NSLog(@"[PG-AFFECTED] lastAffectedRows set to: %lu", (unsigned long)lastAffectedRows);

    // Create SPPostgresStreamingResultStore (required by SPDataStorage)
    SPPostgresStreamingResultStore *result = [[SPPostgresStreamingResultStore alloc] initWithPGResult:res];

    if (PQresultStatus(res) != PGRES_TUPLES_OK && PQresultStatus(res) != PGRES_COMMAND_OK) {
        lastErrorMessage = [NSString stringWithUTF8String:PQresultErrorMessage(res)];
    } else {
        lastErrorMessage = nil;
    }

    // For synchronous queries, immediately populate the data storage so callers
    // can iterate the results without explicitly calling startDownload.
    // This is safe because startDownload has a guard against re-entry.
    [result startDownload];

    return result;
}

- (SPPostgresStreamingResult *)streamingQueryString:(NSString *)query useLowMemoryBlockingStreaming:(BOOL)lowMemory {
    if (!isConnected || !connection) return nil;

    queryWasCancelled = NO;  // Reset cancellation flag before new query

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

- (NSString *)escapeAndQuoteString:(id)value {
    if (!value) return @"NULL";

    // Convert non-string objects to string representation
    NSString *string;
    if ([value isKindOfClass:[NSString class]]) {
        string = value;
    } else if ([value isKindOfClass:[NSNumber class]]) {
        string = [value stringValue];
    } else {
        string = [value description];
    }

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
    return queryWasCancelled;
}

- (void)cancelCurrentQuery {
    if (connection) {
        char errbuf[256];
        PGcancel *cancel = PQgetCancel(connection);
        if (cancel) {
            if (PQcancel(cancel, errbuf, sizeof(errbuf))) {
                queryWasCancelled = YES;
                NSLog(@"SPPostgresConnection: Query cancelled successfully");
            } else {
                NSLog(@"SPPostgresConnection: Failed to cancel query: %s", errbuf);
            }
            PQfreeCancel(cancel);
        }
    }
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

- (SPPostgresStreamingResultStore *)resultStoreFromQueryString:(NSString *)query {
    // Execute query and wrap in streaming result store for SPDataStorage compatibility
    if (!connection || !query) {
        NSLog(@"[PG-DEBUG] resultStoreFromQueryString: connection=%p, query=%@", connection, query);
        return nil;
    }

    // DEBUG: Log query and connection status
    NSLog(@"[PG-DEBUG] Query: %@", query);
    NSLog(@"[PG-DEBUG] Connection status before query: %d (OK=%d)", PQstatus(connection), CONNECTION_OK);

    const char *utf8Query = [query UTF8String];
    PGresult *result = PQexec(connection, utf8Query);

    // Track affected rows for consistency
    char *affected = PQcmdTuples(result);
    if (affected && strlen(affected) > 0) {
        lastAffectedRows = (NSUInteger)atol(affected);
    } else {
        lastAffectedRows = 0;
    }

    // DEBUG: Log result details
    int rowCount = result ? PQntuples(result) : -1;
    int fieldCount = result ? PQnfields(result) : -1;
    ExecStatusType status = result ? PQresultStatus(result) : (ExecStatusType)-1;
    NSLog(@"[PG-DEBUG] PQntuples=%d, PQnfields=%d, status=%d (TUPLES_OK=%d)", rowCount, fieldCount, status, PGRES_TUPLES_OK);

    if (!result || status != PGRES_TUPLES_OK) {
        NSLog(@"[PG-DEBUG] Query error: %s", PQerrorMessage(connection));
        if (result) {
            PQclear(result);
        }
        return nil;
    }

    // Create a streaming result store with the PG result
    SPPostgresStreamingResultStore *resultStore = [[SPPostgresStreamingResultStore alloc] initWithPGResult:result];

    // DEBUG: Log the result store row count
    NSLog(@"[PG-DEBUG] resultStore created, numberOfRows=%lu (before startDownload)", (unsigned long)[resultStore numberOfRows]);

    // Do NOT start download here - let SPTableContent handle it via updateResultStore
    // [resultStore startDownload];

    return resultStore;
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
    NSLog(@"[PG-AFFECTED] rowsAffectedByLastQuery returning: %lu", (unsigned long)lastAffectedRows);
    return lastAffectedRows;
}

- (NSString *)escapeString:(id)value includingQuotes:(BOOL)includeQuotes {
    if (!value || !connection) return includeQuotes ? @"''" : @"";

    // Convert non-string objects to string representation
    NSString *string;
    if ([value isKindOfClass:[NSString class]]) {
        string = value;
    } else if ([value isKindOfClass:[NSNumber class]]) {
        string = [value stringValue];
    } else {
        string = [value description];
    }

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

#pragma mark - Connection Management

- (NSUInteger)port {
    return port;
}

- (void)setPort:(NSUInteger)thePort {
    port = thePort;
}

- (BOOL)checkConnectionIfNecessary {
    if (!connection) return NO;
    
    // Check if the connection is still valid
    if (PQstatus(connection) != CONNECTION_OK) {
        // Try to reset the connection
        PQreset(connection);
        if (PQstatus(connection) != CONNECTION_OK) {
            isConnected = NO;
            lastErrorMessage = [NSString stringWithUTF8String:PQerrorMessage(connection)];
            return NO;
        }
    }
    
    isConnected = YES;
    return YES;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    SPPostgresConnection *copy = [[SPPostgresConnection allocWithZone:zone] init];
    
    // Copy connection details (but not the actual connection)
    if (copy) {
        [copy setConnectionDetailsWithHost:host
                                  username:username
                                  password:password
                                      port:port
                                  database:database];
    }
    
    return copy;
}

#pragma mark - MySQL Compatibility Methods

static BOOL _lastQueryWasCancelledFlag = NO;
static BOOL _useLatin1Transport = NO;
static BOOL _delegateQueryLogging = NO;
static BOOL _retryQueriesOnConnectionFailure = NO;

- (BOOL)checkConnection {
    return [self checkConnectionIfNecessary];
}

- (BOOL)serverShutdown {
    // PostgreSQL doesn't support remote shutdown via SQL
    // This is a MySQL-specific command
    return NO;
}

- (void)setLastQueryWasCancelled:(BOOL)wasCancelled {
    _lastQueryWasCancelledFlag = wasCancelled;
}

- (NSUInteger)connectionThreadId {
    // PostgreSQL uses backend PID instead of thread ID
    if (!connection) return 0;
    return (NSUInteger)PQbackendPID(connection);
}

- (void)setEncodingUsesLatin1Transport:(BOOL)useLatin1 {
    _useLatin1Transport = useLatin1;
}

- (BOOL)encodingUsesLatin1Transport {
    return _useLatin1Transport;
}

- (SPPostgresResult *)queryString:(NSString *)query usingEncoding:(NSStringEncoding)encoding withResultType:(int)resultType {
    // Compatibility stub: Ignore encoding (handled by client_encoding) and resultType for now
    return [self queryString:query];
}

- (void)setDelegateQueryLogging:(BOOL)shouldLog {
    _delegateQueryLogging = shouldLog;
}

- (void)setRetryQueriesOnConnectionFailure:(BOOL)shouldRetry {
    _retryQueriesOnConnectionFailure = shouldRetry;
}

- (NSUInteger)killQueryOnThreadID:(NSUInteger)threadID {
    // PostgreSQL uses pg_cancel_backend() or pg_terminate_backend()
    if (!connection || threadID == 0) return 0;
    
    NSString *query = [NSString stringWithFormat:@"SELECT pg_cancel_backend(%lu)", (unsigned long)threadID];
    [self queryString:query];
    
    return 0;
}



- (void)setUsername:(NSString *)userName {
    username = [userName copy];
}

- (void)updateTimeZoneIdentifier:(NSString *)timeZoneIdentifier {
    // PostgreSQL handles time zones differently
    // Set the session time zone if needed
    if (connection && timeZoneIdentifier) {
        NSString *query = [NSString stringWithFormat:@"SET TIME ZONE '%@'", timeZoneIdentifier];
        [self queryString:query];
    }
}

- (BOOL)isConnectedViaSSL {
    // Check if the connection is using SSL
    if (!connection) return NO;
    // PQsslInUse returns 1 if SSL is in use
    return PQsslInUse(connection) == 1;
}

#pragma mark - Connection Setter Methods

static BOOL _useSSL = NO;
static NSString *_sslKeyFilePath = nil;
static NSString *_sslCertificatePath = nil;
static NSString *_sslCACertificatePath = nil;
static BOOL _allowDataLocalInfile = NO;
static BOOL _enableClearTextPlugin = NO;

- (void)setHost:(NSString *)theHost {
    host = [theHost copy];
}

- (void)setPassword:(NSString *)thePassword {
    password = [thePassword copy];
}

- (void)setDatabase:(NSString *)theDatabase {
    database = [theDatabase copy];
}

- (void)setUseSSL:(BOOL)useSSL {
    _useSSL = useSSL;
}

- (void)setSslKeyFilePath:(NSString *)path {
    _sslKeyFilePath = [path copy];
}

- (void)setSslCertificatePath:(NSString *)path {
    _sslCertificatePath = [path copy];
}

- (void)setSslCACertificatePath:(NSString *)path {
    _sslCACertificatePath = [path copy];
}

- (void)setAllowDataLocalInfile:(BOOL)allow {
    _allowDataLocalInfile = allow;
}

- (void)setEnableClearTextPlugin:(BOOL)enable {
    _enableClearTextPlugin = enable;
}

- (NSString *)encodingName {
    // Convert NSStringEncoding to a PostgreSQL encoding name string
    switch (stringEncoding) {
        case NSUTF8StringEncoding:
            return @"UTF8";
        case NSISOLatin1StringEncoding:
            return @"LATIN1";
        case NSASCIIStringEncoding:
            return @"SQL_ASCII";
        default:
            return @"UTF8";
    }
}

@end

