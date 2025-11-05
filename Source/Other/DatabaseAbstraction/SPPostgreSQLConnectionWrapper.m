//
//  SPPostgreSQLConnectionWrapper.m
//  Sequel Ace
//
//  Created for PostgreSQL abstraction support
//

#import "SPPostgreSQLConnectionWrapper.h"
#import "SPPostgreSQLResultWrapper.h"
#import "SPPostgreSQLStreamingResultWrapper.h"
#import "SPConstants.h"

// Import the Rust FFI C header
#import "sppostgresql_ffi.h"

@interface SPPostgreSQLConnectionWrapper ()
{
    SPPostgreSQLConnection *_pgConnection;
    NSString *_host;
    NSString *_username;
    NSString *_password;
    NSString *_database;
    NSUInteger _port;
    NSUInteger _timeout;
    BOOL _useSSL;
    BOOL _connected;
    BOOL _hasDisconnected; // Flag to prevent double-disconnect
    NSString *_lastErrorMessage;
    NSUInteger _lastErrorID;
}
@end

@implementation SPPostgreSQLConnectionWrapper

@synthesize pgConnection = _pgConnection;
@synthesize delegate = _delegate;

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _pgConnection = NULL;
        _host = @"localhost";
        _username = @"";
        _password = @"";
        _database = @"";
        _port = 5432; // Default PostgreSQL port
        _timeout = 10;
        _useSSL = NO;
        _connected = NO;
        _hasDisconnected = NO;
        _lastErrorMessage = nil;
        _lastErrorID = 0;
    }
    return self;
}

- (void)dealloc {
    // Ensure connection is properly cleaned up on dealloc
    [self disconnect];
}

#pragma mark - Database Type

- (NSUInteger)databaseType {
    return (NSUInteger)SPDatabaseTypePostgreSQL;
}

#pragma mark - Connection Properties

- (NSString *)host {
    return _host;
}

- (void)setHost:(NSString *)host {
    _host = [host copy];
}

- (NSString *)username {
    return _username;
}

- (void)setUsername:(NSString *)username {
    _username = [username copy];
}

- (NSString *)password {
    return _password;
}

- (void)setPassword:(NSString *)password {
    _password = [password copy];
}

- (NSUInteger)port {
    return _port;
}

- (void)setPort:(NSUInteger)port {
    _port = port;
}

- (NSString *)database {
    return _database;
}

- (void)setDatabase:(NSString *)database {
    _database = [database copy];
}

- (NSUInteger)timeout {
    return _timeout;
}

- (void)setTimeout:(NSUInteger)timeout {
    _timeout = timeout;
}

- (BOOL)useSSL {
    return _useSSL;
}

- (void)setUseSSL:(BOOL)useSSL {
    _useSSL = useSSL;
}

- (id)delegate {
    return _delegate;
}

- (void)setDelegate:(id<SPDatabaseConnectionProxy>)delegate {
    _delegate = delegate;
}

- (BOOL)delegateQueryLogging {
    return NO; // Not implemented for PostgreSQL
}

- (void)setDelegateQueryLogging:(BOOL)delegateQueryLogging {
    // No-op for PostgreSQL
}

- (BOOL)userTriggeredDisconnect {
    return NO; // Not tracked for PostgreSQL
}

- (unsigned long)mysqlConnectionThreadId {
    return 0; // Not applicable for PostgreSQL
}

- (NSString *)socketPath {
    return nil; // Not applicable for PostgreSQL TCP/IP
}

- (void)setSocketPath:(NSString *)socketPath {
    // No-op for PostgreSQL
}

- (BOOL)useSocket {
    return NO; // Not applicable for PostgreSQL TCP/IP
}

- (void)setUseSocket:(BOOL)useSocket {
    // No-op for PostgreSQL
}

- (NSString *)sslKeyFilePath {
    return nil; // TODO: Implement SSL certificate support
}

- (void)setSslKeyFilePath:(NSString *)sslKeyFilePath {
    // TODO: Implement SSL certificate support
}

- (NSString *)sslCertificatePath {
    return nil; // TODO: Implement SSL certificate support
}

- (void)setSslCertificatePath:(NSString *)sslCertificatePath {
    // TODO: Implement SSL certificate support
}

- (NSString *)sslCACertificatePath {
    return nil; // TODO: Implement SSL certificate support
}

- (void)setSslCACertificatePath:(NSString *)sslCACertificatePath {
    // TODO: Implement SSL certificate support
}

- (NSString *)sslCipherList {
    return nil; // TODO: Implement SSL cipher configuration
}

- (void)setSslCipherList:(NSString *)sslCipherList {
    // TODO: Implement SSL cipher configuration
}

- (BOOL)useKeepAlive {
    return NO; // Not implemented for PostgreSQL
}

- (void)setUseKeepAlive:(BOOL)useKeepAlive {
    // No-op for PostgreSQL
}

- (CGFloat)keepAliveInterval {
    return 0.0; // Not implemented for PostgreSQL
}

- (void)setKeepAliveInterval:(CGFloat)keepAliveInterval {
    // No-op for PostgreSQL
}

- (BOOL)retryQueriesOnConnectionFailure {
    return NO; // Not implemented for PostgreSQL
}

- (void)setRetryQueriesOnConnectionFailure:(BOOL)retryQueriesOnConnectionFailure {
    // No-op for PostgreSQL
}

- (id<SPDatabaseConnectionProxy>)proxy {
    return nil; // Not implemented for PostgreSQL
}

- (void)setProxy:(id<SPDatabaseConnectionProxy>)proxy {
    // No-op for PostgreSQL
}

#pragma mark - Connection Management

