//
//  SPMutableArrayAdditionsTests.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on February 2, 2011.
//  Copyright (c) 2011 Stuart Connolly. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  More info at <https://github.com/sequelpro/sequelpro>

#import "SPMutableArrayAdditions.h"
#import "NSMutableArray-MultipleSort.h"
#import "SPTestingUtils.h"
#import "SPFunctions.h"
#import <XCTest/XCTest.h>

/**
 * @class SPMutableArrayAdditionsTest SPMutableArrayAdditionsTest.h
 *
 * @author Stuart Connolly http://stuconnolly.com/
 *
 * SPMutableArrayAdditions tests class.
 */
@interface SPMutableArrayAdditionsTests : XCTestCase

@end

@implementation SPMutableArrayAdditionsTests

/**
 * reverse test case.
 */
- (void)testReverse
{
	NSMutableArray *testArray = [NSMutableArray arrayWithObjects:@"1", @"2", @"3", @"4", @"5", nil];
	NSMutableArray *expectedArray = [NSMutableArray arrayWithObjects:@"5", @"4", @"3", @"2", @"1", nil];

	[testArray reverse];
	
	XCTAssertEqualObjects(testArray, expectedArray, @"The reversed array should look like: %@, but actually looks like: %@", expectedArray, testArray);

}

- (void)testSafeSetArray
{
    NSMutableArray *testArray = [NSMutableArray arrayWithObjects:@"1", @"2", @"3", @"4", @"5", nil];
    NSMutableArray *expectedArray = [NSMutableArray arrayWithObjects:@"5", @"4", @"3", @"2", @"1", nil];

    [testArray setArray:expectedArray];

    XCTAssertEqualObjects(testArray, expectedArray, @"The reversed array should look like: %@, but actually looks like: %@", expectedArray, testArray);

    expectedArray = nil;
    testArray = [NSMutableArray arrayWithObjects:@"1", @"2", @"3", @"4", @"5", nil];

    [testArray setArray:expectedArray];

    XCTAssertTrue(IsEmpty(testArray));
    XCTAssertNotNil(testArray);

    testArray = [NSMutableArray arrayWithObjects:@"1", @"2", @"3", @"4", @"5", nil];

    [testArray safeSetArray:expectedArray];

    XCTAssertFalse(IsEmpty(testArray));
    XCTAssertNotNil(testArray);

    testArray = nil;

    [testArray setArray:expectedArray];

    XCTAssertTrue(IsEmpty(testArray));
    XCTAssertNil(testArray);

    testArray = nil;

    [testArray safeSetArray:expectedArray];

    XCTAssertTrue(IsEmpty(testArray));
    XCTAssertNil(testArray);

}


- (void)testSort
{
	NSMutableArray *testArray = [NSMutableArray arrayWithObjects:@"o" ,@"n" ,@"m" ,@"l" ,@"k" ,@"j" ,@"i" ,@"h" ,@"g" ,@"f" ,@"e" ,@"d" ,@"c" ,@"b" ,@"a", nil];
	NSMutableArray *expectedArray = [NSMutableArray arrayWithObjects:@"a", @"b", @"c", @"d", @"e", @"f", @"g", @"h", @"i", @"j", @"k", @"l", @"m", @"n", @"o", nil];

	NSMutableArray *sortedArray = [NSMutableArray array];

	NSMutableArray *PairedMutableArray = [NSMutableArray arrayWithObjects:@0, @0, @0, @0, @0, @0, @0, @0, @0, @0, @0, @0, @0, @0, @0, @0, nil];

	[sortedArray setArray:[testArray sortedArrayUsingSelector:@selector(localizedCompare:)]];

	XCTAssertEqualObjects(sortedArray, expectedArray, @"The sorted array should look like: %@, but actually looks like: %@", expectedArray, testArray);

	[testArray sortArrayUsingSelector:@selector(localizedCompare:) withPairedMutableArrays:PairedMutableArray, nil];

	XCTAssertEqualObjects(testArray, expectedArray, @"The sorted array should look like: %@, but actually looks like: %@", expectedArray, testArray);
}


- (void)testPerformance_withPairedMutableArrays {
	// this is on main thread
	[self measureBlock:^{
		// Put the code you want to measure the time of here.
		NSMutableArray *testArray = [NSMutableArray arrayWithObjects:@"o" ,@"n" ,@"m" ,@"l" ,@"k" ,@"j" ,@"i" ,@"h" ,@"g" ,@"f" ,@"e" ,@"d" ,@"c" ,@"b" ,@"a", nil];
		NSMutableArray *PairedMutableArray = [NSMutableArray arrayWithObjects:@0, @0, @0, @0, @0, @0, @0, @0, @0, @0, @0, @0, @0, @0, @0, @0, nil];

		int const iterations = 100000;
		for (int i = 0; i < iterations; i++) {
			@autoreleasepool {
				[testArray sortArrayUsingSelector:@selector(localizedCompare:) withPairedMutableArrays:PairedMutableArray, nil];
			}
		}
	}];
}

