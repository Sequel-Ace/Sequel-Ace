//
//  SPDatabaseData.h
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on May 20, 2009.
//  Copyright (c) 2009 Stuart Connolly. All rights reserved.
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
//
//  More info at <https://github.com/sequelpro/sequelpro>

@class SPServerSupport;
@class SPPostgresConnection;

/**
 * @class SPDatabaseData SPDatabaseData.h
 *
 * @author Stuart Connolly http://stuconnolly.com/
 *
 * This class provides various convenience methods for obtaining data associated with the current database, 
 * if available. This includes available encodings, collations, etc.
 */
@interface SPDatabaseData : NSObject 
{
	NSString *characterSetEncoding;
	NSString *defaultCollationForCharacterSet;
	NSString *defaultCharacterSetEncoding;
	NSString *defaultCollation;
	NSString *serverDefaultCharacterSetEncoding;
	NSString *serverDefaultCollation;
	NSString *defaultStorageEngine;
	
	NSMutableArray *collations;
	NSMutableArray *characterSetCollations;
	NSMutableArray *storageEngines;
	NSMutableArray *characterSetEncodings;
	NSMutableDictionary *cachedCollationsByEncoding;
	
	SPPostgresConnection *connection;
	SPServerSupport *serverSupport;
	
	NSObject *charsetCollationLock;
}

/**
 * @property connection The current database connection
 */
@property (readwrite, strong) SPPostgresConnection *connection;

/**
 * @property serverSupport The connection's associated SPServerSupport instance
 */
@property (readwrite, strong) SPServerSupport *serverSupport;

- (void)resetAllData;

- (NSArray *)getDatabaseCollations;
- (NSArray *)getDatabaseCollationsForEncoding:(NSString *)encoding;
- (NSString *)getDefaultCollationForEncoding:(NSString *)encoding;
- (NSString *)getEncodingFromCollation:(NSString *)collation;
- (NSArray *)getDatabaseStorageEngines;
- (NSArray *)getDatabaseCharacterSetEncodings;

- (NSString *)getDatabaseDefaultCharacterSet;
- (NSString *)getDatabaseDefaultCollation;
- (NSString *)getDatabaseDefaultStorageEngine;

- (NSString *)getServerDefaultCharacterSet;
- (NSString *)getServerDefaultCollation;

#pragma mark - PostgreSQL Schema Operations

/**
 * Returns all available schemas in the current database.
 */
- (NSArray *)getDatabaseSchemas;

/**
 * Returns all sequences in the specified schema.
 */
- (NSArray *)getSequencesForSchema:(NSString *)schema;

/**
 * Returns all materialized views in the specified schema.
 */
- (NSArray *)getMaterializedViewsForSchema:(NSString *)schema;

/**
 * Returns all domains in the specified schema.
 */
- (NSArray *)getDomainsForSchema:(NSString *)schema;

/**
 * Returns all aggregate functions in the specified schema.
 */
- (NSArray *)getAggregatesForSchema:(NSString *)schema;

/**
 * Returns all operators in the specified schema.
 */
- (NSArray *)getOperatorsForSchema:(NSString *)schema;

/**
 * Returns all FTS configurations in the specified schema.
 */
- (NSArray *)getFTSConfigurationsForSchema:(NSString *)schema;

/**
 * Returns all FTS dictionaries in the specified schema.
 */
- (NSArray *)getFTSDictionariesForSchema:(NSString *)schema;

/**
 * Returns all foreign tables in the specified schema.
 */
- (NSArray *)getForeignTablesForSchema:(NSString *)schema;

/**
 * Returns all custom types in the specified schema.
 */
- (NSArray *)getTypesForSchema:(NSString *)schema;

/**
 * Returns all collations in the specified schema.
 */
- (NSArray *)getCollationsForSchema:(NSString *)schema;

/**
 * Returns all trigger functions in the specified schema.
 */
- (NSArray *)getTriggerFunctionsForSchema:(NSString *)schema;

@end
