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
#import "SPUserManager.h"
#import "sequel-ace-Swift.h"
#import <SPMySQL/SPMySQL.h>
#import "../Source/Controllers/DataControllers/SPServerSupport.m"

@interface SPDatabaseActionTest : XCTestCase

- (void)testCreateDatabase_01_emptyName;
- (void)testCreateDatabase_02_allParams;
- (void)testCreateDatabase_03_nameOnly;

@end

@interface SPServerSupportTests : XCTestCase

- (void)testIsMySQL8Flag_IsTrueForVersion8AndHigher;
- (void)testIsMySQL8Flag_IsFalseForPreMySQL8Versions;
- (void)testIsMySQL5Flag_RemainsLimitedToMajorVersion5;

@end

@interface SPUserManagerPrivilegeErrorTests : XCTestCase

- (void)testMariaDBShowCreateRoutineErrorAddsSpecificExplanation;
- (void)testMariaDBGrantAllErrorAddsSpecificExplanationWhenShowCreateRoutineIsSupported;
- (void)testRegularMySQLErrorDoesNotMentionMariaDBShowCreateRoutine;
- (void)testRevokeGrantOptionFailureMessageUsesGrantOptionContext;
- (void)testUserManagerModelSupportsCurrentGlobalGrantTablePrivileges;
- (void)testUserManagerModelKeepsGlobalOnlyPrivilegesOutOfSchemaPrivileges;
- (void)testMySQLDynamicPrivilegeGrantNamesKeepUnderscores;
- (void)testMySQLDynamicPrivAccessFailureHidesDynamicPrivilegeSupport;
- (void)testMySQLDynamicGrantOptionPreservationOnlyAppliesToTrackedDynamicPrivileges;
- (void)testMariaDBGlobalPrivAccessFailureKeepsSchemaShowCreateRoutineSupport;
- (void)testGrantAllShortcutIsDatabaseScoped;

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

@implementation SPUserManagerPrivilegeErrorTests

- (void)testMariaDBShowCreateRoutineErrorAddsSpecificExplanation
{
	NSString *message = SPUserManagerPrivilegeOperationErrorMessageForServerError(@"Access denied for user 'admin'@'127.0.0.1' to database 'sample_db'",
																				 @[@"show create routine"],
																				 @"grant",
																				 @"sample_db",
																				 @"app_user",
																				 @"localhost",
																				 @"GRANT SHOW CREATE ROUTINE ON `sample_db`.* TO 'app_user'@'localhost'",
																				 YES,
																				 YES);

	XCTAssertTrue([message containsString:@"Could not grant SHOW CREATE ROUTINE on database \"sample_db\" for app_user@localhost"]);
	XCTAssertTrue([message containsString:@"Access denied for user 'admin'@'127.0.0.1' to database 'sample_db'"]);
	XCTAssertTrue([message containsString:@"SHOW CREATE ROUTINE"]);
	XCTAssertTrue([message containsString:@"SHOW GRANTS FOR CURRENT_USER()"]);
}

- (void)testMariaDBGrantAllErrorAddsSpecificExplanationWhenShowCreateRoutineIsSupported
{
	NSString *message = SPUserManagerPrivilegeOperationErrorMessageForServerError(@"Access denied for user 'root'@'localhost' to database 'test'",
																				 @[],
																				 @"grant",
																				 @"test",
																				 @"testuser",
																				 @"localhost",
																				 @"GRANT ALL ON `test`.* TO 'testuser'@'localhost' WITH GRANT OPTION",
																				 YES,
																				 YES);

	XCTAssertTrue([message containsString:@"Could not grant ALL PRIVILEGES on database \"test\" for testuser@localhost"]);
	XCTAssertTrue([message containsString:@"SHOW CREATE ROUTINE"]);
}

- (void)testRegularMySQLErrorDoesNotMentionMariaDBShowCreateRoutine
{
	NSString *message = SPUserManagerPrivilegeOperationErrorMessageForServerError(@"Access denied",
																				 @[@"select"],
																				 @"grant",
																				 @"sample_db",
																				 @"app_user",
																				 @"localhost",
																				 @"GRANT SELECT ON `sample_db`.* TO 'app_user'@'localhost'",
																				 NO,
																				 YES);

	XCTAssertTrue([message containsString:@"Could not grant SELECT on database \"sample_db\" for app_user@localhost"]);
	XCTAssertTrue([message containsString:@"Access denied"]);
	XCTAssertFalse([message containsString:@"SHOW CREATE ROUTINE"]);
}

