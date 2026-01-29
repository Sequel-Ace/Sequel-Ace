//
//  SPDatabaseData.m
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

#import "SPDatabaseData.h"
#import "SPServerSupport.h"
#import "sequel-pace-Swift.h"

#import "SPFunctions.h"
#import "SPPostgresConnection.h"

@interface SPDatabaseData ()

- (NSString *)_getSingleVariableValue:(NSString *)variable;
- (NSArray *)_getDatabaseDataForQuery:(NSString *)query;

NSInteger _sortStorageEngineEntry(NSDictionary *itemOne, NSDictionary *itemTwo, void *context);

@end

@implementation SPDatabaseData

@synthesize connection;
@synthesize serverSupport;

#pragma mark -
#pragma mark Initialisation

- (instancetype)init
{
	if ((self = [super init])) {
		characterSetEncoding = nil;
		defaultCollationForCharacterSet = nil;
		defaultCollation = nil;
		defaultCharacterSetEncoding = nil;
		serverDefaultCollation = nil;
		serverDefaultCharacterSetEncoding = nil;
		
		collations             = [[NSMutableArray alloc] init];
		characterSetCollations = [[NSMutableArray alloc] init];
		storageEngines         = [[NSMutableArray alloc] init];
		characterSetEncodings  = [[NSMutableArray alloc] init];
		
		cachedCollationsByEncoding = [[NSMutableDictionary alloc] init];
		
		charsetCollationLock = [[NSObject alloc] init];
	}
	
	return self;
}

#pragma mark -
#pragma mark Public API

/**
 * Reset all the cached values.
 *
 * This method is NOT thread-safe! (except for charset/collation data)
 */
- (void)resetAllData
{
	[storageEngines removeAllObjects];
	
	@synchronized(charsetCollationLock) {
		
		// need to set these to nil
		// otherwise leftover values are used
		// in future queries
		characterSetEncoding = nil;
		defaultCollationForCharacterSet = nil;
		defaultCharacterSetEncoding = nil;
		defaultCollation = nil;
		serverDefaultCharacterSetEncoding = nil;
		serverDefaultCollation = nil;
		
		[collations removeAllObjects];
		[characterSetEncodings removeAllObjects];
		[characterSetCollations removeAllObjects];
	}
}

/**
 * Returns all of the database's currently available collations by querying pg_collation.
 *
 * This method is thread-safe.
 */
- (NSArray *)getDatabaseCollations
{
	@synchronized(charsetCollationLock) {
		if ([collations count] == 0) {
			
			// For PostgreSQL, use pg_collation instead of information_schema.collations
			[collations addObjectsFromArray:[self _getDatabaseDataForQuery:@"SELECT collname AS COLLATION_NAME, 'UTF8' AS CHARACTER_SET_NAME FROM pg_collation ORDER BY collname ASC LIMIT 100"]];
			
			// No error alert for PostgreSQL - collations work differently
		}
			
		return [NSArray arrayWithArray:collations];
	}
}

/**
 * Returns all of the database's currently available collations allowed for the supplied encoding by 
 * querying information_schema.collations.
 *
 * This method is thread-safe.
 */ 
- (NSArray *)getDatabaseCollationsForEncoding:(NSString *)encoding
{
	@synchronized(charsetCollationLock) {
		// PostgreSQL handles collations differently than MySQL
		// In PostgreSQL, collations are tied to the database locale, not per-column encoding
		// Return empty array silently instead of showing error alerts
		if (!encoding || [encoding length] == 0) {
			return @[];
		}
		
		if (((characterSetEncoding == nil) || (![characterSetEncoding isEqualToString:encoding]) || ([characterSetCollations count] == 0))) {
			[characterSetCollations removeAllObjects];
			
			characterSetEncoding = [[NSString alloc] initWithString:encoding];

			NSArray *cachedCollations = [cachedCollationsByEncoding objectForKey:characterSetEncoding];
			if([cachedCollations count]) {
				[characterSetCollations addObjectsFromArray:cachedCollations];
				goto copy_return;
			}

			// For PostgreSQL, query pg_collation instead of information_schema.collations
			// PostgreSQL collations are not filtered by encoding the same way MySQL does
			NSArray *results = [self _getDatabaseDataForQuery:@"SELECT collname AS COLLATION_NAME, 'Yes' AS IS_DEFAULT FROM pg_collation ORDER BY collname ASC LIMIT 50"];
			
			if ([results count]) {
				[characterSetCollations addObjectsFromArray:results];
			}

			if ([characterSetCollations count]) {
				[cachedCollationsByEncoding setObject:[NSArray arrayWithArray:characterSetCollations] forKey:characterSetEncoding];
			}
		}
copy_return:
		return [NSArray arrayWithArray:characterSetCollations];
	}
}

