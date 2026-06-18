//
//  SPTestingUtils.h
//  sequel-ace
//
//  Created by James on 23/12/2020.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

#ifndef SPTestingUtils_h
#define SPTestingUtils_h

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#ifndef SEQUEL_ACE_RUN_PERFORMANCE_TESTS
#define SEQUEL_ACE_RUN_PERFORMANCE_TESTS 0
#endif

static inline BOOL SARunPerformanceTests(void)
{
#if SEQUEL_ACE_RUN_PERFORMANCE_TESTS
	return YES;
#else
	NSString *value = [[[[NSProcessInfo processInfo] environment] objectForKey:@"SEQUEL_ACE_RUN_PERFORMANCE_TESTS"] lowercaseString];
	return [value isEqualToString:@"1"] || [value isEqualToString:@"true"] || [value isEqualToString:@"yes"];
#endif
}

#define SASkipUnlessPerformanceTestsEnabled() \
	do { \
		if (!SARunPerformanceTests()) { \
			XCTSkip(@"Set SEQUEL_ACE_RUN_PERFORMANCE_TESTS=1 to run performance measurement tests."); \
			return; \
		} \
	} while (0)

@interface SPTestingUtils : NSObject

+ (NSMutableArray *)randomHistArray;
+ (NSMutableArray *)randomSSHKeyArray;
+ (NSPointerArray *)randomPointerArray;


@end

#endif /* SPTestingUtils_h */
