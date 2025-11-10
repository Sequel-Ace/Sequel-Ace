//
//  SPDatabaseConnection.h
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

#import <Foundation/Foundation.h>

@protocol SPDatabaseResult;
@protocol SPDatabaseConnectionProxy;

// SPDatabaseType enum is defined in SPConstants.h
// Import that header if you need to use the enum values

/**
 * Connection lost decision enum
 */
typedef NS_ENUM(NSUInteger, SPDatabaseConnectionLostDecision) {
    SPDatabaseConnectionLostDisconnect = 0,
    SPDatabaseConnectionLostReconnect  = 1
};

/**
 * SPDatabaseConnection protocol
 * 
 * This protocol defines a common interface for database connections,
 * abstracting the underlying database implementation (MySQL, PostgreSQL, etc.)
 */
@protocol SPDatabaseConnection <NSObject>

#pragma mark - Database Type

/**
 * Returns the database type (MySQL, PostgreSQL, etc.)
 * @return Database type enum value (defined in SPConstants.h)
 */
- (NSUInteger)databaseType;

#pragma mark - Connection Properties

@property (readwrite, copy) NSString *host;
@property (readwrite, copy) NSString *username;
@property (readwrite, copy) NSString *password;
@property (readwrite, copy) NSString *database;
@property (readwrite, assign) NSUInteger port;
@property (readwrite, assign) BOOL useSocket;
@property (readwrite, copy) NSString *socketPath;

// SSL properties
@property (readwrite, assign) BOOL useSSL;
@property (readwrite, copy) NSString *sslKeyFilePath;
@property (readwrite, copy) NSString *sslCertificatePath;
@property (readwrite, copy) NSString *sslCACertificatePath;
@property (readwrite, copy) NSString *sslCipherList;

// Connection settings
@property (readwrite, assign) NSUInteger timeout;
@property (readwrite, assign) BOOL useKeepAlive;
@property (readwrite, assign) CGFloat keepAliveInterval;
@property (readwrite, assign) BOOL retryQueriesOnConnectionFailure;

// Delegate
@property (readwrite, weak) id delegate;
@property (readwrite, assign) BOOL delegateQueryLogging;

// Connection state
@property (readonly) BOOL userTriggeredDisconnect;
@property (readonly) unsigned long mysqlConnectionThreadId; // Note: MySQL-specific but kept for compatibility

// Proxy (for SSH tunnels, etc.)
@property (readwrite, strong) id<SPDatabaseConnectionProxy> proxy;

#pragma mark - Connection Management

/**
 * Establish connection to the database server
 * @return YES if successful, NO otherwise
 */
- (BOOL)connect;

/**
 * Reconnect to the database server
 * @return YES if successful, NO otherwise
 */
- (BOOL)reconnect;

/**
 * Disconnect from the database server
 */
- (void)disconnect;

/**
 * Check if currently connected
 * @return YES if connected, NO otherwise
 */
- (BOOL)isConnected;

/**
 * Check if connected via SSL
 * @return YES if connected with SSL, NO otherwise
 */
- (BOOL)isConnectedViaSSL;

/**
 * Check connection status and attempt to restore if necessary
 * @return YES if connection is valid, NO otherwise
 */
- (BOOL)checkConnection;

/**
 * Check connection only if necessary (based on last usage time)
 * @return YES if connection is valid, NO otherwise
 */
- (BOOL)checkConnectionIfNecessary;

/**
 * Get time elapsed since connection was established
 * @return Time in seconds
 */
- (double)timeConnected;

#pragma mark - Query Execution

/**
 * Execute a query and return results
 * @param query The SQL query to execute
 * @return Result set or nil on error
 */
- (id<SPDatabaseResult>)queryString:(NSString *)query;

/**
 * Execute a streaming query for large result sets
 * @param query The SQL query to execute
 * @return Streaming result set or nil on error
 */
- (id<SPDatabaseResult>)streamingQueryString:(NSString *)query;

/**
 * Execute a streaming query with specific options
 * @param query The SQL query to execute
 * @param options Query execution options
 * @return Streaming result set or nil on error
 */
