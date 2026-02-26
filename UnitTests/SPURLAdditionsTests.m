//
//  SPURLAdditions.m
//  Unit Tests
//
//  Created by James on 12/12/2020.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "SPFunctions.h"

@interface SPURLAdditionsTests : XCTestCase

@end

@implementation SPURLAdditionsTests


- (void)testExample {
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.

	NSURL *tmp = [NSURL fileURLWithPath:@"jimmy"];
	NSURL *tmp2 = [NSURL fileURLWithPath:@"jimmy" isDirectory:NO];

	XCTAssertEqualObjects(tmp, tmp2);
}

- (void)testMySQLURLParserSupportsExplicitAWSIAMType
{
	NSURL *url = [NSURL URLWithString:@"mysql://db_user@db.example.com:3306/my_database?type=aws_iam&aws_profile=production&aws_region=us-east-1"];
	NSMutableDictionary *details = [NSMutableDictionary dictionary];
	BOOL autoConnect = NO;
	NSArray<NSString *> *invalidParameters = nil;

	BOOL parsed = SPExtractConnectionDetailsFromMySQLURL(url,
													 details,
													 &autoConnect,
													 &invalidParameters);

	XCTAssertTrue(parsed);
	XCTAssertFalse(autoConnect);
	XCTAssertEqual(invalidParameters.count, 0);
	XCTAssertEqualObjects(details[@"type"], @"SPAWSIAMConnection");
	XCTAssertEqualObjects(details[@"host"], @"db.example.com");
	XCTAssertEqualObjects(details[@"user"], @"db_user");
	XCTAssertEqualObjects(details[@"database"], @"my_database");
	XCTAssertEqualObjects(details[@"port"], @3306);
	XCTAssertEqualObjects(details[@"aws_profile"], @"production");
	XCTAssertEqualObjects(details[@"aws_region"], @"us-east-1");
}

- (void)testMySQLURLParserInfersAWSIAMTypeFromAWSQueryParameters
{
	NSURL *url = [NSURL URLWithString:@"mysql://db_user@db.example.com/my_database?aws_profile=default&aws_region=us-west-2"];
	NSMutableDictionary *details = [NSMutableDictionary dictionary];
	BOOL autoConnect = NO;
	NSArray<NSString *> *invalidParameters = nil;

	BOOL parsed = SPExtractConnectionDetailsFromMySQLURL(url,
													 details,
													 &autoConnect,
													 &invalidParameters);

	XCTAssertTrue(parsed);
	XCTAssertFalse(autoConnect);
	XCTAssertEqual(invalidParameters.count, 0);
	XCTAssertEqualObjects(details[@"type"], @"SPAWSIAMConnection");
	XCTAssertEqualObjects(details[@"aws_profile"], @"default");
	XCTAssertEqualObjects(details[@"aws_region"], @"us-west-2");
}

- (void)testMySQLURLParserSupportsExplicitAWSIAMTypeWithoutAWSQueryParameters
{
	NSURL *url = [NSURL URLWithString:@"mysql://db_user@db.example.com:3306/my_database?type=aws_iam"];
	NSMutableDictionary *details = [NSMutableDictionary dictionary];
	BOOL autoConnect = NO;
	NSArray<NSString *> *invalidParameters = nil;

	BOOL parsed = SPExtractConnectionDetailsFromMySQLURL(url,
													 details,
													 &autoConnect,
													 &invalidParameters);

	XCTAssertTrue(parsed);
	XCTAssertFalse(autoConnect);
	XCTAssertEqual(invalidParameters.count, 0);
	XCTAssertEqualObjects(details[@"type"], @"SPAWSIAMConnection");
}

- (void)testMySQLURLParserSupportsExplicitSocketType
{
	NSURL *url = [NSURL URLWithString:@"mysql://root@localhost/my_database?type=socket&socket=%2Ftmp%2Fmysql.sock"];
	NSMutableDictionary *details = [NSMutableDictionary dictionary];
	BOOL autoConnect = NO;
	NSArray<NSString *> *invalidParameters = nil;

	BOOL parsed = SPExtractConnectionDetailsFromMySQLURL(url,
													 details,
													 &autoConnect,
													 &invalidParameters);

	XCTAssertTrue(parsed);
	XCTAssertFalse(autoConnect);
	XCTAssertEqual(invalidParameters.count, 0);
	XCTAssertEqualObjects(details[@"type"], @"SPSocketConnection");
	XCTAssertEqualObjects(details[@"socket"], @"/tmp/mysql.sock");
	XCTAssertEqualObjects(details[@"database"], @"my_database");
}

