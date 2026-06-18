//
//  SAPHPSerializedParserTests.m
//  sequel-ace
//
//  Created by Codex on 2026-06-15.
//

#import "SAPHPSerializedValue.h"
#import <XCTest/XCTest.h>

@interface SAPHPSerializedParserTests : XCTestCase

@end

@implementation SAPHPSerializedParserTests

- (void)testRoundTripsStructuredSerializedData
{
	NSString *serialized = @"a:4:{s:4:\"name\";s:5:\"Marco\";s:5:\"count\";i:42;s:5:\"valid\";b:1;s:6:\"nested\";a:1:{i:0;s:3:\"yes\";}}";
	SAPHPSerializedValue *value = [SAPHPSerializedParser parseString:serialized error:nil];

	XCTAssertNotNil(value);
	XCTAssertEqualObjects([value serializedString], serialized);
}

- (void)testRecalculatesUtf8StringLengths
{
	SAPHPSerializedValue *value = [SAPHPSerializedParser parseString:@"s:2:\"é\";" error:nil];

	XCTAssertNotNil(value);
	value.scalarValue = @"éé";
	XCTAssertEqualObjects([value serializedString], @"s:4:\"éé\";");
}

- (void)testParsesStringLengthsUsingProvidedEncoding
{
	NSString *serialized = @"s:1:\"é\";";
	NSString *errorMessage = nil;
	SAPHPSerializedValue *utf8Value = [SAPHPSerializedParser parseString:serialized error:&errorMessage];
	SAPHPSerializedValue *latin1Value = [SAPHPSerializedParser parseString:serialized encoding:NSISOLatin1StringEncoding error:nil];

	XCTAssertNil(utf8Value);
	XCTAssertNotNil(errorMessage);
	XCTAssertNotNil(latin1Value);
	XCTAssertEqualObjects(latin1Value.scalarValue, @"é");
	XCTAssertEqualObjects([latin1Value serializedString], serialized);
}

- (void)testSerializesStringLengthsUsingProvidedEncoding
{
	SAPHPSerializedValue *value = [SAPHPSerializedParser parseString:@"s:1:\"é\";" encoding:NSISOLatin1StringEncoding error:nil];

	XCTAssertNotNil(value);
	value.scalarValue = @"éé";
	XCTAssertEqualObjects([value serializedString], @"s:2:\"éé\";");
}

- (void)testRejectsOversizedSerializedLength
{
	NSString *errorMessage = nil;
	SAPHPSerializedValue *value = [SAPHPSerializedParser parseString:@"s:184467440737095516150:\"x\";" error:&errorMessage];

	XCTAssertNil(value);
	XCTAssertNotNil(errorMessage);
}

- (void)testRejectsStringLengthBeyondAvailableBytes
{
	NSString *errorMessage = nil;
	SAPHPSerializedValue *value = [SAPHPSerializedParser parseString:@"s:999:\"abc\";" error:&errorMessage];

	XCTAssertNil(value);
	XCTAssertNotNil(errorMessage);
}

- (void)testRejectsInvalidFloatPayload
{
	NSString *errorMessage = nil;
	SAPHPSerializedValue *value = [SAPHPSerializedParser parseString:@"d:hello;" error:&errorMessage];

	XCTAssertNil(value);
	XCTAssertNotNil(errorMessage);
}

- (void)testFloatValidationUsesPHPDotDecimalFormat
{
	XCTAssertTrue([SAPHPSerializedValue isValidPHPFloatString:@"12.34"]);
	XCTAssertFalse([SAPHPSerializedValue isValidPHPFloatString:@"12,34"]);
}

- (void)testFloatValidationRejectsNoncanonicalSpecialTokens
{
	XCTAssertTrue([SAPHPSerializedValue isValidPHPFloatString:@"INF"]);
	XCTAssertTrue([SAPHPSerializedValue isValidPHPFloatString:@"-INF"]);
	XCTAssertTrue([SAPHPSerializedValue isValidPHPFloatString:@"NAN"]);
	XCTAssertFalse([SAPHPSerializedValue isValidPHPFloatString:@"inf"]);
	XCTAssertFalse([SAPHPSerializedValue isValidPHPFloatString:@"-inf"]);
	XCTAssertFalse([SAPHPSerializedValue isValidPHPFloatString:@"nan"]);
}

- (void)testRejectsNoncanonicalSerializedSpecialFloatTokens
{
	NSString *errorMessage = nil;
	SAPHPSerializedValue *value = [SAPHPSerializedParser parseString:@"d:inf;" error:&errorMessage];

	XCTAssertNil(value);
	XCTAssertNotNil(errorMessage);
}

