//
//  SACellFilterOperatorRoundTripControllerTests.m
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <objc/message.h>

#import "sequel-ace-Swift.h"

@interface NSObject (SACellFilterRuleControllerTesting)
+ (NSDictionary *)makeSerializedFilterForColumn:(NSString *)colName operator:(NSString *)opName values:(NSArray *)values;
- (void)restoreSerializedFilters:(NSDictionary *)serialized;
- (NSDictionary *)serializedFilter;
- (void)setColumns:(NSArray *)dataColumns;
- (BOOL)appendFilterForColumn:(NSString *)columnName value:(NSString *)value isNull:(BOOL)isNull;
@end

@interface SACellFilterOperatorRoundTripControllerTests : XCTestCase
@end

@implementation SACellFilterOperatorRoundTripControllerTests

- (void)testAllAdvertisedOperatorsRestoreAndSerializeThroughRuleFilterController
{
	NSArray<NSString *> *typeGroupings = @[
		@"bit",
		@"integer",
		@"float",
		@"date",
		@"string",
		@"binary",
		@"textdata",
		@"blobdata",
		@"enum",
		@"geometry",
	];

	for (NSString *typeGrouping in typeGroupings) {
		NSArray<SACellFilterOperator *> *operators = [SACellFilterOperator operatorsForTypeGrouping:typeGrouping];
		XCTAssertGreaterThan([operators count], 0, @"%@ should advertise at least one operator", typeGrouping);

		for (SACellFilterOperator *op in operators) {
			NSString *columnName = [NSString stringWithFormat:@"%@_column", typeGrouping];
			id controller = [self ruleFilterControllerForTypeGrouping:typeGrouping columnName:columnName];
			NSArray<NSString *> *values = [self valuesForOperator:op];
			NSDictionary *leaf = [self serializedFilterForColumn:columnName operator:[op serializedName] values:values];

			((void (*)(id, SEL, NSDictionary *))objc_msgSend)(controller, @selector(restoreSerializedFilters:), leaf);
			NSDictionary *serialized = ((NSDictionary *(*)(id, SEL))objc_msgSend)(controller, @selector(serializedFilter));

			XCTAssertEqualObjects(serialized[@"filterClass"], @"expressionNode", @"%@/%@ should restore as an expression", typeGrouping, [op serializedName]);
			XCTAssertEqualObjects(serialized[@"column"], columnName, @"%@/%@ changed column during restore", typeGrouping, [op serializedName]);
			XCTAssertEqualObjects(serialized[@"filterComparison"], [op serializedName], @"%@/%@ changed comparison during restore", typeGrouping, [op serializedName]);
			XCTAssertEqualObjects(serialized[@"filterValues"], values, @"%@/%@ changed values during restore", typeGrouping, [op serializedName]);
		}
	}
}

- (id)ruleFilterControllerForTypeGrouping:(NSString *)typeGrouping columnName:(NSString *)columnName
{
	Class controllerClass = NSClassFromString(@"SPRuleFilterController");
	XCTAssertNotNil(controllerClass);

	id controller = [[controllerClass alloc] init];
	NSRuleEditor *ruleEditor = [[NSRuleEditor alloc] initWithFrame:NSMakeRect(0, 0, 600, 120)];
	[ruleEditor setDelegate:(id<NSRuleEditorDelegate>)controller];
	[controller setValue:ruleEditor forKey:@"filterRuleEditor"];
	NSArray *columns = @[
		@{
			@"name": columnName,
			@"typegrouping": typeGrouping,
		},
	];
	((void (*)(id, SEL, NSArray *))objc_msgSend)(controller, @selector(setColumns:), columns);
	return controller;
}

- (NSDictionary *)serializedFilterForColumn:(NSString *)columnName operator:(NSString *)operatorName values:(NSArray<NSString *> *)values
{
	Class controllerClass = NSClassFromString(@"SPRuleFilterController");
	XCTAssertNotNil(controllerClass);
	return ((NSDictionary *(*)(id, SEL, NSString *, NSString *, NSArray *))objc_msgSend)(controllerClass, @selector(makeSerializedFilterForColumn:operator:values:), columnName, operatorName, values);
}

- (NSArray<NSString *> *)valuesForOperator:(SACellFilterOperator *)op
{
	NSMutableArray<NSString *> *values = [NSMutableArray arrayWithCapacity:(NSUInteger)[op valueCount]];
	for (NSInteger i = 0; i < [op valueCount]; i++) {
		[values addObject:[NSString stringWithFormat:@"sample%ld", (long)i]];
	}
	return values;
}

// Regression for the SerIsUntouchedStarterRule zero-value guard.
// Before the fix, an existing zero-argument rule such as IS NULL was
// classified as an untouched starter and replaced on the next
// -appendFilterForColumn:value:isNull: call (cell drop / drag/drop), silently
// dropping the user's NULL filter. After the fix the existing IS NULL must be
// preserved as one branch of an AND-group when a new rule is appended.
- (void)testExistingIsNullRuleIsPreservedWhenAppendingNewFilter
{
	NSString *columnName = @"deleted_at";
	id controller = [self ruleFilterControllerForTypeGrouping:@"date" columnName:columnName];

	NSDictionary *isNullLeaf = [self serializedFilterForColumn:columnName operator:@"IS NULL" values:@[]];
	((void (*)(id, SEL, NSDictionary *))objc_msgSend)(controller, @selector(restoreSerializedFilters:), isNullLeaf);

	NSDictionary *restored = ((NSDictionary *(*)(id, SEL))objc_msgSend)(controller, @selector(serializedFilter));
	XCTAssertEqualObjects(restored[@"filterComparison"], @"IS NULL", @"IS NULL leaf must restore as itself before any append");

	BOOL appended = ((BOOL (*)(id, SEL, NSString *, NSString *, BOOL))objc_msgSend)(
		controller, @selector(appendFilterForColumn:value:isNull:), columnName, @"2026-05-23", NO);
	XCTAssertTrue(appended, @"append must succeed for a real column/value");

	NSDictionary *merged = ((NSDictionary *(*)(id, SEL))objc_msgSend)(controller, @selector(serializedFilter));
	XCTAssertEqualObjects(merged[@"filterClass"], @"groupNode", @"existing IS NULL + new append must produce an AND group");
	XCTAssertEqualObjects(merged[@"isConjunction"], @YES);

	NSArray<NSDictionary *> *children = merged[@"children"];
	XCTAssertEqual([children count], 2u, @"AND group must contain both the IS NULL rule and the new appended rule");
	XCTAssertEqualObjects(children[0][@"filterComparison"], @"IS NULL", @"original IS NULL must remain as a child, not be replaced");
}

@end
