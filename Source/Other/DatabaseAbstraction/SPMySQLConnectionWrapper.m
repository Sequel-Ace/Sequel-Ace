//
//  SPMySQLConnectionWrapper.m
//  sequel-ace
//
//  Created by Sequel Ace on 2024.
//  Copyright (c) 2024 Sequel Ace. All rights reserved.
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

#import "SPMySQLConnectionWrapper.h"
#import "SPMySQLResultWrapper.h"
#import "SPConstants.h"
#import <SPMySQL/SPMySQL.h>
#import "RegexKitLite.h"

@implementation SPMySQLConnectionWrapper

@synthesize mysqlConnection = _mysqlConnection;

#pragma mark - Initialization

- (instancetype)init {
    if ((self = [super init])) {
        _mysqlConnection = [[SPMySQLConnection alloc] init];
    }
    return self;
}

- (instancetype)initWithConnection:(SPMySQLConnection *)connection {
    if ((self = [super init])) {
        _mysqlConnection = connection;
    }
    return self;
}

#pragma mark - Database Type

- (NSUInteger)databaseType {
    return (NSUInteger)SPDatabaseTypeMySQL;
}

+ (NSUInteger)defaultPort {
    return 3306;
}

#pragma mark - Connection Properties

- (NSString *)host {
    return [_mysqlConnection host];
}

- (void)setHost:(NSString *)host {
    [_mysqlConnection setHost:host];
}

- (NSString *)username {
    return [_mysqlConnection username];
}

- (void)setUsername:(NSString *)username {
    [_mysqlConnection setUsername:username];
}

- (NSString *)password {
    return [_mysqlConnection password];
}

- (void)setPassword:(NSString *)password {
    [_mysqlConnection setPassword:password];
}

- (NSString *)database {
    return [_mysqlConnection database];
}

- (void)setDatabase:(NSString *)database {
    [_mysqlConnection setDatabase:database];
}

- (NSUInteger)port {
    return [_mysqlConnection port];
}

- (void)setPort:(NSUInteger)port {
    [_mysqlConnection setPort:port];
}

- (BOOL)useSocket {
    return [_mysqlConnection useSocket];
}

- (void)setUseSocket:(BOOL)useSocket {
    [_mysqlConnection setUseSocket:useSocket];
}

- (NSString *)socketPath {
    return [_mysqlConnection socketPath];
}

- (void)setSocketPath:(NSString *)socketPath {
    [_mysqlConnection setSocketPath:socketPath];
}

// SSL properties
- (BOOL)useSSL {
    return [_mysqlConnection useSSL];
}

- (void)setUseSSL:(BOOL)useSSL {
    [_mysqlConnection setUseSSL:useSSL];
}

- (NSString *)sslKeyFilePath {
    return [_mysqlConnection sslKeyFilePath];
}

- (void)setSslKeyFilePath:(NSString *)sslKeyFilePath {
    [_mysqlConnection setSslKeyFilePath:sslKeyFilePath];
}

- (NSString *)sslCertificatePath {
    return [_mysqlConnection sslCertificatePath];
}

- (void)setSslCertificatePath:(NSString *)sslCertificatePath {
    [_mysqlConnection setSslCertificatePath:sslCertificatePath];
}

- (NSString *)sslCACertificatePath {
    return [_mysqlConnection sslCACertificatePath];
}

- (void)setSslCACertificatePath:(NSString *)sslCACertificatePath {
    [_mysqlConnection setSslCACertificatePath:sslCACertificatePath];
}

- (NSString *)sslCipherList {
    return [_mysqlConnection sslCipherList];
}

- (void)setSslCipherList:(NSString *)sslCipherList {
    [_mysqlConnection setSslCipherList:sslCipherList];
}

// Connection settings
- (NSUInteger)timeout {
    return [_mysqlConnection timeout];
}

- (void)setTimeout:(NSUInteger)timeout {
    [_mysqlConnection setTimeout:timeout];
}

- (BOOL)useKeepAlive {
    return [_mysqlConnection useKeepAlive];
}

- (void)setUseKeepAlive:(BOOL)useKeepAlive {
    [_mysqlConnection setUseKeepAlive:useKeepAlive];
}

- (CGFloat)keepAliveInterval {
    return [_mysqlConnection keepAliveInterval];
}

