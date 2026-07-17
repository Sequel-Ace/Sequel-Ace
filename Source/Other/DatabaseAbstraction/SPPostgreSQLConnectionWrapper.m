//
//  SPPostgreSQLConnectionWrapper.m
//  Sequel Ace
//

#import "SPPostgreSQLConnectionWrapper.h"
#import "SPPostgreSQLResultWrapper.h"
#import "SPPostgreSQLStreamingResultWrapper.h"
#import "Frameworks/SPPostgreSQLFramework/Headers/sppostgresql_ffi.h"

@implementation SPPostgreSQLConnectionWrapper {
    SPPostgreSQLConnection *_conn;

    NSString *_host;
    NSString *_username;
    NSString *_password;
    NSString *_database;
    NSUInteger _port;
    BOOL _useSSL;
    NSUInteger _timeout;

    NSString *_lastErrorMessage;
    NSUInteger _lastErrorID;
    BOOL _lastQueryErrored;
    unsigned long long _rowsAffected;
    unsigned long long _lastInsertID;
}

- (instancetype)init {
    if (self = [super init]) {
        _conn = sp_postgresql_connection_create();
        _port = 5432;
        _useSSL = NO;
        _timeout = 30;
        _rowsAffected = 0;
        _lastInsertID = 0;
    }
    return self;
}

- (void)dealloc {
    if (_conn) {
        sp_postgresql_connection_destroy(_conn);
        _conn = NULL;
    }
}

+ (NSUInteger)defaultPort { return 5432; }

// ─── Configuration ───────────────────────────────────────────────────────────

- (void)setUsername:(NSString *)u  { _username = [u copy]; }
- (void)setPassword:(NSString *)p  { _password = [p copy]; }
- (void)setHost:(NSString *)h      { _host = [h copy]; }
- (void)setPort:(NSUInteger)port   { _port = port; }
- (void)setDatabase:(NSString *)db { _database = [db copy]; }
- (void)setTimeout:(NSUInteger)t   { _timeout = t; }
- (void)setUseSSL:(BOOL)ssl        { _useSSL = ssl; }
- (void)setDelegate:(id<SPDatabaseConnectionProxy>)delegate { /* PostgreSQL wrapper uses its own error handling. */ }

// ─── Connectivity ────────────────────────────────────────────────────────────

- (BOOL)connect {
    if (!_conn) { _conn = sp_postgresql_connection_create(); }

    const char *host     = _host     ? [_host UTF8String]     : "localhost";
    const char *user     = _username ? [_username UTF8String] : "postgres";
    const char *password = _password ? [_password UTF8String] : "";
    const char *database = _database ? [_database UTF8String] : "postgres";

    int result = sp_postgresql_connection_connect(_conn, host, (int)_port, user, password, database, _useSSL ? 1 : 0);

    if (!result) {
        [self _captureLastError];
        return NO;
    }
    _lastErrorMessage = nil;
    _lastErrorID = 0;
    return YES;
}

- (void)disconnect {
    if (_conn) sp_postgresql_connection_disconnect(_conn);
}

- (BOOL)isConnected {
    return _conn && sp_postgresql_connection_is_connected(_conn) != 0;
}

- (BOOL)isConnectedViaSSL { return _useSSL && [self isConnected]; }

// ─── Database selection ───────────────────────────────────────────────────────

- (BOOL)selectDatabase:(NSString *)aDatabase {
    // PostgreSQL does not support in-connection database switching; reconnect instead.
    if ([aDatabase isEqualToString:_database]) return YES;
    _database = [aDatabase copy];
    [self disconnect];
    return [self connect];
}

- (NSArray *)databases {
    if (!_conn) return @[];
    int count = 0;
    char **dbs = sp_postgresql_connection_list_databases(_conn, &count);
    if (!dbs || count == 0) return @[];

    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; i < count; i++) {
        if (dbs[i]) [arr addObject:[NSString stringWithUTF8String:dbs[i]]];
    }
    sp_postgresql_free_string_array(dbs, count);
    return [arr copy];
}

// ─── Querying ────────────────────────────────────────────────────────────────

- (id<SPDatabaseResult>)queryString:(NSString *)query {
    if (!_conn || ![self isConnected]) {
        _lastErrorMessage = @"Not connected to PostgreSQL server";
        _lastErrorID = 1;
        _lastQueryErrored = YES;
        return nil;
    }

    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
    SPPostgreSQLResult *result = sp_postgresql_connection_execute_query(_conn, [query UTF8String]);
    double elapsed = [NSDate timeIntervalSinceReferenceDate] - start;

    if (!result) {
        [self _captureLastError];
        _lastQueryErrored = YES;
        return nil;
    }

    _lastQueryErrored = NO;
    _lastErrorMessage = nil;
    _lastErrorID = 0;
    _rowsAffected = sp_postgresql_result_affected_rows(result);
    _lastInsertID = 0; // PostgreSQL uses RETURNING instead of last-insert-id

    return [[SPPostgreSQLResultWrapper alloc] initWithResult:result queryTime:elapsed];
}

