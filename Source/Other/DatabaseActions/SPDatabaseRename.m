//
//  SPDatabaseRename.m
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

#import "SPDatabaseRename.h"
#import "SPTableCopy.h"
#import "SPViewCopy.h"
#import "SPTablesList.h"
#import "SPCreateDatabaseInfo.h"

#import <SPMySQL/SPMySQL.h>

@interface SPDatabaseRename ()

- (BOOL)_dropDatabase:(NSString *)database;

- (BOOL)_moveTables:(NSArray *)tables fromDatabase:(NSString *)sourceDatabase toDatabase:(NSString *)targetDatabase;
- (void)_moveViews:(NSArray *)views fromDatabase:(NSString *)sourceDatabase toDatabase:(NSString *)targetDatabase;

@end

@implementation SPDatabaseRename

/**
 * Note that this doesn't currently support moving any non-table objects (i.e. views, proc, functions, events, etc).
 */
- (BOOL)renameDatabaseFrom:(SPCreateDatabaseInfo *)sourceDatabase to:(NSString *)targetDatabase
{
    NSString *sourceDatabaseName = [sourceDatabase databaseName];

    SPLog(@"renameDatabaseFrom: %@, to: %@", sourceDatabaseName, targetDatabase);

	// Check, whether the source database exists and the target database doesn't
	BOOL sourceExists = [[connection databases] containsObject:sourceDatabaseName];
	BOOL targetExists = [[connection databases] containsObject:targetDatabase];

    BOOL success = NO;
    BOOL success2 = NO;
    BOOL success3 = NO;

    if (!sourceExists || targetExists){
        SPLog(@"!sourceExists || targetExists");
        return NO;
    }

	NSArray *tables = [tablesList allTableNames];

    success = [self createDatabase:targetDatabase
                      withEncoding:[sourceDatabase defaultEncoding]
                         collation:[sourceDatabase defaultCollation]];

    if(success == YES){
        SPLog(@"createDatabase SUCCESS, calling move tables");
        success2 = [self _moveTables:tables fromDatabase:sourceDatabaseName toDatabase:targetDatabase];
        if(success2 == NO){
            SPLog(@"_moveTables FAILED: %@", [connection lastErrorMessage]);
        }
        else{
            SPLog(@"_moveTables SUCCESS, calling _dropDatabase");
            success3 = [self _dropDatabase:sourceDatabaseName];
            if(success3 == NO){
                SPLog(@"_dropDatabase FAILED: %@", [connection lastErrorMessage]);
            }
            else{
                SPLog(@"_dropDatabase SUCCESS");
            }
        }
    }
    else{
        SPLog(@"createDatabase FAILED: %@", [connection lastErrorMessage]);
    }

    BOOL ret = success && success2 && success3;

    SPLog(@"ret code: %hhd", ret);

	return ret;
}

#pragma mark -
#pragma mark Private API

/**
 * This method drops a database.
 *
 * @param NSString databaseName name of the database to drop
 * @return BOOL YES on success, otherwise NO
 */
- (BOOL)_dropDatabase:(NSString *)database 
{
    SPLog(@"_dropDatabase: %@", database);

	[connection queryString:[NSString stringWithFormat:@"DROP DATABASE %@", [database backtickQuotedString]]];	
	
	return ![connection queryErrored];
}

- (BOOL)_moveTables:(NSArray *)tables fromDatabase:(NSString *)sourceDatabase toDatabase:(NSString *)targetDatabase
{
    SPLog(@"_moveTables from : %@, to: %@", sourceDatabase, targetDatabase);

    BOOL success = YES;

	SPTableCopy *dbActionTableCopy = [[SPTableCopy alloc] init];
	
	[dbActionTableCopy setConnection:connection];
	
	for (NSString *table in tables) 
	{
        success = [dbActionTableCopy moveTable:table from:sourceDatabase to:targetDatabase];
	}

    return success;
}

- (void)_moveViews:(NSArray *)views fromDatabase:(NSString *)sourceDatabase toDatabase:(NSString *)targetDatabase
{
	SPViewCopy *dbActionViewCopy = [[SPViewCopy alloc] init];
	
	[dbActionViewCopy setConnection:connection];
	
	for (NSString *view in views) 
	{
		[dbActionViewCopy moveView:view from:sourceDatabase to:targetDatabase];
	}
}

@end