- (void)setKeepAliveInterval:(CGFloat)keepAliveInterval {
    [_mysqlConnection setKeepAliveInterval:keepAliveInterval];
}

- (BOOL)retryQueriesOnConnectionFailure {
    return [_mysqlConnection retryQueriesOnConnectionFailure];
}

- (void)setRetryQueriesOnConnectionFailure:(BOOL)retryQueriesOnConnectionFailure {
    [_mysqlConnection setRetryQueriesOnConnectionFailure:retryQueriesOnConnectionFailure];
}

// Delegate
- (id)delegate {
    return [_mysqlConnection delegate];
}

- (void)setDelegate:(id)delegate {
    [_mysqlConnection setDelegate:delegate];
}

- (BOOL)delegateQueryLogging {
    return [_mysqlConnection delegateQueryLogging];
}

- (void)setDelegateQueryLogging:(BOOL)delegateQueryLogging {
    [_mysqlConnection setDelegateQueryLogging:delegateQueryLogging];
}

// Connection state
- (BOOL)userTriggeredDisconnect {
    return [_mysqlConnection userTriggeredDisconnect];
}

- (unsigned long)mysqlConnectionThreadId {
    return [_mysqlConnection mysqlConnectionThreadId];
}

// Proxy
- (id<SPDatabaseConnectionProxy>)proxy {
    return (id<SPDatabaseConnectionProxy>)[_mysqlConnection proxy];
}

- (void)setProxy:(id<SPDatabaseConnectionProxy>)proxy {
    [_mysqlConnection setProxy:(id)proxy];
}

#pragma mark - Connection Management

- (BOOL)connect {
    return [_mysqlConnection connect];
}

- (BOOL)reconnect {
    return [_mysqlConnection reconnect];
}

- (void)disconnect {
    [_mysqlConnection disconnect];
}

- (BOOL)isConnected {
    return [_mysqlConnection isConnected];
}

- (BOOL)isConnectedViaSSL {
    return [_mysqlConnection isConnectedViaSSL];
}

- (BOOL)checkConnection {
    return [_mysqlConnection checkConnection];
}

- (BOOL)checkConnectionIfNecessary {
    return [_mysqlConnection checkConnectionIfNecessary];
}

- (double)timeConnected {
    return [_mysqlConnection timeConnected];
}

#pragma mark - Query Execution

- (id<SPDatabaseResult>)queryString:(NSString *)query {
    SPMySQLResult *result = [_mysqlConnection queryString:query];
    if (!result) return nil;
    return [[SPMySQLResultWrapper alloc] initWithMySQLResult:result];
}

- (id<SPDatabaseResult>)streamingQueryString:(NSString *)query {
    SPMySQLResult *result = [_mysqlConnection streamingQueryString:query];
    if (!result) return nil;
    return [[SPMySQLResultWrapper alloc] initWithMySQLResult:result];
}

- (id<SPDatabaseResult>)streamingQueryString:(NSString *)query useLowMemoryBlockingStreaming:(BOOL)fullStream {
    SPMySQLResult *result = [_mysqlConnection streamingQueryString:query useLowMemoryBlockingStreaming:fullStream];
    if (!result) return nil;
    return [[SPMySQLResultWrapper alloc] initWithMySQLResult:result];
}

- (id)resultStoreFromQueryString:(NSString *)query {
    // This returns a SPMySQLStreamingResultStore which is also a SPMySQLResult subclass
    SPMySQLResult *result = [_mysqlConnection resultStoreFromQueryString:query];
    if (!result) return nil;
    return [[SPMySQLResultWrapper alloc] initWithMySQLResult:result];
}

- (NSArray *)getAllRowsFromQuery:(NSString *)query {
    return [_mysqlConnection getAllRowsFromQuery:query];
}

- (id)getFirstFieldFromQuery:(NSString *)query {
    return [_mysqlConnection getFirstFieldFromQuery:query];
}

- (id<SPDatabaseResult>)listProcesses {
    SPMySQLResult *result = [_mysqlConnection listProcesses];
    if (!result) return nil;
    return [[SPMySQLResultWrapper alloc] initWithMySQLResult:result];
}

- (unsigned long long)rowsAffectedByLastQuery {
    return [_mysqlConnection rowsAffectedByLastQuery];
}

#pragma mark - Query State

- (BOOL)queryErrored {
    return [_mysqlConnection queryErrored];
}