- (id<SPDatabaseResult>)streamingQueryString:(NSString *)query useLowMemoryBlockingStreaming:(BOOL)fullStream;

/**
 * Execute a query and return a result store (caches all results in memory)
 * @param query SQL query string
 * @return Result store or nil on error
 */
- (id)resultStoreFromQueryString:(NSString *)query;

/**
 * Execute a query and return all rows as an array
 * @param query SQL query string
 * @return Array of rows (each row is an array) or empty array
 */
- (NSArray *)getAllRowsFromQuery:(NSString *)query;

/**
 * Execute a query and return the first field of the first row
 * @param query SQL query string
 * @return First field value or nil
 */
- (id)getFirstFieldFromQuery:(NSString *)query;

/**
 * List running processes/queries (MySQL specific)
 * @return Result set of processes or nil
 */
- (id<SPDatabaseResult>)listProcesses;

/**
 * Get number of rows affected by last query
 * @return Number of affected rows
 */
- (unsigned long long)rowsAffectedByLastQuery;

#pragma mark - Query State

/**
 * Check if last query encountered an error
 * @return YES if error occurred, NO otherwise
 */
- (BOOL)queryErrored;

/**
 * Get error message from last query
 * @return Error message or nil
 */
- (NSString *)lastErrorMessage;

/**
 * Get error ID from last query
 * @return Error code
 */
- (NSUInteger)lastErrorID;

/**
 * Get SQLSTATE from last query
 * @return SQLSTATE string or nil
 */
- (NSString *)lastSqlstate;

/**
 * Get last insert ID
 * @return Insert ID
 */
- (unsigned long long)lastInsertID;

/**
 * Get execution time of last query
 * @return Time in seconds
 */
- (double)lastQueryExecutionTime;

/**
 * Check if last query was cancelled
 * @return YES if cancelled, NO otherwise
 */
- (BOOL)lastQueryWasCancelled;

/**
 * Set cancellation state for last query
 */
- (void)setLastQueryWasCancelled:(BOOL)cancelled;

#pragma mark - Database Operations

/**
 * Select a database
 * @param dbName Database name
 * @return YES if successful, NO otherwise
 */
- (BOOL)selectDatabase:(NSString *)dbName;

/**
 * List all databases
 * @return Array of database names
 */
- (NSArray<NSString *> *)databases;

/**
 * List all tables in current database
 * @return Array of table names
 */
- (NSArray<NSString *> *)tables;

/**
 * List all tables of specific type
 * @param tableType Type filter (implementation-specific)
 * @return Array of table names
 */
- (NSArray<NSString *> *)tablesOfType:(NSString *)tableType;

/**
 * Get detailed table information (names, types, and optionally comments)
 * @param includeComments YES to include table comments, NO otherwise
 * @return Array of dictionaries with keys: "Name", "Table_type", "Comment" (if includeComments is YES)
 */
- (NSArray<NSDictionary *> *)getTableInfo:(BOOL)includeComments;

#pragma mark - Table Structure and Metadata

/**
 * Get CREATE TABLE statement for a table
 * @param tableName The name of the table
 * @param database The database name (can be nil to use current database)
 * @return Result set with CREATE TABLE statement or nil on error
 */
- (id<SPDatabaseResult>)getCreateTableStatement:(NSString *)tableName fromDatabase:(NSString *)database;

/**
 * Get column information for a table
 * @param tableName The name of the table
 * @return Result set with column information or nil on error
 */
- (id<SPDatabaseResult>)getColumnsForTable:(NSString *)tableName;

/**
 * Get table status/metadata information
 * @param tableName The name of the table
 * @return Result set with table status information or nil on error
 */
- (id<SPDatabaseResult>)getTableStatus:(NSString *)tableName;

/**
 * Get triggers for a table
 * @param tableName The name of the table
 * @return Result set with trigger information or nil on error
 */
- (id<SPDatabaseResult>)getTriggersForTable:(NSString *)tableName;

/**
 * Get indexes for a table
 * @param tableName The name of the table
 * @return Result set with index information or nil on error
 */
- (id<SPDatabaseResult>)getIndexesForTable:(NSString *)tableName;

#pragma mark - Server Information

