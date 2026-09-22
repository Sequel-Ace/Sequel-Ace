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
/** Seeds the unchecked starter row, as the content view does on a table switch. */
- (void)addStarterFilterExpression;
/** The drop zone's "add a filter" click. */
- (void)addEmptyFilterRow;
/** Enables or disables the rule editor. */
- (void)setEnabled:(BOOL)enabled;
/** Called while the user types into an argument field. */
- (void)controlTextDidChange:(NSNotification *)notification;
/** Called when the user clicks a row's enable checkbox. */
- (IBAction)_checkboxClicked:(id)sender;
/** The WHERE clause the enabled rules produce. */
- (NSString *)sqlWhereExpressionWithBinary:(BOOL)isBINARY error:(NSError **)err;
@end

@interface SACellFilterOperatorRoundTripControllerTests : XCTestCase
@end

@implementation SACellFilterOperatorRoundTripControllerTests

/**
 * Verifies every advertised operator round-trips through SPRuleFilterController without changing its serialized leaf.
 */
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

/**
 * Verifies the starter row seeded on a table switch starts unchecked, so it is neither previewed nor
 * applied as `id = ''` while the table shows unfiltered.
 */
- (void)testSeededStarterRowStartsUncheckedAndIsNoFilter
{
	id controller = [self boundRuleFilterControllerWithColumn:@"id"];
	[controller addStarterFilterExpression];

	NSRuleEditor *editor = [controller valueForKey:@"filterRuleEditor"];
	XCTAssertEqual([editor numberOfRows], 1);
	XCTAssertEqual([[self checkboxInRow:0 of:editor] state], NSControlStateValueOff);
	XCTAssertEqual([[self whereOf:controller] length], 0u, @"an unchecked starter row must not be a filter");
}

/**
 * Verifies that typing a value into the unchecked starter row checks it, so Apply filters by it.
 */
- (void)testTypingIntoTheStarterRowChecksIt
{
	id controller = [self boundRuleFilterControllerWithColumn:@"id"];
	[controller addStarterFilterExpression];
	NSRuleEditor *editor = [controller valueForKey:@"filterRuleEditor"];

	NSTextField *field = [self firstTextFieldInRow:0 of:editor];
	XCTAssertNotNil(field);
	[field setStringValue:@"5"];
	[controller controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:field]];

	XCTAssertEqual([[self checkboxInRow:0 of:editor] state], NSControlStateValueOn);
	NSString *where = [self whereOf:controller];
	XCTAssertTrue([where containsString:@"`id`"] && [where containsString:@"5"], @"%@", where);
}

/**
 * Verifies that once the user has clicked the starter row's checkbox, typing no longer changes it.
 */
- (void)testAClickOnTheStarterCheckboxIsRespected
{
	id controller = [self boundRuleFilterControllerWithColumn:@"id"];
	[controller addStarterFilterExpression];
	NSRuleEditor *editor = [controller valueForKey:@"filterRuleEditor"];
	NSButton *checkbox = [self checkboxInRow:0 of:editor];

	// Checked and unchecked again by the user.
	[checkbox setState:NSControlStateValueOn];
	[controller _checkboxClicked:checkbox];
	[checkbox setState:NSControlStateValueOff];
	[controller _checkboxClicked:checkbox];

	NSTextField *field = [self firstTextFieldInRow:0 of:editor];
	[field setStringValue:@"5"];
	[controller controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:field]];

	XCTAssertEqual([checkbox state], NSControlStateValueOff);
	XCTAssertEqual([[self whereOf:controller] length], 0u);
}

/**
 * Verifies that a value dropped onto the drop zone still replaces the unchecked starter row, as it
 * replaced the checked one before, and is itself a filter.
 */
- (void)testADroppedValueReplacesTheUncheckedStarterRow
{
	id controller = [self boundRuleFilterControllerWithColumn:@"id"];
	[controller setEnabled:YES];
	[controller addStarterFilterExpression];
	NSRuleEditor *editor = [controller valueForKey:@"filterRuleEditor"];

	XCTAssertTrue([controller appendFilterForColumn:@"id" value:@"7" isNull:NO]);

	XCTAssertEqual([editor numberOfRows], 1);
	XCTAssertEqual([[self checkboxInRow:0 of:editor] state], NSControlStateValueOn);
	XCTAssertTrue([[self whereOf:controller] containsString:@"7"]);
}

/**
 * Verifies that the starter row still waits for its first edit after the filter is saved and restored, as
 * on a reload or a return to the table - otherwise a value typed into it would silently not be applied.
 */