- (NSString *)lastErrorMessage {
    return [_mysqlConnection lastErrorMessage];
}

- (NSUInteger)lastErrorID {
    return [_mysqlConnection lastErrorID];
}

- (NSString *)lastSqlstate {
    return [_mysqlConnection lastSqlstate];
}

- (unsigned long long)lastInsertID {
    return [_mysqlConnection lastInsertID];
}

- (double)lastQueryExecutionTime {
    // Note: lastQueryExecutionTime is tracked in result sets, not the connection itself
    return 0.0;
}

- (BOOL)lastQueryWasCancelled {
    return [_mysqlConnection lastQueryWasCancelled];
}

- (void)setLastQueryWasCancelled:(BOOL)cancelled {
    [_mysqlConnection setLastQueryWasCancelled:cancelled];
}

#pragma mark - Database Operations

- (BOOL)selectDatabase:(NSString *)dbName {
    return [_mysqlConnection selectDatabase:dbName];
}

- (NSArray<NSString *> *)databases {
    return [_mysqlConnection databases];
}

- (NSArray<NSString *> *)tables {
    return [_mysqlConnection tables];
}

- (NSArray<NSString *> *)tablesOfType:(NSString *)tableType {
    // SPMySQLConnection doesn't have tablesOfType method
    // Return all tables for now - specific filtering would need to be done via queries
    return [_mysqlConnection tables];
}

#pragma mark - Server Information

- (NSString *)serverVersionString {
    return [_mysqlConnection serverVersionString];
}

