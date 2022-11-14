//
//  SPMySQLGeometryDataTests.m
//  SPMySQLFramework
//
//  Created by Luis Aguiniga on 11.06.2022
//

#import <XCTest/XCTest.h>
#import "SPMySQLGeometryData.h"
#include <CoreFoundation/CoreFoundation.h>

@interface SPMySQLGeometryDataTests : XCTestCase

@end

// C - Helper Functions - Declerations
static void initialize_point(void *buffer, uint32_t srid, double x, double y);

@implementation SPMySQLGeometryDataTests

- (void)test_PointWithSrid4326_MySQL_5 {
  uint8_t buffer[32] = {0};

  // Simulate MySQL 5.5+ < 8 behavior for SRID 4326:
  //
  //     mysql> select
  //         ->   HEX(ST_GeomFromText('POINT(10 20)', 4326)) as `Point_4326`,
  //         ->   ST_AsText(ST_GeomFromText('POINT(10 20)', 4326)) as `AsText_4326`;
  //     +----------------------------------------------------+--------------+
  //     | Point_4326                                         | AsText_4326  |
  //     +----------------------------------------------------+--------------+
  //     | E6100000010100000000000000000024400000000000003440 | POINT(10 20) |
  //     +----------------------------------------------------+--------------+
  //
  // buffer breakdown:
  // [ SRID ]  [ByteOrder]  [WKB Type]  [      X       ]  [      Y       ]
  // [ 4326 ]  [    1    ]  [    1   ]  [     10       ]  [     20       ]
  // E6100000      01        01000000   0000000000002440  0000000000003440
  initialize_point(buffer, 4326, 10.0, 20.0);

  SPMySQLGeometryData *mysql5 = [SPMySQLGeometryData dataWithBytes:(const void *)buffer length: 25 version: 5];
  NSString *result = [mysql5 wktString];
  XCTAssertTrue([@"POINT(10 20),4326" isEqual: result]);
}

- (void)test_PointWithSrid4326_MySQL_8 {
  uint8_t buffer[32] = {0};

  // Simulate MySQL 8 behavior for SRID 4326:
  //
  //     mysql> select
  //         ->   HEX(ST_GeomFromText('POINT(10 20)', 4326)) as `Point_4326`,
  //         ->   ST_AsText(ST_GeomFromText('POINT(10 20)', 4326)) as `AsText_4326`;
  //     +----------------------------------------------------+--------------+
  //     | Point_4326                                         | AsText_4326  |
  //     +----------------------------------------------------+--------------+
  //     | E6100000010100000000000000000034400000000000002440 | POINT(10 20) |
  //     +----------------------------------------------------+--------------+
  //
  // buffer breakdown:
  // [ SRID ]  [ByteOrder]  [WKB Type]  [      Y       ]  [      X       ]
  // [ 4326 ]  [    1    ]  [    1   ]  [     20       ]  [     10       ]
  // E6100000      01       01000000    0000000000003440  0000000000002440
  // Note: while we use POINT(10 20) in both examples, MySQL 8 swaps X Y values in storage so we swap them here to simulate that:
  initialize_point(buffer, 4326, 20.0, 10.0);

  // Pre-Fix (version 5 approach swaps coordinates):
  SPMySQLGeometryData *mysql5 = [SPMySQLGeometryData dataWithBytes:(const void *)buffer length: 25 version: 5];
  NSString *result5 = [mysql5 wktString];
  XCTAssertTrue([@"POINT(20 10),4326" isEqual: result5]);

  // Post Fix (version 8 recognizes swap and corrects for it based on SRID):
  SPMySQLGeometryData *mysql8 = [SPMySQLGeometryData dataWithBytes:(const void *)buffer length: 25 version: 8];
  NSString *result8 = [mysql8 wktString];
  XCTAssertTrue([@"POINT(10 20),4326" isEqual: result8]);
}

- (void)test_PointWithSrid0_MySQL_5_and_8 {
  uint8_t buffer[32] = {0};

  // Simulate MySQL 5.5 & 8 behavior for SRID 0:
  //
  //     mysql> select
  //         ->   HEX(ST_GeomFromText('POINT(10 20)')) as `Point`,
  //         ->   ST_AsText(ST_GeomFromText('POINT(10 20)')) as `AsText`;
  //     +----------------------------------------------------+--------------+
  //     | Point                                              | AsText       |
  //     +----------------------------------------------------+--------------+
  //     | 00000000010100000000000000000024400000000000003440 | POINT(10 20) |
  //     +----------------------------------------------------+--------------+
  //
  // buffer breakdown:
  // [ SRID ]  [ByteOrder]  [WKB Type]  [      Y       ]  [      X       ]
  // [ 4326 ]  [    1    ]  [    1   ]  [     20       ]  [     10       ]
  // 00000000      01        01000000   0000000000002440  0000000000003440
  initialize_point(buffer, 0, 10.0, 20.0);

  // Pre-Fix (version 5 approach swaps coordinates):
  SPMySQLGeometryData *mysql5 = [SPMySQLGeometryData dataWithBytes:(const void *)buffer length: 25 version: 5];
  NSString *result5 = [mysql5 wktString];
  XCTAssertTrue([@"POINT(10 20)" isEqual: result5]);

  // Post Fix (version 8 recognizes swap and corrects for it based on SRID):
  SPMySQLGeometryData *mysql8 = [SPMySQLGeometryData dataWithBytes:(const void *)buffer length: 25 version: 8];
  NSString *result8 = [mysql8 wktString];
  XCTAssertTrue([@"POINT(10 20)" isEqual: result8]);
}

@end

// C - Helper Functions - Implementations
static void initialize_point(void *buffer, uint32_t srid, double x, double y) {
  static uint8_t  byteOrder = 0x01;
  static uint32_t wkbtype   = 0x00000001; // wkb_point

  // clear buffer
  memset(buffer, 0x00, 32);

  // set buffer
  memcpy(buffer +  0,      &srid, 4);
  memcpy(buffer +  4, &byteOrder, 1); // byte order == little endian
  memcpy(buffer +  5,   &wkbtype, 4);
  memcpy(buffer +  9,         &x, 8);
  memcpy(buffer + 17,         &y, 8);
}
