//
//  SPDatabaseConnection.h
//  Sequel Ace
//
//  Protocol abstracting SPMySQLConnection and SPPostgreSQLConnectionWrapper.
//  Controllers that previously held `SPMySQLConnection *mySQLConnection`
//  should change the ivar type to `id<SPDatabaseConnection>`.
//

#import <Foundation/Foundation.h>
#import "SPDatabaseResult.h"
#import "SPDatabaseConnectionProxy.h"

@protocol SPDatabaseConnection <NSObject>

// ─── Connectivity ────────────────────────────────────────────────────────────

- (BOOL)connect;
- (void)disconnect;
- (BOOL)isConnected;
- (BOOL)isConnectedViaSSL;

// ─── Configuration ───────────────────────────────────────────────────────────

- (void)setUsername:(NSString *)username;
- (void)setPassword:(NSString *)password;
- (void)setHost:(NSString *)host;
- (void)setPort:(NSUInteger)port;
- (void)setDatabase:(NSString *)database;
- (void)setTimeout:(NSUInteger)timeout;
- (void)setUseSSL:(BOOL)useSSL;
- (void)setDelegate:(id<SPDatabaseConnectionProxy>)delegate;

// ─── Database selection ───────────────────────────────────────────────────────

- (BOOL)selectDatabase:(NSString *)aDatabase;
- (NSArray *)databases;

// ─── Querying ────────────────────────────────────────────────────────────────

- (id<SPDatabaseResult>)queryString:(NSString *)query;
- (id)streamingQueryString:(NSString *)query;
- (id)streamingQueryString:(NSString *)query useLowMemoryBlockingStreaming:(BOOL)fullStreaming;

// Query state
- (BOOL)queryErrored;
- (NSString *)lastErrorMessage;
- (NSUInteger)lastErrorID;
- (unsigned long long)rowsAffectedByLastQuery;
- (unsigned long long)lastInsertID;
- (void)cancelCurrentQuery;

// ─── Encoding (MySQL-specific; PostgreSQL provides stubs) ─────────────────────

- (NSString *)encoding;
- (BOOL)setEncoding:(NSString *)encoding;
- (void)storeEncodingForRestoration;
- (void)restoreStoredEncoding;

/// UTF-8 encoding name appropriate for this backend ("utf8mb4" for MySQL, "UTF8" for PostgreSQL).
- (NSString *)preferredUTF8Encoding;

// ─── Server info ─────────────────────────────────────────────────────────────

- (NSString *)serverVersionString;
- (NSUInteger)serverMajorVersion;
- (NSUInteger)serverMinorVersion;
- (NSUInteger)serverReleaseVersion;
- (BOOL)serverVersionIsGreaterThanOrEqualTo:(NSUInteger)major minorVersion:(NSUInteger)minor releaseVersion:(NSUInteger)release;

/// Returns the value of a server variable, or nil if not applicable / not found.
- (NSString *)getServerVariableValue:(NSString *)variable;

// ─── Collation helpers ────────────────────────────────────────────────────────

/// Returns an array of collation dictionaries for the given encoding,
/// or an empty array when not applicable (PostgreSQL).
- (NSArray *)getCollationsForEncoding:(NSString *)encoding;

// ─── Backend type ─────────────────────────────────────────────────────────────

/// YES when this connection is a PostgreSQL connection.
- (BOOL)isPostgreSQL;

/// The quoting character for identifiers: backtick for MySQL, double-quote for PostgreSQL.
- (NSString *)identifierQuoteCharacter;

@end
