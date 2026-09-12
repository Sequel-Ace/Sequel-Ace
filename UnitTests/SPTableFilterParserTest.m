//
//  SPTableFilterParserTest.m
//  sequel-pro
//
//  Created by Max Lohrmann on 23.04.15.
//
//

#import <Foundation/Foundation.h>
#import "SPTableFilterParser.h"

#define USE_APPLICATION_UNIT_TEST 1

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>

@interface SPTableFilterParserTest : XCTestCase

- (void)testFilterString;
- (void)testLengthFiltersProduceCharLengthComparison;
- (void)testLengthFiltersAreDefinedForStringFields;

@end

@implementation SPTableFilterParserTest

- (void)testFilterString {
	//simple zero argument case
	{
		SPTableFilterParser *p = [[SPTableFilterParser alloc] initWithFilterClause:@" constant $BINARY string" numberOfArguments:0];
		[p setCurrentField:@"FLD"];
		
		// binary matches as "$BINARY ", eating the one additional whitespace
		XCTAssertEqualObjects([p filterString],@"`FLD`  constant string", @"Constant replacement");
	}
	//simple one argument case with binary
	{
		SPTableFilterParser *p = [[SPTableFilterParser alloc] initWithFilterClause:@"= FOO($BINARY ${})" numberOfArguments:1];
		[p setCurrentField:@"FLD2"];
		[p setCaseSensitive:YES];
		[p setArgument:@"arg1"];
		
		XCTAssertEqualObjects([p filterString], @"`FLD2` = FOO(BINARY arg1)", @"One Argument, $BINARY variable");
	}
	//simple two argument case with explicit current field
	{
		SPTableFilterParser *p = [[SPTableFilterParser alloc] initWithFilterClause:@"MIN($CURRENT_FIELD,${}) = ${}" numberOfArguments:2];
		[p setCurrentField:@"FLD3"];
		[p setSuppressLeadingTablePlaceholder:YES];
		[p setFirstBetweenArgument:@"LA"];
		[p setSecondBetweenArgument:@"RA"];
		
		XCTAssertEqualObjects([p filterString], @"MIN(`FLD3`,LA) = RA", @"Two Arguments, $CURRENT_FIELD variable");
	}

}

/**
 * The "length" filters added for issue #1844 have to suppress the leading field
 * placeholder, otherwise the field name would be emitted twice - once by the parser
 * and once by CHAR_LENGTH($CURRENT_FIELD).
 */
- (void)testLengthFiltersProduceCharLengthComparison {
	NSDictionary *expectedClauses = @{
		@"length =" : @"CHAR_LENGTH(`username`) = 10",
		@"length >" : @"CHAR_LENGTH(`username`) > 10",
		@"length <" : @"CHAR_LENGTH(`username`) < 10",
	};

	for (NSDictionary *filter in [self stringFilters]) {
		NSString *label = [filter objectForKey:@"MenuLabel"];
		NSString *expected = [expectedClauses objectForKey:label];

		if (!expected) continue;

		SPTableFilterParser *p = [[SPTableFilterParser alloc] initWithFilterClause:[filter objectForKey:@"Clause"]
		                                                        numberOfArguments:[[filter objectForKey:@"NumberOfArguments"] integerValue]];
		[p setCurrentField:@"username"];
		[p setSuppressLeadingTablePlaceholder:[[filter objectForKey:@"SuppressLeadingFieldPlaceholder"] boolValue]];
		[p setArgument:@"10"];

		XCTAssertEqualObjects([p filterString], expected, @"Clause for “%@”", label);
	}
}

- (void)testLengthFiltersAreDefinedForStringFields {
	NSMutableArray *labels = [NSMutableArray array];

	for (NSDictionary *filter in [self stringFilters]) {
		NSString *label = [filter objectForKey:@"MenuLabel"];

		if (![label hasPrefix:@"length "]) continue;

		[labels addObject:label];

		XCTAssertEqualObjects([filter objectForKey:@"NumberOfArguments"], @1, @"“%@” takes one argument", label);
		XCTAssertTrue([[filter objectForKey:@"SuppressLeadingFieldPlaceholder"] boolValue], @"“%@” suppresses the leading field", label);
		XCTAssertTrue([[filter objectForKey:@"Clause"] hasPrefix:@"CHAR_LENGTH($CURRENT_FIELD)"], @"“%@” measures the current field", label);
	}

	NSArray *expected = @[@"length =", @"length >", @"length <"];
	XCTAssertEqualObjects(labels, expected, @"String fields offer the length filters from issue #1844");
}

/**
 * Returns the 'string' filter definitions straight out of ContentFilters.plist, so the
 * tests exercise the clauses that actually ship rather than copies of them.
 */
- (NSArray *)stringFilters {
	// The plist ships in both the app and the test bundle, so check both rather than
	// assuming which one the tests are hosted in.
	for (NSBundle *bundle in @[[NSBundle bundleForClass:[self class]], [NSBundle mainBundle]]) {
		NSString *path = [bundle pathForResource:@"ContentFilters" ofType:@"plist"];

		if (!path) continue;

		NSArray *filters = [[NSDictionary dictionaryWithContentsOfFile:path] objectForKey:@"string"];

		if (filters) return filters;
	}

	XCTFail(@"Could not find 'string' filters in ContentFilters.plist in any loaded bundle");

	return @[];
}

@end
