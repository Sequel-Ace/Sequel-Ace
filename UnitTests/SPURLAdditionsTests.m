//
//  SPURLAdditions.m
//  Unit Tests
//
//  Created by James on 12/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

#import <XCTest/XCTest.h>

@interface SPURLAdditionsTests : XCTestCase

@end

@implementation SPURLAdditionsTests


- (void)testExample {
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.

	NSURL *tmp = [NSURL fileURLWithPath:@"jimmy"];
	NSURL *tmp2 = [NSURL fileURLWithPath:@"jimmy" isDirectory:NO];

	XCTAssertEqualObjects(tmp, tmp2);
}

// 0.15 s
- (void)testPerformanceSwizzle{
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.

		int const iterations = 10000;
		for (int i = 0; i < iterations; i++) {
			@autoreleasepool {
				NSURL __unused *tmp2 = [NSURL fileURLWithPath:@"jimmy" isDirectory:NO];
			}
		}
    }];
}

// 0.161 s
- (void)testPerformanceNoSwizzle{
	// This is an example of a performance test case.
	[self measureBlock:^{
		// Put the code you want to measure the time of here.

		int const iterations = 10000;
		for (int i = 0; i < iterations; i++) {
			@autoreleasepool {
				NSURL __unused *tmp2 = [NSURL fileURLWithPath:@"jimmy"];
			}
		}
	}];
}

@end