- (void)testMySQLURLParserInfersSocketTypeFromSocketQueryParameter
{
	NSURL *url = [NSURL URLWithString:@"mysql://root@localhost/my_database?socket=%2FUsers%2Fjason%2FLibrary%2FContainers%2Fcom.sequel-ace.sequel-ace%2FData%2Fmysql.sock"];
	NSMutableDictionary *details = [NSMutableDictionary dictionary];
	BOOL autoConnect = NO;
	NSArray<NSString *> *invalidParameters = nil;

	BOOL parsed = SPExtractConnectionDetailsFromMySQLURL(url,
													 details,
													 &autoConnect,
													 &invalidParameters);

	XCTAssertTrue(parsed);
	XCTAssertFalse(autoConnect);
	XCTAssertEqual(invalidParameters.count, 0);
	XCTAssertEqualObjects(details[@"type"], @"SPSocketConnection");
	XCTAssertEqualObjects(details[@"socket"], @"/Users/jason/Library/Containers/com.sequel-ace.sequel-ace/Data/mysql.sock");
}

- (void)testMySQLURLParserRejectsInvalidConnectionTypeParameter
{
	NSURL *url = [NSURL URLWithString:@"mysql://root:secret@127.0.0.1:3306/my_database?type=banana"];
	NSMutableDictionary *details = [NSMutableDictionary dictionary];
	BOOL autoConnect = NO;
	NSArray<NSString *> *invalidParameters = nil;

	BOOL parsed = SPExtractConnectionDetailsFromMySQLURL(url,
													 details,
													 &autoConnect,
													 &invalidParameters);

	XCTAssertFalse(parsed);
	XCTAssertTrue([invalidParameters containsObject:@"type"]);
}

- (void)testMySQLURLParserPreservesSSHInference
{
	NSURL *url = [NSURL URLWithString:@"mysql://db_user:db_password@127.0.0.1:3306/my_database?ssh_host=ssh.example.com&ssh_port=22&ssh_user=ssh_user"];
	NSMutableDictionary *details = [NSMutableDictionary dictionary];
	BOOL autoConnect = NO;
	NSArray<NSString *> *invalidParameters = nil;

	BOOL parsed = SPExtractConnectionDetailsFromMySQLURL(url,
													 details,
													 &autoConnect,
													 &invalidParameters);

	XCTAssertTrue(parsed);
	XCTAssertTrue(autoConnect);
	XCTAssertEqual(invalidParameters.count, 0);
	XCTAssertEqualObjects(details[@"type"], @"SPSSHTunnelConnection");
	XCTAssertEqualObjects(details[@"ssh_host"], @"ssh.example.com");
	XCTAssertEqualObjects(details[@"ssh_port"], @"22");
	XCTAssertEqualObjects(details[@"ssh_user"], @"ssh_user");
}

- (void)testMySQLURLParserRespectsExplicitTCPIPType
{
	NSURL *url = [NSURL URLWithString:@"mysql://db_user@db.example.com:3306/my_database?type=tcpip&ssh_host=ssh.example.com&aws_profile=production"];
	NSMutableDictionary *details = [NSMutableDictionary dictionary];
	BOOL autoConnect = NO;
	NSArray<NSString *> *invalidParameters = nil;

	BOOL parsed = SPExtractConnectionDetailsFromMySQLURL(url,
													 details,
													 &autoConnect,
													 &invalidParameters);

	XCTAssertTrue(parsed);
	XCTAssertEqual(invalidParameters.count, 0);
	XCTAssertEqualObjects(details[@"type"], @"SPTCPIPConnection");
}

// 0.15 s
- (void)testPerformanceSwizzle{
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.

		int const iterations = 10000;
		for (int i = 0; i < iterations; i++) {
			@autoreleasepool {
				NSURL __unused *tmp2 = [NSURL fileURLWithPath:@"jimmy" isDirectory:NO];
			}
		}
    }];
}

// 0.161 s
- (void)testPerformanceNoSwizzle{
	// This is an example of a performance test case.
	[self measureBlock:^{
		// Put the code you want to measure the time of here.

		int const iterations = 10000;
		for (int i = 0; i < iterations; i++) {
			@autoreleasepool {
				NSURL __unused *tmp2 = [NSURL fileURLWithPath:@"jimmy"];
			}
		}
	}];
}

@end
