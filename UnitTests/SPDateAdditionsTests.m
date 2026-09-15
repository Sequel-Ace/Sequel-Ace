//
//  SPDateAdditions.m
//  Unit Tests
//
//  Created by James on 15/7/2020.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//
#import <Cocoa/Cocoa.h>
#include <mach/mach_time.h>

#import <XCTest/XCTest.h>
#import "SPDateAdditions.h"
#import "SPTestingUtils.h"
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
    SASkipUnlessPerformanceTestsEnabled();
    [self measureBlock:^{
        // Put the code you want to measure the time of here.

		int const iterations = 1000000;

		for (int i = 0; i < iterations; i++) {
			@autoreleasepool {
				// exec on bg thread
				uint64_t __unused startTime = [NSDate monotonicTime];
			}
		}

    }];
}

//0.9s - twice as slow as the Obj C static
- (void)testPerformanceFormatWithFormat {
	// This is an example of a performance test case.
	SASkipUnlessPerformanceTestsEnabled();
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
	SASkipUnlessPerformanceTestsEnabled();
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


// The two formatters disagree on the seconds digit when the instant has a
// fractional part in the last half millisecond of a second: NSDateFormatter
// (behind -stringWithFormat:locale:timeZone:) rounds to the nearest
// millisecond, so x.9995 s and later format as the next second, while the
// legacy -descriptionWithCalendarFormat:timeZone:locale: truncates and still
// prints x. Measured on macOS 26 with an instant at x.9994 s (both print x)
// and x.9995 s (legacy x, NSDateFormatter x+1). Formatting [NSDate date]
// therefore failed on CI whenever the test happened to run inside that
// window, so the test formats a fixed whole-second instant instead; the
// wall clock no longer takes part.
- (void)testOldvsNewDateFormat {

	// 2020-07-15 13:54:47 UTC, chosen with no fractional second so both
	// formatters see the same integral second; formatted in the local zone
	// by both calls below, so the zone itself does not matter.
	NSDate *instant = [NSDate dateWithTimeIntervalSince1970:1594821287];

	NSString *str1 = [NSString stringWithFormat:@"%@%@",
									SPImportClipboardTempFileNamePrefix,
									[instant descriptionWithCalendarFormat:@"%H%M%S"
											timeZone:nil
											locale:[[NSUserDefaults standardUserDefaults] dictionaryRepresentation]]];

	
	NSString *str3 = [NSString stringWithFormat:@"%@%@",
									SPImportClipboardTempFileNamePrefix,
									[instant stringWithFormat:@"HHmmss"
																	locale:[NSLocale autoupdatingCurrentLocale]
														   timeZone:[NSTimeZone localTimeZone]]];
	
	
	XCTAssertEqualObjects(str1, str3);

	str1 = [instant descriptionWithCalendarFormat:@"%Y-%m-%d" timeZone:nil locale:nil];
	str3 = [instant stringWithFormat:@"yyyy-MM-dd" locale:[NSLocale autoupdatingCurrentLocale] timeZone:[NSTimeZone localTimeZone]];

	XCTAssertEqualObjects(str1, str3);

	str1 = [instant descriptionWithCalendarFormat:@"%Y" timeZone:nil locale:nil];
	str3 = [instant stringWithFormat:@"yyyy" locale:[NSLocale autoupdatingCurrentLocale] timeZone:[NSTimeZone localTimeZone]];

	XCTAssertEqualObjects(str1, str3);

	str1 = [instant descriptionWithCalendarFormat:@"%m" timeZone:nil locale:nil];
	str3 = [instant stringWithFormat:@"MM" locale:[NSLocale autoupdatingCurrentLocale] timeZone:[NSTimeZone localTimeZone]];

	XCTAssertEqualObjects(str1, str3);

	str1 = [instant descriptionWithCalendarFormat:@"%d" timeZone:nil locale:nil];
	str3 = [instant stringWithFormat:@"dd" locale:[NSLocale autoupdatingCurrentLocale] timeZone:[NSTimeZone localTimeZone]];

	XCTAssertEqualObjects(str1, str3);

	str1 = [instant descriptionWithCalendarFormat:@"%H:%M:%S" timeZone:nil locale:nil];
	str3 = [instant stringWithFormat:@"HH:mm:ss" locale:[NSLocale autoupdatingCurrentLocale] timeZone:[NSTimeZone localTimeZone]];

	XCTAssertEqualObjects(str1, str3);

}
#pragma clang diagnostic pop

@end