- (NSString *)databaseDisplayName {
    NSString *versionString = [self serverVersionString];
    if (!versionString) {
        return @"MySQL";
    }
    
    // Check if it's MariaDB
    if ([versionString rangeOfString:@"MariaDB" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return @"MariaDB";
    }
    
    return @"MySQL";
}

- (NSString *)shortServerVersionString {
    NSString *versionString = [self serverVersionString];
    if (!versionString) {
        return @"Unknown";
    }
    
    // For MySQL/MariaDB, the version string is already short (e.g., "8.0.28" or "10.11.2-MariaDB")
    // Just extract the version number part
    NSRange spaceRange = [versionString rangeOfString:@" "];
    if (spaceRange.location != NSNotFound) {
        return [versionString substringToIndex:spaceRange.location];
    }
    
    return versionString;
}

- (NSInteger)serverMajorVersion {
    return [_mysqlConnection serverMajorVersion];
}

- (NSInteger)serverMinorVersion {
    return [_mysqlConnection serverMinorVersion];
}

- (NSInteger)serverReleaseVersion {
    return [_mysqlConnection serverReleaseVersion];
}

- (NSString *)getServerVariableValue:(NSString *)variableName {
    // MySQL: Use SHOW VARIABLES LIKE
    NSString *query = [NSString stringWithFormat:@"SHOW VARIABLES LIKE %@", [variableName tickQuotedString]];
    SPMySQLResult *result = [_mysqlConnection queryString:query];
    
    if (!result || [_mysqlConnection queryErrored] || [result numberOfRows] != 1) {
        return nil;
    }
    
    [result setReturnDataAsStrings:YES];
    NSDictionary *row = [result getRowAsDictionary];
    return [row objectForKey:@"Value"];
}

- (NSArray<NSDictionary *> *)getTableInfo:(BOOL)includeComments {
    // MySQL: Use SHOW TABLE STATUS or SHOW FULL TABLES
    SPMySQLResult *result;
    if (includeComments) {
        result = [_mysqlConnection queryString:@"SHOW TABLE STATUS"];
    } else {
        result = [_mysqlConnection queryString:@"SHOW FULL TABLES"];
    }
    
    if (!result || [_mysqlConnection queryErrored]) {
        return @[];
    }
    
    [result setReturnDataAsStrings:YES];
    // Use SPMySQLResultRowType since we're working directly with SPMySQLResult here
    [result setDefaultRowReturnType:SPMySQLResultRowAsDictionary];
    
    NSMutableArray *tableInfo = [NSMutableArray array];
    for (NSDictionary *row in result) {
        // Normalize the dictionary to have consistent keys
        NSMutableDictionary *normalizedRow = [NSMutableDictionary dictionary];
        
        // Find the table name - SHOW FULL TABLES uses "Tables_in_<dbname>" or "Name" from SHOW TABLE STATUS
        NSString *tableName = nil;
        for (NSString *key in [row allKeys]) {
            if ([key hasPrefix:@"Tables_in_"] || [key isEqualToString:@"Name"]) {
                tableName = [row objectForKey:key];
                break;
            }
        }
        
        if (tableName) {
            [normalizedRow setObject:tableName forKey:@"Name"];
        }
        
        // Copy Table_type
        if ([row objectForKey:@"Table_type"]) {
            [normalizedRow setObject:[row objectForKey:@"Table_type"] forKey:@"Table_type"];
        }
        
        // Copy Comment if present
        if ([row objectForKey:@"Comment"]) {
            [normalizedRow setObject:[row objectForKey:@"Comment"] forKey:@"Comment"];
        }
        
        [tableInfo addObject:normalizedRow];
    }
    
    return [tableInfo copy];
}

#pragma mark - Encoding

- (NSString *)encoding {
    return [_mysqlConnection encoding];
}

- (BOOL)setEncoding:(NSString *)encoding {
    return [_mysqlConnection setEncoding:encoding];
}

- (NSString *)preferredUTF8Encoding {
    // MySQL uses utf8mb4 as the preferred UTF-8 encoding
    return @"utf8mb4";
}

- (NSArray *)getAvailableEncodings {
    // MySQL: Query information_schema.character_sets
    SPMySQLResult *result = [_mysqlConnection queryString:@"SELECT * FROM `information_schema`.`character_sets` ORDER BY `character_set_name` ASC"];
    if (!result || [_mysqlConnection queryErrored]) {
        return @[];
    }
    
    NSMutableArray *encodings = [NSMutableArray array];
    [result setReturnDataAsStrings:YES];
    
    for (NSDictionary *row in result) {
        [encodings addObject:row];
    }
    
    return [encodings copy];
}

- (NSArray *)getCollationsForEncoding:(NSString *)encoding {
    if (!encoding) return @[];
    
    // MySQL: Query information_schema.collations
    NSString *query = [NSString stringWithFormat:@"SELECT * FROM `information_schema`.`collations` WHERE character_set_name = '%@' ORDER BY `collation_name` ASC", 
                       [encoding stringByReplacingOccurrencesOfString:@"'" withString:@"''"]];
    SPMySQLResult *result = [_mysqlConnection queryString:query];
    if (!result || [_mysqlConnection queryErrored]) {
        return @[];
    }
    
    NSMutableArray *collations = [NSMutableArray array];
    [result setReturnDataAsStrings:YES];
    
    for (NSDictionary *row in result) {
        [collations addObject:row];
    }
    
    return [collations copy];
}

- (NSArray *)getDatabaseStorageEngines {
    // MySQL: Check if information_schema.engines table is accessible
    SPMySQLResult *checkResult = [_mysqlConnection queryString:@"SHOW TABLES IN information_schema LIKE 'ENGINES'"];
    
    if (!checkResult || [checkResult numberOfRows] != 1) {
        return @[];
    }
    
    // Table is accessible, get available storage engines
    // Note: The case of the column names specified in this query are important
    SPMySQLResult *result = [_mysqlConnection queryString:@"SELECT Engine, Support FROM `information_schema`.`engines` WHERE SUPPORT IN ('DEFAULT', 'YES') AND Engine != 'PERFORMANCE_SCHEMA'"];
    
    if (!result || [_mysqlConnection queryErrored]) {
        return @[];
    }
    
    NSMutableArray *engines = [NSMutableArray array];
    [result setReturnDataAsStrings:YES];
    
    for (NSDictionary *row in result) {
        [engines addObject:row];
    }
    
    return [engines copy];
}

- (void)storeEncodingForRestoration {
    [_mysqlConnection storeEncodingForRestoration];
}

- (void)restoreStoredEncoding {
    [_mysqlConnection restoreStoredEncoding];
}

- (NSStringEncoding)stringEncoding {
    return [_mysqlConnection stringEncoding];
}

#pragma mark - Transactions

- (BOOL)beginTransaction {
    [_mysqlConnection queryString:@"START TRANSACTION"];
    return ![_mysqlConnection queryErrored];
}

- (BOOL)commitTransaction {
    [_mysqlConnection queryString:@"COMMIT"];
    return ![_mysqlConnection queryErrored];
}

- (BOOL)rollbackTransaction {
    [_mysqlConnection queryString:@"ROLLBACK"];
    return ![_mysqlConnection queryErrored];
}

#pragma mark - String Escaping

- (NSString *)escapeString:(NSString *)theString {
    return [_mysqlConnection escapeString:theString includingQuotes:NO];
}

- (NSString *)escapeString:(NSString *)string includingQuotes:(BOOL)includeQuotes {
    return [_mysqlConnection escapeString:string includingQuotes:includeQuotes];
}

- (NSString *)escapeAndQuoteString:(NSString *)theString {
    return [_mysqlConnection escapeAndQuoteString:theString];
}

- (NSString *)escapeData:(NSData *)theData {
    return [_mysqlConnection escapeData:theData includingQuotes:NO];
}

- (NSString *)escapeData:(NSData *)data includingQuotes:(BOOL)includeQuotes {
    return [_mysqlConnection escapeData:data includingQuotes:includeQuotes];
}

- (NSString *)escapeAndQuoteData:(NSData *)theData {
    return [_mysqlConnection escapeAndQuoteData:theData];
}

#pragma mark - Locking

- (void)lock {
    // SPMySQLConnection uses internal locking, no public lock method
}

- (void)unlock {
    // SPMySQLConnection uses internal locking, no public unlock method
}

#pragma mark - Max Packet Size

- (NSUInteger)maxQuerySize {
    return [_mysqlConnection maxQuerySize];
}

- (BOOL)isMaxQuerySizeEditable {
    return [_mysqlConnection isMaxQuerySizeEditable];
}

- (BOOL)setMaxQuerySize:(NSUInteger)size {
    // setMaxQuerySize is in a category but doesn't return BOOL
    // SPMySQLConnection has maxQuerySize property but it's complex to set
    // Return NO for now - would need proper implementation
    return NO;
}

#pragma mark - Database-Specific Abstractions

- (NSString *)identifierQuoteCharacter {
    return @"`";  // MySQL uses backticks
}

- (NSString *)quoteIdentifier:(NSString *)identifier {
    if (!identifier) return @"``";
    // Escape any backticks in the identifier by doubling them
    NSString *escaped = [identifier stringByReplacingOccurrencesOfString:@"`" withString:@"``"];
    return [NSString stringWithFormat:@"`%@`", escaped];
}

- (NSString *)buildLimitClause:(NSUInteger)count offset:(NSUInteger)offset {
    // MySQL uses: LIMIT offset,count
    return [NSString stringWithFormat:@"LIMIT %lu,%lu", (unsigned long)offset, (unsigned long)count];
}

- (BOOL)supportsFeature:(NSString *)feature {
    // MySQL-specific feature support
    if ([feature isEqualToString:@"storageEngines"]) return YES;
    if ([feature isEqualToString:@"charsets"]) return YES;
    if ([feature isEqualToString:@"collations"]) return YES;
    if ([feature isEqualToString:@"compression"]) return YES;
    if ([feature isEqualToString:@"sshTunnel"]) return YES;
    if ([feature isEqualToString:@"ssl"]) return YES;
    if ([feature isEqualToString:@"socket"]) return YES;
    if ([feature isEqualToString:@"triggers"]) return YES;
    if ([feature isEqualToString:@"events"]) return YES;
    if ([feature isEqualToString:@"procedures"]) return YES;
    if ([feature isEqualToString:@"functions"]) return YES;
    if ([feature isEqualToString:@"views"]) return YES;
    return NO;
}

- (BOOL)supportsTableEngines {
    // MySQL supports storage engines (InnoDB, MyISAM, etc.)
    return YES;
}

- (BOOL)supportsTableLevelCharacterSets {
    // MySQL supports table-level character sets and collations
    return YES;
}

- (BOOL)supportsLimitInUpdateDelete {
    // MySQL supports LIMIT in UPDATE and DELETE statements
    return YES;
}

- (BOOL)isDefaultValueServerExpression:(NSString *)defaultValue {
    if (!defaultValue || [defaultValue length] == 0) {
        return NO;
    }
    
    // MySQL: Check for common server-side expressions
    // CURRENT_TIMESTAMP and variations are computed server-side
    NSString *uppercaseDefault = [defaultValue uppercaseString];
    
    if ([uppercaseDefault isEqualToString:@"CURRENT_TIMESTAMP"] ||
        [uppercaseDefault isEqualToString:@"CURRENT_DATE"] ||
        [uppercaseDefault isEqualToString:@"CURRENT_TIME"] ||
        [uppercaseDefault hasPrefix:@"CURRENT_TIMESTAMP("] ||
        [uppercaseDefault isEqualToString:@"NOW()"] ||
        [uppercaseDefault hasPrefix:@"NOW("] ||
        [uppercaseDefault isEqualToString:@"CURDATE()"] ||
        [uppercaseDefault isEqualToString:@"CURTIME()"]) {
        return YES;
    }
    
    // Most other MySQL defaults are literal values
    return NO;
}

- (NSString *)buildCreateTableStatementForTable:(NSString *)tableName
                                      tableType:(NSString *)tableType
                                   encodingName:(NSString *)encodingName
                                  collationName:(NSString *)collationName {
    // MySQL: Create table with AUTO_INCREMENT
    NSMutableString *createStatement = [NSMutableString string];
    
    NSString *quotedTableName = [self quoteIdentifier:tableName];
    
    // Build column definition
    // For CSV tables, don't add PRIMARY KEY AUTO_INCREMENT
    if ([tableType isEqualToString:@"CSV"]) {
        [createStatement appendFormat:@"CREATE TABLE %@ (id INT(11) UNSIGNED NOT NULL)", quotedTableName];
    } else {
        [createStatement appendFormat:@"CREATE TABLE %@ (id INT(11) UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT)", quotedTableName];
    }
    
    // Add character set if specified
    if (encodingName && [encodingName length] > 0) {
        [createStatement appendFormat:@" DEFAULT CHARACTER SET %@", [self quoteIdentifier:encodingName]];
    }
    
    // Add collation if specified
    if (collationName && [collationName length] > 0) {
        [createStatement appendFormat:@" DEFAULT COLLATE %@", [self quoteIdentifier:collationName]];
    }
    
    // Add engine/storage type if specified
    if (tableType && [tableType length] > 0 && ![tableType isEqualToString:@"CSV"]) {
        [createStatement appendFormat:@" ENGINE = %@", [self quoteIdentifier:tableType]];
    }
    
    return [createStatement copy];
}

- (NSString *)getCreateStatementForTable:(NSString *)tableName {
    // MySQL: Use SHOW CREATE TABLE
    id<SPDatabaseResult> result = [self queryString:[NSString stringWithFormat:@"SHOW CREATE TABLE %@", [self quoteIdentifier:tableName]]];
    if (!result || [result numberOfRows] == 0) {
        return nil;
    }
    [result setReturnDataAsStrings:YES];
    NSArray *row = [result getRowAsArray];
    if (row && [row count] >= 2) {
        return row[1]; // Second column contains CREATE TABLE statement
    }
    return nil;
}

- (NSString *)getCreateStatementForView:(NSString *)viewName {
    // MySQL: Use SHOW CREATE VIEW
    id<SPDatabaseResult> result = [self queryString:[NSString stringWithFormat:@"SHOW CREATE VIEW %@", [self quoteIdentifier:viewName]]];
    if (!result || [result numberOfRows] == 0) {
        return nil;
    }
    [result setReturnDataAsStrings:YES];
    NSArray *row = [result getRowAsArray];
    if (row && [row count] >= 2) {
        return row[1]; // Second column contains CREATE VIEW statement
    }
    return nil;
}

- (NSString *)getCreateStatementForProcedure:(NSString *)procedureName {
    // MySQL: Use SHOW CREATE PROCEDURE
    id<SPDatabaseResult> result = [self queryString:[NSString stringWithFormat:@"SHOW CREATE PROCEDURE %@", [self quoteIdentifier:procedureName]]];
    if (!result || [result numberOfRows] == 0) {
        return nil;
    }
    [result setReturnDataAsStrings:YES];
    NSArray *row = [result getRowAsArray];
    if (row && [row count] >= 3) {
        return row[2]; // Third column contains CREATE PROCEDURE statement
    }
    return nil;
}

- (NSString *)getCreateStatementForFunction:(NSString *)functionName {
    // MySQL: Use SHOW CREATE FUNCTION
    id<SPDatabaseResult> result = [self queryString:[NSString stringWithFormat:@"SHOW CREATE FUNCTION %@", [self quoteIdentifier:functionName]]];
    if (!result || [result numberOfRows] == 0) {
        return nil;
    }
    [result setReturnDataAsStrings:YES];
    NSArray *row = [result getRowAsArray];
    if (row && [row count] >= 3) {
        return row[2]; // Third column contains CREATE FUNCTION statement
    }
    return nil;
}

#pragma mark - Table Structure and Metadata

- (id<SPDatabaseResult>)getCreateTableStatement:(NSString *)tableName fromDatabase:(NSString *)database {
    NSString *query;
    if (database) {
        query = [NSString stringWithFormat:@"SHOW CREATE TABLE %@.%@", 
                 [database backtickQuotedString], 
                 [tableName backtickQuotedString]];
    } else {
        query = [NSString stringWithFormat:@"SHOW CREATE TABLE %@", 
                 [tableName backtickQuotedString]];
    }
    
    SPMySQLResult *result = [_mysqlConnection queryString:query];
    if (result) {
        return [[SPMySQLResultWrapper alloc] initWithMySQLResult:result];
    }
    return nil;
}

- (id<SPDatabaseResult>)getColumnsForTable:(NSString *)tableName {
    NSString *query = [NSString stringWithFormat:@"SHOW COLUMNS FROM %@", 
                      [self quoteIdentifier:tableName]];
    SPMySQLResult *result = [_mysqlConnection queryString:query];
    if (result) {
        return [[SPMySQLResultWrapper alloc] initWithMySQLResult:result];
    }
    return nil;
}

- (id<SPDatabaseResult>)getTableStatus:(NSString *)tableName {
    // Escape the table name for use in LIKE pattern
    NSMutableString *escapedTableName = [NSMutableString stringWithString:tableName];
    [escapedTableName replaceOccurrencesOfString:@"\\" withString:@"\\\\" 
                                         options:0 
                                           range:NSMakeRange(0, [escapedTableName length])];
    [escapedTableName replaceOccurrencesOfString:@"'" withString:@"\\'" 
                                         options:0 
                                           range:NSMakeRange(0, [escapedTableName length])];
    [escapedTableName replaceOccurrencesOfRegex:@"\\\\(?=\\Z|[^'])" withString:@"\\\\\\\\"];
    
    NSString *query = [NSString stringWithFormat:@"SHOW TABLE STATUS LIKE '%@'", escapedTableName];
    SPMySQLResult *result = [_mysqlConnection queryString:query];
    if (result) {
        return [[SPMySQLResultWrapper alloc] initWithMySQLResult:result];
    }
    return nil;
}

- (id<SPDatabaseResult>)getTriggersForTable:(NSString *)tableName {
    NSString *query = [NSString stringWithFormat:@"/*!50003 SHOW TRIGGERS WHERE `Table` = %@ */",
                      [tableName tickQuotedString]];
    SPMySQLResult *result = [_mysqlConnection queryString:query];
    if (result) {
        return [[SPMySQLResultWrapper alloc] initWithMySQLResult:result];
    }
    return nil;
}

- (id<SPDatabaseResult>)getIndexesForTable:(NSString *)tableName {
    NSString *query = [NSString stringWithFormat:@"SHOW INDEX FROM %@", [tableName backtickQuotedString]];
    SPMySQLResult *result = [_mysqlConnection queryString:query];
    if (result) {
        return [[SPMySQLResultWrapper alloc] initWithMySQLResult:result];
    }
    return nil;
}

#pragma mark - Utility

- (id)copy {
    return [[SPMySQLConnectionWrapper alloc] initWithConnection:[_mysqlConnection copy]];
}

- (id)copyWithZone:(NSZone *)zone {
    return [[SPMySQLConnectionWrapper alloc] initWithConnection:[_mysqlConnection copy]];
}

#pragma mark - MySQL-Specific Methods

- (BOOL)serverShutdown {
    return [_mysqlConnection serverShutdown];
}

- (void)cancelCurrentQuery {
    [_mysqlConnection cancelCurrentQuery];
}

- (BOOL)killQueryOnThreadID:(unsigned long)theThreadID {
    return [_mysqlConnection killQueryOnThreadID:theThreadID];
}

- (void)setEncodingUsesLatin1Transport:(BOOL)useLatin1 {
    [_mysqlConnection setEncodingUsesLatin1Transport:useLatin1];
}

@end

