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
        // First check if the process exists before trying to kill it
        NSTask *checkTask = [[NSTask alloc] init];
        [checkTask setLaunchPath:@"/bin/sh"];
        [checkTask setArguments:@[@"-c", [NSString stringWithFormat:@"ps -p %i >/dev/null 2>&1 && echo \"exists\" || echo \"not exists\"", processID]]];
        
        NSPipe *pipe = [NSPipe pipe];
        [checkTask setStandardOutput:pipe];
        [checkTask launch];
        [checkTask waitUntilExit];
        
        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        
        // Only attempt to kill if the process actually exists
        if ([output containsString:@"exists"]) {
            [killTask setArguments:@[@"-c",[NSString stringWithFormat:@"kill -9 %@", [NSString stringWithFormat:@"%i", processID]]]];
            [killTask launch];
            [killTask waitUntilExit];
        }
        
        [SPAppDelegate.sshProcessIDs removeObject:@(processID)];
        SPLog(@"sshProcessIDs count: %lu", (unsigned long)SPAppDelegate.sshProcessIDs.count);
    });
}

@end
