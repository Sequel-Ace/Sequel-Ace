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

@interface SPProcessListSerializationTest : XCTestCase

- (void)testSerializedProcessRow_01_nullValuesBecomeEmptyTokens;
- (void)testSerializedProcessRow_02_progressIsIncludedWhenRequestedAndPresent;
- (void)testSerializedProcessRow_03_progressIsSkippedWhenNullOrMissing;
- (void)testSerializedProcessRow_04_progressIsIgnoredWhenNotRequested;

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

@implementation SPProcessListSerializationTest

- (void)testSerializedProcessRow_01_nullValuesBecomeEmptyTokens
{
	NSDictionary *process = @{
		@"Id": @42,
		@"User": @"alice",
		@"Host": @"localhost:3306",
		@"db": [NSNull null],
		@"Command": @"Query",
		@"Time": @15,
		@"State": [NSNull null],
		@"Info": [NSNull null]
	};

	NSString *serialized = [self _serializeProcess:process includeProgress:NO];

	XCTAssertFalse([serialized containsString:@"(null)"]);
	XCTAssertEqualObjects([self _nonEmptyTokensFromSerializedRow:serialized], (@[@"42", @"alice", @"localhost:3306", @"Query", @"15"]));
}

- (void)testSerializedProcessRow_02_progressIsIncludedWhenRequestedAndPresent
{
	NSDictionary *process = @{
		@"Id": @7,
		@"User": @"bob",
		@"Host": @"db.internal",
		@"db": @"analytics",
		@"Command": @"Query",
		@"Time": @3,
		@"State": @"executing",
		@"Info": @"SELECT_1",
		@"Progress": @"99.50"
	};

	NSString *serialized = [self _serializeProcess:process includeProgress:YES];

	XCTAssertFalse([serialized containsString:@"(null)"]);
	XCTAssertEqualObjects([self _nonEmptyTokensFromSerializedRow:serialized], (@[@"7", @"bob", @"db.internal", @"analytics", @"Query", @"3", @"executing", @"SELECT_1", @"99.50"]));
}

- (void)testSerializedProcessRow_03_progressIsSkippedWhenNullOrMissing
{
	NSDictionary *processWithNullProgress = @{
		@"Id": @12,
		@"User": @"carol",
		@"Host": @"127.0.0.1",
		@"db": @"sales",
		@"Command": @"Sleep",
		@"Time": @22,
		@"State": @"idle",
		@"Info": @"-",
		@"Progress": [NSNull null]
	};

	NSDictionary *processWithoutProgress = @{
		@"Id": @12,
		@"User": @"carol",
		@"Host": @"127.0.0.1",
		@"db": @"sales",
		@"Command": @"Sleep",
		@"Time": @22,
		@"State": @"idle",
		@"Info": @"-"
	};

	NSString *serializedWithNullProgress = [self _serializeProcess:processWithNullProgress includeProgress:YES];
	NSString *serializedWithoutProgress = [self _serializeProcess:processWithoutProgress includeProgress:YES];

	XCTAssertEqualObjects([self _nonEmptyTokensFromSerializedRow:serializedWithNullProgress], (@[@"12", @"carol", @"127.0.0.1", @"sales", @"Sleep", @"22", @"idle", @"-"]));
	XCTAssertEqualObjects(serializedWithNullProgress, serializedWithoutProgress);
}

- (void)testSerializedProcessRow_04_progressIsIgnoredWhenNotRequested
{
	NSDictionary *process = @{
		@"Id": @100,
		@"User": @"dave",
		@"Host": @"10.0.0.4",
		@"db": @"reporting",
		@"Command": @"Query",
		@"Time": @5,
		@"State": @"running",
		@"Info": @"SELECT 1",
		@"Progress": @"33.20"
	};

	NSString *serialized = [self _serializeProcess:process includeProgress:NO];

	XCTAssertFalse([serialized containsString:@"33.20"]);
	XCTAssertEqualObjects([self _nonEmptyTokensFromSerializedRow:serialized], (@[@"100", @"dave", @"10.0.0.4", @"reporting", @"Query", @"5", @"running", @"SELECT", @"1"]));
}

- (NSArray<NSString *> *)_nonEmptyTokensFromSerializedRow:(NSString *)serializedRow
{
	NSArray<NSString *> *tokens = [serializedRow componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	NSPredicate *nonEmptyPredicate = [NSPredicate predicateWithFormat:@"length > 0"];
	return [tokens filteredArrayUsingPredicate:nonEmptyPredicate];
}

- (NSString *)_serializeProcess:(NSDictionary *)process includeProgress:(BOOL)includeProgress
{
	return [SPProcessListRowSerializer serializedProcessRow:process includeProgress:includeProgress];
}

@end
