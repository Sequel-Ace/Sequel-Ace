//
//  SPFunctionsTests.m
//  Unit Tests
//
//  Created by James on 14/1/2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

#import "SPFunctions.h"
#import "SPTestingUtils.h"

#import <XCTest/XCTest.h>

@interface SPFunctionsTests : XCTestCase

@end

@implementation SPFunctionsTests

- (void)testIsEmpty{

    NSString *str = @"Baby you're a 스타";
    XCTAssertFalse(IsEmpty(str));

    str = @"";
    XCTAssertTrue(IsEmpty(str));

    str = nil;
    XCTAssertTrue(IsEmpty(str));

    NSMutableArray *testArray = [NSMutableArray arrayWithArray:@[@"first", @"second", @"third", @"fourth"]];
    XCTAssertFalse(IsEmpty(testArray));

    testArray = nil;
    XCTAssertTrue(IsEmpty(testArray));

    NSArray *newTestArray = @[];
    XCTAssertTrue(IsEmpty(newTestArray));

    NSAttributedString *testAttStr = [[NSAttributedString alloc] initWithString:@"Han shot first."];
    XCTAssertFalse(IsEmpty(testAttStr));

    testAttStr = nil;
    XCTAssertTrue(IsEmpty(testAttStr));

    testAttStr = [[NSAttributedString alloc] initWithString:@""];
    XCTAssertTrue(IsEmpty(testAttStr));

    str = @"You’re gonna need a bigger boat...";
    NSData *testData = [str dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertFalse(IsEmpty(testData));

    str = @"";
    testData = [str dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue(IsEmpty(testData));

    NSSet *testSet = [[NSSet alloc] initWithArray:@[@"E.", @"F.", @"F.", @"E.", @"C.", @"T."]];
    XCTAssertFalse(IsEmpty(testSet));

    testSet = [[NSSet alloc] initWithArray:@[]];
    XCTAssertTrue(IsEmpty(testSet));

    testSet = nil;
    XCTAssertTrue(IsEmpty(testSet));

}

// 0.0354 s
- (void)testPerformanceIsEmptyString {
    [self measureBlock:^{
        // Put the code you want to measure the time of here.

        int const iterations = 1000000;

        NSString *str = @"You’re gonna need a bigger boat...";

        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                BOOL __unused res = IsEmpty(str);
            }
        }
    }];
}
//0.0118 s
- (void)testPerformanceIsEmptyString2{
    [self measureBlock:^{
        // Put the code you want to measure the time of here.

        int const iterations = 1000000;

        NSString *str = nil;

        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                BOOL __unused res = IsEmpty(str);
            }
        }
    }];
}

// 0.0105 s
- (void)testPerformanceIsEmptyStringOldSchool {
    [self measureBlock:^{
        // Put the code you want to measure the time of here.

        int const iterations = 1000000;

        NSString *str = @"You’re gonna need a bigger boat...";

        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                if (str != nil && [str length] > 0){
                    BOOL __unused res = NO;
                }
            }
        }
    }];
}

//0.0438 s
- (void)testPerformanceIsEmptySet {
    [self measureBlock:^{
        // Put the code you want to measure the time of here.

        int const iterations = 1000000;

        NSSet *testSet = [[NSSet alloc] initWithArray:@[@"E.", @"F.", @"F.", @"E.", @"C.", @"T."]];

        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                BOOL __unused res = IsEmpty(testSet);
            }
        }
    }];
}

// 0.0121 s
- (void)testPerformanceIsEmptySet2{
    [self measureBlock:^{
        // Put the code you want to measure the time of here.

        int const iterations = 1000000;

        NSSet *testSet = nil;

        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                BOOL __unused res = IsEmpty(testSet);
            }
        }
    }];
}

//0.0104 s
- (void)testPerformanceIsEmptySetOldSchool {
    [self measureBlock:^{
        // Put the code you want to measure the time of here.

        int const iterations = 1000000;

        NSSet *testSet = [[NSSet alloc] initWithArray:@[@"E.", @"F.", @"F.", @"E.", @"C.", @"T."]];

        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                if (testSet != nil && [testSet count] > 0){
                    BOOL __unused res = YES;
                }
            }
        }
    }];
}

//0.00845 s
- (void)testPerformanceIsEmptySetOldSchool2{
    [self measureBlock:^{
        // Put the code you want to measure the time of here.

        int const iterations = 1000000;

        NSSet *testSet = nil;

        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                if (testSet != nil && [testSet count] > 0){
                    BOOL __unused res = YES;
                }
            }
        }
    }];
}

// 0.0292 s
- (void)testPerformanceNormalForLoop {
    [self measureBlock:^{
        // Put the code you want to measure the time of here.

        int const iterations = 100;

        NSMutableArray *randomArray = [SPTestingUtils randomHistArray];

        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                for(NSString* __unused obj in randomArray){}
            }
        }
    }];
}

@end
