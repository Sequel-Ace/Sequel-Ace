//
//  SPPostgreSQLTypeMapperTests.m
//  Unit Tests
//
//  Tests for SPPostgreSQLTypeMapper: OID → SQL type name, and the
//  numeric/text/datetime categorisation helpers.
//

#import <XCTest/XCTest.h>
#import "SPPostgreSQLTypeMapper.h"

@interface SPPostgreSQLTypeMapperTests : XCTestCase
@property (nonatomic, strong) SPPostgreSQLTypeMapper *mapper;
@end

@implementation SPPostgreSQLTypeMapperTests

- (void)setUp {
    [super setUp];
    self.mapper = [[SPPostgreSQLTypeMapper alloc] init];
}

- (void)tearDown {
    self.mapper = nil;
    [super tearDown];
}

// MARK: - Known OIDs

- (void)testOID23IsInteger {
    // OID 23 = int4
    NSString *type = [self.mapper typeNameForOID:23];
    XCTAssertEqualObjects(type, @"int4");
}

- (void)testOID25IsText {
    // OID 25 = text
    NSString *type = [self.mapper typeNameForOID:25];
    XCTAssertEqualObjects(type, @"text");
}

- (void)testOID16IsBoolean {
    // OID 16 = bool
    NSString *type = [self.mapper typeNameForOID:16];
    XCTAssertEqualObjects(type, @"bool");
}

- (void)testOID700IsFloat4 {
    // OID 700 = float4
    NSString *type = [self.mapper typeNameForOID:700];
    XCTAssertEqualObjects(type, @"float4");
}

- (void)testOID701IsFloat8 {
    // OID 701 = float8
    NSString *type = [self.mapper typeNameForOID:701];
    XCTAssertEqualObjects(type, @"float8");
}

- (void)testOID1700IsNumeric {
    // OID 1700 = numeric
    NSString *type = [self.mapper typeNameForOID:1700];
    XCTAssertEqualObjects(type, @"numeric");
}

- (void)testOID1114IsTimestamp {
    // OID 1114 = timestamp
    NSString *type = [self.mapper typeNameForOID:1114];
    XCTAssertEqualObjects(type, @"timestamp");
}

- (void)testOID1082IsDate {
    // OID 1082 = date
    NSString *type = [self.mapper typeNameForOID:1082];
    XCTAssertEqualObjects(type, @"date");
}

- (void)testUnknownOIDReturnsUnknown {
    // An OID we definitely don't know should return a non-nil fallback
    NSString *type = [self.mapper typeNameForOID:99999];
    XCTAssertNotNil(type);
}

// MARK: - Type categorisation

- (void)testIntegerOIDIsInteger {
    XCTAssertTrue([self.mapper isIntegerTypeForOID:23]);   // int4
    XCTAssertTrue([self.mapper isIntegerTypeForOID:20]);   // int8
    XCTAssertTrue([self.mapper isIntegerTypeForOID:21]);   // int2
}

- (void)testTextOIDIsNotInteger {
    XCTAssertFalse([self.mapper isIntegerTypeForOID:25]);  // text
}

- (void)testFloatOIDIsFloat {
    XCTAssertTrue([self.mapper isFloatTypeForOID:700]);    // float4
    XCTAssertTrue([self.mapper isFloatTypeForOID:701]);    // float8
    XCTAssertTrue([self.mapper isFloatTypeForOID:1700]);   // numeric
}

- (void)testTextOIDIsString {
    XCTAssertTrue([self.mapper isStringTypeForOID:25]);    // text
    XCTAssertTrue([self.mapper isStringTypeForOID:1043]);  // varchar
}

- (void)testTimestampOIDIsDatetime {
    XCTAssertTrue([self.mapper isDatetimeTypeForOID:1114]);  // timestamp
    XCTAssertTrue([self.mapper isDatetimeTypeForOID:1082]);  // date
    XCTAssertTrue([self.mapper isDatetimeTypeForOID:1083]);  // time
}

@end
