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
@property (nonatomic, copy, readwrite, nullable) NSString *warningDescription;
@property (nonatomic, readwrite) BOOL changedServer;
@property (nonatomic, readwrite) BOOL connectionUsable;

@end

@implementation SPDatabaseRename

/**
 * Hands the rename to SADatabaseRenameConnectionSession, which switches the
 * connection to UTF-8 where needed, lets SADatabaseRenameExecutor inspect the
 * source, move the tables, recreate the views and drop the source only when
 * everything moved, and restores and verifies the connection afterwards. This
 * method only reaches the connection for it and reports the outcome.
 */
- (BOOL)renameDatabaseFrom:(SPCreateDatabaseInfo *)sourceDatabase to:(NSString *)targetDatabase
{
    NSString *sourceDatabaseName = [sourceDatabase databaseName];

    SPLog(@"renameDatabaseFrom: %@, to: %@", sourceDatabaseName, targetDatabase);

    self.failureDescription = nil;
    self.warningDescription = nil;
    self.changedServer = NO;
    self.connectionUsable = YES;

	// Check, whether the source database exists and the target database doesn't
	BOOL sourceExists = [[connection databases] containsObject:sourceDatabaseName];
	BOOL targetExists = [[connection databases] containsObject:targetDatabase];

    if (!sourceExists || targetExists){
        SPLog(@"!sourceExists || targetExists");
        return NO;
    }

    SPMySQLConnection *renameConnection = connection;

    SADatabaseRenameConnectionSession *session = [[SADatabaseRenameConnectionSession alloc] initWithRun:^SADatabaseRenameStatementResult *(NSString *statement) {
        // The result type decides what counts as success, including a
        // missing result object that the connection did not flag as an error.
        SPMySQLResult *result = [renameConnection queryString:statement];
        BOOL errored = [renameConnection queryErrored];
        NSMutableArray *rows = [NSMutableArray array];
        if (result && !errored) {
            [result setReturnDataAsStrings:YES];
            NSArray *row;
            while ((row = [result getRowAsArray]) != nil) {
                [rows addObject:row];
            }
        }
        return [[SADatabaseRenameStatementResult alloc] initWithRows:rows resultReturned:(result != nil) errored:errored errorMessage:[renameConnection lastErrorMessage]];
    } quote:^NSString *(NSString *value) {
        return [renameConnection escapeAndQuoteString:value];
    } encoding:^NSString *{
        return [renameConnection encoding];
    } usesLatin1Transport:^BOOL{
        return [renameConnection encodingUsesLatin1Transport];
    } setEncoding:^BOOL(NSString *encoding) {
        return [renameConnection setEncoding:encoding];
    } setLatin1Transport:^BOOL(BOOL useLatin1Transport) {
        return [renameConnection setEncodingUsesLatin1Transport:useLatin1Transport];
    } storeEncodingForRestoration:^{
        [renameConnection storeEncodingForRestoration];
    } restoreStoredEncoding:^{
        [renameConnection restoreStoredEncoding];
    } reconnect:^BOOL{
        return [renameConnection reconnect];
    }];

    self.failureDescription = [session renameDatabase:sourceDatabaseName
                                                   to:targetDatabase
                                             encoding:[sourceDatabase defaultEncoding]
                                            collation:[sourceDatabase defaultCollation]];
    self.changedServer = [session changedServer];
    self.warningDescription = [session warningDescription];
    self.connectionUsable = [session connectionUsable];
    if (self.warningDescription) {
        SPLog(@"rename warning: %@", self.warningDescription);
    }
    if (self.failureDescription) {
        SPLog(@"rename failed: %@", self.failureDescription);
        return NO;
    }

    return YES;
}

@end