- (BOOL)connect {
    if (_connected) {
        return YES;
    }
    
    const char *hostCStr = [_host UTF8String];
    const char *userCStr = [_username UTF8String];
    const char *passCStr = [_password UTF8String];
    const char *dbCStr = [_database UTF8String];
    
    if (!hostCStr || !userCStr || !passCStr || !dbCStr) {
        _lastErrorMessage = @"Missing required connection parameters (host, user, password, or database)";
        _lastErrorID = 1;
        _connected = NO;
        return NO;
    }
    
    _pgConnection = sp_postgresql_connection_create();
    
    if (_pgConnection == NULL) {
        _lastErrorMessage = @"Failed to create PostgreSQL connection object";
        _lastErrorID = 1;
        _connected = NO;
        return NO;
    }
    
    // Attempt to connect
    int result = sp_postgresql_connection_connect(_pgConnection, hostCStr, (int)_port, userCStr, passCStr, dbCStr, _useSSL ? 1 : 0);
    
    if (result == 0) {
        char *errorCStr = sp_postgresql_connection_last_error(_pgConnection);
        _lastErrorMessage = errorCStr ? [NSString stringWithUTF8String:errorCStr] : @"Unknown connection error";
        if (errorCStr) sp_postgresql_free_string(errorCStr);
        _lastErrorID = 2;
        sp_postgresql_connection_destroy(_pgConnection);
        _pgConnection = NULL;
        _connected = NO;
        return NO;
    }
    
    _connected = YES;
    _hasDisconnected = NO; // Reset disconnect flag on successful connection
    _lastErrorMessage = nil;
    _lastErrorID = 0;
    return YES;
}

- (void)disconnect {
    // Prevent double-disconnect by checking flag first
    if (_hasDisconnected) {
        return;
    }
    
    // Mark as disconnected first to prevent race conditions
    _connected = NO;
    _hasDisconnected = YES;
    
    if (_pgConnection != NULL) {
        // Call disconnect on the Rust side
        sp_postgresql_connection_disconnect(_pgConnection);
        
        // Destroy the connection object to free memory
        sp_postgresql_connection_destroy(_pgConnection);
        _pgConnection = NULL;
    }
}

- (BOOL)isConnected {
    if (_pgConnection == NULL) {
        return NO;
    }
    return sp_postgresql_connection_is_connected(_pgConnection) != 0;
}

- (BOOL)isConnectedViaSSL {
    // PostgreSQL SSL status - for now return based on useSSL property
    // In a full implementation, we'd query the connection for actual SSL status
    return _useSSL && [self isConnected];
}

- (BOOL)checkConnection {
    return [self isConnected];
}

- (BOOL)checkConnectionIfNecessary {
    return [self isConnected];
}

- (double)timeConnected {
    // TODO: Track connection time
    return 0.0;
}

- (BOOL)reconnect {
    [self disconnect];
    return [self connect];
}

- (NSString *)serverVersionString {
    if (![self isConnected]) {
        return nil;
    }
    
    id<SPDatabaseResult> result = [self queryString:@"SELECT version()"];
    if (!result || [result numberOfRows] == 0) {
        return @"Unknown";
    }
    
    NSArray *row = [result getRowAsArray];
    return row && [row count] > 0 ? row[0] : @"Unknown";
}

- (NSString *)databaseDisplayName {
    return @"PostgreSQL";
}