- (void)testPerformance_sortArrayUsingSelector {
	// this is on main thread
	[self measureBlock:^{
		// Put the code you want to measure the time of here.
		NSMutableArray *testArray = [NSMutableArray arrayWithObjects:@"o" ,@"n" ,@"m" ,@"l" ,@"k" ,@"j" ,@"i" ,@"h" ,@"g" ,@"f" ,@"e" ,@"d" ,@"c" ,@"b" ,@"a", nil];
		NSMutableArray *sortedArray = [NSMutableArray array];
		int const iterations = 100000;
		for (int i = 0; i < iterations; i++) {
			@autoreleasepool {
				[sortedArray setArray:[testArray sortedArrayUsingSelector:@selector(localizedCompare:)]];
			}
		}
	}];
}

- (void)testSafeReplaceObjectAtIndex {

    NSMutableArray *testArray = [NSMutableArray arrayWithArray:@[@"first", @"second", @"third", @"fourth"]];

    [testArray safeReplaceObjectAtIndex:0 withObject:@"fifth"];

    XCTAssertEqual([testArray safeObjectAtIndex:0], @"fifth");

    XCTAssertNoThrow([testArray safeReplaceObjectAtIndex:testArray.count withObject:@"fifth"]);
    XCTAssertThrows([testArray replaceObjectAtIndex:testArray.count withObject:@"fifth"]);

    NSMutableArray *testArrayCopy = [testArray copy];

    XCTAssertNoThrow([testArray safeReplaceObjectAtIndex:0 withObject:nil]);

    XCTAssertEqual([testArray safeObjectAtIndex:0], [testArrayCopy safeObjectAtIndex:0]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    XCTAssertThrows([testArray replaceObjectAtIndex:0 withObject:nil]);
#pragma clang diagnostic pop

    NSInteger anIndex = -1;

    XCTAssertNoThrow([testArray safeReplaceObjectAtIndex:anIndex withObject:@"fifth"]);
    XCTAssertThrows([testArray replaceObjectAtIndex:anIndex withObject:@"fifth"]);

}

//0.0271s
- (void)testPerformanceSafeReplaceObjectAtIndex {

    [self measureBlock:^{

        NSMutableArray *randomArray = [SPTestingUtils randomHistArray];

        NSUInteger iterations = randomArray.count;
        for (NSUInteger i = 0, j = randomArray.count-1;
             i < iterations && j > 0;
             i++, j--) {
            @autoreleasepool {
                [randomArray safeReplaceObjectAtIndex:j withObject:@(i)];
            }
        }
    }];
}

//0.0262s
- (void)testPerformanceReplaceObjectAtIndex {

    [self measureBlock:^{
        NSMutableArray *randomArray = [SPTestingUtils randomHistArray];

        NSUInteger iterations = randomArray.count;
        for (NSUInteger i = 0, j = randomArray.count-1;
             i < iterations && j > 0;
             i++, j--) {
            @autoreleasepool {
                [randomArray replaceObjectAtIndex:j withObject:@(i)];
            }
        }

    }];
}

- (void)testSafeRemoveObjectAtIndex {

    NSMutableArray *testArray = [NSMutableArray arrayWithArray:@[@"first", @"second", @"third", @"fourth"]];

    [testArray safeRemoveObjectAtIndex:0];

    XCTAssertTrue(testArray.count == 3);

    XCTAssertNoThrow([testArray safeRemoveObjectAtIndex:testArray.count]);
    XCTAssertThrows([testArray removeObjectAtIndex:testArray.count]);

    XCTAssertNoThrow([testArray safeRemoveObjectAtIndex:-1]);
    XCTAssertThrows([testArray removeObjectAtIndex:-1]);

}
// 0.0272s
- (void)testPerformanceRemoveObjectAtIndex {

    [self measureBlock:^{
        NSMutableArray *randomArray = [SPTestingUtils randomHistArray];

        for (NSUInteger i = randomArray.count-1; i > 0; i--) {
            @autoreleasepool {
                [randomArray removeObjectAtIndex:i];
            }
        }
    }];
}
//0.0289s
- (void)testPerformanceSafeRemoveObjectAtIndex {

    [self measureBlock:^{
        NSMutableArray *randomArray = [SPTestingUtils randomHistArray];

        for (NSUInteger i = randomArray.count-1; i > 0; i--) {
            @autoreleasepool {
                [randomArray safeRemoveObjectAtIndex:i];
            }
        }
    }];
}

// 0.761 s
- (void)testPerformanceReverse {

    [self measureBlock:^{

        NSMutableArray *randomArray = [SPTestingUtils randomHistArray];

        int const iterations = 1000;
        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                [randomArray reverse];
            }
        }
    }];
}

@end
