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
@import AppCenterCrashes;


// see: https://docs.microsoft.com/en-us/appcenter/sdk/crashes/macos#enable-catching-uncaught-exceptions-thrown-on-the-main-thread
@interface ReportExceptionApplication : NSApplication
@end

@implementation ReportExceptionApplication

- (void)reportException:(NSException *)exception {
    // Log the exception to console for debugging - this is safe
    NSLog(@"========================================");
    NSLog(@"SEQUEL PACE EXCEPTION CAUGHT:");
    NSLog(@"Name: %@", [exception name]);
    NSLog(@"Reason: %@", [exception reason]);
    NSLog(@"Stack: %@", [exception callStackSymbols]);
    NSLog(@"========================================");

    // Kill SSH processes asynchronously to avoid blocking
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            NSTask *killTask = [[NSTask alloc] init];
            [killTask setLaunchPath:@"/bin/sh"];
            NSArray *sshIDs = [SPAppDelegate.sshProcessIDs copy];
            if (sshIDs && [sshIDs count] > 0) {
                [killTask setArguments:@[@"-c", [NSString stringWithFormat:@"kill -9 %@", [sshIDs componentsJoinedByString:@" "]]]];
                [killTask launch];
                [killTask waitUntilExit];
            }
        } @catch (NSException *e) {
            NSLog(@"Error killing SSH processes: %@", e);
        }
    });

    // Forward exception to MSACCrashes (optional analytics)
    @try {
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        if ([prefs boolForKey:SPSaveApplicationUsageAnalytics]) {
            [MSACCrashes applicationDidReportException:exception];
        }
    } @catch (NSException *e) {
        NSLog(@"MSACAppCenter Exception on Crash Report: %@", e);
    }

    // DEVELOPMENT MODE: Show alert instead of crashing
    // Use dispatch_async to avoid blocking or deadlocking
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setAlertStyle:NSAlertStyleCritical];
            [alert setMessageText:@"Exception Caught (Dev Mode)"];
            [alert setInformativeText:[NSString stringWithFormat:@"Name: %@\n\nReason: %@\n\nCheck Console.app for stack trace.", 
                [exception name], 
                [exception reason]]];
            [alert addButtonWithTitle:@"Continue"];
            [alert addButtonWithTitle:@"Quit"];
            
            NSModalResponse response = [alert runModal];
            if (response == NSAlertSecondButtonReturn) {
                [NSApp terminate:nil];
            }
        } @catch (NSException *alertException) {
            NSLog(@"Error showing exception alert: %@", alertException);
        }
    });
    
    // DO NOT call super - that would crash the app
    // [super reportException:exception];
}

- (void)sendEvent:(NSEvent *)theEvent {
    @try {
        [super sendEvent:theEvent];
    } @catch (NSException *exception) {
        [self reportException:exception];
    }
}

@end