- (NSString *)shortServerVersionString {
    NSString *versionString = [self serverVersionString];
    if (!versionString || [versionString isEqualToString:@"Unknown"]) {
        return @"Unknown";
    }
    
    // PostgreSQL version format: "PostgreSQL 15.4 on aarch64-unknown-linux-musl, compiled by gcc..."
    // Extract just "15.4"
    NSRange postgresqlRange = [versionString rangeOfString:@"PostgreSQL" options:NSCaseInsensitiveSearch];
    if (postgresqlRange.location == NSNotFound) {
        return versionString;
    }
    
    // Find the version number after "PostgreSQL"
    NSString *afterPostgreSQL = [versionString substringFromIndex:postgresqlRange.location + postgresqlRange.length];
    afterPostgreSQL = [afterPostgreSQL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    // Extract version number (e.g., "15.4")
    NSRange onRange = [afterPostgreSQL rangeOfString:@" on "];
    if (onRange.location != NSNotFound) {
        return [afterPostgreSQL substringToIndex:onRange.location];
    }
    
    // Fallback: just get the first two components (major.minor)
    NSRange spaceRange = [afterPostgreSQL rangeOfString:@" "];
    if (spaceRange.location != NSNotFound) {
        return [afterPostgreSQL substringToIndex:spaceRange.location];
    }
    
    return afterPostgreSQL;
}

#pragma mark - Query Execution

- (id<SPDatabaseResult>)queryString:(NSString *)query {
    // Clear error state at the start of each query
    _lastErrorMessage = nil;
    _lastErrorID = 0;
    
    if (![self isConnected]) {
        _lastErrorMessage = @"Not connected to database";
        _lastErrorID = 100;
        return nil;
    }
    
    const char *queryCStr = [query UTF8String];
    SPPostgreSQLResult *pgResult = sp_postgresql_connection_execute_query(_pgConnection, queryCStr);
    
    if (pgResult == NULL) {
        char *errorCStr = sp_postgresql_connection_last_error(_pgConnection);
        _lastErrorMessage = errorCStr ? [NSString stringWithUTF8String:errorCStr] : @"Query execution failed";
        if (errorCStr) sp_postgresql_free_string(errorCStr);
        _lastErrorID = 101;
        return nil;
    }
    
    return [[SPPostgreSQLResultWrapper alloc] initWithPGResult:pgResult connection:self];
}

- (id<SPDatabaseResult>)streamingQueryString:(NSString *)query {
    // Use streaming query with default batch size
    return [self streamingQueryString:query useLowMemoryBlockingStreaming:NO];
}

- (id<SPDatabaseResult>)streamingQueryString:(NSString *)query useLowMemoryBlockingStreaming:(BOOL)fullStream {
    // Clear error state at the start of each query
    _lastErrorMessage = nil;
    _lastErrorID = 0;
    
    if (![self isConnected]) {
        _lastErrorMessage = @"Not connected to database";
        _lastErrorID = 100;
        return nil;
    }
    
    // Choose batch size based on streaming mode
    // fullStream = YES means low memory mode, use smaller batches
    NSUInteger batchSize = fullStream ? 500 : 1000;
    
    // Create streaming wrapper that will execute the query asynchronously when startDownload is called
    return [[SPPostgreSQLStreamingResultWrapper alloc] initWithQuery:query 
                                                          connection:self
                                                           batchSize:batchSize];
}

- (id)resultStoreFromQueryString:(NSString *)query {
    // Use streaming query to match MySQL behavior
    // This allows async loading, cancellation, and progress updates
    return [self streamingQueryString:query useLowMemoryBlockingStreaming:NO];
}

- (NSArray *)getAllRowsFromQuery:(NSString *)query {
    id<SPDatabaseResult> result = [self queryString:query];
    if (!result) return @[];
    return [result getAllRows];
}

- (id)getFirstFieldFromQuery:(NSString *)query {
    id<SPDatabaseResult> result = [self queryString:query];
    if (!result || [result numberOfRows] == 0) return nil;
    
    [result seekToRow:0];
    NSArray *row = [result getRowAsArray];
    if (!row || [row count] == 0) return nil;
    
    return row[0];
}

- (id<SPDatabaseResult>)listProcesses {
    // PostgreSQL equivalent: pg_stat_activity
    return [self queryString:@"SELECT pid, usename, application_name, client_addr, state, query FROM pg_stat_activity WHERE pid <> pg_backend_pid()"];
}

- (unsigned long long)rowsAffectedByLastQuery {
    // This is tracked differently in PostgreSQL
    // For now, return the value from affectedRows
    return [self affectedRows];
}

- (BOOL)queryErrored {
    return (_lastErrorID != 0);
}

#pragma mark - Error Handling

- (NSString *)lastErrorMessage {
    if (_lastErrorMessage) {
        return _lastErrorMessage;
    }
    
    if (_pgConnection != NULL) {
        char *errorCStr = sp_postgresql_connection_last_error(_pgConnection);
        if (errorCStr) {
            NSString *errorStr = [NSString stringWithUTF8String:errorCStr];
            sp_postgresql_free_string(errorCStr);
            return errorStr;
        }
    }
    
    return nil;
}

- (NSUInteger)lastErrorID {
    return _lastErrorID;
}

- (NSString *)lastSqlstate {
    return nil; // Not tracked via FFI for now
}

- (double)lastQueryExecutionTime {
    return 0.0; // Not tracked via FFI for now
}

- (BOOL)lastQueryWasCancelled {
    return NO; // Not tracked via FFI for now
}

- (void)setLastQueryWasCancelled:(BOOL)cancelled {
    // No-op for PostgreSQL
}

#pragma mark - Database Information

- (BOOL)selectDatabase:(NSString *)dbName {
    // In PostgreSQL, selecting a database requires reconnection
    // For now, just check if we're already on that database
    if ([_database isEqualToString:dbName]) {
        return YES;
    }
    
    // Would need to reconnect to switch databases
    _lastErrorMessage = [NSString stringWithFormat:@"Cannot select database '%@' without reconnecting. PostgreSQL requires a new connection to switch databases.", dbName];
    _lastErrorID = 100;
    return NO;
}

#pragma mark - Database Information

- (NSArray *)databases {
    id<SPDatabaseResult> result = [self queryString:@"SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname"];
    if (!result) {
        return @[];
    }
    
    NSUInteger rowCount = [result numberOfRows];
    NSMutableArray *databases = [NSMutableArray arrayWithCapacity:rowCount];
    for (NSUInteger i = 0; i < rowCount; i++) {
        [result seekToRow:i];
        NSArray *row = [result getRowAsArray];
        if (row && [row count] > 0 && row[0] != [NSNull null]) {
            [databases addObject:row[0]];
        }
    }
    
    return [databases copy];
}

- (NSArray *)tables {
    return [self tablesFromDatabase:_database];
}

- (NSArray *)tablesFromDatabase:(NSString *)database {
    NSString *query = @"SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename";
    id<SPDatabaseResult> result = [self queryString:query];
    if (!result) {
        return @[];
    }
    
    NSUInteger rowCount = [result numberOfRows];
    NSMutableArray *tables = [NSMutableArray arrayWithCapacity:rowCount];
    for (NSUInteger i = 0; i < rowCount; i++) {
        [result seekToRow:i];
        NSArray *row = [result getRowAsArray];
        if (row && [row count] > 0 && row[0] != [NSNull null]) {
            [tables addObject:row[0]];
        }
    }
    
    return [tables copy];
}

- (NSArray<NSString *> *)tablesOfType:(NSString *)tableType {
    // PostgreSQL has different table types: BASE TABLE, VIEW, etc.
    // Map MySQL types to PostgreSQL types
    NSString *pgType = @"BASE TABLE";
    if ([tableType isEqualToString:@"VIEW"]) {
        pgType = @"VIEW";
    }
    
    NSString *query = [NSString stringWithFormat:@"SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename NOT LIKE 'pg_%%' ORDER BY tablename"];
    id<SPDatabaseResult> result = [self queryString:query];
    if (!result) {
        return @[];
    }
    
    NSUInteger rowCount = [result numberOfRows];
    NSMutableArray *tables = [NSMutableArray arrayWithCapacity:rowCount];
    for (NSUInteger i = 0; i < rowCount; i++) {
        [result seekToRow:i];
        NSArray *row = [result getRowAsArray];
        if (row && [row count] > 0 && row[0] != [NSNull null]) {
            [tables addObject:row[0]];
        }
    }
    
    return [tables copy];
}

#pragma mark - Query Information

- (unsigned long long)affectedRows {
    // This would need to be tracked per query
    // For now, return 0
    return 0;
}

- (unsigned long long)lastInsertID {
    // PostgreSQL uses RETURNING clause or sequences
    // This is a simplified implementation
    id<SPDatabaseResult> result = [self queryString:@"SELECT lastval()"];
    if (!result || [result numberOfRows] == 0) {
        return 0;
    }
    
    NSArray *row = [result getRowAsArray];
    if (row && [row count] > 0 && row[0] != [NSNull null]) {
        return [row[0] unsignedLongLongValue];
    }
    
    return 0;
}

#pragma mark - Transactions

- (BOOL)beginTransaction {
    [self queryString:@"BEGIN"];
    return ![self queryErrored];
}

- (BOOL)commitTransaction {
    [self queryString:@"COMMIT"];
    return ![self queryErrored];
}

- (BOOL)rollbackTransaction {
    [self queryString:@"ROLLBACK"];
    return ![self queryErrored];
}

#pragma mark - String Escaping

- (NSString *)escapeString:(NSString *)theString {
    if (!theString) return @"";
    const char *inputCStr = [theString UTF8String];
    char *escapedCStr = sp_postgresql_escape_string(_pgConnection, inputCStr);
    if (escapedCStr) {
        NSString *escapedString = [NSString stringWithUTF8String:escapedCStr];
        sp_postgresql_free_string(escapedCStr);
        return escapedString;
    }
    return theString; // Fallback
}

- (NSString *)escapeString:(NSString *)string includingQuotes:(BOOL)includeQuotes {
    if (!string) return includeQuotes ? @"''" : @"";
    NSString *escaped = [self escapeString:string];
    return includeQuotes ? [NSString stringWithFormat:@"'%@'", escaped] : escaped;
}

- (NSString *)escapeAndQuoteString:(NSString *)theString {
    return [NSString stringWithFormat:@"'%@'", [self escapeString:theString]];
}

- (NSString *)escapeData:(NSData *)theData {
    // For now, convert data to string and escape.
    // A more robust solution might involve bytea encoding.
    NSString *dataAsString = [[NSString alloc] initWithData:theData encoding:NSUTF8StringEncoding];
    return [self escapeString:dataAsString];
}

- (NSString *)escapeData:(NSData *)data includingQuotes:(BOOL)includeQuotes {
    if (!data) return includeQuotes ? @"''" : @"";
    NSString *escaped = [self escapeData:data];
    return includeQuotes ? [NSString stringWithFormat:@"'%@'", escaped] : escaped;
}

- (NSString *)escapeAndQuoteData:(NSData *)theData {
    return [NSString stringWithFormat:@"'%@'", [self escapeData:theData]];
}

#pragma mark - Connection State

- (NSString *)encoding {
    id<SPDatabaseResult> result = [self queryString:@"SHOW client_encoding"];
    if (!result || [result numberOfRows] == 0) {
        return @"UTF8";
    }
    
    NSArray *row = [result getRowAsArray];
    return row && [row count] > 0 ? row[0] : @"UTF8";
}

- (BOOL)setEncoding:(NSString *)encoding {
    NSString *query = [NSString stringWithFormat:@"SET client_encoding TO '%@'", [self escapeString:encoding]];
    [self queryString:query];
    return ![self queryErrored];
}

- (NSString *)preferredUTF8Encoding {
    // PostgreSQL uses UTF8 (or UNICODE) as the standard UTF-8 encoding
    return @"UTF8";
}

- (NSArray *)getAvailableEncodings {
    // PostgreSQL: Query pg_catalog.pg_encoding for available encodings
    // Note: PostgreSQL doesn't expose encodings the same way MySQL does
    // Return current encoding as the only "available" one to avoid errors
    NSString *currentEncoding = [self encoding];
    if (!currentEncoding) {
        currentEncoding = @"UTF8";
    }
    
    // Return a single encoding in MySQL-compatible format
    return @[@{
        @"Charset": currentEncoding,
        @"Description": [NSString stringWithFormat:@"PostgreSQL %@ encoding", currentEncoding],
        @"Default collation": @"default",
        @"Maxlen": @"4"
    }];
}

- (NSArray *)getCollationsForEncoding:(NSString *)encoding {
    if (!encoding) return @[];
    
    // PostgreSQL: Return a default collation for the encoding
    // PostgreSQL uses LC_COLLATE which is set at database creation
    // Return a synthetic collation in MySQL-compatible format
    id<SPDatabaseResult> result = [self queryString:@"SHOW LC_COLLATE"];
    NSString *collation = @"default";
    
    if (result && [result numberOfRows] > 0) {
        [result setReturnDataAsStrings:YES];
        NSDictionary *row = [result getRowAsDictionary];
        NSArray *values = [row allValues];
        if (values.count > 0) {
            collation = values[0];
        }
    }
    
    // Return a single collation in MySQL-compatible format
    return @[@{
        @"COLLATION_NAME": collation,
        @"CHARACTER_SET_NAME": encoding,
        @"IS_DEFAULT": @"YES",
        @"IS_COMPILED": @"YES",
        @"SORTLEN": @"1"
    }];
}

- (NSArray *)getDatabaseStorageEngines {
    // PostgreSQL doesn't have storage engines like MySQL (InnoDB, MyISAM, etc.)
    // Return empty array
    return @[];
}

- (void)storeEncodingForRestoration {
    // TODO: Implement encoding restoration support
}

- (void)restoreStoredEncoding {
    // TODO: Implement encoding restoration support
}

- (NSStringEncoding)stringEncoding {
    // Return UTF8 as default for PostgreSQL
    return NSUTF8StringEncoding;
}

- (NSString *)serverInfo {
    return [self serverVersionString];
}

- (NSInteger)serverMajorVersion {
    NSString *versionString = [self serverVersionString];
    if (!versionString || [versionString isEqualToString:@"Unknown"]) {
        return 0;
    }
    
    // PostgreSQL version format: "PostgreSQL 15.4 on ..."
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"PostgreSQL (\\d+)\\." options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:versionString options:0 range:NSMakeRange(0, [versionString length])];
    if (match && match.numberOfRanges > 1) {
        return [[versionString substringWithRange:[match rangeAtIndex:1]] integerValue];
    }
    return 0;
}