/**
 * Get server version string
 * @return Version string (e.g., "8.0.28")
 */
- (NSString *)serverVersionString;

/**
 * Get database display name for UI
 * @return Display name (e.g., "MySQL", "PostgreSQL", "MariaDB")
 */
- (NSString *)databaseDisplayName;

/**
 * Get short server version string for UI display
 * @return Short version (e.g., "8.0.28", "15.4")
 */
- (NSString *)shortServerVersionString;

/**
 * Get server major version
 * @return Major version number
 */
- (NSInteger)serverMajorVersion;

/**
 * Get server minor version
 * @return Minor version number
 */
- (NSInteger)serverMinorVersion;

/**
 * Get server release version
 * @return Release version number
 */
- (NSInteger)serverReleaseVersion;

/**
 * Get a server variable value
 * @param variableName The name of the server variable (e.g., "character_set_database")
 * @return The variable value as a string, or nil if not found
 */
- (NSString *)getServerVariableValue:(NSString *)variableName;

#pragma mark - Encoding

/**
 * Get current connection encoding
 * @return Encoding name
 */
- (NSString *)encoding;

/**
 * Set connection encoding
 * @param encoding Encoding name
 * @return YES if successful, NO otherwise
 */
- (BOOL)setEncoding:(NSString *)encoding;

/**
 * Get the preferred UTF-8 encoding name for this database type
 * @return UTF-8 encoding name (e.g., "utf8mb4" for MySQL, "UTF8" for PostgreSQL)
 */
- (NSString *)preferredUTF8Encoding;

/**
 * Get available character set encodings for this database
 * @return Array of dictionaries with encoding information, or empty array if not supported
 */
- (NSArray *)getAvailableEncodings;

/**
 * Get available collations for a specific encoding
 * @param encoding The character set encoding name
 * @return Array of dictionaries with collation information, or empty array if not supported
 */
- (NSArray *)getCollationsForEncoding:(NSString *)encoding;

/**
 * Get available storage engines for this database
 * @return Array of dictionaries with storage engine information (MySQL: Engine, Support, etc.), 
 *         or empty array for databases that don't support storage engines (e.g., PostgreSQL)
 */
- (NSArray *)getDatabaseStorageEngines;

/**
 * Store current encoding for later restoration
 */
- (void)storeEncodingForRestoration;

/**
 * Restore previously stored encoding
 */
- (void)restoreStoredEncoding;

/**
 * Get string encoding equivalent
 * @return NSStringEncoding value
 */
- (NSStringEncoding)stringEncoding;

#pragma mark - Transactions

/**
 * Start a transaction
 * @return YES if successful, NO otherwise
 */
- (BOOL)beginTransaction;

/**
 * Commit current transaction
 * @return YES if successful, NO otherwise
 */
- (BOOL)commitTransaction;

/**
 * Rollback current transaction
 * @return YES if successful, NO otherwise
 */
- (BOOL)rollbackTransaction;

#pragma mark - String Escaping

/**
 * Escape a string for safe use in SQL queries
 * @param theString String to escape
 * @return Escaped string
 */
- (NSString *)escapeString:(NSString *)theString;

/**
 * Escape and quote a string for safe use in SQL queries
 * @param theString String to escape and quote
 * @return Escaped and quoted string
 */
- (NSString *)escapeAndQuoteString:(NSString *)theString;

/**
 * Escape data for safe use in SQL queries
 * @param theData Data to escape
 * @return Escaped data string
 */
- (NSString *)escapeData:(NSData *)theData;

/**
 * Escape and quote data for safe use in SQL queries
 * @param theData Data to escape and quote
 * @return Escaped and quoted data string
 */
- (NSString *)escapeAndQuoteData:(NSData *)theData;

/**
 * Escape a string for safe use in SQL queries, optionally with quotes
 * @param string String to escape
 * @param includeQuotes Whether to include quotes
 * @return Escaped string
 */
- (NSString *)escapeString:(NSString *)string includingQuotes:(BOOL)includeQuotes;

/**
 * Escape data for safe use in SQL queries, optionally with quotes
 * @param data Data to escape
 * @param includeQuotes Whether to include quotes
 * @return Escaped data string
 */
