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

@interface SPMySQLConnectionDatabaseAssertion_Tests : XCTestCase

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
	BOOL workersFinished = YES;

	@try {
		[connection queryString:[NSString stringWithFormat:@"CREATE DATABASE %@", [databaseA mySQLBacktickQuotedString]]];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		[connection queryString:[NSString stringWithFormat:@"CREATE DATABASE %@", [databaseB mySQLBacktickQuotedString]]];
		XCTAssertFalse([connection queryErrored], @"%@", [connection lastErrorMessage]);
		[connection queryString:[NSString stringWithFormat:@"CREATE DATABASE %@", [unicodeDatabase mySQLBacktickQuotedString]]];
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

		SPMySQLStreamingResultStore *resultStore = [connection resultStoreFromQueryString:@"SELECT DATABASE()" assertingDatabase:databaseA];
		[resultStore startDownload];
		NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
		while ([resultStore numberOfRows] == 0 && [deadline timeIntervalSinceNow] > 0) {
			usleep(1000);
		}
		NSUInteger rowCount = [resultStore numberOfRows];
		XCTAssertEqual(rowCount, 1);
		if (rowCount == 1) {
			XCTAssertEqualObjects([[resultStore rowContentsAtIndex:0] firstObject], databaseA);
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