- (NSInteger)serverMinorVersion {
    NSString *versionString = [self serverVersionString];
    if (!versionString || [versionString isEqualToString:@"Unknown"]) {
        return 0;
    }
    
    // PostgreSQL version format: "PostgreSQL 15.4 on ..."
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"PostgreSQL \\d+\\.(\\d+)" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:versionString options:0 range:NSMakeRange(0, [versionString length])];
    if (match && match.numberOfRanges > 1) {
        return [[versionString substringWithRange:[match rangeAtIndex:1]] integerValue];
    }
    return 0;
}

- (NSInteger)serverReleaseVersion {
    // PostgreSQL typically doesn't have a third version number in the display
    return 0;
}

- (NSString *)getServerVariableValue:(NSString *)variableName {
    // PostgreSQL: Map MySQL variable names to PostgreSQL equivalents
    id<SPDatabaseResult> result = nil;
    
    if ([variableName isEqualToString:@"character_set_database"]) {
        result = [self queryString:@"SHOW client_encoding"];
    } else if ([variableName isEqualToString:@"collation_database"]) {
        result = [self queryString:@"SHOW LC_COLLATE"];
    } else if ([variableName isEqualToString:@"character_set_server"]) {
        result = [self queryString:@"SHOW server_encoding"];
    } else if ([variableName isEqualToString:@"collation_server"]) {
        result = [self queryString:@"SHOW LC_COLLATE"];
    } else {
        // For other variables, try SHOW command directly
        NSString *query = [NSString stringWithFormat:@"SHOW %@", variableName];
        result = [self queryString:query];
    }
    
    if (!result || [self queryErrored] || [result numberOfRows] != 1) {
        return nil;
    }
    
    [result setReturnDataAsStrings:YES];
    
    // PostgreSQL SHOW returns a single column with the value
    NSDictionary *row = [result getRowAsDictionary];
    NSArray *values = [row allValues];
    return values.count > 0 ? values[0] : nil;
}