- (id)streamingQueryString:(NSString *)query {
    return [self streamingQueryString:query useLowMemoryBlockingStreaming:YES];
}

- (id)streamingQueryString:(NSString *)query useLowMemoryBlockingStreaming:(BOOL)fullStreaming {
    if (!_conn || ![self isConnected]) {
        _lastErrorMessage = @"Not connected to PostgreSQL server";
        _lastErrorID = 1;
        _lastQueryErrored = YES;
        return nil;
    }

    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
    int batchSize = fullStreaming ? 100 : 1000;
    SPPostgreSQLStreamingResult *result = sp_postgresql_connection_execute_streaming_query(
        _conn, [query UTF8String], batchSize);
    double elapsed = [NSDate timeIntervalSinceReferenceDate] - start;

    if (!result) {
        [self _captureLastError];
        _lastQueryErrored = YES;
        return nil;
    }

    _lastQueryErrored = NO;
    _lastErrorMessage = nil;
    _lastErrorID = 0;

    return [[SPPostgreSQLStreamingResultWrapper alloc] initWithStreamingResult:result queryTime:elapsed];
}

- (BOOL)queryErrored { return _lastQueryErrored; }
- (NSString *)lastErrorMessage { return _lastErrorMessage; }
- (NSUInteger)lastErrorID { return _lastErrorID; }
- (unsigned long long)rowsAffectedByLastQuery { return _rowsAffected; }
- (unsigned long long)lastInsertID { return _lastInsertID; }
- (void)cancelCurrentQuery { /* Best-effort: PostgreSQL async cancel would require a separate connection. */ }

// ─── Encoding ────────────────────────────────────────────────────────────────

- (NSString *)encoding { return @"utf8"; }
- (BOOL)setEncoding:(NSString *)encoding { return YES; /* PostgreSQL manages encoding per-connection. */ }
- (void)storeEncodingForRestoration { }
- (void)restoreStoredEncoding { }
- (NSString *)preferredUTF8Encoding { return @"UTF8"; }

// ─── Server info ─────────────────────────────────────────────────────────────

- (NSString *)serverVersionString {
    id<SPDatabaseResult> result = [self queryString:@"SELECT version()"];
    if (!result) return @"PostgreSQL (unknown version)";
    NSArray *row = [result getRowAsArray];
    return row.firstObject ?: @"PostgreSQL";
}

- (NSUInteger)_versionComponentAtIndex:(NSUInteger)idx {
    NSString *ver = [self serverVersionString];
    // "PostgreSQL 15.3 on ..." → extract "15.3"
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)\\.(\\d+)(?:\\.(\\d+))?" options:0 error:nil];
    NSTextCheckingResult *match = [re firstMatchInString:ver options:0 range:NSMakeRange(0, ver.length)];
    if (!match || idx + 1 > match.numberOfRanges) return 0;
    NSRange range = [match rangeAtIndex:idx + 1];
    if (range.location == NSNotFound) return 0;
    return (NSUInteger)[[ver substringWithRange:range] integerValue];
}

- (NSUInteger)serverMajorVersion   { return [self _versionComponentAtIndex:0]; }
- (NSUInteger)serverMinorVersion   { return [self _versionComponentAtIndex:1]; }
- (NSUInteger)serverReleaseVersion { return [self _versionComponentAtIndex:2]; }

- (BOOL)serverVersionIsGreaterThanOrEqualTo:(NSUInteger)major
                               minorVersion:(NSUInteger)minor
                             releaseVersion:(NSUInteger)release {
    NSUInteger maj = self.serverMajorVersion;
    NSUInteger min = self.serverMinorVersion;
    NSUInteger rel = self.serverReleaseVersion;
    if (maj != major) return maj > major;
    if (min != minor) return min > minor;
    return rel >= release;
}

- (NSString *)getServerVariableValue:(NSString *)variable {
    NSString *query = [NSString stringWithFormat:@"SHOW %@", variable];
    id<SPDatabaseResult> result = [self queryString:query];
    if (!result) return nil;
    NSArray *row = [result getRowAsArray];
    return row.firstObject;
}

// ─── Collation helpers ────────────────────────────────────────────────────────

- (NSArray *)getCollationsForEncoding:(NSString *)encoding {
    // PostgreSQL uses collations from the operating system; not relevant for this UI.
    return @[];
}

// ─── Backend type ─────────────────────────────────────────────────────────────

- (BOOL)isPostgreSQL { return YES; }
- (NSString *)identifierQuoteCharacter { return @"\""; }

// ─── Private ──────────────────────────────────────────────────────────────────

- (void)_captureLastError {
    if (!_conn) return;
    char *err = sp_postgresql_connection_last_error(_conn);
    if (err) {
        _lastErrorMessage = [NSString stringWithUTF8String:err];
        sp_postgresql_free_string(err);
    } else {
        _lastErrorMessage = @"Unknown PostgreSQL error";
    }
    _lastErrorID = 2;
}

@end
