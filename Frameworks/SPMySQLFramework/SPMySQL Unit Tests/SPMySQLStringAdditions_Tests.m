//
//  SPMySQLStringAdditions_Tests.m
//  SPMySQLFramework
//
//  Created by Max Lohrmann on 04.10.15.
//
//

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>
#import <dispatch/dispatch.h>
#import <SPMySQL/SPMySQL.h>

@interface SPMySQLStringAdditions_Tests : XCTestCase

- (void)test_mySQLBacktickQuotedString;
- (void)test_mySQLTickQuotedString;
- (void)test_stringForDataBytesLengthEncoding;

@end

@interface SPMySQLConnectionDatabaseAssertion_Tests : XCTestCase <SPMySQLStreamingResultStoreDelegate>

@property (nonatomic, strong) XCTestExpectation *resultStoreDownloadExpectation;

@end

@implementation SPMySQLConnectionDatabaseAssertion_Tests

- (SPMySQLConnection *)_newLocalConnection
{
	NSDictionary *environment = [[NSProcessInfo processInfo] environment];
	NSString *socketPath = [environment objectForKey:@"SPMYSQL_TEST_SOCKET"];
	NSString *testHost = [environment objectForKey:@"SPMYSQL_TEST_HOST"];
	if (![socketPath length] && ![testHost length]) {
		for (NSString *candidate in @[@"/tmp/mysql.sock", @"/opt/homebrew/var/mysql/mysql.sock"]) {
			if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
				socketPath = candidate;
				break;
			}
		}
	}

	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	NSString *testUser = [environment objectForKey:@"SPMYSQL_TEST_USER"];
	connection.username = [testUser length] ? testUser : @"root";
	connection.password = [environment objectForKey:@"SPMYSQL_TEST_PASSWORD"];
	connection.useKeepAlive = NO;

	if ([testHost length]) {
		connection.useSocket = NO;
		connection.host = testHost;
		NSString *testPort = [environment objectForKey:@"SPMYSQL_TEST_PORT"];
		if ([testPort length]) {
			connection.port = [testPort integerValue];
		}
	} else if ([socketPath length]) {
		connection.useSocket = YES;
		connection.socketPath = socketPath;
	} else {
		return nil;
	}

	return connection;
}

- (void)_recordMismatch:(NSString *)message lock:(NSLock *)lock firstMismatch:(NSString * __strong *)firstMismatch
{
	[lock lock];
	if (!*firstMismatch) {
		*firstMismatch = message;
	}
	[lock unlock];
}

- (void)resultStoreDidFinishLoadingData:(SPMySQLStreamingResultStore *)resultStore
{
	[self.resultStoreDownloadExpectation fulfill];
}

