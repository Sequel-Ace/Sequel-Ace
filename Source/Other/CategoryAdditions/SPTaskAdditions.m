//
//  SPTaskAdditions.m
//  Sequel Ace
//
//  Created by James on 28/2/2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

#import "SPTaskAdditions.h"
#import "SPAppController.h"
#import "SPFunctions.h"

@implementation NSTask (SPTaskAdditions)

- (void)SPlaunch{

    [self launch];

    SPMainLoopAsync(^{
        [SPAppDelegate.sshProcessIDs addObject:@(self.processIdentifier)];
        SPLog(@"sshProcessIDs count: %lu", (unsigned long)SPAppDelegate.sshProcessIDs.count);
    });
}

- (void)SPterminate{

    int processID = self.processIdentifier;

    [self terminate];

    NSTask *killTask = [[NSTask alloc] init];
    [killTask setLaunchPath:@"/bin/sh"];
    SPMainQSync(^{
        [killTask setArguments:@[@"-c",[NSString stringWithFormat:@"kill -9 %@", [NSString stringWithFormat:@"%i", processID]]]];
        [killTask launch];
        [killTask waitUntilExit];

        [SPAppDelegate.sshProcessIDs removeObject:@(processID)];
        SPLog(@"sshProcessIDs count: %lu", (unsigned long)SPAppDelegate.sshProcessIDs.count);
    });
}

@end