- (void)testRejectsExcessiveNestingDepth
{
	NSMutableString *serialized = [NSMutableString stringWithString:@"s:3:\"end\";"];
	for (NSUInteger i = 0; i < 600; i++) {
		[serialized insertString:@"a:1:{i:0;" atIndex:0];
		[serialized appendString:@"}"];
	}

	NSString *errorMessage = nil;
	SAPHPSerializedValue *value = [SAPHPSerializedParser parseString:serialized error:&errorMessage];

	XCTAssertNil(value);
	XCTAssertNotNil(errorMessage);
}

- (void)testIntegerEditsAreTrimmedBeforeSerialization
{
	SAPHPSerializedValue *value = [SAPHPSerializedParser parseString:@"i:1;" error:nil];
	value.scalarValue = [SAPHPSerializedValue normalizedIntegerStringFromEditedString:@" 42 "];

	XCTAssertEqualObjects([value serializedString], @"i:42;");
}

- (void)testAddingArrayChildUsesNextIntegerKey
{
	SAPHPSerializedValue *value = [SAPHPSerializedParser parseString:@"a:2:{i:0;s:4:\"zero\";i:2;s:3:\"two\";}" error:nil];
	SAPHPSerializedEntry *entry = [[SAPHPSerializedEntry alloc] init];
	entry.keyIsInteger = YES;
	entry.key = [value nextAvailableArrayKey];
	entry.value = [SAPHPSerializedValue valueWithType:SAPHPSerializedValueTypeString];

	[value.children addObject:entry];

	XCTAssertEqualObjects([value serializedString], @"a:3:{i:0;s:4:\"zero\";i:2;s:3:\"two\";i:3;s:0:\"\";}");
}

- (void)testAddingNestedArrayChildSerializesSubArray
{
	SAPHPSerializedValue *value = [SAPHPSerializedParser parseString:@"a:1:{i:0;s:4:\"root\";}" error:nil];
	SAPHPSerializedEntry *entry = [[SAPHPSerializedEntry alloc] init];
	entry.keyIsInteger = YES;
	entry.key = [value nextAvailableArrayKey];
	entry.value = [SAPHPSerializedValue valueWithType:SAPHPSerializedValueTypeArray];

	SAPHPSerializedEntry *nestedEntry = [[SAPHPSerializedEntry alloc] init];
	nestedEntry.parent = entry;
	nestedEntry.keyIsInteger = YES;
	nestedEntry.key = [entry.value nextAvailableArrayKey];
	nestedEntry.value = [SAPHPSerializedValue valueWithType:SAPHPSerializedValueTypeString];
	nestedEntry.value.scalarValue = @"nested";
	[entry.value.children addObject:nestedEntry];

	[value.children addObject:entry];

	XCTAssertEqualObjects([value serializedString], @"a:2:{i:0;s:4:\"root\";i:1;a:1:{i:0;s:6:\"nested\";}}");
}

- (void)testDetectsReferencesRecursively
{
	SAPHPSerializedValue *withoutReference = [SAPHPSerializedParser parseString:@"a:1:{i:0;s:5:\"plain\";}" error:nil];
	SAPHPSerializedValue *withReference = [SAPHPSerializedParser parseString:@"a:2:{i:0;s:5:\"plain\";i:1;R:2;}" error:nil];

	XCTAssertNotNil(withoutReference);
	XCTAssertNotNil(withReference);
	XCTAssertFalse([withoutReference containsReference]);
	XCTAssertTrue([withReference containsReference]);
}

- (void)testAddingObjectChildUsesUniquePropertyName
{
	SAPHPSerializedValue *value = [SAPHPSerializedParser parseString:@"O:8:\"stdClass\":2:{s:12:\"new_property\";s:3:\"old\";s:14:\"new_property_2\";s:3:\"two\";}" error:nil];
	SAPHPSerializedEntry *entry = [[SAPHPSerializedEntry alloc] init];
	entry.keyIsInteger = NO;
	entry.key = [value uniqueObjectPropertyName];
	entry.value = [SAPHPSerializedValue valueWithType:SAPHPSerializedValueTypeString];

	[value.children addObject:entry];

	XCTAssertEqualObjects([value serializedString], @"O:8:\"stdClass\":3:{s:12:\"new_property\";s:3:\"old\";s:14:\"new_property_2\";s:3:\"two\";s:14:\"new_property_3\";s:0:\"\";}");
}

@end