- (NSString *)escapeData:(NSData *)data includingQuotes:(BOOL)includeQuotes;

#pragma mark - Locking

/**
 * Lock connection for current thread
 */
- (void)lock;

/**
 * Unlock connection
 */
- (void)unlock;

#pragma mark - Max Packet Size

/**
 * Get maximum query size
 * @return Size in bytes
 */
- (NSUInteger)maxQuerySize;

/**
 * Check if max query size is editable
 * @return YES if editable, NO otherwise
 */
- (BOOL)isMaxQuerySizeEditable;

/**
 * Set maximum query size
 * @param size Size in bytes
 * @return YES if successful, NO otherwise
 */
- (BOOL)setMaxQuerySize:(NSUInteger)size;

#pragma mark - Database-Specific Abstractions

/**
 * Get the identifier quote character(s) for this database
 * (backticks for MySQL, double quotes for PostgreSQL)
 * @return Quote character string
 */
- (NSString *)identifierQuoteCharacter;

/**
 * Quote an identifier (table/column name) for safe use in SQL queries
 * Uses the appropriate quote character for the database (backticks for MySQL, double quotes for PostgreSQL)
 * @param identifier The identifier to quote
 * @return Quoted identifier
 */
- (NSString *)quoteIdentifier:(NSString *)identifier;

/**
 * Build a LIMIT clause with database-specific syntax
 * MySQL: "LIMIT offset,count"
 * PostgreSQL: "LIMIT count OFFSET offset"
 * @param count Maximum number of rows to return
 * @param offset Number of rows to skip
 * @return LIMIT clause string (including "LIMIT" keyword)
 */
- (NSString *)buildLimitClause:(NSUInteger)count offset:(NSUInteger)offset;

/**
 * Check if database supports a specific feature
 * @param feature Feature identifier string
 * @return YES if supported, NO otherwise
 */
- (BOOL)supportsFeature:(NSString *)feature;

/**
 * Check if database supports table-level storage engines (e.g., InnoDB, MyISAM in MySQL)
 * @return YES if supported (MySQL), NO otherwise (PostgreSQL)
 */
- (BOOL)supportsTableEngines;

/**
 * Check if database supports table-level character set encoding
 * @return YES if supported (MySQL), NO otherwise (PostgreSQL uses database-level encoding)
 */
- (BOOL)supportsTableLevelCharacterSets;

/**
 * Build a CREATE TABLE statement for a new table with database-specific syntax
 * @param tableName The name of the table to create
 * @param tableType Optional table type/engine (e.g., "InnoDB", "MyISAM" for MySQL; ignored for PostgreSQL)
 * @param encodingName Optional character set encoding (e.g., "utf8mb4" for MySQL; ignored for PostgreSQL)
 * @param collationName Optional collation (e.g., "utf8mb4_general_ci" for MySQL; ignored for PostgreSQL)
 * @return CREATE TABLE statement with database-specific syntax
 */
- (NSString *)buildCreateTableStatementForTable:(NSString *)tableName
                                      tableType:(NSString *)tableType
                                   encodingName:(NSString *)encodingName
                                  collationName:(NSString *)collationName;

#pragma mark - Utility

/**
 * Copy this connection (for threading)
 * @return New connection instance with same settings
 */
- (id)copy;

#pragma mark - MySQL-Specific Methods (to be abstracted or removed)

/**
 * Shutdown the database server (MySQL-specific, stub for PostgreSQL)
 * @return YES if successful, NO otherwise
 */
- (BOOL)serverShutdown;

/**
 * Cancel currently executing query
 */
- (void)cancelCurrentQuery;

/**
 * Kill a query running on a specific thread
 * @param theThreadID Thread ID to kill
 * @return YES if successful, NO otherwise
 */
- (BOOL)killQueryOnThreadID:(unsigned long)theThreadID;

/**
 * Set encoding to use Latin1 transport (MySQL-specific, no-op for PostgreSQL)
 * @param useLatin1 YES to use Latin1 transport, NO otherwise
 */
- (void)setEncodingUsesLatin1Transport:(BOOL)useLatin1;

@end

