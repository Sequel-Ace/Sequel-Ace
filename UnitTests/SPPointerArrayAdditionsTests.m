//
//  SPPointerArrayAdditionsTests.m
//  Unit Tests
//
//  Created by James on 1/1/2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

#import "SPTestingUtils.h"
#import "SPPointerArrayAdditions.h"
#import <XCTest/XCTest.h>

@interface SPPointerArrayAdditionsTests : XCTestCase

@end

@implementation SPPointerArrayAdditionsTests

- (void)testSafeReplacePointerAtIndex {

    NSPointerArray *randomPointerArray = [SPTestingUtils randomPointerArray];
    NSUInteger count = randomPointerArray.count;

    XCTAssertNotNil([randomPointerArray pointerAtIndex:4]);
    XCTAssertNotNil([randomPointerArray pointerAtIndex:0]);
    XCTAssertNotNil([randomPointerArray pointerAtIndex:count-1]);

    NSLog(@"%@", [randomPointerArray pointerAtIndex:4]);
    NSLog(@"count: %lu", (unsigned long)count);

    NSArray *objAtIndexZero = [randomPointerArray pointerAtIndex:0];

    [randomPointerArray safeReplacePointerAtIndex:0 withPointer:(__bridge void * _Nullable)(@[@(10)])];

    NSArray *newObjAtIndexZero = [randomPointerArray pointerAtIndex:0];

    NSLog(@"objAtIndexZero: %@", objAtIndexZero);
    NSLog(@"newObjAtIndexZero: %@", newObjAtIndexZero);

    XCTAssertNotEqualObjects(objAtIndexZero, newObjAtIndexZero);
    XCTAssertEqualObjects(newObjAtIndexZero, @[@(10)]);

    XCTAssertNoThrow([randomPointerArray safeReplacePointerAtIndex:count withPointer:(__bridge void * _Nullable)(@[@(10)])]);
    XCTAssertThrows([randomPointerArray replacePointerAtIndex:count withPointer:(__bridge void * _Nullable)(@[@(10)])]);

    NSInteger anIndex = -1;
    XCTAssertNoThrow([randomPointerArray safeReplacePointerAtIndex:anIndex withPointer:(__bridge void * _Nullable)(@[@(10)])]);

}

//0.00328s
- (void)testPerformanceSafeReplacePointerAtIndex {

    [self measureBlock:^{
        NSPointerArray *randomPointerArray = [SPTestingUtils randomPointerArray];

        NSUInteger iterations = randomPointerArray.count;
        for (NSUInteger i = 0; i < iterations; i++) {
            @autoreleasepool {
                [randomPointerArray safeReplacePointerAtIndex:i withPointer:(__bridge void * _Nullable)(@[@(i)])];
            }
        }
    }];
}

//0.00327s
- (void)testPerformanceReplacePointerAtIndex {

    [self measureBlock:^{
        NSPointerArray *randomPointerArray = [SPTestingUtils randomPointerArray];

        NSUInteger iterations = randomPointerArray.count;
        for (NSUInteger i = 0; i < iterations; i++) {
            @autoreleasepool {
                [randomPointerArray replacePointerAtIndex:i withPointer:(__bridge void * _Nullable)(@[@(i)])];
            }
        }
    }];
}

@end
