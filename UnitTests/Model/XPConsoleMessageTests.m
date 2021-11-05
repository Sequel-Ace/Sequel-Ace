//
//  XPConsoleMessageTests.m
//  Unit Tests
//
//  Created by Christopher Jensen-Reimann on 11/4/21.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "SPConsoleMessage.h"

@interface XPConsoleMessageTests : XCTestCase

@end

@implementation XPConsoleMessageTests

- (void)testExample {
    SPConsoleMessage *message = [SPConsoleMessage consoleMessageWithMessage:@"Hello" date:[NSDate now] connection:@"foo" database:@"bar"];
    XCTAssertNotNil(message);
}

@end
