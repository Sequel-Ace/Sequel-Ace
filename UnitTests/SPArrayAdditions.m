//
//  SPArrayAdditions.m
//  Unit Tests
//
//  Created by James on 23/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//
#import "SPArrayAdditions.h"
#import "SPTestingUtils.h"

#import <XCTest/XCTest.h>

@interface SPArrayAdditions : XCTestCase

@end

@implementation SPArrayAdditions

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

// MARK: pretty much no difference between these methods
// so I don't know why we are using NSArrayObjectAtIndex all over.
// should switch to safeObjectAtIndex for safety

//0.0259
- (void)testPerformance_NormalNSArrayObjectAtIndex {
    // this is on main thread
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
        int const iterations = 10000;

        NSArray *queryHist = [SPTestingUtils randomHistArray];

        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                id __unused ret = [queryHist objectAtIndex:i];
            }
        }
    }];
}

// 0.0264
- (void)testPerformance_safeObjectAtIndex {
    // this is on main thread
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
        int const iterations = 10000;

        NSArray *queryHist = [NSArray arrayWithArray:[SPTestingUtils randomHistArray]];

        for (NSUInteger i = 0; i < iterations; i++) {
            @autoreleasepool {
                id __unused ret = [queryHist safeObjectAtIndex:i];
            }
        }
    }];
}

- (void)testSafeObjectAtIndex {

    NSArray *testArray = @[@"first", @"second", @"third", @"fourth"];

    XCTAssertNil([testArray safeObjectAtIndex:4]);
    XCTAssertNotNil([testArray safeObjectAtIndex:3]);
    XCTAssertNotNil([testArray safeObjectAtIndex:0]);

    XCTAssertTrue([testArray safeObjectAtIndex:3] == testArray[3]);

    testArray = @[];

    XCTAssertNil([testArray safeObjectAtIndex:0]);
    XCTAssertNil([testArray safeObjectAtIndex:10]);

    NSInteger anIndex = -1;

    XCTAssertNoThrow([testArray safeObjectAtIndex:(NSUInteger)anIndex]);
    XCTAssertNil([testArray safeObjectAtIndex:(NSUInteger)anIndex]);
}

- (void)testFirstObjectPassingTest {

    NSArray *testArray = @[@"first", @"second", @"third", @"fourth"];

    id obj2 = [testArray firstObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        if ([(NSString *)obj contains:@"first"]) {
            *stop = YES;
            return YES;
        }
        return NO;
    }];

    XCTAssertNotNil(obj2);

    obj2 = [testArray firstObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        if ([(NSString *)obj contains:@"f"]) {
            *stop = YES;
            return YES;
        }
        return NO;
    }];

    XCTAssertNotNil(obj2);
    XCTAssertEqual(obj2, @"first");


    obj2 = [testArray firstObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        if ([(NSString *)obj contains:@"fifth"]) {
            *stop = YES;
            return YES;
        }
        return NO;
    }];

    XCTAssertNil(obj2);

}

//0.668 s
- (void)testPerformance_FirstObjectPassingTest_Last {
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
        int const iterations = 100;

        NSArray *queryHist = [NSArray arrayWithArray:[SPTestingUtils randomHistArray]];
        NSString *last = [queryHist lastObject];

        for (NSUInteger i = 0; i < iterations; i++) {
            @autoreleasepool {
               id obj2 = [queryHist firstObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
                    if ([(NSString *)obj contains:last]) {
                        *stop = YES;
                        return YES;
                    }
                    return NO;
                }];
                XCTAssertNotNil(obj2);
            }
        }
    }];
}

// 0.0274 s
- (void)testPerformance_FirstObjectPassingTest_First {
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
        int const iterations = 100;

        NSArray *queryHist = [NSArray arrayWithArray:[SPTestingUtils randomHistArray]];
        NSString *first = [queryHist firstObject];

        for (NSUInteger i = 0; i < iterations; i++) {
            @autoreleasepool {
               id obj2 = [queryHist firstObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
                    if ([(NSString *)obj contains:first]) {
                        *stop = YES;
                        return YES;
                    }
                    return NO;
                }];

                XCTAssertNotNil(obj2);
            }
        }
    }];
}


@end
