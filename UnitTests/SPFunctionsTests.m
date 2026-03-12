//
//  SPFunctionsTests.m
//  Unit Tests
//
//  Created by James on 14/1/2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

#import "SPFunctions.h"
#import "SPTestingUtils.h"

#import <SPMySQL/SPMySQL.h>

#import <XCTest/XCTest.h>

@interface SPMySQLConnection (TestingPrivateAPI)
+ (NSArray<NSString *> *)defaultSSLCipherList;
+ (NSArray<NSString *> *)legacySSLCipherList;
+ (NSString *)_defaultTLSSuiteListString;
+ (NSArray<NSString *> *)_mergedSSLCipherPreferenceListFromSavedCipherString:(NSString *)savedCipherString disabledMarker:(NSString *)disabledMarker;
+ (NSString *)_reachabilityProbeHostForHost:(NSString *)host useSocket:(BOOL)useSocket hasProxy:(BOOL)hasProxy;
@end

@interface NSString (TestingColumnHeader)
+ (NSString *)tableContentColumnHeaderStringForColumnName:(NSString *)columnName columnType:(NSString *)columnType columnTypesVisible:(BOOL)columnTypesVisible;
@end

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
    XCTAssertTrue(SPIsLikelyLocalNetworkHost(@" [192.168.1.7] "));
    XCTAssertTrue(SPIsLikelyLocalNetworkHost(@"[fe80::2]"));
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
    XCTAssertFalse(SPIsLikelyLocalNetworkHost(@""));
    XCTAssertFalse(SPIsLikelyLocalNetworkHost(nil));
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

    NSString *ipv6LinkLocalDebugLog = @"debug1: Connecting to test-host [fe80::1234] port 22.\n"
                                      @"ssh: connect to host test-host port 22: No route to host";
    XCTAssertTrue(SPSSHNoRouteToHostLikelyLocalNetworkPrivacyIssue(nil, ipv6LinkLocalDebugLog, @"test-host"));

    NSString *noCandidateDebugLog = @"ssh: connect to host remote.example.com port 22: No route to host";
    XCTAssertFalse(SPSSHNoRouteToHostLikelyLocalNetworkPrivacyIssue(nil, noCandidateDebugLog, @"remote.example.com"));

    XCTAssertTrue(SPSSHNoRouteToHostLikelyLocalNetworkPrivacyIssue(@"No route to host", nil, @"db.local"));
    XCTAssertFalse(SPSSHNoRouteToHostLikelyLocalNetworkPrivacyIssue(@"Connection timed out", @"Operation timed out", @"192.168.1.5"));
}

- (void)testQueryColumnHeaderIncludesTypeWhenEnabled
{
    NSString *expectedHeader = @"hire_time TIMESTAMP";
    NSString *header = [NSString tableContentColumnHeaderStringForColumnName:@"hire_time" columnType:@"TIMESTAMP" columnTypesVisible:YES];
    
    XCTAssertEqualObjects(header, expectedHeader);
}

- (void)testQueryColumnHeaderOmitsTypeWhenDisabled
{
    NSString *header = [NSString tableContentColumnHeaderStringForColumnName:@"hire_time" columnType:@"TIMESTAMP" columnTypesVisible:NO];
    
    XCTAssertEqualObjects(header, @"hire_time");
}

- (void)testQueryColumnHeaderFallsBackToNameWhenTypeIsMissing
{
    NSString *header = [NSString tableContentColumnHeaderStringForColumnName:@"hire_time" columnType:nil columnTypesVisible:YES];
    
    XCTAssertEqualObjects(header, @"hire_time");
}

