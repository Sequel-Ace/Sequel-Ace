//
//  ReportExceptionApplication.m
//  Sequel Ace
//
//  Created by James on 28/2/2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

#import "SPFunctions.h"
#import "SPAppController.h"
@import Cocoa;
@import AppCenterCrashes;


// see: https://docs.microsoft.com/en-us/appcenter/sdk/crashes/macos#enable-catching-uncaught-exceptions-thrown-on-the-main-thread
@interface ReportExceptionApplication : NSApplication
@end

@implementation ReportExceptionApplication

- (void)reportException:(NSException *)exception {

    // kill any ssh pids we started
    NSTask *killTask = [[NSTask alloc] init];
    [killTask setLaunchPath:@"/bin/sh"];
    [killTask setArguments:@[@"-c",[NSString stringWithFormat:@"kill -15 %@", [NSString stringWithString:[SPAppDelegate.sshProcessIDs componentsJoinedByString:@" "]]]]];
    [killTask launch];
    [killTask waitUntilExit];
    [killTask setArguments:@[@"-c",[NSString stringWithFormat:@"kill -9 %@", [NSString stringWithString:[SPAppDelegate.sshProcessIDs componentsJoinedByString:@" "]]]]];
    [killTask launch];
    [killTask waitUntilExit];

    // forward exception to MSACCrashes
    [MSACCrashes applicationDidReportException:exception];
    [super reportException:exception];
}

- (void)sendEvent:(NSEvent *)theEvent {
    @try {
        [super sendEvent:theEvent];
    } @catch (NSException *exception) {
        [self reportException:exception];
    }
}

@end
