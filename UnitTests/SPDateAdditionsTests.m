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
#import "sequel-ace-Swift.h"


@interface SPDateAdditionsTests : XCTestCase

@end

@implementation SPDateAdditionsTests

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testPerformanceMonotonicTimeInterval {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.

		int const iterations = 1000000;

		for (int i = 0; i < iterations; i++) {
			@autoreleasepool {
				// exec on bg thread
				uint64_t startTime = [NSDate monotonicTime];
				startTime = 0;
			}
		}

    }];
}

//0.9s - twice as slow as the Obj C static
- (void)testPerformanceFormatWithFormat {
	// This is an example of a performance test case.
	[self measureBlock:^{
		// Put the code you want to measure the time of here.

		int const iterations = 100000;

		for (int i = 0; i < iterations; i++) {
			@autoreleasepool {
				// exec on bg thread
				NSString __unused *tmp = [[NSDate date] stringWithFormat:@"HHmmss"
														 locale:[NSLocale autoupdatingCurrentLocale]
													   timeZone:[NSTimeZone localTimeZone]];
			}
		}

	}];
}

// locale:[NSLocale autoupdatingCurrentLocale] timeZone:[NSTimeZone localTimeZone]

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
// 0.5s
- (void)testPerformanceDescriptionWithCalendarFormat {
	// This is an example of a performance test case.
	[self measureBlock:^{
		// Put the code you want to measure the time of here.

		int const iterations = 100000;

		for (int i = 0; i < iterations; i++) {
			@autoreleasepool {
				// exec on bg thread
				NSString __unused *tmp = [[NSDate  date] descriptionWithCalendarFormat:@"%H%M%S"
																			  timeZone:[NSTimeZone localTimeZone]
													  locale:[NSLocale autoupdatingCurrentLocale]];
			}
		}

	}];
}


- (void)testOldvsNewDateFormat {
	
	NSString *str1 = [NSString stringWithFormat:@"%@%@",
									SPImportClipboardTempFileNamePrefix,
									[[NSDate  date] descriptionWithCalendarFormat:@"%H%M%S"
											timeZone:nil
											locale:[[NSUserDefaults standardUserDefaults] dictionaryRepresentation]]];

	
	NSString *str3 = [NSString stringWithFormat:@"%@%@",
									SPImportClipboardTempFileNamePrefix,
									[[NSDate date] stringWithFormat:@"HHmmss"
																	locale:[NSLocale autoupdatingCurrentLocale]
														   timeZone:[NSTimeZone localTimeZone]]];
	
	
	XCTAssertEqualObjects(str1, str3);

	str1 = [[NSDate date] descriptionWithCalendarFormat:@"%Y-%m-%d" timeZone:nil locale:nil];
	str3 = [[NSDate date] stringWithFormat:@"yyyy-MM-dd" locale:[NSLocale autoupdatingCurrentLocale] timeZone:[NSTimeZone localTimeZone]];

	XCTAssertEqualObjects(str1, str3);

	str1 = [[NSDate date] descriptionWithCalendarFormat:@"%Y" timeZone:nil locale:nil];
	str3 = [[NSDate date] stringWithFormat:@"yyyy" locale:[NSLocale autoupdatingCurrentLocale] timeZone:[NSTimeZone localTimeZone]];

	XCTAssertEqualObjects(str1, str3);

	str1 = [[NSDate date] descriptionWithCalendarFormat:@"%m" timeZone:nil locale:nil];
	str3 = [[NSDate date] stringWithFormat:@"MM" locale:[NSLocale autoupdatingCurrentLocale] timeZone:[NSTimeZone localTimeZone]];

	XCTAssertEqualObjects(str1, str3);

	str1 = [[NSDate date] descriptionWithCalendarFormat:@"%d" timeZone:nil locale:nil];
	str3 = [[NSDate date] stringWithFormat:@"dd" locale:[NSLocale autoupdatingCurrentLocale] timeZone:[NSTimeZone localTimeZone]];

	XCTAssertEqualObjects(str1, str3);

	str1 = [[NSDate date] descriptionWithCalendarFormat:@"%H:%M:%S" timeZone:nil locale:nil];
	str3 = [[NSDate date] stringWithFormat:@"HH:mm:ss" locale:[NSLocale autoupdatingCurrentLocale] timeZone:[NSTimeZone localTimeZone]];

	XCTAssertEqualObjects(str1, str3);


}
#pragma clang diagnostic pop

@end
