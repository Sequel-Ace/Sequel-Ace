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
#import "sequel-ace-Swift.h"

#import "SPFunctions.h"
#import <SPMySQL/SPMySQL.h>

@interface NSAlert (SPDatabaseDataAlertCompatibility)
+ (void)createWarningAlertWithTitle:(NSString *)title message:(NSString *)message callback:(void (^)(void))callback;
@end

@interface SPDatabaseData ()

- (NSString *)_getSingleVariableValue:(NSString *)variable;
- (NSArray *)_getDatabaseDataForQuery:(NSString *)query;
- (NSArray *)_normalizedCharacterSetEncodingsFromRows:(NSArray *)rows;
- (NSArray *)_fallbackCharacterSetEncodings;
- (void)_showCharacterSetFallbackWarning;

NSInteger _sortStorageEngineEntry(NSDictionary *itemOne, NSDictionary *itemTwo, void *context);

@end

@implementation SPDatabaseData
{
	BOOL _hasShownCharacterSetFallbackWarning;
}

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
		_hasShownCharacterSetFallbackWarning = NO;
		
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
		_hasShownCharacterSetFallbackWarning = NO;
	}
}

/**
 * Returns all of the database's currently available collations by querying information_schema.collations.
 *
 * This method is thread-safe.
 */
