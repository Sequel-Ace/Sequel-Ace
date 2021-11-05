//
//  SPBundleRunnerTests.m
//  Unit Tests
//
//  Created by Christopher Jensen-Reimann on 11/4/21.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "SABundleRunner.h"

@interface SPBundleRunnerTests : XCTestCase

@end

@implementation SPBundleRunnerTests

- (void)testNilError {
    NSError *err;
    XCTAssertEqualObjects([SABundleRunner computeActionFor:&err], @"");
    NSLog(@"I ran the test!");
    XCTAssertNil(err);
}

- (void)testUnknownError {
    NSError *err = [NSError errorWithDomain:@"" code:666 userInfo:nil];
    XCTAssertEqualObjects([SABundleRunner computeActionFor:&err], @"");
    XCTAssertNotNil(err);
}

- (void) testRedirectActionNone {
    NSError *err = [NSError errorWithDomain: @"" code: SPBundleRedirectActionNone userInfo: nil];
    XCTAssertEqualObjects([SABundleRunner computeActionFor:&err], SPBundleOutputActionNone);
    XCTAssertNil(err);
}

- (void) testRedirectActionReplaceSection {
    NSError *err = [NSError errorWithDomain: @"" code: SPBundleRedirectActionReplaceSection userInfo: nil];
    XCTAssertEqualObjects([SABundleRunner computeActionFor:&err], SPBundleOutputActionReplaceSelection);
    XCTAssertNil(err);
}

- (void) testRedirectActionReplaceContent {
    NSError *err = [NSError errorWithDomain: @"" code: SPBundleRedirectActionReplaceContent userInfo: nil];
    XCTAssertEqualObjects([SABundleRunner computeActionFor:&err], SPBundleOutputActionReplaceContent);
    XCTAssertNil(err);
}

- (void) testRedirectActionInsertAsText {
    NSError *err = [NSError errorWithDomain: @"" code: SPBundleRedirectActionInsertAsText userInfo: nil];
    XCTAssertEqualObjects([SABundleRunner computeActionFor:&err], SPBundleOutputActionInsertAsText);
    XCTAssertNil(err);
}

- (void) testRedirectActionInsertAsSnippet {
    NSError *err = [NSError errorWithDomain: @"" code: SPBundleRedirectActionInsertAsSnippet userInfo: nil];
    XCTAssertEqualObjects([SABundleRunner computeActionFor:&err], SPBundleOutputActionInsertAsSnippet);
    XCTAssertNil(err);
}

- (void) testRedirectActionShowAsHTML {
    NSError *err = [NSError errorWithDomain: @"" code: SPBundleRedirectActionShowAsHTML userInfo: nil];
    XCTAssertEqualObjects([SABundleRunner computeActionFor:&err], SPBundleOutputActionShowAsHTML);
    XCTAssertNil(err);
}

- (void) testRedirectActionShowAsTextTooltip {
    NSError *err = [NSError errorWithDomain: @"" code: SPBundleRedirectActionShowAsTextTooltip userInfo: nil];
    XCTAssertEqualObjects([SABundleRunner computeActionFor:&err], SPBundleOutputActionShowAsTextTooltip);
    XCTAssertNil(err);
}

- (void) testRedirectActionShowAsHTMLTooltip {
    NSError *err = [NSError errorWithDomain: @"" code: SPBundleRedirectActionShowAsHTMLTooltip userInfo: nil];
    XCTAssertEqualObjects([SABundleRunner computeActionFor:&err], SPBundleOutputActionShowAsHTMLTooltip);
    XCTAssertNil(err);
}

@end
