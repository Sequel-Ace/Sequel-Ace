//
//  SPMySQLConnectionWrapper.m
//  Sequel Ace
//

#import "SPMySQLConnectionWrapper.h"
#import <SPMySQL/SPMySQL.h>

@implementation SPMySQLConnectionWrapper {
    SPMySQLConnection *_connection;
}

- (instancetype)initWithConnection:(SPMySQLConnection *)connection {
    if (self = [super init]) {
        _connection = connection;
    }
    return self;
}

- (SPMySQLConnection *)underlyingConnection {
    return _connection;
}

+ (NSUInteger)defaultPort { return 3306; }

// ─── Connectivity ────────────────────────────────────────────────────────────

- (BOOL)connect    { return [_connection connect]; }
- (void)disconnect { [_connection disconnect]; }
- (BOOL)isConnected { return [_connection isConnected]; }
- (BOOL)isConnectedViaSSL { return [_connection isConnectedViaSSL]; }

// ─── Configuration ───────────────────────────────────────────────────────────

- (void)setUsername:(NSString *)u { [_connection setUsername:u]; }
- (void)setPassword:(NSString *)p { [_connection setPassword:p]; }
- (void)setHost:(NSString *)h     { [_connection setHost:h]; }
- (void)setPort:(NSUInteger)port  { [_connection setPort:port]; }
- (void)setDatabase:(NSString *)db { [_connection setDatabase:db]; }
- (void)setTimeout:(NSUInteger)t  { [_connection setTimeout:t]; }
- (void)setUseSSL:(BOOL)ssl       { [_connection setUseSSL:ssl]; }

- (void)setDelegate:(id<SPDatabaseConnectionProxy>)delegate {
    // SPMySQLConnection uses its own SPMySQLConnectionDelegate protocol.
    // SPDatabaseDocument already conforms to both, so a direct cast is safe.
    [_connection setDelegate:(id<SPMySQLConnectionDelegate>)delegate];
}

// ─── Database selection ───────────────────────────────────────────────────────

- (BOOL)selectDatabase:(NSString *)aDatabase { return [_connection selectDatabase:aDatabase]; }
- (NSArray *)databases { return [_connection databases]; }

// ─── Querying ────────────────────────────────────────────────────────────────

- (id<SPDatabaseResult>)queryString:(NSString *)query {
    return (id<SPDatabaseResult>)[_connection queryString:query];
}

- (id)streamingQueryString:(NSString *)query {
    return [_connection streamingQueryString:query];
}

- (id)streamingQueryString:(NSString *)query useLowMemoryBlockingStreaming:(BOOL)full {
    return [_connection streamingQueryString:query useLowMemoryBlockingStreaming:full];
}

- (BOOL)queryErrored { return [_connection queryErrored]; }
- (NSString *)lastErrorMessage { return [_connection lastErrorMessage]; }
- (NSUInteger)lastErrorID { return [_connection lastErrorID]; }
- (unsigned long long)rowsAffectedByLastQuery { return [_connection rowsAffectedByLastQuery]; }
- (unsigned long long)lastInsertID { return [_connection lastInsertID]; }
- (void)cancelCurrentQuery { [_connection cancelCurrentQuery]; }

// ─── Encoding ────────────────────────────────────────────────────────────────

- (NSString *)encoding { return [_connection encoding]; }
- (BOOL)setEncoding:(NSString *)enc { return [_connection setEncoding:enc]; }
- (void)storeEncodingForRestoration { [_connection storeEncodingForRestoration]; }
- (void)restoreStoredEncoding { [_connection restoreStoredEncoding]; }

- (NSString *)preferredUTF8Encoding {
    // Prefer utf8mb4 on MySQL 5.5.3+, fall back to utf8.
    if ([_connection serverVersionIsGreaterThanOrEqualTo:5 minorVersion:5 releaseVersion:3]) {
        return @"utf8mb4";
    }
    return @"utf8";
}

// ─── Server info ─────────────────────────────────────────────────────────────

- (NSString *)serverVersionString { return [_connection serverVersionString]; }
- (NSUInteger)serverMajorVersion  { return [_connection serverMajorVersion]; }
- (NSUInteger)serverMinorVersion  { return [_connection serverMinorVersion]; }
- (NSUInteger)serverReleaseVersion { return [_connection serverReleaseVersion]; }

- (BOOL)serverVersionIsGreaterThanOrEqualTo:(NSUInteger)major minorVersion:(NSUInteger)minor releaseVersion:(NSUInteger)release {
    return [_connection serverVersionIsGreaterThanOrEqualTo:major minorVersion:minor releaseVersion:release];
}

- (NSString *)getServerVariableValue:(NSString *)variable {
    NSString *query = [NSString stringWithFormat:@"SHOW VARIABLES LIKE '%@'", variable];
    id result = [_connection queryString:query];
    if (result && [result respondsToSelector:@selector(getRowAsArray)]) {
        NSArray *row = [result getRowAsArray];
        if (row.count >= 2) return row[1];
    }
    return nil;
}

// ─── Collation helpers ────────────────────────────────────────────────────────

- (NSArray *)getCollationsForEncoding:(NSString *)encoding {
    // Return empty; callers fall back to the existing MySQL-specific query path.
    return @[];
}

// ─── Backend type ─────────────────────────────────────────────────────────────

- (BOOL)isPostgreSQL { return NO; }
- (NSString *)identifierQuoteCharacter { return @"`"; }

@end