- (void)testRevokeGrantOptionFailureMessageUsesGrantOptionContext
{
	NSString *message = SPUserManagerPrivilegeOperationErrorMessageForServerError(@"You are not allowed to revoke this privilege",
																				 @[@"grant option"],
																				 @"revoke",
																				 @"sample_db",
																				 @"app_user",
																				 @"localhost",
																				 @"REVOKE GRANT OPTION ON `sample_db`.* FROM 'app_user'@'localhost'",
																				 NO,
																				 NO);

	XCTAssertTrue([message containsString:@"Could not revoke GRANT OPTION on database \"sample_db\" for app_user@localhost"]);
	XCTAssertTrue([message containsString:@"You are not allowed to revoke this privilege"]);
	XCTAssertFalse([message containsString:@"SELECT"]);
}

- (void)testRevokeFailureMessageIncludesPrivilegeTargetAndServerReason
{
	NSString *message = SPUserManagerPrivilegeOperationErrorMessageForServerError(@"You are not allowed to revoke this privilege",
																				 @[@"insert", @"update"],
																				 @"revoke",
																				 @"sample_db",
																				 @"app_user",
																				 @"localhost",
																				 @"REVOKE INSERT, UPDATE ON `sample_db`.* FROM 'app_user'@'localhost'",
																				 NO,
																				 NO);

	XCTAssertTrue([message containsString:@"Could not revoke INSERT, UPDATE on database \"sample_db\" for app_user@localhost"]);
	XCTAssertTrue([message containsString:@"You are not allowed to revoke this privilege"]);
}