- (NSArray<NSDictionary *> *)getTableInfo:(BOOL)includeComments {
    // PostgreSQL: Query pg_tables and pg_views with optional pg_description for comments
    NSMutableArray *tableInfo = [NSMutableArray array];
    
    // Query tables
    NSString *tablesQuery;
    if (includeComments) {
        tablesQuery = @"SELECT "
                      @"  t.tablename AS \"Name\", "
                      @"  'BASE TABLE' AS \"Table_type\", "
                      @"  COALESCE(obj_description((quote_ident(t.schemaname) || '.' || quote_ident(t.tablename))::regclass), '') AS \"Comment\" "
                      @"FROM pg_tables t "
                      @"WHERE t.schemaname = 'public' "
                      @"ORDER BY t.tablename";
    } else {
        tablesQuery = @"SELECT "
                      @"  tablename AS \"Name\", "
                      @"  'BASE TABLE' AS \"Table_type\" "
                      @"FROM pg_tables "
                      @"WHERE schemaname = 'public' "
                      @"ORDER BY tablename";
    }
    
    id<SPDatabaseResult> result = [self queryString:tablesQuery];
    if (result && ![self queryErrored]) {
        [result setReturnDataAsStrings:YES];
        [result setDefaultRowReturnType:SPDatabaseResultRowAsDictionary];
        
        for (NSDictionary *row in result) {
            [tableInfo addObject:row];
        }
    }
    
    // Query views
    NSString *viewsQuery;
    if (includeComments) {
        viewsQuery = @"SELECT "
                     @"  v.viewname AS \"Name\", "
                     @"  'VIEW' AS \"Table_type\", "
                     @"  COALESCE(obj_description((quote_ident(v.schemaname) || '.' || quote_ident(v.viewname))::regclass), '') AS \"Comment\" "
                     @"FROM pg_views v "
                     @"WHERE v.schemaname = 'public' "
                     @"ORDER BY v.viewname";
    } else {
        viewsQuery = @"SELECT "
                     @"  viewname AS \"Name\", "
                     @"  'VIEW' AS \"Table_type\" "
                     @"FROM pg_views "
                     @"WHERE schemaname = 'public' "
                     @"ORDER BY viewname";
    }
    
    result = [self queryString:viewsQuery];
    if (result && ![self queryErrored]) {
        [result setReturnDataAsStrings:YES];
        [result setDefaultRowReturnType:SPDatabaseResultRowAsDictionary];
        
        for (NSDictionary *row in result) {
            [tableInfo addObject:row];
        }
    }
    
    return [tableInfo copy];
}

- (NSString *)identifierQuoteCharacter {
    // PostgreSQL uses double quotes for identifiers
    return @"\"";
}