- (NSArray *)getDatabaseCollations
{
	@synchronized(charsetCollationLock) {
		if ([collations count] == 0) {
			
			// Try to retrieve the available collations from the database
            [collations addObjectsFromArray:[self _getDatabaseDataForQuery:@"SELECT * FROM `information_schema`.`collations` ORDER BY `collation_name` ASC"]];
			
			// If that failed, get the list of collations from the hard-coded list
			if (![collations count]) {
				[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error", @"error") message:NSLocalizedString(@"Unable to get database collations", @"Unable to get database collations") callback:nil];
			}
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
		if (encoding && ((characterSetEncoding == nil) || (![characterSetEncoding isEqualToString:encoding]) || ([characterSetCollations count] == 0))) {
			 //depends on encoding
			[characterSetCollations removeAllObjects];
			
			characterSetEncoding = [[NSString alloc] initWithString:encoding];

			NSArray *cachedCollations = [cachedCollationsByEncoding objectForKey:characterSetEncoding];
			if([cachedCollations count]) {
				[characterSetCollations addObjectsFromArray:cachedCollations];
				goto copy_return;
			}

			// Try to retrieve the available collations for the supplied encoding from the database
            [characterSetCollations addObjectsFromArray:[self _getDatabaseDataForQuery:[NSString stringWithFormat:@"SELECT * FROM `information_schema`.`collations` WHERE character_set_name = '%@' ORDER BY `collation_name` ASC", characterSetEncoding]]];

            //Special handling to try utf8 if the encoding is utf8mb3 https://github.com/Sequel-Ace/Sequel-Ace/issues/1064
            if (![characterSetCollations count] && [characterSetEncoding isEqualToString:@"utf8mb3"]) {
                [characterSetCollations addObjectsFromArray:[self _getDatabaseDataForQuery:[NSString stringWithFormat:@"SELECT * FROM `information_schema`.`collations` WHERE character_set_name = '%@' ORDER BY `collation_name` ASC", @"utf8"]]];
            } else if (![characterSetCollations count] && [characterSetEncoding isEqualToString:@"utf8"]) {
                [characterSetCollations addObjectsFromArray:[self _getDatabaseDataForQuery:[NSString stringWithFormat:@"SELECT * FROM `information_schema`.`collations` WHERE character_set_name = '%@' ORDER BY `collation_name` ASC", @"utf8mb3"]]];
            }

			// If that failed, get the list of collations matching the supplied encoding from the hard-coded list
			if (![characterSetCollations count]) {
                SPMainQSync(^{
                    [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error", @"error") message:NSLocalizedString(@"Unable to get database collations for given encoding", @"Unable to get database collations for given encoding") callback:nil];
                });
			}

			if ([characterSetCollations count]) {
				[cachedCollationsByEncoding setObject:[NSArray arrayWithArray:characterSetCollations] forKey:characterSetEncoding];
			}

		}
copy_return:
		return [NSArray arrayWithArray:characterSetCollations]; //copy because it is a mutable array and we keep changing it
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
	if ([storageEngines count] == 0) {
        // Check the information_schema.engines table is accessible
        SPMySQLResult *result = [connection queryString:@"SHOW TABLES IN information_schema LIKE 'ENGINES'"];
        
        if ([result numberOfRows] == 1) {
            
            // Table is accessible so get available storage engines
            // Note, that the case of the column names specified in this query are important.
            [storageEngines addObjectsFromArray:[self _getDatabaseDataForQuery:@"SELECT Engine, Support FROM `information_schema`.`engines` WHERE SUPPORT IN ('DEFAULT', 'YES') AND Engine != 'PERFORMANCE_SCHEMA'"]];
        }
	}
	
	return [storageEngines sortedArrayUsingFunction:_sortStorageEngineEntry context:nil];
}

/**
 * Returns all of the database's currently available character set encodings 
 * @return [{CHARACTER_SET_NAME: 'utf8', DESCRIPTION: 'UTF-8 Unicode', DEFAULT_COLLATE_NAME: 'utf8_general_ci', MAXLEN: 3},...]
 *         The Array is never empty and never nil but results might be unreliable.
 *
 * On MySQL 5+ this will query information_schema.character_sets
 * On MySQL 4.1+ this will query SHOW CHARACTER SET
 * Else a hardcoded list will be returned
 *
 * This method is thread-safe.
 */ 
- (NSArray *)getDatabaseCharacterSetEncodings
{
	BOOL shouldShowFallbackWarning = NO;

	@synchronized(charsetCollationLock) {
		if ([characterSetEncodings count] == 0) {

			// Prefer information_schema when available.
			[characterSetEncodings addObjectsFromArray:[self _normalizedCharacterSetEncodingsFromRows:[self _getDatabaseDataForQuery:@"SELECT * FROM `information_schema`.`character_sets` ORDER BY `character_set_name` ASC"]]];

			// Fallback for MySQL-compatible proxies that don't fully expose information_schema.
			if (![characterSetEncodings count]) {
				[characterSetEncodings addObjectsFromArray:[self _normalizedCharacterSetEncodingsFromRows:[self _getDatabaseDataForQuery:@"SHOW CHARACTER SET"]]];
			}

			// Last-resort fallback keeps the app usable with limited protocol implementations.
			if (![characterSetEncodings count]) {
				[characterSetEncodings addObjectsFromArray:[self _fallbackCharacterSetEncodings]];
				if (!_hasShownCharacterSetFallbackWarning) {
					_hasShownCharacterSetFallbackWarning = YES;
					shouldShowFallbackWarning = YES;
				}
			}
		}
	}

	if (shouldShowFallbackWarning) {
		[self _showCharacterSetFallbackWarning];
	}

	return [NSArray arrayWithArray:characterSetEncodings]; // return a copy since we keep changing it
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
	SPMySQLResult *result = [connection queryString:[NSString stringWithFormat:@"SHOW VARIABLES LIKE %@", [variable tickQuotedString]]];;
	
	[result setReturnDataAsStrings:YES];
	
	if([connection queryErrored])
		SPLog(@"server variable lookup failed for '%@': %@ (%lu)",variable,[connection lastErrorMessage],[connection lastErrorID]);
	
	if ([result numberOfRows] != 1)
		return nil;
	
	return [[result getRowAsDictionary] objectForKey:@"Value"];
}

/**
 * Executes the supplied query against the current connection and returns the result as an array of 
 * NSDictionarys, one for each row.
 */
- (NSArray *)_getDatabaseDataForQuery:(NSString *)query
{
	SPMySQLResult *result = [connection queryString:query];
	
	if ([connection queryErrored]) return @[];
	
	[result setReturnDataAsStrings:YES];
	
	return [result getAllRows];
}

- (NSArray *)_normalizedCharacterSetEncodingsFromRows:(NSArray *)rows
{
	if (![rows count]) return @[];

	NSMutableArray *normalizedRows = [NSMutableArray array];
	NSMutableSet *seenCharsetNames = [NSMutableSet set];

	for (NSDictionary *row in rows) {

		NSString *charsetName = [row objectForKey:@"CHARACTER_SET_NAME"];
		if (![charsetName length]) charsetName = [row objectForKey:@"character_set_name"];
		if (![charsetName length]) charsetName = [row objectForKey:@"Charset"];
		if (![charsetName length]) charsetName = [row objectForKey:@"charset"];
		if (![charsetName length] || [seenCharsetNames containsObject:charsetName]) continue;

		NSString *description = [row objectForKey:@"DESCRIPTION"];
		if (!description) description = [row objectForKey:@"Description"];
		if (!description) description = [row objectForKey:@"description"];

		NSString *defaultCollationName = [row objectForKey:@"DEFAULT_COLLATE_NAME"];
		if (!defaultCollationName) defaultCollationName = [row objectForKey:@"default_collate_name"];
		if (!defaultCollationName) defaultCollationName = [row objectForKey:@"Default collation"];
		if (!defaultCollationName) defaultCollationName = [row objectForKey:@"Default Collation"];

		id maxLength = [row objectForKey:@"MAXLEN"];
		if (!maxLength) maxLength = [row objectForKey:@"Maxlen"];
		if (!maxLength) maxLength = [row objectForKey:@"maxlen"];

		NSMutableDictionary *normalizedRow = [NSMutableDictionary dictionaryWithObject:charsetName forKey:@"CHARACTER_SET_NAME"];
		[normalizedRow setObject:(description ?: @"") forKey:@"DESCRIPTION"];
		if (defaultCollationName) [normalizedRow setObject:defaultCollationName forKey:@"DEFAULT_COLLATE_NAME"];
		if (maxLength) [normalizedRow setObject:[NSString stringWithFormat:@"%@", maxLength] forKey:@"MAXLEN"];

		[seenCharsetNames addObject:charsetName];
		[normalizedRows addObject:normalizedRow];
	}

	return normalizedRows;
}

- (NSArray *)_fallbackCharacterSetEncodings
{
	return @[
		@{@"CHARACTER_SET_NAME" : @"utf8mb4", @"DESCRIPTION" : @"UTF-8 Unicode"},
		@{@"CHARACTER_SET_NAME" : @"utf8", @"DESCRIPTION" : @"UTF-8 Unicode (BMP only)"},
		@{@"CHARACTER_SET_NAME" : @"latin1", @"DESCRIPTION" : @"cp1252 West European"}
	];
}

- (void)_showCharacterSetFallbackWarning
{
	SPMainQSync(^{
		[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Limited Character Set Metadata", @"charset fallback warning title")
									 message:NSLocalizedString(@"The server did not provide character set metadata. Sequel Ace will continue using a fallback UTF-8 compatible character set list.", @"charset fallback warning message")
									callback:nil];
	});
}


/**
 * Sorts a storage engine array by the Engine key.
 */
NSInteger _sortStorageEngineEntry(NSDictionary *itemOne, NSDictionary *itemTwo, void *context)
{
	return [[itemOne objectForKey:@"Engine"] compare:[itemTwo objectForKey:@"Engine"]];
}

#pragma mark -
#pragma mark Other

- (void)dealloc
{
	[self resetAllData];

}

@end
