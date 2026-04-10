//
//  ReportExceptionApplication.m
//  Sequel Ace
//
//  Created by James on 28/2/2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

#import "SPFunctions.h"
#import "SPAppController.h"
@import Cocoa;

@import FirebaseCrashlytics;

@interface ReportExceptionApplication : NSApplication
@end

@implementation ReportExceptionApplication

- (void)reportException:(NSException *)exception {

    // kill any ssh pids we started
    NSTask *killTask = [[NSTask alloc] init];
    [killTask setLaunchPath:@"/bin/sh"];

    SPMainQSync(^{
        [killTask setArguments:@[@"-c",[NSString stringWithFormat:@"kill -9 %@", [NSString stringWithString:[SPAppDelegate.sshProcessIDs componentsJoinedByString:@" "]]]]];
        [killTask launch];
        [killTask waitUntilExit];
    });

    // forward exception to Firebase Crashlytics
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    @try {
        if ([prefs boolForKey:SPSaveApplicationUsageAnalytics]) {
            FIRExceptionModel *model = [FIRExceptionModel exceptionModelWithName:exception.name reason:exception.reason];
            NSMutableArray<FIRStackFrame *> *frames = [NSMutableArray array];
            for (NSNumber *address in exception.callStackReturnAddresses) {
                [frames addObject:[FIRStackFrame stackFrameWithAddress:[address unsignedIntegerValue]]];
            }
            model.stackTrace = frames;
            [[FIRCrashlytics crashlytics] recordExceptionModel:model];
        }
    } @catch (NSException * e) {
        SPLog(@"Firebase Crashlytics Exception on Crash Report: %@", e);
    }

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
