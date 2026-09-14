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
#import "SPCreateDatabaseInfo.h"
#import "sequel-ace-Swift.h"

#import <SPMySQL/SPMySQL.h>

@interface SPDatabaseRename ()

@property (nonatomic, copy, readwrite, nullable) NSString *failureDescription;
@property (nonatomic, readwrite) BOOL changedServer;

@end

@implementation SPDatabaseRename

/**
 * Hands the rename to SADatabaseRenameExecutor, which inspects the source,
 * refuses databases holding triggers, routines or events, moves the tables,
 * recreates the views and drops the source only when everything moved. This
 * method only runs the statements it is given and reports the outcome.
 */
- (BOOL)renameDatabaseFrom:(SPCreateDatabaseInfo *)sourceDatabase to:(NSString *)targetDatabase
{
    NSString *sourceDatabaseName = [sourceDatabase databaseName];

    SPLog(@"renameDatabaseFrom: %@, to: %@", sourceDatabaseName, targetDatabase);

    self.failureDescription = nil;
    self.changedServer = NO;

	// Check, whether the source database exists and the target database doesn't
	BOOL sourceExists = [[connection databases] containsObject:sourceDatabaseName];
	BOOL targetExists = [[connection databases] containsObject:targetDatabase];

    if (!sourceExists || targetExists){
        SPLog(@"!sourceExists || targetExists");
        return NO;
    }

    SPMySQLConnection *renameConnection = connection;

    // View definitions travel through the connection's encoding on the way
    // in and out; on a latin1 connection every character outside latin1
    // would arrive as '?' and be written back that way. Read and replay them
    // through utf8mb4 (utf8 on servers without it) and restore the encoding
    // afterwards.
    BOOL encodingChanged = NO;
    NSString *originalCollation = nil;
    if (![[renameConnection encoding] isEqualToString:@"utf8mb4"] || [renameConnection encodingUsesLatin1Transport]) {
        // SET NAMES replaces the session's collation with the character set's
        // default on the way in and out; keep the one the session had. Without
        // it the restore would leave the connection on that default, so a
        // collation that cannot be read stops the rename before anything is
        // switched.
        SPMySQLResult *collationResult = [renameConnection queryString:@"SELECT @@collation_connection"];
        if (![renameConnection queryErrored]) {
            [collationResult setReturnDataAsStrings:YES];
            originalCollation = [[collationResult getRowAsArray] firstObject];
        }
        if (![originalCollation isKindOfClass:[NSString class]]) {
            self.failureDescription = NSLocalizedString(@"The connection's collation could not be read, so it could not be restored after the rename. Nothing was changed.", @"rename database refused because @@collation_connection could not be read before switching the connection to UTF-8");
            SPLog(@"rename refused: %@", self.failureDescription);
            return NO;
        }
        [renameConnection storeEncodingForRestoration];
        encodingChanged = [renameConnection setEncoding:@"utf8mb4"] || [renameConnection setEncoding:@"utf8"];
        if (!encodingChanged) {
            // Without UTF-8 transport a view definition could arrive and go
            // back with characters replaced; better not to start at all.
            [renameConnection restoreStoredEncoding];
            self.failureDescription = NSLocalizedString(@"The connection could not be switched to UTF-8, which Rename Database needs to move view definitions without loss. Nothing was changed.", @"rename database refused because the connection could not be switched to a UTF-8 character set");
            SPLog(@"rename refused: %@", self.failureDescription);
            return NO;
        }
        [renameConnection setEncodingUsesLatin1Transport:NO];
    }

    SADatabaseRenameExecutor *executor = [[SADatabaseRenameExecutor alloc] initWithRun:^SADatabaseRenameStatementResult *(NSString *statement) {
        SPMySQLResult *result = [renameConnection queryString:statement];
        if ([renameConnection queryErrored]) {
            return [[SADatabaseRenameStatementResult alloc] initWithError:[renameConnection lastErrorMessage]];
        }
        [result setReturnDataAsStrings:YES];
        NSMutableArray *rows = [NSMutableArray array];
        NSArray *row;
        while ((row = [result getRowAsArray]) != nil) {
            [rows addObject:row];
        }
        return [[SADatabaseRenameStatementResult alloc] initWithRows:rows];
    } quote:^NSString *(NSString *value) {
        return [renameConnection escapeAndQuoteString:value];
    }];

    self.failureDescription = [executor renameDatabase:sourceDatabaseName
                                                    to:targetDatabase
                                              encoding:[sourceDatabase defaultEncoding]
                                             collation:[sourceDatabase defaultCollation]];
    self.changedServer = [executor changedServer];
    if (encodingChanged) {
        [renameConnection restoreStoredEncoding];
        if ([originalCollation isKindOfClass:[NSString class]]) {
            [renameConnection queryString:[NSString stringWithFormat:@"SET collation_connection = %@", [renameConnection escapeAndQuoteString:originalCollation]]];
        }
    }
    if (self.failureDescription) {
        SPLog(@"rename failed: %@", self.failureDescription);
        return NO;
    }

    return YES;
}

@end
