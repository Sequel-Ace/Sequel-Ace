//
//  SPReleaseTests.m
//  Unit Tests
//
//  Created by James on 27/10/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "SPConstants.h"


#define SASafeRelease(__v) ([__v release], __v = nil);
#define SASafeReleaseIF(__v) ((__v) == nil ?:[__v release], __v = nil);
#define SASafeRelease2(__v) do{ if(__v != nil) [__v release], __v = nil; } while(0)


@interface SPReleaseTests : XCTestCase

@end

@implementation SPReleaseTests

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testPerformance_IF_Release_nil {
	// this is on main thread
	[self measureBlock:^{
		// Put the code you want to measure the time of here.
		int const iterations = 1000000;
		
		for (int i = 0; i < iterations; i++) {
			
			NSString *queryErrorMessage = [@"this is a big, crazy test st'ring  with som'e random  spaces and quot'es" retain];
						
			if (queryErrorMessage) {
			   [queryErrorMessage release];
			   queryErrorMessage = nil;
			}
			
		}
	}];
}

- (void)testPerformance_IF_Release_nil_var_is_nil {
	// this is on main thread
	[self measureBlock:^{
		// Put the code you want to measure the time of here.
		int const iterations = 1000000;
		
		for (int i = 0; i < iterations; i++) {
			
			NSString *queryErrorMessage = [@"this is a big, crazy test st'ring  with som'e random  spaces and quot'es" retain];
			
			queryErrorMessage = nil;
			
			if (queryErrorMessage) {
			   [queryErrorMessage release];
			   queryErrorMessage = nil;
			}
			
		}
	}];
}

- (void)testPerformance_SPClear {
    // this is on main thread
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
        int const iterations = 1000000;
        
        for (int i = 0; i < iterations; i++) {
            
            NSString *queryErrorMessage = [@"this is a big, crazy test st'ring  with som'e random  spaces and quot'es" retain];
                       
            SPClear(queryErrorMessage);
            
        }
    }];
}

- (void)testPerformance_SPClear_var_is_nil {
    // this is on main thread
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
        int const iterations = 1000000;
        
        for (int i = 0; i < iterations; i++) {
            
            NSString *queryErrorMessage = [@"this is a big, crazy test st'ring  with som'e random  spaces and quot'es" retain];
                        
			queryErrorMessage = nil;

			SPClear(queryErrorMessage);

        }
    }];
}




- (void)testPerformance_NO_IF_Release_nil {
	// this is on main thread
	[self measureBlock:^{
		// Put the code you want to measure the time of here.
		int const iterations = 1000000;
		
		for (int i = 0; i < iterations; i++) {
			
			NSString *queryErrorMessage = [@"this is a big, crazy test st'ring  with som'e random  spaces and quot'es" retain];

		   [queryErrorMessage release];
		   queryErrorMessage = nil;
			
			
		}
	}];
}

- (void)testPerformance_NO_IF_Release_nil_var_is_nil {
	// this is on main thread
	[self measureBlock:^{
		// Put the code you want to measure the time of here.
		int const iterations = 1000000;
		
		for (int i = 0; i < iterations; i++) {
			
			NSString *queryErrorMessage = [@"this is a big, crazy test st'ring  with som'e random  spaces and quot'es" retain];

			queryErrorMessage = nil;

			[queryErrorMessage release];
			queryErrorMessage = nil;
			
			
		}
	}];
}

- (void)testPerformance_macro_no_if {
	// this is on main thread
	[self measureBlock:^{
		// Put the code you want to measure the time of here.
		int const iterations = 1000000;
		
		for (int i = 0; i < iterations; i++) {
			
			NSString *queryErrorMessage = [@"this is a big, crazy test st'ring  with som'e random  spaces and quot'es" retain];

			SASafeRelease(queryErrorMessage);
		}
	}];
}

- (void)testPerformance_macro_no_if_var_is_nil {
	// this is on main thread
	[self measureBlock:^{
		// Put the code you want to measure the time of here.
		int const iterations = 1000000;
		
		for (int i = 0; i < iterations; i++) {
			
			NSString *queryErrorMessage = [@"this is a big, crazy test st'ring  with som'e random  spaces and quot'es" retain];

			queryErrorMessage = nil;

			SASafeRelease(queryErrorMessage);
		}
	}];
}

- (void)testPerformance_macro_with_if {
	// this is on main thread
	[self measureBlock:^{
		// Put the code you want to measure the time of here.
		int const iterations = 1000000;
		
		for (int i = 0; i < iterations; i++) {
			
			NSString *queryErrorMessage = [@"this is a big, crazy test st'ring  with som'e random  spaces and quot'es" retain];

			SASafeReleaseIF(queryErrorMessage);
		}
	}];
}

- (void)testPerformance_macro_with_if_var_is_nil {
	// this is on main thread
	[self measureBlock:^{
		// Put the code you want to measure the time of here.
		int const iterations = 1000000;
		
		for (int i = 0; i < iterations; i++) {
			
			NSString *queryErrorMessage = [@"this is a big, crazy test st'ring  with som'e random  spaces and quot'es" retain];
			queryErrorMessage = nil;

			SASafeReleaseIF(queryErrorMessage);
		}
	}];
}

- (void)testPerformance_macro_with_do_if {
	// this is on main thread
	[self measureBlock:^{
		// Put the code you want to measure the time of here.
		int const iterations = 1000000;
		
		for (int i = 0; i < iterations; i++) {
			
			NSString *queryErrorMessage = [@"this is a big, crazy test st'ring  with som'e random  spaces and quot'es" retain];

			SASafeRelease2(queryErrorMessage);
		}
	}];
}

- (void)testPerformance_macro_with_do_if_var_is_nil {
	// this is on main thread
	[self measureBlock:^{
		// Put the code you want to measure the time of here.
		int const iterations = 1000000;
		
		for (int i = 0; i < iterations; i++) {
			
			NSString *queryErrorMessage = [@"this is a big, crazy test st'ring  with som'e random  spaces and quot'es" retain];
			queryErrorMessage = nil;

			SASafeRelease2(queryErrorMessage);
		}
	}];
}

@end