- (NSString *)quoteIdentifier:(NSString *)identifier {
    if (!identifier) return @"\"\"";
    // Escape any double quotes in the identifier by doubling them
    NSString *escaped = [identifier stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}

- (NSString *)buildLimitClause:(NSUInteger)count offset:(NSUInteger)offset {
    // PostgreSQL uses: LIMIT count OFFSET offset
    return [NSString stringWithFormat:@"LIMIT %lu OFFSET %lu", (unsigned long)count, (unsigned long)offset];
}

- (BOOL)supportsFeature:(NSString *)feature {
    // Basic feature support for PostgreSQL
    if ([feature isEqualToString:@"triggers"]) return YES;
    if ([feature isEqualToString:@"functions"]) return YES;
    if ([feature isEqualToString:@"views"]) return YES;
    if ([feature isEqualToString:@"stored_procedures"]) return YES;
    // Events are MySQL-specific
    if ([feature isEqualToString:@"events"]) return NO;
    return NO;
}

- (void)lock {
    // PostgreSQL connection locking not implemented
    // Would use mutexes if needed
}

- (void)unlock {
    // PostgreSQL connection unlocking not implemented
}

- (NSUInteger)maxQuerySize {
    // PostgreSQL doesn't have a hard query size limit like MySQL
    // Return a reasonable default
    return 16777216; // 16 MB
}

- (BOOL)isMaxQuerySizeEditable {
    return NO; // PostgreSQL doesn't have max_allowed_packet equivalent
}

- (BOOL)setMaxQuerySize:(NSUInteger)size {
    // PostgreSQL doesn't have max_allowed_packet equivalent
    return NO;
}

- (id)copy {
    // Create a new wrapper with the same connection details
    SPPostgreSQLConnectionWrapper *newConnection = [[SPPostgreSQLConnectionWrapper alloc] init];
    newConnection.host = self.host;
    newConnection.port = self.port;
    newConnection.username = self.username;
    newConnection.password = self.password;
    newConnection.database = self.database;
    newConnection.useSSL = self.useSSL;
    newConnection.timeout = self.timeout;
    return newConnection;
}

- (id)copyWithZone:(NSZone *)zone {
    return [self copy];
}

#pragma mark - Table Structure and Metadata

- (id<SPDatabaseResult>)getCreateTableStatement:(NSString *)tableName fromDatabase:(NSString *)database {
    // PostgreSQL doesn't have SHOW CREATE TABLE
    // We need to build a CREATE TABLE statement from information_schema
    
    // IMPORTANT: In PostgreSQL, the "database" parameter refers to the database you're connected to,
    // NOT the schema. We need to query for the current schema from search_path.
    // The database parameter is ignored for PostgreSQL (unlike MySQL where database == schema)
    
    NSString *schemaName = nil;
    
    // Get current schema from search_path
    id<SPDatabaseResult> schemaResult = [self queryString:@"SELECT current_schema()"];
    if (schemaResult && [schemaResult numberOfRows] > 0) {
        NSArray *row = [schemaResult getRowAsArray];
        if (row && [row count] > 0) {
            schemaName = row[0];
        }
    }
    if (!schemaName || [schemaName isKindOfClass:[NSNull class]]) {
        schemaName = @"public";
    }
    
    // First, get column information
    // PostgreSQL converts unquoted identifiers to lowercase, so we need to search case-insensitively
    NSString *columnsQuery = [NSString stringWithFormat:
        @"SELECT "
        @"  c.column_name, "
        @"  c.data_type, "
        @"  c.character_maximum_length, "
        @"  c.numeric_precision, "
        @"  c.numeric_scale, "
        @"  c.is_nullable, "
        @"  c.column_default, "
        @"  c.udt_name "
        @"FROM information_schema.columns c "
        @"WHERE LOWER(c.table_schema) = LOWER('%@') AND LOWER(c.table_name) = LOWER('%@') "
        @"ORDER BY c.ordinal_position",
        [schemaName stringByReplacingOccurrencesOfString:@"'" withString:@"''"],
        [tableName stringByReplacingOccurrencesOfString:@"'" withString:@"''"]];
    
    if (_pgConnection == NULL || !_connected) {
        return nil;
    }
    
    SPPostgreSQLResult *columnsResult = sp_postgresql_connection_execute_query(_pgConnection, [columnsQuery UTF8String]);
    if (columnsResult == NULL) {
        _lastErrorMessage = [self lastErrorMessage];
        NSLog(@"getCreateTableStatement: columnsResult is NULL");
        return nil;
    }
    
    // Build CREATE TABLE statement
    NSMutableString *createTableSQL = [NSMutableString stringWithFormat:@"CREATE TABLE \"%@\" (\n", tableName];
    
    // Wrap the result
    SPPostgreSQLResultWrapper *columnsWrapper = [[SPPostgreSQLResultWrapper alloc] initWithPGResult:columnsResult connection:self];
    [columnsWrapper setReturnDataAsStrings:YES];
    
    BOOL firstColumn = YES;
    NSDictionary *row;
    while ((row = [columnsWrapper getRowAsDictionary]) != nil) {
        if (!firstColumn) {
            [createTableSQL appendString:@",\n"];
        }
        firstColumn = NO;
        
        // Get column attributes, handling NSNull properly
        id columnNameObj = [row objectForKey:@"column_name"];
        id dataTypeObj = [row objectForKey:@"data_type"];
        id isNullableObj = [row objectForKey:@"is_nullable"];
        id columnDefaultObj = [row objectForKey:@"column_default"];
        id charMaxLengthObj = [row objectForKey:@"character_maximum_length"];
        
        NSString *columnName = ([columnNameObj isKindOfClass:[NSNull class]] || !columnNameObj) ? @"unknown" : columnNameObj;
        NSString *dataType = ([dataTypeObj isKindOfClass:[NSNull class]] || !dataTypeObj) ? @"text" : dataTypeObj;
        NSString *isNullable = ([isNullableObj isKindOfClass:[NSNull class]] || !isNullableObj) ? @"YES" : isNullableObj;
        NSString *columnDefault = ([columnDefaultObj isKindOfClass:[NSNull class]] || !columnDefaultObj) ? nil : columnDefaultObj;
        NSString *charMaxLength = ([charMaxLengthObj isKindOfClass:[NSNull class]] || !charMaxLengthObj) ? nil : charMaxLengthObj;
        
        // Build column type string
        NSString *fullType = dataType;
        if (charMaxLength && ![charMaxLength isEqualToString:@""]) {
            fullType = [NSString stringWithFormat:@"%@(%@)", dataType, charMaxLength];
        }
        
        // Build column definition
        [createTableSQL appendFormat:@"  \"%@\" %@", columnName, fullType];
        
        // Add NOT NULL if applicable
        if ([isNullable isEqualToString:@"NO"]) {
            [createTableSQL appendString:@" NOT NULL"];
        }
        
        // Add DEFAULT if present
        if (columnDefault && ![columnDefault isEqualToString:@""]) {
            [createTableSQL appendFormat:@" DEFAULT %@", columnDefault];
        }
    }
    
    [createTableSQL appendString:@"\n)"];
    
    // Create a synthetic result that mimics MySQL's SHOW CREATE TABLE format
    // Return format: [tableName, CREATE TABLE statement]
    // Use PostgreSQL dollar quoting to avoid escaping issues with the CREATE TABLE statement
    NSString *escapedTableName = [tableName stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
    NSString *syntheticQuery = [NSString stringWithFormat:@"SELECT '%@' AS \"Table\", $$%@$$ AS \"Create Table\"",
                                escapedTableName,
                                createTableSQL];
    
    SPPostgreSQLResult *syntheticResult = sp_postgresql_connection_execute_query(_pgConnection, [syntheticQuery UTF8String]);
    if (syntheticResult == NULL) {
        return nil;
    }
    
    return [[SPPostgreSQLResultWrapper alloc] initWithPGResult:syntheticResult connection:self];
}

- (id<SPDatabaseResult>)getColumnsForTable:(NSString *)tableName {
    // PostgreSQL equivalent of SHOW COLUMNS FROM
    // Get current schema
    NSString *schemaName = @"public";
    id<SPDatabaseResult> schemaResult = [self queryString:@"SELECT current_schema()"];
    if (schemaResult && [schemaResult numberOfRows] > 0) {
        NSArray *row = [schemaResult getRowAsArray];
        if (row && [row count] > 0 && ![row[0] isKindOfClass:[NSNull class]]) {
            schemaName = row[0];
        }
    }
    
    NSString *query = [NSString stringWithFormat:
        @"SELECT "
        @"  column_name AS \"Field\", "
        @"  data_type AS \"Type\", "
        @"  is_nullable AS \"Null\", "
        @"  column_default AS \"Default\", "
        @"  '' AS \"Extra\" "
        @"FROM information_schema.columns "
        @"WHERE LOWER(table_schema) = LOWER('%@') AND LOWER(table_name) = LOWER('%@') "
        @"ORDER BY ordinal_position",
        [schemaName stringByReplacingOccurrencesOfString:@"'" withString:@"''"],
        [tableName stringByReplacingOccurrencesOfString:@"'" withString:@"''"]];
    
    if (_pgConnection == NULL || !_connected) {
        return nil;
    }
    
    SPPostgreSQLResult *rawResult = sp_postgresql_connection_execute_query(_pgConnection, [query UTF8String]);
    if (rawResult == NULL) {
        _lastErrorMessage = [self lastErrorMessage];
        return nil;
    }
    
    return [[SPPostgreSQLResultWrapper alloc] initWithPGResult:rawResult connection:self];
}

- (id<SPDatabaseResult>)getTableStatus:(NSString *)tableName {
    // PostgreSQL equivalent of SHOW TABLE STATUS
    // Query pg_catalog for table metadata
    
    // Get current schema
    NSString *schemaName = @"public";
    id<SPDatabaseResult> schemaResult = [self queryString:@"SELECT current_schema()"];
    if (schemaResult && [schemaResult numberOfRows] > 0) {
        NSArray *row = [schemaResult getRowAsArray];
        if (row && [row count] > 0 && ![row[0] isKindOfClass:[NSNull class]]) {
            schemaName = row[0];
        }
    }
    
    // Escape single quotes for SQL string literals
    NSString *escapedTableName = [tableName stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
    NSString *escapedSchemaName = [schemaName stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
    
    NSString *query = [NSString stringWithFormat:
        @"SELECT "
        @"  t.tablename AS \"Name\", "
        @"  'BASE TABLE' AS \"Engine\", "
        @"  pg_total_relation_size(quote_ident(t.schemaname)||'.'||quote_ident(t.tablename)) AS \"Data_length\", "
        @"  (SELECT COUNT(*) FROM \"%@\".\"%@\") AS \"Rows\", "
        @"  pg_size_pretty(pg_total_relation_size(quote_ident(t.schemaname)||'.'||quote_ident(t.tablename))) AS \"Size\", "
        @"  obj_description((quote_ident(t.schemaname)||'.'||quote_ident(t.tablename))::regclass) AS \"Comment\", "
        @"  CURRENT_TIMESTAMP AS \"Create_time\", "
        @"  CURRENT_TIMESTAMP AS \"Update_time\" "
        @"FROM pg_tables t "
        @"WHERE LOWER(t.schemaname) = LOWER('%@') AND LOWER(t.tablename) = LOWER('%@')",
        schemaName,
        tableName,
        escapedSchemaName,
        escapedTableName];
    
    if (_pgConnection == NULL || !_connected) {
        return nil;
    }
    
    SPPostgreSQLResult *rawResult = sp_postgresql_connection_execute_query(_pgConnection, [query UTF8String]);
    if (rawResult == NULL) {
        _lastErrorMessage = [self lastErrorMessage];
        return nil;
    }
    
    return [[SPPostgreSQLResultWrapper alloc] initWithPGResult:rawResult connection:self];
}

- (id<SPDatabaseResult>)getTriggersForTable:(NSString *)tableName {
    // PostgreSQL equivalent of SHOW TRIGGERS
    
    // Get current schema
    NSString *schemaName = @"public";
    id<SPDatabaseResult> schemaResult = [self queryString:@"SELECT current_schema()"];
    if (schemaResult && [schemaResult numberOfRows] > 0) {
        NSArray *row = [schemaResult getRowAsArray];
        if (row && [row count] > 0 && ![row[0] isKindOfClass:[NSNull class]]) {
            schemaName = row[0];
        }
    }
    
    NSString *query = [NSString stringWithFormat:
        @"SELECT "
        @"  trigger_name AS \"Trigger\", "
        @"  event_manipulation AS \"Event\", "
        @"  event_object_table AS \"Table\", "
        @"  action_statement AS \"Statement\", "
        @"  action_timing AS \"Timing\", "
        @"  created AS \"Created\" "
        @"FROM information_schema.triggers "
        @"WHERE LOWER(event_object_schema) = LOWER('%@') AND LOWER(event_object_table) = LOWER('%@')",
        [schemaName stringByReplacingOccurrencesOfString:@"'" withString:@"''"],
        [tableName stringByReplacingOccurrencesOfString:@"'" withString:@"''"]];
    
    if (_pgConnection == NULL || !_connected) {
        return nil;
    }
    
    SPPostgreSQLResult *rawResult = sp_postgresql_connection_execute_query(_pgConnection, [query UTF8String]);
    if (rawResult == NULL) {
        _lastErrorMessage = [self lastErrorMessage];
        return nil;
    }
    
    return [[SPPostgreSQLResultWrapper alloc] initWithPGResult:rawResult connection:self];
}

- (id<SPDatabaseResult>)getIndexesForTable:(NSString *)tableName {
    // PostgreSQL equivalent of SHOW INDEX
    
    // Get current schema
    NSString *schemaName = @"public";
    id<SPDatabaseResult> schemaResult = [self queryString:@"SELECT current_schema()"];
    if (schemaResult && [schemaResult numberOfRows] > 0) {
        NSArray *row = [schemaResult getRowAsArray];
        if (row && [row count] > 0 && ![row[0] isKindOfClass:[NSNull class]]) {
            schemaName = row[0];
        }
    }
    
    // Query to get index information in a MySQL-compatible format
    NSString *query = [NSString stringWithFormat:
        @"SELECT "
        @"  t.relname AS \"Table\", "
        @"  CASE WHEN ix.indisunique THEN 0 ELSE 1 END AS \"Non_unique\", "
        @"  i.relname AS \"Key_name\", "
        @"  a.attnum AS \"Seq_in_index\", "
        @"  a.attname AS \"Column_name\", "
        @"  NULL AS \"Collation\", "
        @"  NULL AS \"Cardinality\", "
        @"  NULL AS \"Sub_part\", "
        @"  NULL AS \"Packed\", "
        @"  CASE WHEN a.attnotnull THEN '' ELSE 'YES' END AS \"Null\", "
        @"  am.amname AS \"Index_type\", "
        @"  '' AS \"Comment\", "
        @"  '' AS \"Index_comment\" "
        @"FROM pg_class t "
        @"JOIN pg_index ix ON t.oid = ix.indrelid "
        @"JOIN pg_class i ON i.oid = ix.indexrelid "
        @"JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey) "
        @"JOIN pg_am am ON i.relam = am.oid "
        @"JOIN pg_namespace n ON t.relnamespace = n.oid "
        @"WHERE LOWER(n.nspname) = LOWER('%@') AND LOWER(t.relname) = LOWER('%@') "
        @"ORDER BY i.relname, a.attnum",
        [schemaName stringByReplacingOccurrencesOfString:@"'" withString:@"''"],
        [tableName stringByReplacingOccurrencesOfString:@"'" withString:@"''"]];
    
    if (_pgConnection == NULL || !_connected) {
        return nil;
    }
    
    SPPostgreSQLResult *rawResult = sp_postgresql_connection_execute_query(_pgConnection, [query UTF8String]);
    if (rawResult == NULL) {
        _lastErrorMessage = [self lastErrorMessage];
        return nil;
    }
    
    return [[SPPostgreSQLResultWrapper alloc] initWithPGResult:rawResult connection:self];
}

#pragma mark - MySQL-Specific Methods (Stubs for PostgreSQL)

- (BOOL)serverShutdown {
    // PostgreSQL doesn't support shutting down from a client connection
    // This would require pg_ctl or similar system-level commands
    NSLog(@"Warning: serverShutdown is not supported for PostgreSQL connections");
    return NO;
}

- (void)cancelCurrentQuery {
    // PostgreSQL query cancellation would use pg_cancel_backend
    // For now, this is a stub
    NSLog(@"Warning: cancelCurrentQuery not yet implemented for PostgreSQL");
}

- (BOOL)killQueryOnThreadID:(unsigned long)theThreadID {
    // PostgreSQL uses pg_cancel_backend(pid) or pg_terminate_backend(pid)
    // For now, this is a stub
    NSLog(@"Warning: killQueryOnThreadID not yet implemented for PostgreSQL");
    return NO;
}

- (void)setEncodingUsesLatin1Transport:(BOOL)useLatin1 {
    // This is MySQL-specific and doesn't apply to PostgreSQL
    // PostgreSQL handles encodings differently
    // No-op for PostgreSQL
}

@end

