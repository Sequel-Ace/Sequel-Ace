//
//  SPTableCopy.m
//  sequel-pro
//
//  Created by David Rekowski on April 13, 2010.
//  Copyright (c) 2010 David Rekowski. All rights reserved.
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

#import "SPTableCopy.h"

#import <SPMySQL/SPMySQL.h>

@interface SPTableCopy ()

- (NSString *)_createTableStatementFor:(NSString *)tableName inDatabase:(NSString *)sourceDatabase;

@end

@implementation SPTableCopy

- (BOOL)copyTable:(NSString *)tableName from:(NSString *)sourceDatabase to:(NSString *)targetDatabase
{
	NSString *createTableResult = [self _createTableStatementFor:tableName inDatabase:sourceDatabase];
	
	if ([createTableResult hasPrefix:@"CREATE TABLE"]) {
		// Postgres specific copy structure
		NSString *createTableStatement = [NSString stringWithFormat:@"CREATE TABLE %@.%@ (LIKE %@.%@ INCLUDING ALL)",
										  [targetDatabase postgresQuotedIdentifier],
										  [tableName postgresQuotedIdentifier],
										  [sourceDatabase postgresQuotedIdentifier],
										  [tableName postgresQuotedIdentifier]];

		[connection queryString:createTableStatement];		
		
		return ![connection queryErrored];
	}
	
	return NO;
}

- (BOOL)copyTable:(NSString *)tableName from:(NSString *)sourceDatabase to:(NSString *)targetDatabase withContent:(BOOL)copyWithContent
{
	// Copy the table structure
	BOOL structureCopySuccess = [self copyTable:tableName from:sourceDatabase to:targetDatabase];
	
	// Optionally copy the table data using an insert select
	if (structureCopySuccess && copyWithContent) {
		
		NSString *copyDataStatement = [NSString stringWithFormat:@"INSERT INTO %@.%@ SELECT * FROM %@.%@", 
									   [targetDatabase postgresQuotedIdentifier],
									   [tableName postgresQuotedIdentifier],
									   [sourceDatabase postgresQuotedIdentifier],
									   [tableName postgresQuotedIdentifier]
									   ];
		
		[connection queryString:copyDataStatement];		

		return ![connection queryErrored];
	}
	
	return structureCopySuccess;
}

- (BOOL)copyTables:(NSArray *)tablesArray from:(NSString *)sourceDatabase to:(NSString *)targetDatabase withContent:(BOOL)copyWithContent
{
	BOOL success = YES;
	
	// Disable foreign key checks
	[connection queryString:@"/*!32352 SET foreign_key_checks=0 */"];
	
	if ([connection queryErrored]) {
		success = NO;
	}
	
	// Disable auto-id creation for '0' values
	[connection queryString:@"/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */"];
	
	if([connection queryErrored]) {
		success = NO;
	}
	
	for (NSString *tableName in tablesArray) 
	{
		if (![self copyTable:tableName from:sourceDatabase to:targetDatabase withContent:copyWithContent]) {
			success = NO;
		}
	}
	
	// Enable foreign key checks
	[connection queryString:@"/*!32352 SET foreign_key_checks=1 */"];
	
	if ([connection queryErrored]) {
		success = NO;
	}
	
	// Re-enable id creation
	[connection queryString:@"/*!40101 SET SQL_MODE=@OLD_SQL_MODE */"];
	
	if ([connection queryErrored]) {
		success = NO;
	}
	
	return success;
}

- (BOOL)moveTable:(NSString *)tableName from:(NSString *)sourceDatabase to:(NSString *)targetDatabase
{
	NSString *moveStatement = [NSString stringWithFormat:@"ALTER TABLE %@.%@ RENAME TO %@", 
							   [sourceDatabase postgresQuotedIdentifier],
							   [tableName postgresQuotedIdentifier],
							   [tableName postgresQuotedIdentifier]];
	// Postgres RENAME TO only takes the new name, not the schema.
	// If we want to move to another schema, we use SET SCHEMA.
	// But here it seems we are renaming across databases? Postgres databases are isolated.
	// If sourceDatabase and targetDatabase are different, we can't easily move tables between them in Postgres unless they are schemas in the same DB.
	// Assuming they are schemas for now (since Sequel Ace treats schemas as databases often).
	
	if (![sourceDatabase isEqualToString:targetDatabase]) {
		moveStatement = [NSString stringWithFormat:@"ALTER TABLE %@.%@ SET SCHEMA %@",
						 [sourceDatabase postgresQuotedIdentifier],
						 [tableName postgresQuotedIdentifier],
						 [targetDatabase postgresQuotedIdentifier]];
	} else {
		// Just renaming in same schema? The method signature implies moving/renaming.
		// If just renaming:
		// moveStatement = [NSString stringWithFormat:@"ALTER TABLE %@.%@ RENAME TO %@", ...];
		// But the arguments are sourceDatabase and targetDatabase.
		// If they are same, it's a rename? But tableName is same in args?
		// The method is moveTable:from:to:
		// If tableName is same, and db is different, it's a move.
	}

    SPLog(@"moveTable from : %@, to: %@", sourceDatabase, targetDatabase);
    SPLog(@"moveTable moveStatement: %@", moveStatement);

	[connection queryString:moveStatement];
	
	return ![connection queryErrored];
}

#pragma mark -
#pragma mark Private API

- (NSString *)_createTableStatementFor:(NSString *)tableName inDatabase:(NSString *)sourceDatabase
{

    if([tableName respondsToSelector:@selector(postgresQuotedIdentifier)] == NO || [sourceDatabase respondsToSelector:@selector(postgresQuotedIdentifier)] == NO){
        SPLog(@"_createTableStatementFor: tableName or sourceDatabase does not respond to selector: postgresQuotedIdentifier");
        return  nil;
    }

	NSString *showCreateTableStatment = [NSString stringWithFormat:@"SHOW CREATE TABLE %@.%@", [sourceDatabase postgresQuotedIdentifier], [tableName postgresQuotedIdentifier]];
	
	SPMySQLResult *result = [connection queryString:showCreateTableStatment];
	
	if ([result numberOfRows] > 0) return [[result getRowAsArray] objectAtIndex:1];
	
	SPLog(@"query <%@> failed to return the expected result.\n  Error state: %@ (%lu)", showCreateTableStatment, [connection lastErrorMessage], [connection lastErrorID]);

	return nil;
}

@end
