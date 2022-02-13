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

    SPMainQSync(^{
        [SPAppDelegate.sshProcessIDs removeObject:@(self.processIdentifier)];
        SPLog(@"sshProcessIDs count: %lu", (unsigned long)SPAppDelegate.sshProcessIDs.count);
    });
    
    [self terminate];
}

@end
