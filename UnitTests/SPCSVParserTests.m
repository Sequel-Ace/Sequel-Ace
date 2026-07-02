//
//  SPCSVParserTests.m
//  Unit Tests
//
//  Created by Codex on 17.06.26.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "SPCSVParser.h"

@interface SPCSVParserTests : XCTestCase

@end

@implementation SPCSVParserTests

- (NSArray *)rowsForCSVString:(NSString *)csvString lineTerminator:(NSString *)lineTerminator
{
	SPCSVParser *parser = [[SPCSVParser alloc] initWithString:csvString];
	[parser setLineTerminatorString:lineTerminator convertDisplayStrings:YES];

	return [parser array];
}

- (void)testCRLFTerminatorDoesNotImportTrailingCR
{
	NSArray *rows = [self rowsForCSVString:@"id,name\r\n1,Alice\r\n" lineTerminator:@"\\r\\n"];

	XCTAssertEqual([rows count], 2U);
	XCTAssertEqualObjects(rows[0], (@[@"id", @"name"]));
	XCTAssertEqualObjects(rows[1], (@[@"1", @"Alice"]));
}

- (void)testCRTerminatorDoesNotImportTrailingCR
{
	NSArray *rows = [self rowsForCSVString:@"id,name\r1,Alice\r" lineTerminator:@"\\r"];

	XCTAssertEqual([rows count], 2U);
	XCTAssertEqualObjects(rows[0], (@[@"id", @"name"]));
	XCTAssertEqualObjects(rows[1], (@[@"1", @"Alice"]));
}

- (void)testSelectedLineTerminatorControlsRowBoundaries
{
	NSArray *rows = [self rowsForCSVString:@"id,name\r\n1,Alice\r\n" lineTerminator:@"\\n"];

	XCTAssertEqual([rows count], 2U);
	XCTAssertEqualObjects(rows[0], (@[@"id", @"name\r"]));
	XCTAssertEqualObjects(rows[1], (@[@"1", @"Alice\r"]));
}

- (void)testQuotedCRLFIsPreservedInsideField
{
	NSArray *rows = [self rowsForCSVString:@"note,value\r\n\"line one\r\nline two\",2\r\n" lineTerminator:@"\\r\\n"];

	XCTAssertEqual([rows count], 2U);
	XCTAssertEqualObjects(rows[0], (@[@"note", @"value"]));
	XCTAssertEqualObjects(rows[1], (@[@"line one\r\nline two", @"2"]));
}

@end