/** Get the collation that is marked as default for a given encoding by the server
 * @param encoding The encoding, e.g. @"latin1"
 * @return The default collation (e.g. @"latin1_swedish_ci") or 
 *         nil if either encoding was nil or the server does not provide the neccesary details
 *
 * This method is thread-safe.
 */
- (NSString *)getDefaultCollationForEncoding:(NSString *)encoding
{
	if(!encoding) return nil;
	// if (
	//   - we have not yet fetched info about the default collation OR
	//   - encoding is different than the one we currently know about
	// ) => we need to load it from server, otherwise just return cached value
	@synchronized(charsetCollationLock) {
		if ((defaultCollationForCharacterSet == nil) || (![characterSetEncoding isEqualToString:encoding])) {
			NSArray *cols = [self getDatabaseCollationsForEncoding:encoding]; //will clear stored encoding and collation if neccesary
			for (NSDictionary *collation in cols) {
				if([[[collation objectForKey:@"IS_DEFAULT"] lowercaseString] isEqualToString:@"yes"]) {
					defaultCollationForCharacterSet = [[NSString alloc] initWithString:[collation objectForKey:@"COLLATION_NAME"]];
					break;
				}
			}
		}
		return [defaultCollationForCharacterSet copy]; // -copy accepts nil, -stringWithString: does not
	}
}

/** Get the name of the mysql charset a given collation belongs to.
 * @param collation Name of the collation (e.g. "latin1_swedish_ci")
 * @return name of the charset (e.g. "latin1") or nil if unknown
 *
 * According to the MySQL doc every collation can only ever belong to a single charset.
 *
 * This method is thread-safe.
 */
- (NSString *)getEncodingFromCollation:(NSString *)collation {
	if([collation length]) { //shortcut for nil and @""
		for(NSDictionary *coll in [self getDatabaseCollations]) {
			if([[coll objectForKey:@"COLLATION_NAME"] isEqualToString:collation]) {
				return [coll objectForKey:@"CHARACTER_SET_NAME"];
			}
		}
	}
	return nil;
}

/**
 * Returns all of the database's available storage engines.
 *
 * This method is NOT thread-safe!
 */
- (NSArray *)getDatabaseStorageEngines
{	
	return @[];
}

/**
 * Returns all of the database's currently available character set encodings 
 * @return [{CHARACTER_SET_NAME: 'UTF8', ...},...] for PostgreSQL
 *         The Array is never empty and never nil but results might be unreliable.
 *
 * For PostgreSQL this queries pg_encoding
 *
 * This method is thread-safe.
 */ 
- (NSArray *)getDatabaseCharacterSetEncodings
{
	@synchronized(charsetCollationLock) {
		if ([characterSetEncodings count] == 0) {
			
			// For PostgreSQL, get encoding from current database
			// PostgreSQL doesn't have a character_sets table like MySQL
			// Return the server encoding as the available encoding
			NSArray *results = [self _getDatabaseDataForQuery:@"SELECT pg_encoding_to_char(encoding) AS CHARACTER_SET_NAME, pg_encoding_to_char(encoding) AS DESCRIPTION FROM pg_database WHERE datname = current_database()"];
			
			if ([results count]) {
				[characterSetEncodings addObjectsFromArray:results];
			} else {
				// Fallback: add UTF8 as default
				[characterSetEncodings addObject:@{@"CHARACTER_SET_NAME": @"UTF8", @"DESCRIPTION": @"UTF-8 Unicode"}];
			}
		}
			
		return [NSArray arrayWithArray:characterSetEncodings];
	}
}