- (void)testTheStarterRowWaitsForItsFirstEditAfterARestore
{
	id controller = [self boundRuleFilterControllerWithColumn:@"id"];
	[controller addStarterFilterExpression];
	NSDictionary *saved = [controller serializedFilter];

	[controller restoreSerializedFilters:saved];
	NSRuleEditor *editor = [controller valueForKey:@"filterRuleEditor"];
	XCTAssertEqual([editor numberOfRows], 1);
	XCTAssertEqual([[self checkboxInRow:0 of:editor] state], NSControlStateValueOff);
	XCTAssertEqual([[self whereOf:controller] length], 0u);

	NSTextField *field = [self firstTextFieldInRow:0 of:editor];
	[field setStringValue:@"5"];
	[controller controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:field]];

	XCTAssertEqual([[self checkboxInRow:0 of:editor] state], NSControlStateValueOn);
	XCTAssertTrue([[self whereOf:controller] containsString:@"5"]);
}

/**
 * Verifies that a drop that cannot become a rule leaves the starter row unchecked and waiting.
 */
- (void)testARejectedDropLeavesTheStarterRowAlone
{
	id controller = [self boundRuleFilterControllerWithColumn:@"id"];
	[controller setEnabled:YES];
	[controller addStarterFilterExpression];
	NSRuleEditor *editor = [controller valueForKey:@"filterRuleEditor"];

	XCTAssertFalse([controller appendFilterForColumn:@"no_such_column" value:@"7" isNull:NO]);
	XCTAssertEqual([[self checkboxInRow:0 of:editor] state], NSControlStateValueOff);
	XCTAssertEqual([[self whereOf:controller] length], 0u);

	// Still waiting: the first edit checks it.
	[controller addEmptyFilterRow];
	XCTAssertEqual([editor numberOfRows], 1);
	XCTAssertEqual([[self checkboxInRow:0 of:editor] state], NSControlStateValueOn);
}

/** The WHERE clause the controller would apply; empty when nothing is enabled. */
- (NSString *)whereOf:(id)controller
{
	NSError *error = nil;
	NSString *where = [controller sqlWhereExpressionWithBinary:NO error:&error];
	XCTAssertNil(error);
	return where ?: @"";
}

/**
 * Verifies that the drop zone's "add a filter" click checks the unchecked starter row instead of adding a
 * second empty row next to it.
 */
- (void)testAddingAFilterUsesTheUncheckedStarterRow
{
	id controller = [self boundRuleFilterControllerWithColumn:@"id"];
	[controller setEnabled:YES];
	[controller addStarterFilterExpression];
	NSRuleEditor *editor = [controller valueForKey:@"filterRuleEditor"];

	[controller addEmptyFilterRow];

	XCTAssertEqual([editor numberOfRows], 1);
	XCTAssertEqual([[self checkboxInRow:0 of:editor] state], NSControlStateValueOn);

	// With no starter pending, the click adds a row as before.
	[controller addEmptyFilterRow];
	XCTAssertEqual([editor numberOfRows], 2);
}

/**
 * A controller whose rule editor is set up and bound to the controller's model the way DBView.xib and
 * -awakeFromNib do it, so rows added through the editor reach the model the WHERE clause is built from.
 */
- (id)boundRuleFilterControllerWithColumn:(NSString *)columnName
{
	id controller = [self ruleFilterControllerForTypeGrouping:@"integer" columnName:columnName];
	NSRuleEditor *editor = [controller valueForKey:@"filterRuleEditor"];
	[editor setNestingMode:NSRuleEditorNestingModeCompound];
	[editor setCanRemoveAllRows:YES];
	[controller awakeFromNib];
	return controller;
}

/** The enable checkbox of `row`. */
- (NSButton *)checkboxInRow:(NSInteger)row of:(NSRuleEditor *)editor
{
	id value = [[editor displayValuesForRow:row] firstObject];
	XCTAssertTrue([value isKindOfClass:[NSButton class]]);
	return value;
}

/** The first argument field of `row`, or nil. */
- (NSTextField *)firstTextFieldInRow:(NSInteger)row of:(NSRuleEditor *)editor
{
	for (id value in [editor displayValuesForRow:row]) {
		if ([value isKindOfClass:[NSTextField class]]) return value;
	}
	return nil;
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

/**
 * Verifies appending a filter preserves an existing IS NULL rule as an AND-group child.
 */
- (void)testExistingIsNullRuleIsPreservedWhenAppendingNewFilter
{
	// Regression for the SerIsUntouchedStarterRule zero-value guard: before the
	// fix, this append path replaced the user's existing zero-argument NULL rule.
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
