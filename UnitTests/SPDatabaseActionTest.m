//
//  SPDatabaseActionTest.m
//  sequel-pro
//
//  Created by Max Lohrmann on 12.03.15.
//  Copyright (c) 2015 Max Lohrmann. All rights reserved.
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

#import <OCMock/OCMock.h>
#import <XCTest/XCTest.h>

#import "SPDatabaseAction.h"
#import "SPDatabaseData.h"
#import "sequel-ace-Swift.h"
#import <SPMySQL/SPMySQL.h>

@interface SPDatabaseActionTest : XCTestCase

- (void)testCreateDatabase_01_emptyName;
- (void)testCreateDatabase_02_allParams;
- (void)testCreateDatabase_03_nameOnly;

@end

@interface SPDatabaseDataCharsetTests : XCTestCase

- (void)testNormalizeCharacterSetRows_MapsShowCharacterSetColumns;
- (void)testNormalizeCharacterSetRows_DeduplicatesByCharacterSetName;
- (void)testNormalizeCharacterSetRows_SkipsRowsWithoutCharacterSetName;
- (void)testFallbackCharacterSetEncodings_UsesExpectedOrder;

@end

@interface SPTableDataLoadFailureTests : XCTestCase

- (void)testTableInformationLoadFailureTracking_MatchesOnlySameTarget;
- (void)testTableInformationLoadFailureTracking_HandlesNilTargetValues;

@end

@interface SPDatabaseData (SPDatabaseDataTests)

- (NSArray *)_normalizedCharacterSetEncodingsFromRows:(NSArray *)rows;
- (NSArray *)_fallbackCharacterSetEncodings;

@end

@implementation SPDatabaseActionTest

- (void)testCreateDatabase_01_emptyName
{
	id mockConnection = OCMStrictClassMock([SPMySQLConnection class]);
	//OCMStrictClassMock would fail on any call, which is desired here
	
	SPDatabaseAction *createDb = [[SPDatabaseAction alloc] init];
	[createDb setConnection:mockConnection];
	XCTAssertFalse([createDb createDatabase:@"" withEncoding:nil collation:nil],@"create database = NO with empty db name");
	
	OCMVerifyAll(mockConnection);
}

- (void)testCreateDatabase_02_allParams
{
	id mockConnection = OCMStrictClassMock([SPMySQLConnection class]);
	
	OCMExpect([mockConnection queryString:@"CREATE DATABASE `target_name` DEFAULT CHARACTER SET = `utf8` DEFAULT COLLATE = `utf8_bin_ci`"]);
	OCMStub([mockConnection queryErrored]).andReturn(NO);
	
	SPDatabaseAction *createDb = [[SPDatabaseAction alloc] init];
	[createDb setConnection:mockConnection];
	
	XCTAssertTrue([createDb createDatabase:@"target_name" withEncoding:@"utf8" collation:@"utf8_bin_ci"], @"create database return");
	
	OCMVerifyAll(mockConnection);
}

- (void)testCreateDatabase_03_nameOnly
{
	id mockConnection = OCMStrictClassMock([SPMySQLConnection class]);
	
	OCMExpect([mockConnection queryString:@"CREATE DATABASE `target_name`"]);
	OCMStub([mockConnection queryErrored]).andReturn(NO);
	
	SPDatabaseAction *createDb = [[SPDatabaseAction alloc] init];
	[createDb setConnection:mockConnection];
	
	XCTAssertTrue([createDb createDatabase:@"target_name" withEncoding:@"" collation:nil], @"create database return");
	
	OCMVerifyAll(mockConnection);
}

@end

@implementation SPTableDataLoadFailureTests

- (void)testTableInformationLoadFailureTracking_MatchesOnlySameTarget
{
	SPTableLoadFailure *failure = [SPTableLoadFailure failureWithTableName:@"orders" database:@"app" tableType:1];

	XCTAssertTrue([failure matchesTableName:@"orders" database:@"app" tableType:1]);
	XCTAssertFalse([failure matchesTableName:@"orders" database:@"analytics" tableType:1]);
	XCTAssertFalse([failure matchesTableName:@"orders" database:@"app" tableType:2]);
}