/**
 * Returns the databases's default character set encoding.
 *
 * @return The default encoding as a string
 *
 * This method is thread-safe.
 */
- (NSString *)getDatabaseDefaultCharacterSet
{
	@synchronized(charsetCollationLock) {
		if (!defaultCharacterSetEncoding) {
			defaultCharacterSetEncoding = [self _getSingleVariableValue:@"character_set_database"];
		}
		
		return [defaultCharacterSetEncoding copy];
	}
}

/**
 * Returns the database's default collation.
 *
 * @return The default collation as a string
 *
 * This method is thread-safe.
 */
- (NSString *)getDatabaseDefaultCollation
{
	@synchronized(charsetCollationLock) {
		if (!defaultCollation) {
			defaultCollation = [self _getSingleVariableValue:@"collation_database"];
		}
			
		return [defaultCollation copy];
	}
}

/**
 * Returns the server's default character set encoding.
 *
 * @return The default encoding as a string
 *
 * This method is thread-safe.
 */
- (NSString *)getServerDefaultCharacterSet
{
	@synchronized(charsetCollationLock) {
		if (!serverDefaultCharacterSetEncoding) {
			serverDefaultCharacterSetEncoding = [self _getSingleVariableValue:@"character_set_server"];
		}
		
		return [serverDefaultCharacterSetEncoding copy];
	}
}

/**
 * Returns the server's default collation.
 *
 * @return The default collation as a string (nil on MySQL 3 databases)
 *
 * This method is thread-safe.
 */
- (NSString *)getServerDefaultCollation
{
	@synchronized(charsetCollationLock) {
		if (!serverDefaultCollation) {
			serverDefaultCollation = [self _getSingleVariableValue:@"collation_server"];
		}
		
		return [serverDefaultCollation copy];
	}
}

/**
 * Returns the database's default storage engine.
 *
 * @return The default storage engine as a string
 *
 * This method is NOT thread-safe!
 */
- (NSString *)getDatabaseDefaultStorageEngine
{
	if (!defaultStorageEngine) {

		// Determine which variable to use based on server version.  'table_type' has been available since MySQL 3.23.0.
		NSString *storageEngineKey = @"table_type";

		// Post 5.5, storage_engine was deprecated; use default_storage_engine
		if ([serverSupport isEqualToOrGreaterThanMajorVersion:5 minor:5 release:0]) {
			storageEngineKey = @"default_storage_engine";

		// For the rest of 5.x, use storage_engine
		} else if ([serverSupport isEqualToOrGreaterThanMajorVersion:5 minor:0 release:0]) {
			storageEngineKey = @"storage_engine";
		}

		// Retrieve the corresponding value for the determined key, ensuring return as a string
		defaultStorageEngine = [self _getSingleVariableValue:storageEngineKey];
	}
	
	return defaultStorageEngine;
}

#pragma mark -
#pragma mark Private API

/**
 * Look up the value of a single server variable
 * @param variable The name of a server variable. Must not contain wildcards
 * @return The value as string or nil if no such variable exists or the result is ambigious
 */
- (NSString *)_getSingleVariableValue:(NSString *)variable
{
    // Map MySQL variables to Postgres settings
    NSString *postgresSetting = variable;
    if ([variable isEqualToString:@"character_set_database"] || [variable isEqualToString:@"character_set_server"]) {
        postgresSetting = @"server_encoding";
    } else if ([variable isEqualToString:@"collation_database"] || [variable isEqualToString:@"collation_server"]) {
        postgresSetting = @"lc_collate";
    } else if ([variable isEqualToString:@"storage_engine"] || [variable isEqualToString:@"default_storage_engine"]) {
        return @"HEAP"; // Default Postgres access method
    }

	SPPostgresResult *result = [connection queryString:[NSString stringWithFormat:@"SELECT current_setting('%@')", postgresSetting]];
	
	[result setReturnDataAsStrings:YES];
	
	if([connection queryErrored])
		SPLog(@"server variable lookup failed for '%@': %@ (%lu)",variable,[connection lastErrorMessage],[connection lastErrorID]);
	
	if ([result numberOfRows] != 1)
		return nil;
	
	return [[result getRowAsArray] firstObject];
}

/**
 * Executes the supplied query against the current connection and returns the result as an array of 
 * NSDictionarys, one for each row.
 */