- (void)testQueriesCanAssertDatabaseAtomicallyOnSharedConnection
{
	SPMySQLConnection *connection = [self _newLocalConnection];
	if (!connection) {
		XCTSkip(@"No local MySQL connection configured. Set SPMYSQL_TEST_SOCKET or SPMYSQL_TEST_HOST to run this integration regression.");
		return;
	}
	if (![connection connect]) {
		XCTSkip(@"Local MySQL connection is unavailable for the database assertion regression.");
		return;
	}

	NSString *identifier = [[[[NSUUID UUID] UUIDString] lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
	NSString *databaseA = [NSString stringWithFormat:@"sa_atomic_%@_a", identifier];
	NSString *databaseB = [NSString stringWithFormat:@"sa_atomic_%@_b", identifier];
	NSString *unicodeDatabase = [NSString stringWithFormat:@"sa_atomic_%@_\u00E9", identifier];
	NSString *unrepresentableDatabase = [NSString stringWithFormat:@"sa_atomic_%@_\u65E5", identifier];
	NSString *noDatabaseContextDatabase = [NSString stringWithFormat:@"sa_atomic_%@_none", identifier];
	BOOL workersFinished = YES;

	@try {
		[connection queryString:[NSString stringWithFormat:@"CREATE DATABASE %@", [databaseA mySQLBacktickQuotedString]]];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		[connection queryString:[NSString stringWithFormat:@"CREATE DATABASE %@", [databaseB mySQLBacktickQuotedString]]];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		[connection queryString:[NSString stringWithFormat:@"CREATE DATABASE %@", [unicodeDatabase mySQLBacktickQuotedString]]];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		[connection queryString:[NSString stringWithFormat:@"CREATE DATABASE %@", [unrepresentableDatabase mySQLBacktickQuotedString]]];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		[connection queryString:[NSString stringWithFormat:@"CREATE DATABASE %@", [noDatabaseContextDatabase mySQLBacktickQuotedString]]];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);

		XCTAssertTrue([connection selectDatabase:databaseB]);
		SPMySQLResult *result = [connection queryString:@"SELECT DATABASE()" assertingDatabase:databaseA];
		XCTAssertEqualObjects([[result getRowAsArray] firstObject], databaseA);
		XCTAssertEqualObjects([connection getFirstFieldFromQuery:@"SELECT DATABASE()" assertingDatabase:databaseA], databaseA);
		NSArray *allRows = [connection getAllRowsFromQuery:@"SELECT DATABASE() AS db" assertingDatabase:databaseA];
		NSDictionary *row = [allRows firstObject];
		XCTAssertEqualObjects([row objectForKey:@"db"], databaseA);

		NSString *originalEncoding = [connection encoding];
		XCTAssertTrue([connection setEncoding:@"latin1"]);
		SPMySQLResult *unicodeResult = [connection queryString:@"SELECT DATABASE()" assertingDatabase:unicodeDatabase];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		XCTAssertEqualObjects([[unicodeResult getRowAsArray] firstObject], unicodeDatabase);
		XCTAssertEqualObjects([connection encoding], @"latin1");

		NSString *missingDatabase = [unicodeDatabase stringByAppendingString:@"_missing"];
		[connection queryString:@"SELECT 1" assertingDatabase:missingDatabase];
		XCTAssertTrue([connection queryErrored]);
		XCTAssertEqual([connection lastErrorID], 1049U);
		XCTAssertEqualObjects([connection encoding], @"latin1");
		XCTAssertTrue([connection setEncoding:originalEncoding]);

		// SQL imports issue SET NAMES directly so that the query's file encoding,
		// rather than the framework's cached connection encoding, controls the
		// session. Asserting a database must not overwrite that caller-managed
		// state before the imported query runs.
		XCTAssertTrue([connection setEncoding:@"latin1"]);
		[connection queryString:@"SET NAMES utf8mb4 COLLATE utf8mb4_bin"];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		XCTAssertTrue([unicodeDatabase canBeConvertedToEncoding:NSWindowsCP1252StringEncoding]);
		SPMySQLResult *representableDatabaseResult = [connection queryString:@"SELECT @@character_set_client, @@character_set_results, @@character_set_connection, @@collation_connection"
		                                                                     assertingDatabase:unicodeDatabase];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		if (![connection queryErrored]) {
			NSArray *representableDatabaseState = [representableDatabaseResult getRowAsArray];
			XCTAssertEqualObjects([representableDatabaseState objectAtIndex:0], @"utf8mb4");
			XCTAssertEqualObjects([representableDatabaseState objectAtIndex:1], @"utf8mb4");
			XCTAssertEqualObjects([representableDatabaseState objectAtIndex:2], @"utf8mb4");
			XCTAssertEqualObjects([representableDatabaseState objectAtIndex:3], @"utf8mb4_bin");
		}

		XCTAssertFalse([unrepresentableDatabase canBeConvertedToEncoding:NSASCIIStringEncoding]);
		SPMySQLResult *callerManagedEncodingResult = [connection queryString:@"SELECT @@character_set_client, @@character_set_results, @@character_set_connection, @@collation_connection"
		                                                                    usingEncoding:NSASCIIStringEncoding
		                                                                   withResultType:SPMySQLResultAsResult
		                                                               assertingDatabase:unrepresentableDatabase];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		NSArray *callerManagedEncodingState = [callerManagedEncodingResult getRowAsArray];
		XCTAssertEqualObjects([callerManagedEncodingState objectAtIndex:0], @"utf8mb4");
		XCTAssertEqualObjects([callerManagedEncodingState objectAtIndex:1], @"utf8mb4");
		XCTAssertEqualObjects([callerManagedEncodingState objectAtIndex:2], @"utf8mb4");
		XCTAssertEqualObjects([callerManagedEncodingState objectAtIndex:3], @"utf8mb4_bin");
		XCTAssertEqualObjects([connection encoding], @"latin1");
		XCTAssertTrue([connection setEncoding:originalEncoding]);

		// Exercise the inverse stale-cache direction as well: the framework cache
		// remains UTF-8 while a caller-managed session expects latin1 bytes.
		[connection queryString:@"SET NAMES latin1 COLLATE latin1_bin"];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		SPMySQLResult *inverseCallerManagedResult = [connection queryString:@"SELECT @@character_set_client, @@character_set_results, @@character_set_connection, @@collation_connection"
		                                                                      assertingDatabase:unicodeDatabase];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		if (![connection queryErrored]) {
			NSArray *inverseCallerManagedState = [inverseCallerManagedResult getRowAsArray];
			XCTAssertEqualObjects([inverseCallerManagedState objectAtIndex:0], @"latin1");
			XCTAssertEqualObjects([inverseCallerManagedState objectAtIndex:1], @"latin1");
			XCTAssertEqualObjects([inverseCallerManagedState objectAtIndex:2], @"latin1");
			XCTAssertEqualObjects([inverseCallerManagedState objectAtIndex:3], @"latin1_bin");
		}
		[connection queryString:@"SET CHARACTER_SET_RESULTS=NULL, CHARACTER_SET_CONNECTION=utf8mb4, COLLATION_CONNECTION=utf8mb4_bin"];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		SPMySQLResult *inverseUnrepresentableResult = [connection queryString:@"SELECT @@character_set_client, @@character_set_results IS NULL, @@character_set_connection, @@collation_connection"
		                                                                         assertingDatabase:unrepresentableDatabase];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		if (![connection queryErrored]) {
			NSArray *inverseUnrepresentableState = [inverseUnrepresentableResult getRowAsArray];
			XCTAssertEqualObjects([inverseUnrepresentableState objectAtIndex:0], @"latin1");
			XCTAssertEqualObjects([inverseUnrepresentableState objectAtIndex:1], @"1");
			XCTAssertEqualObjects([inverseUnrepresentableState objectAtIndex:2], @"utf8mb4");
			XCTAssertEqualObjects([inverseUnrepresentableState objectAtIndex:3], @"utf8mb4_bin");
		}
		XCTAssertEqualObjects([connection encoding], originalEncoding);

		[connection queryString:@"SELECT 1" assertingDatabase:[unrepresentableDatabase stringByAppendingString:@"_missing"]];
		XCTAssertTrue([connection queryErrored]);
		XCTAssertEqual([connection lastErrorID], 1049U);
		SPMySQLResult *failedAssertionStateResult = [connection queryString:@"SELECT @@character_set_client, @@character_set_results IS NULL, @@character_set_connection, @@collation_connection"];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		NSArray *failedAssertionState = [failedAssertionStateResult getRowAsArray];
		XCTAssertEqualObjects([failedAssertionState objectAtIndex:0], @"latin1");
		XCTAssertEqualObjects([failedAssertionState objectAtIndex:1], @"1");
		XCTAssertEqualObjects([failedAssertionState objectAtIndex:2], @"utf8mb4");
		XCTAssertEqualObjects([failedAssertionState objectAtIndex:3], @"utf8mb4_bin");

		[connection queryString:@"SET NAMES utf8mb4"];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);

		// CLIENT_SESSION_TRACK is only a negotiated capability. Administrators can
		// exclude charset variables from the session tracking payload, in which case
		// mysql_character_set_name remains stale after caller-issued SET NAMES.
		NSString *trackedSystemVariables = [connection getFirstFieldFromQuery:@"SELECT @@session.session_track_system_variables"];
		if (![connection queryErrored] && [trackedSystemVariables length]) {
			[connection queryString:@"SELECT DATABASE()" assertingDatabase:databaseA];
			XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
			[connection queryString:@"SET SESSION session_track_system_variables=''"];
			XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
			[connection queryString:@"SET NAMES latin1"];
			XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);

			XCTAssertEqualObjects([connection getFirstFieldFromQuery:@"SELECT @@character_set_client" assertingDatabase:unicodeDatabase], @"latin1");
			XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);

			[connection queryString:[NSString stringWithFormat:@"SET SESSION session_track_system_variables=%@", [trackedSystemVariables mySQLTickQuotedString]]];
			XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
			[connection queryString:@"SET NAMES utf8mb4"];
			XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		}

		// The schema tracker can likewise be disabled while the capability bits stay
		// set. A successful USE must invalidate assertion state so a stale MYSQL->db
		// value can never make a later assertion skip the required selection.
		NSString *schemaTrackingEnabled = [connection getFirstFieldFromQuery:@"SELECT @@session.session_track_schema"];
		if (![connection queryErrored] && [schemaTrackingEnabled length]) {
			[connection queryString:@"SELECT DATABASE()" assertingDatabase:databaseA];
			XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
			[connection queryString:@"SET SESSION session_track_schema=OFF"];
			XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
			[connection queryString:[NSString stringWithFormat:@"USE %@", [databaseB mySQLBacktickQuotedString]]];
			XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);

			XCTAssertEqualObjects([connection getFirstFieldFromQuery:@"SELECT DATABASE()" assertingDatabase:databaseA], databaseA);
			XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);

			NSString *schemaTrackingRestoreValue = [schemaTrackingEnabled integerValue] ? @"ON" : @"OFF";
			[connection queryString:[NSString stringWithFormat:@"SET SESSION session_track_schema=%@", schemaTrackingRestoreValue]];
			XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		}

		XCTAssertTrue([connection setEncoding:@"latin2"]);
		NSString *expectedConnectionCharacterSet = [connection getFirstFieldFromQuery:@"SELECT @@character_set_connection"];
		XCTAssertTrue([connection setEncodingUsesLatin1Transport:YES]);
		SPMySQLResult *latin1TransportResult = [connection queryString:@"SELECT DATABASE()" assertingDatabase:unicodeDatabase];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		XCTAssertEqualObjects([[latin1TransportResult getRowAsArray] firstObject], unicodeDatabase);
		XCTAssertEqualObjects([connection encoding], @"latin2");
		XCTAssertTrue([connection encodingUsesLatin1Transport]);

		SPMySQLResult *transportStateResult = [connection queryString:@"SELECT @@character_set_client, @@character_set_results, @@character_set_connection"];
		NSArray *transportState = [transportStateResult getRowAsArray];
		XCTAssertEqualObjects([transportState objectAtIndex:0], @"latin1");
		XCTAssertEqualObjects([transportState objectAtIndex:1], @"latin1");
		XCTAssertEqualObjects([transportState objectAtIndex:2], expectedConnectionCharacterSet);
		XCTAssertTrue([connection setEncodingUsesLatin1Transport:NO]);
		XCTAssertTrue([connection setEncoding:originalEncoding]);

		// A matching assertion must not issue a hidden SELECT or redundant
		// mysql_select_db before the target query. Those operations overwrite
		// statement diagnostics that the next SQL statement can inspect.
		[connection queryString:@"CREATE TABLE assertion_diagnostics (id INT PRIMARY KEY, value INT)" assertingDatabase:unicodeDatabase];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		[connection queryString:@"INSERT INTO assertion_diagnostics VALUES (1, 0)" assertingDatabase:unicodeDatabase];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		[connection queryString:@"UPDATE assertion_diagnostics SET value = value + 1 WHERE id = 1" assertingDatabase:unicodeDatabase];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		XCTAssertEqualObjects([connection getFirstFieldFromQuery:@"SELECT ROW_COUNT()" assertingDatabase:unicodeDatabase], @"1");

		[connection queryString:@"DROP TABLE IF EXISTS assertion_missing_table" assertingDatabase:unicodeDatabase];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		SPMySQLResult *warningsResult = [connection queryString:@"SHOW WARNINGS" assertingDatabase:unicodeDatabase];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		XCTAssertGreaterThan([warningsResult numberOfRows], 0ULL);

		[connection queryString:@"SELECT SQL_CALC_FOUND_ROWS value FROM assertion_diagnostics UNION ALL SELECT 2 UNION ALL SELECT 3 LIMIT 1" assertingDatabase:unicodeDatabase];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		XCTAssertEqualObjects([connection getFirstFieldFromQuery:@"SELECT FOUND_ROWS()" assertingDatabase:unicodeDatabase], @"3");

		// The context API treats nil as an explicit no-database state. The
		// legacy assertingDatabase:nil API remains intentionally nonasserting.
		XCTAssertTrue([connection selectDatabase:noDatabaseContextDatabase]);
		[connection queryString:[NSString stringWithFormat:@"DROP DATABASE %@", [noDatabaseContextDatabase mySQLBacktickQuotedString]] assertingDatabase:noDatabaseContextDatabase];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		SPMySQLResult *noDatabaseResult = [connection queryString:@"SELECT DATABASE()" assertingDatabaseContext:nil];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		XCTAssertEqualObjects([[noDatabaseResult getRowAsArray] firstObject], [NSNull null]);

		[connection queryString:@"CREATE TABLE assertion_no_database_guard (id INT)" assertingDatabaseContext:nil];
		XCTAssertTrue([connection queryErrored]);
		XCTAssertEqual([connection lastErrorID], 1046U);

		XCTAssertTrue([connection selectDatabase:databaseB]);
		[connection queryString:@"CREATE TABLE assertion_no_database_guard (id INT)" assertingDatabaseContext:nil];
		XCTAssertTrue([connection queryErrored]);
		XCTAssertEqual([connection lastErrorID], 1046U);
		XCTAssertEqualObjects([connection lastSqlstate], @"3D000");
		XCTAssertEqualObjects([connection lastErrorMessage], @"No database selected");
		XCTAssertEqualObjects([connection getFirstFieldFromQuery:@"SELECT DATABASE()" assertingDatabase:nil], databaseB);
		XCTAssertEqualObjects([connection getFirstFieldFromQuery:@"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'assertion_no_database_guard'" assertingDatabase:databaseB], @"0");

		SPMySQLStreamingResultStore *resultStore = [connection resultStoreFromQueryString:@"SELECT DATABASE()" assertingDatabase:databaseA];
		self.resultStoreDownloadExpectation = [self expectationWithDescription:@"Streaming result store download completes"];
		resultStore.delegate = self;
		[resultStore startDownload];
		XCTWaiterResult resultStoreWaitResult = [XCTWaiter waitForExpectations:@[self.resultStoreDownloadExpectation] timeout:5];
		XCTAssertEqual(resultStoreWaitResult, XCTWaiterResultCompleted);
		if (resultStoreWaitResult == XCTWaiterResultCompleted) {
			NSUInteger rowCount = [resultStore numberOfRows];
			XCTAssertEqual(rowCount, 1);
			if (rowCount == 1) {
				XCTAssertEqualObjects([[resultStore rowContentsAtIndex:0] firstObject], databaseA);
			}
		}
		[resultStore cancelResultLoad];

		__block NSString *firstMismatch = nil;
		NSLock *mismatchLock = [[NSLock alloc] init];
		dispatch_group_t group = dispatch_group_create();
		dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
		const NSInteger iterations = 500;
		workersFinished = NO;

		dispatch_group_async(group, queue, ^{
			for (NSInteger i = 0; i < iterations; i++) {
				@autoreleasepool {
					SPMySQLResult *loopResult = [connection queryString:@"SELECT DATABASE()" assertingDatabase:databaseA];
					NSString *selectedDatabase = [[loopResult getRowAsArray] firstObject];
					if (![selectedDatabase isEqualToString:databaseA]) {
						[self _recordMismatch:[NSString stringWithFormat:@"Expected %@, got %@ at iteration %ld", databaseA, selectedDatabase, (long)i] lock:mismatchLock firstMismatch:&firstMismatch];
						break;
					}
				}
			}
		});

		dispatch_group_async(group, queue, ^{
			for (NSInteger i = 0; i < iterations; i++) {
				@autoreleasepool {
					if (![connection selectDatabase:databaseB]) {
						[self _recordMismatch:[NSString stringWithFormat:@"selectDatabase failed at iteration %ld: %@", (long)i, [connection lastErrorMessage]] lock:mismatchLock firstMismatch:&firstMismatch];
						break;
					}
				}
			}
		});

		long waitResult = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
		workersFinished = (waitResult == 0);
		XCTAssertEqual(waitResult, 0);
		XCTAssertNil(firstMismatch);
	}
	@finally {
		if (workersFinished) {
			[connection queryString:[NSString stringWithFormat:@"DROP DATABASE IF EXISTS %@", [databaseA mySQLBacktickQuotedString]]];
			[connection queryString:[NSString stringWithFormat:@"DROP DATABASE IF EXISTS %@", [databaseB mySQLBacktickQuotedString]]];
			[connection queryString:[NSString stringWithFormat:@"DROP DATABASE IF EXISTS %@", [unicodeDatabase mySQLBacktickQuotedString]]];
			[connection queryString:[NSString stringWithFormat:@"DROP DATABASE IF EXISTS %@", [unrepresentableDatabase mySQLBacktickQuotedString]]];
			[connection queryString:[NSString stringWithFormat:@"DROP DATABASE IF EXISTS %@", [noDatabaseContextDatabase mySQLBacktickQuotedString]]];
			[connection disconnect];
		}
	}
}

