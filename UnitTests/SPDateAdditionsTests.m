//
//  SPDateAdditions.m
//  Unit Tests
//
//  Created by James on 15/7/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//
#import <Cocoa/Cocoa.h>
#include <mach/mach_time.h>

#import <XCTest/XCTest.h>
#import "SPDateAdditions.h"


@interface SPDateAdditionsTests : XCTestCase

@end

@implementation SPDateAdditionsTests

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testOldvsNewMonotonicTimeInterval {

	double startTimeOld = [self monotonicTimeIntervalOLD];
	double startNew = [NSDate monotonicTimeInterval];
	
	SPLog(@"JIMMY startTimeOld: %f", startTimeOld);
	SPLog(@"JIMMY startNew: %f", startNew);
	
	XCTAssertEqualWithAccuracy(startTimeOld, startNew, 0.0001);
}

- (void)testPerformanceMonotonicTimeIntervalOLD {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
		
		int const iterations = 1000000;
		
		for (int i = 0; i < iterations; i++) {
			@autoreleasepool {
				// exec on bg thread
				double startTimeOld = [self monotonicTimeIntervalOLD];
				startTimeOld = 0;
			}
		}
		
    }];
}

- (void)testPerformanceMonotonicTimeIntervalNEW {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
		
		int const iterations = 1000000;
		
		for (int i = 0; i < iterations; i++) {
			@autoreleasepool {
				// exec on bg thread
				double startTimeNEW = [NSDate monotonicTimeInterval];
				startTimeNEW = 0;
			}
		}
		
    }];
}
// OLD method for testing
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (double)monotonicTimeIntervalOLD{
	
	uint64_t elapsedTime_t = mach_absolute_time();
	Nanoseconds nanosecondsElapsed = AbsoluteToNanoseconds(*(AbsoluteTime *)&(elapsedTime_t));

	return (((double)UnsignedWideToUInt64(nanosecondsElapsed)) * 1e-9);
	
}
#pragma clang diagnostic pop

@end