- (NSArray *)_getDatabaseDataForQuery:(NSString *)query
{
	SPPostgresResult *result = [connection queryString:query];
	
	if ([connection queryErrored]) return @[];
	
	[result setReturnDataAsStrings:YES];
	
	// Get rows as dictionaries
	NSArray *rawRows = [result getAllRowsAsDictionaries];
	
	// PostgreSQL returns lowercase column names, but much of the code expects uppercase (MySQL style)
	// Convert all keys to uppercase for compatibility
	NSMutableArray *uppercasedRows = [NSMutableArray arrayWithCapacity:[rawRows count]];
	for (NSDictionary *row in rawRows) {
		NSMutableDictionary *uppercasedRow = [NSMutableDictionary dictionaryWithCapacity:[row count]];
		for (NSString *key in row) {
			[uppercasedRow setObject:[row objectForKey:key] forKey:[key uppercaseString]];
		}
		[uppercasedRows addObject:uppercasedRow];
	}
	
	return uppercasedRows;
}


/**
 * Sorts a storage engine array by the Engine key.
 */
NSInteger _sortStorageEngineEntry(NSDictionary *itemOne, NSDictionary *itemTwo, void *context)
{
	return [[itemOne objectForKey:@"Engine"] compare:[itemTwo objectForKey:@"Engine"]];
}

#pragma mark -
#pragma mark PostgreSQL Schema Operations

/**
 * Returns all available schemas in the current database.
 */
- (NSArray *)getDatabaseSchemas
{
	NSString *query = @"SELECT nspname AS schema_name FROM pg_namespace "
					   "WHERE nspname NOT LIKE 'pg_%' "
					   "AND nspname != 'information_schema' "
					   "ORDER BY nspname";
	return [self _getDatabaseDataForQuery:query];
}

/**
 * Returns all sequences in the specified schema.
 */
- (NSArray *)getSequencesForSchema:(NSString *)schema
{
	if (!schema) schema = @"public";
	NSString *query = [NSString stringWithFormat:
		@"SELECT sequence_name, data_type, start_value, minimum_value, maximum_value, increment "
		 "FROM information_schema.sequences WHERE sequence_schema = '%@' ORDER BY sequence_name", schema];
	return [self _getDatabaseDataForQuery:query];
}

/**
 * Returns all materialized views in the specified schema.
 */
- (NSArray *)getMaterializedViewsForSchema:(NSString *)schema
{
	if (!schema) schema = @"public";
	NSString *query = [NSString stringWithFormat:
		@"SELECT matviewname AS name, matviewowner AS owner, ispopulated "
		 "FROM pg_matviews WHERE schemaname = '%@' ORDER BY matviewname", schema];
	return [self _getDatabaseDataForQuery:query];
}

/**
 * Returns all domains in the specified schema.
 */
- (NSArray *)getDomainsForSchema:(NSString *)schema
{
	if (!schema) schema = @"public";
	NSString *query = [NSString stringWithFormat:
		@"SELECT domain_name, data_type, domain_default, character_maximum_length "
		 "FROM information_schema.domains WHERE domain_schema = '%@' ORDER BY domain_name", schema];
	return [self _getDatabaseDataForQuery:query];
}

/**
 * Returns all aggregate functions in the specified schema.
 */
- (NSArray *)getAggregatesForSchema:(NSString *)schema
{
	if (!schema) schema = @"public";
	NSString *query = [NSString stringWithFormat:
		@"SELECT p.proname AS aggregate_name, pg_get_function_arguments(p.oid) AS arguments "
		 "FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid "
		 "WHERE n.nspname = '%@' AND p.prokind = 'a' ORDER BY p.proname", schema];
	return [self _getDatabaseDataForQuery:query];
}

/**
 * Returns all operators in the specified schema.
 */