@end

@implementation SPMySQLStringAdditions_Tests

- (void)test_mySQLBacktickQuotedString
{
	XCTAssertEqualObjects([@"" mySQLBacktickQuotedString], @"``",@"empty string");
	
	XCTAssertEqualObjects([@"tbl1" mySQLBacktickQuotedString], @"`tbl1`", @"regular string");
	
	XCTAssertEqualObjects([@"tbl`1" mySQLBacktickQuotedString], @"`tbl``1`",@"string with control character");
	
	XCTAssertEqualObjects([@"tbl``" mySQLBacktickQuotedString], @"`tbl`````",@"string with escaped control character at end");
}

- (void)test_mySQLTickQuotedString
{
	XCTAssertEqualObjects([@"" mySQLTickQuotedString], @"''",@"empty string");
	
	XCTAssertEqualObjects([@"tbl1" mySQLTickQuotedString], @"'tbl1'", @"regular string");
	
	XCTAssertEqualObjects([@"tbl'1" mySQLTickQuotedString], @"'tbl''1'",@"string with control character");
	
	XCTAssertEqualObjects([@"tbl''" mySQLTickQuotedString], @"'tbl'''''",@"string with escaped control character at end");
}

- (void)test_stringForDataBytesLengthEncoding
{
	{
		const char chr = '\0';
		NSString *conv = [NSString stringForDataBytes:&chr length:0 encoding:NSISOLatin1StringEncoding];
		XCTAssertEqualObjects(conv, @"",@"empty string test");
	}
	{
		const char *cstr = "an ASCII C string";
		NSString *conv = [NSString stringForDataBytes:cstr length:strlen(cstr) encoding:NSASCIIStringEncoding];
		XCTAssertEqualObjects(conv, @"an ASCII C string", @"simple ASCII string test");
	}
	{
		// the euro sign is the tricky part
		// ISO-8859-1 (aka Latin1):              not supported, codepoint 0x80 is not in use
		// ISO-8859-1 + ISO/IEC 6429:            not supported, codepoint 0x80 is PAD control character
		// ISO-8859-15 (aka Latin9):             € is at 0xA4, codepoint 0x80 is PAD control character
		// Windows cp1252 (aka latin1 in mysql): € is at 0x80, codepoint 0xA4 is "¤"
		const char cstr[] = {'\xE4','-','\xDF','-','\x80','\0'};
		NSString *conv = [NSString stringForDataBytes:cstr length:strlen(cstr) encoding:NSWindowsCP1252StringEncoding];
		XCTAssertEqualObjects(conv, @"ä-ß-€",@"handling of cp1252 special characters");
		
		unsigned char latin9 = 0xA4;
		NSString *conv2 = [NSString stringForDataBytes:&latin9 length:1 encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin9)];
		XCTAssertEqualObjects(conv2, @"€",@"handling of iso-8859-15 special characters");
	}
	{
		const char *cstr = "エスキューエル";
		NSString *conv = [NSString stringForDataBytes:cstr length:strlen(cstr) encoding:NSUTF8StringEncoding];
		XCTAssertEqualObjects(conv, @"エスキューエル",@"handling of valid utf-8 string");
	}
	{
		// this is a test for a certain mysql issue:
		// mysql limits field names to 255 characters and will even cut multibyte chars in the middle,
		// if neccesary. This will create invalid characters which cause NSString
		// to fail and return nil on the whole string. Since we know that, we can
		// at least try to return something.
		char cstr[] = {'\xE3','\x82','\xA8','\xE3','\x82','\xB9','\xE3','\x82','\xAD','\xE3','\x83','\xA5','\xE3','\x83','\xBC','\xE3','\x82','\xA8','\xE3','\x83','\xAB','\0'}; // エスキューエル
		cstr[strlen(cstr)-2] = '\0'; //simulate cutting off the string
		NSString *conv = [NSString stringForDataBytes:cstr length:strlen(cstr) encoding:NSUTF8StringEncoding];
		XCTAssertNotNil(conv, @"handling of invalid utf8 sequences");
	}
}

@end