- (void)testTableInformationLoadFailureTracking_HandlesNilTargetValues
{
	SPTableLoadFailure *failure = [SPTableLoadFailure failureWithTableName:nil database:nil tableType:3];

	XCTAssertTrue([failure matchesTableName:nil database:nil tableType:3]);
	XCTAssertTrue([failure matchesTableName:@"" database:@"" tableType:3]);
	XCTAssertFalse([failure matchesTableName:@"users" database:nil tableType:3]);
}

@end

@implementation SPDatabaseDataCharsetTests

- (void)testNormalizeCharacterSetRows_MapsShowCharacterSetColumns
{
	SPDatabaseData *databaseData = [[SPDatabaseData alloc] init];

	NSArray *rows = @[
		@{
			@"Charset": @"utf8mb4",
			@"Description": @"UTF-8 Unicode",
			@"Default collation": @"utf8mb4_general_ci",
			@"Maxlen": @4
		}
	];

	NSArray *normalizedRows = [databaseData _normalizedCharacterSetEncodingsFromRows:rows];

	XCTAssertEqual([normalizedRows count], 1UL);
	NSDictionary *row = [normalizedRows firstObject];
	XCTAssertEqualObjects([row objectForKey:@"CHARACTER_SET_NAME"], @"utf8mb4");
	XCTAssertEqualObjects([row objectForKey:@"DESCRIPTION"], @"UTF-8 Unicode");
	XCTAssertEqualObjects([row objectForKey:@"DEFAULT_COLLATE_NAME"], @"utf8mb4_general_ci");
	XCTAssertEqualObjects([row objectForKey:@"MAXLEN"], @"4");
}

- (void)testNormalizeCharacterSetRows_DeduplicatesByCharacterSetName
{
	SPDatabaseData *databaseData = [[SPDatabaseData alloc] init];

	NSArray *rows = @[
		@{@"Charset": @"utf8", @"Description": @"first"},
		@{@"CHARACTER_SET_NAME": @"utf8", @"DESCRIPTION": @"second"},
		@{@"Charset": @"latin1", @"Description": @"third"}
	];

	NSArray *normalizedRows = [databaseData _normalizedCharacterSetEncodingsFromRows:rows];

	XCTAssertEqual([normalizedRows count], 2UL);
	XCTAssertEqualObjects([[normalizedRows firstObject] objectForKey:@"CHARACTER_SET_NAME"], @"utf8");
	XCTAssertEqualObjects([[normalizedRows objectAtIndex:1] objectForKey:@"CHARACTER_SET_NAME"], @"latin1");
}

- (void)testNormalizeCharacterSetRows_SkipsRowsWithoutCharacterSetName
{
	SPDatabaseData *databaseData = [[SPDatabaseData alloc] init];

	NSArray *rows = @[
		@{@"Charset": @"", @"Description": @"empty"},
		@{@"CHARACTER_SET_NAME": @"   ", @"DESCRIPTION": @"spaces"},
		@{@"description": @"missing name"},
		@{@"CHARACTER_SET_NAME": @"utf8mb4", @"DESCRIPTION": @"valid"}
	];

	NSArray *normalizedRows = [databaseData _normalizedCharacterSetEncodingsFromRows:rows];

	XCTAssertEqual([normalizedRows count], 1UL);
	XCTAssertEqualObjects([[normalizedRows firstObject] objectForKey:@"CHARACTER_SET_NAME"], @"utf8mb4");
}

- (void)testFallbackCharacterSetEncodings_UsesExpectedOrder
{
	SPDatabaseData *databaseData = [[SPDatabaseData alloc] init];
	NSArray *fallbackRows = [databaseData _fallbackCharacterSetEncodings];

	XCTAssertEqual([fallbackRows count], 3UL);
	XCTAssertEqualObjects([[fallbackRows firstObject] objectForKey:@"CHARACTER_SET_NAME"], @"utf8mb4");
	XCTAssertEqualObjects([[fallbackRows objectAtIndex:1] objectForKey:@"CHARACTER_SET_NAME"], @"utf8");
	XCTAssertEqualObjects([[fallbackRows objectAtIndex:2] objectForKey:@"CHARACTER_SET_NAME"], @"latin1");
}

@end
