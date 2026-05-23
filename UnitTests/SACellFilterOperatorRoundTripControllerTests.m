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

@end