- (NSArray *)getOperatorsForSchema:(NSString *)schema
{
	if (!schema) schema = @"public";
	NSString *query = [NSString stringWithFormat:
		@"SELECT o.oprname AS operator_name, "
		 "COALESCE(lt.typname, 'NONE') AS left_type, "
		 "COALESCE(rt.typname, 'NONE') AS right_type, "
		 "rest.typname AS result_type "
		 "FROM pg_operator o "
		 "JOIN pg_namespace n ON o.oprnamespace = n.oid "
		 "LEFT JOIN pg_type lt ON o.oprleft = lt.oid "
		 "LEFT JOIN pg_type rt ON o.oprright = rt.oid "
		 "JOIN pg_type rest ON o.oprresult = rest.oid "
		 "WHERE n.nspname = '%@' ORDER BY o.oprname", schema];
	return [self _getDatabaseDataForQuery:query];
}

/**
 * Returns all FTS configurations in the specified schema.
 */
- (NSArray *)getFTSConfigurationsForSchema:(NSString *)schema
{
	if (!schema) schema = @"public";
	NSString *query = [NSString stringWithFormat:
		@"SELECT cfgname AS config_name, cfgowner::regrole AS owner "
		 "FROM pg_ts_config c JOIN pg_namespace n ON c.cfgnamespace = n.oid "
		 "WHERE n.nspname = '%@' ORDER BY cfgname", schema];
	return [self _getDatabaseDataForQuery:query];
}

/**
 * Returns all FTS dictionaries in the specified schema.
 */
- (NSArray *)getFTSDictionariesForSchema:(NSString *)schema
{
	if (!schema) schema = @"public";
	NSString *query = [NSString stringWithFormat:
		@"SELECT dictname AS dictionary_name, dictowner::regrole AS owner "
		 "FROM pg_ts_dict d JOIN pg_namespace n ON d.dictnamespace = n.oid "
		 "WHERE n.nspname = '%@' ORDER BY dictname", schema];
	return [self _getDatabaseDataForQuery:query];
}

/**
 * Returns all foreign tables in the specified schema.
 */
- (NSArray *)getForeignTablesForSchema:(NSString *)schema
{
	if (!schema) schema = @"public";
	NSString *query = [NSString stringWithFormat:
		@"SELECT foreign_table_name, foreign_server_name "
		 "FROM information_schema.foreign_tables WHERE foreign_table_schema = '%@' ORDER BY foreign_table_name", schema];
	return [self _getDatabaseDataForQuery:query];
}

/**
 * Returns all custom types in the specified schema.
 */
- (NSArray *)getTypesForSchema:(NSString *)schema
{
	if (!schema) schema = @"public";
	NSString *query = [NSString stringWithFormat:
		@"SELECT t.typname AS type_name, "
		 "CASE t.typtype "
		 "  WHEN 'c' THEN 'composite' "
		 "  WHEN 'e' THEN 'enum' "
		 "  WHEN 'r' THEN 'range' "
		 "  WHEN 'd' THEN 'domain' "
		 "  ELSE 'other' END AS type_category "
		 "FROM pg_type t JOIN pg_namespace n ON t.typnamespace = n.oid "
		 "WHERE n.nspname = '%@' AND t.typtype IN ('c', 'e', 'r') ORDER BY t.typname", schema];
	return [self _getDatabaseDataForQuery:query];
}

/**
 * Returns all collations in the specified schema.
 */
- (NSArray *)getCollationsForSchema:(NSString *)schema
{
	if (!schema) schema = @"public";
	NSString *query = [NSString stringWithFormat:
		@"SELECT collname AS collation_name, collprovider AS provider "
		 "FROM pg_collation c JOIN pg_namespace n ON c.collnamespace = n.oid "
		 "WHERE n.nspname = '%@' ORDER BY collname", schema];
	return [self _getDatabaseDataForQuery:query];
}

/**
 * Returns all trigger functions in the specified schema.
 */
- (NSArray *)getTriggerFunctionsForSchema:(NSString *)schema
{
	if (!schema) schema = @"public";
	NSString *query = [NSString stringWithFormat:
		@"SELECT p.proname AS function_name, pg_get_function_result(p.oid) AS return_type "
		 "FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid "
		 "JOIN pg_type t ON p.prorettype = t.oid "
		 "WHERE n.nspname = '%@' AND t.typname = 'trigger' ORDER BY p.proname", schema];
	return [self _getDatabaseDataForQuery:query];
}

#pragma mark -
#pragma mark Other

- (void)dealloc
{
	[self resetAllData];

}

@end
