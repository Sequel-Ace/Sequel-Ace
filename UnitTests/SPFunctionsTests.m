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

- (void)testIsLikelyLocalNetworkHost
{
    XCTAssertTrue(SPIsLikelyLocalNetworkHost(@"10.0.0.8"));
    XCTAssertTrue(SPIsLikelyLocalNetworkHost(@"172.16.2.10"));
    XCTAssertTrue(SPIsLikelyLocalNetworkHost(@"192.168.88.88"));
    XCTAssertTrue(SPIsLikelyLocalNetworkHost(@"169.254.2.1"));
    XCTAssertTrue(SPIsLikelyLocalNetworkHost(@"devbox.local"));
    XCTAssertTrue(SPIsLikelyLocalNetworkHost(@"internal-dev-host"));
    XCTAssertTrue(SPIsLikelyLocalNetworkHost(@"fc00::1"));
    XCTAssertTrue(SPIsLikelyLocalNetworkHost(@"fe80::1"));

    XCTAssertFalse(SPIsLikelyLocalNetworkHost(@"localhost"));
    XCTAssertFalse(SPIsLikelyLocalNetworkHost(@"127.0.0.1"));
    XCTAssertFalse(SPIsLikelyLocalNetworkHost(@"::1"));
    XCTAssertFalse(SPIsLikelyLocalNetworkHost(@"8.8.8.8"));
    XCTAssertFalse(SPIsLikelyLocalNetworkHost(@"100.64.2.1"));
    XCTAssertFalse(SPIsLikelyLocalNetworkHost(@"example.com"));
}

- (void)testSSHNoRouteToHostLikelyLocalNetworkPrivacyIssue
{
    NSString *privateIPDebugLog = @"debug1: Connecting to dev.ifg.io [192.168.88.88] port 22.\n"
                                  @"debug1: connect to address 192.168.88.88 port 22: No route to host\n"
                                  @"ssh: connect to host dev.ifg.io port 22: No route to host";
    XCTAssertTrue(SPSSHNoRouteToHostLikelyLocalNetworkPrivacyIssue(@"The SSH Tunnel has unexpectedly closed.", privateIPDebugLog, @"dev.ifg.io"));

    NSString *publicIPDebugLog = @"debug1: Connecting to example.com [8.8.8.8] port 22.\n"
                                 @"debug1: connect to address 8.8.8.8 port 22: No route to host\n"
                                 @"ssh: connect to host example.com port 22: No route to host";
    XCTAssertFalse(SPSSHNoRouteToHostLikelyLocalNetworkPrivacyIssue(@"The SSH Tunnel has unexpectedly closed.", publicIPDebugLog, @"example.com"));

    NSString *aliasedPublicIPDebugLog = @"debug1: Connecting to prod-db [8.8.8.8] port 22.\n"
                                        @"debug1: connect to address 8.8.8.8 port 22: No route to host\n"
                                        @"ssh: connect to host prod-db port 22: No route to host";
    XCTAssertFalse(SPSSHNoRouteToHostLikelyLocalNetworkPrivacyIssue(@"The SSH Tunnel has unexpectedly closed.", aliasedPublicIPDebugLog, @"prod-db"));

    XCTAssertTrue(SPSSHNoRouteToHostLikelyLocalNetworkPrivacyIssue(@"No route to host", nil, @"db.local"));
    XCTAssertFalse(SPSSHNoRouteToHostLikelyLocalNetworkPrivacyIssue(@"Connection timed out", @"Operation timed out", @"192.168.1.5"));
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