- (void)testDefaultSSLCipherListsIncludeModernAndLegacySuites
{
    NSArray<NSString *> *defaultCiphers = [SPMySQLConnection defaultSSLCipherList];
    NSArray<NSString *> *legacyCiphers = [SPMySQLConnection legacySSLCipherList];

    XCTAssertTrue([defaultCiphers containsObject:@"ECDHE-RSA-CHACHA20-POLY1305"]);
    XCTAssertTrue([defaultCiphers containsObject:@"ECDHE-ECDSA-AES256-GCM-SHA384"]);
    XCTAssertTrue([defaultCiphers containsObject:@"AES256-GCM-SHA384"]);
    XCTAssertFalse([defaultCiphers containsObject:@"RC4-MD5"]);

    XCTAssertTrue([legacyCiphers containsObject:@"RC4-MD5"]);
    XCTAssertTrue([legacyCiphers containsObject:@"CAMELLIA128-SHA"]);

    NSArray<NSString *> *defaultTLSSuites = [[SPMySQLConnection _defaultTLSSuiteListString] componentsSeparatedByString:@":"];
    XCTAssertEqualObjects(defaultTLSSuites, (@[
        @"TLS_AES_256_GCM_SHA384",
        @"TLS_CHACHA20_POLY1305_SHA256",
        @"TLS_AES_128_GCM_SHA256",
    ]));
}

- (void)testReachabilityProbeHostSelectionIsPureStringLogic
{
    // This helper only normalizes and filters candidate hosts for a later reachability check.
    // It must not depend on DNS, network access, or any machine-specific local setup.
    XCTAssertNil([SPMySQLConnection _reachabilityProbeHostForHost:@"db.lan" useSocket:YES hasProxy:NO]);
    XCTAssertNil([SPMySQLConnection _reachabilityProbeHostForHost:@"db.lan" useSocket:NO hasProxy:YES]);
    XCTAssertNil([SPMySQLConnection _reachabilityProbeHostForHost:@" localhost " useSocket:NO hasProxy:NO]);
    XCTAssertNil([SPMySQLConnection _reachabilityProbeHostForHost:@"127.0.0.1" useSocket:NO hasProxy:NO]);
    XCTAssertNil([SPMySQLConnection _reachabilityProbeHostForHost:@"127.0.0.2" useSocket:NO hasProxy:NO]);
    XCTAssertNil([SPMySQLConnection _reachabilityProbeHostForHost:@"[::1]" useSocket:NO hasProxy:NO]);
    XCTAssertEqualObjects([SPMySQLConnection _reachabilityProbeHostForHost:@" db.example.test " useSocket:NO hasProxy:NO], @"db.example.test");
    XCTAssertEqualObjects([SPMySQLConnection _reachabilityProbeHostForHost:@"[2001:db8::5]" useSocket:NO hasProxy:NO], @"2001:db8::5");
}

- (void)testMergedCipherPreferencesKeepMissingLegacySuitesBelowDisabledMarker
{
    NSString *savedCipherString = [@[
        @"CAMELLIA128-SHA",
        @"ECDHE-RSA-AES256-GCM-SHA384",
        @"--",
        @"AES256-SHA",
    ] componentsJoinedByString:@":"];

    NSArray<NSString *> *mergedCiphers = [SPMySQLConnection _mergedSSLCipherPreferenceListFromSavedCipherString:savedCipherString disabledMarker:@"--"];
    NSUInteger markerIndex = [mergedCiphers indexOfObject:@"--"];
    NSUInteger userEnabledLegacyIndex = [mergedCiphers indexOfObject:@"CAMELLIA128-SHA"];
    NSUInteger userDisabledModernIndex = [mergedCiphers indexOfObject:@"AES256-SHA"];
    NSUInteger missingLegacyIndex = [mergedCiphers indexOfObject:@"RC4-MD5"];

    XCTAssertNotEqual(markerIndex, NSNotFound);
    XCTAssertLessThan(userEnabledLegacyIndex, markerIndex);
    XCTAssertGreaterThan(userDisabledModernIndex, markerIndex);
    XCTAssertGreaterThan(missingLegacyIndex, markerIndex);
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