- (NSXMLDocument *)_userManagerModelDocumentWithError:(NSError **)error
{
	NSString *testFilePath = [NSString stringWithUTF8String:__FILE__];
	NSString *repositoryRoot = [[testFilePath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
	NSURL *modelURL = [NSURL fileURLWithPath:[repositoryRoot stringByAppendingPathComponent:@"Source/Model/CoreData/SPUserManager.xcdatamodel/contents"]];

	return [[NSXMLDocument alloc] initWithContentsOfURL:modelURL options:0 error:error];
}

- (void)testUserManagerModelSupportsCurrentGlobalGrantTablePrivileges
{
	NSError *error = nil;
	NSXMLDocument *modelDocument = [self _userManagerModelDocumentWithError:&error];
	NSArray *globalPrivilegeKeys = @[
		@"allow_nonexistent_definer_priv",
		@"binlog_admin_priv",
		@"binlog_monitor_priv",
		@"binlog_replay_priv",
		@"connection_admin_priv",
		@"create_role_priv",
		@"drop_role_priv",
		@"federated_admin_priv",
		@"read_only_admin_priv",
		@"replica_monitor_priv",
		@"replication_master_admin_priv",
		@"replication_slave_admin_priv",
		@"set_any_definer_priv",
		@"set_user_priv",
		@"show_create_routine_priv"
	];

	XCTAssertNil(error);
	XCTAssertNotNil(modelDocument);

	for (NSString *privilegeKey in globalPrivilegeKeys)
	{
		NSString *xpath = [NSString stringWithFormat:@"/model/entity[@name='SPUser']/attribute[@name='%@']", privilegeKey];
		XCTAssertEqual([[modelDocument nodesForXPath:xpath error:&error] count], 1U, @"Missing global privilege key %@", privilegeKey);
		XCTAssertNil(error);
	}
}

- (void)testUserManagerModelKeepsGlobalOnlyPrivilegesOutOfSchemaPrivileges
{
	NSError *error = nil;
	NSXMLDocument *modelDocument = [self _userManagerModelDocumentWithError:&error];
	NSArray *globalOnlyPrivilegeKeys = @[
		@"allow_nonexistent_definer_priv",
		@"binlog_admin_priv",
		@"binlog_monitor_priv",
		@"binlog_replay_priv",
		@"connection_admin_priv",
		@"create_role_priv",
		@"drop_role_priv",
		@"federated_admin_priv",
		@"read_only_admin_priv",
		@"replica_monitor_priv",
		@"replication_master_admin_priv",
		@"replication_slave_admin_priv",
		@"set_any_definer_priv",
		@"set_user_priv"
	];

	XCTAssertNil(error);
	XCTAssertNotNil(modelDocument);
	XCTAssertEqual([[modelDocument nodesForXPath:@"/model/entity[@name='Privileges']/attribute[@name='show_create_routine_priv']" error:&error] count], 1U);
	XCTAssertNil(error);

	for (NSString *privilegeKey in globalOnlyPrivilegeKeys)
	{
		NSString *xpath = [NSString stringWithFormat:@"/model/entity[@name='Privileges']/attribute[@name='%@']", privilegeKey];
		XCTAssertEqual([[modelDocument nodesForXPath:xpath error:&error] count], 0U, @"Global-only privilege key %@ should not be available as a schema privilege", privilegeKey);
		XCTAssertNil(error);
	}
}

- (void)testMySQLDynamicPrivilegeGrantNamesKeepUnderscores
{
	XCTAssertEqualObjects(SPUserManagerGrantNameForPrivilegeKey(@"allow_nonexistent_definer_priv", NO), @"allow_nonexistent_definer");
	XCTAssertEqualObjects(SPUserManagerGrantNameForPrivilegeKey(@"binlog_admin_priv", NO), @"binlog_admin");
	XCTAssertEqualObjects(SPUserManagerGrantNameForPrivilegeKey(@"connection_admin_priv", NO), @"connection_admin");
	XCTAssertEqualObjects(SPUserManagerGrantNameForPrivilegeKey(@"read_only_admin_priv", NO), @"read_only_admin");
	XCTAssertEqualObjects(SPUserManagerGrantNameForPrivilegeKey(@"replication_slave_admin_priv", NO), @"replication_slave_admin");
	XCTAssertEqualObjects(SPUserManagerGrantNameForPrivilegeKey(@"set_any_definer_priv", NO), @"set_any_definer");

	XCTAssertEqualObjects(SPUserManagerGrantNameForPrivilegeKey(@"create_user_priv", NO), @"create user");
	XCTAssertEqualObjects(SPUserManagerGrantNameForPrivilegeKey(@"set_user_priv", YES), @"set user");
}

- (void)testMySQLDynamicPrivAccessFailureHidesDynamicPrivilegeSupport
{
	NSMutableDictionary *supportedPrivileges = [@{
		@"allow_nonexistent_definer_priv": @YES,
		@"binlog_admin_priv": @YES,
		@"connection_admin_priv": @YES,
		@"create_role_priv": @YES,
		@"read_only_admin_priv": @YES,
		@"replication_slave_admin_priv": @YES,
		@"select_priv": @YES,
		@"set_any_definer_priv": @YES
	} mutableCopy];

	SPUserManagerApplyMySQLDynamicPrivilegeSupportAvailability(supportedPrivileges, YES);

	XCTAssertEqualObjects([supportedPrivileges objectForKey:@"binlog_admin_priv"], @YES);
	XCTAssertEqualObjects([supportedPrivileges objectForKey:@"set_any_definer_priv"], @YES);

	SPUserManagerApplyMySQLDynamicPrivilegeSupportAvailability(supportedPrivileges, NO);

	XCTAssertNil([supportedPrivileges objectForKey:@"allow_nonexistent_definer_priv"]);
	XCTAssertNil([supportedPrivileges objectForKey:@"binlog_admin_priv"]);
	XCTAssertNil([supportedPrivileges objectForKey:@"connection_admin_priv"]);
	XCTAssertNil([supportedPrivileges objectForKey:@"read_only_admin_priv"]);
	XCTAssertNil([supportedPrivileges objectForKey:@"replication_slave_admin_priv"]);
	XCTAssertNil([supportedPrivileges objectForKey:@"set_any_definer_priv"]);
	XCTAssertEqualObjects([supportedPrivileges objectForKey:@"create_role_priv"], @YES);
	XCTAssertEqualObjects([supportedPrivileges objectForKey:@"select_priv"], @YES);
}

- (void)testMySQLDynamicGrantOptionPreservationOnlyAppliesToTrackedDynamicPrivileges
{
	NSSet *grantOptionPrivilegeKeys = [NSSet setWithObjects:@"binlog_admin_priv", @"select_priv", nil];

	XCTAssertTrue(SPUserManagerShouldPreserveMySQLDynamicPrivilegeGrantOption(@"binlog_admin_priv", grantOptionPrivilegeKeys));
	XCTAssertFalse(SPUserManagerShouldPreserveMySQLDynamicPrivilegeGrantOption(@"select_priv", grantOptionPrivilegeKeys));
	XCTAssertFalse(SPUserManagerShouldPreserveMySQLDynamicPrivilegeGrantOption(@"set_any_definer_priv", grantOptionPrivilegeKeys));
	XCTAssertFalse(SPUserManagerShouldPreserveMySQLDynamicPrivilegeGrantOption(@"create_role_priv", grantOptionPrivilegeKeys));
}

- (void)testMariaDBGlobalPrivAccessFailureKeepsSchemaShowCreateRoutineSupport
{
	NSMutableDictionary *supportedPrivileges = [@{
		@"select_priv": @YES,
		@"create_role_priv": @YES,
		@"binlog_admin_priv": @YES,
		@"connection_admin_priv": @YES,
		@"replication_master_admin_priv": @YES,
		@"show_create_routine_priv": @YES
	} mutableCopy];

	SPUserManagerApplyMariaDBGlobalPrivilegeSupportAvailability(supportedPrivileges, YES);

	XCTAssertEqualObjects([supportedPrivileges objectForKey:SPUserManagerGlobalShowCreateRoutinePrivilegeSupportKey()], @YES);

	SPUserManagerApplyMariaDBGlobalPrivilegeSupportAvailability(supportedPrivileges, NO);

	XCTAssertEqualObjects([supportedPrivileges objectForKey:@"select_priv"], @YES);
	XCTAssertEqualObjects([supportedPrivileges objectForKey:@"create_role_priv"], @YES);
	XCTAssertNil([supportedPrivileges objectForKey:@"binlog_admin_priv"]);
	XCTAssertNil([supportedPrivileges objectForKey:@"connection_admin_priv"]);
	XCTAssertNil([supportedPrivileges objectForKey:@"replication_master_admin_priv"]);
	XCTAssertEqualObjects([supportedPrivileges objectForKey:@"show_create_routine_priv"], @YES);
	XCTAssertNil([supportedPrivileges objectForKey:SPUserManagerGlobalShowCreateRoutinePrivilegeSupportKey()]);
}

- (void)testGrantAllShortcutIsDatabaseScoped
{
	XCTAssertTrue(SPUserManagerShouldUseAllPrivilegesShortcut(3, 3, YES));
	XCTAssertFalse(SPUserManagerShouldUseAllPrivilegesShortcut(2, 3, YES));
	XCTAssertFalse(SPUserManagerShouldUseAllPrivilegesShortcut(0, 0, YES));
	XCTAssertFalse(SPUserManagerShouldUseAllPrivilegesShortcut(3, 3, NO));
}

@end

@implementation SPServerSupportTests

- (void)testIsMySQL8Flag_IsTrueForVersion8AndHigher
{
	XCTAssertTrue([[SPServerSupport alloc] initWithMajorVersion:8 minor:0 release:0].isMySQL8);
	XCTAssertTrue([[SPServerSupport alloc] initWithMajorVersion:9 minor:2 release:1].isMySQL8);
}

- (void)testIsMySQL8Flag_IsFalseForPreMySQL8Versions
{
	XCTAssertFalse([[SPServerSupport alloc] initWithMajorVersion:7 minor:9 release:0].isMySQL8);
	XCTAssertFalse([[SPServerSupport alloc] initWithMajorVersion:5 minor:7 release:44].isMySQL8);
}

- (void)testIsMySQL5Flag_RemainsLimitedToMajorVersion5
{
	XCTAssertTrue([[SPServerSupport alloc] initWithMajorVersion:5 minor:7 release:44].isMySQL5);
	XCTAssertFalse([[SPServerSupport alloc] initWithMajorVersion:8 minor:0 release:0].isMySQL5);
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
