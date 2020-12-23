//
//  SPTestingUtils.m
//  Unit Tests
//
//  Created by James on 23/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "SPTestingUtils.h"

@implementation SPTestingUtils

+ (NSMutableArray *)randomHistArray {

    NSMutableArray *randomHistArray = [NSMutableArray array];

    for (int i = 0; i < 10000; i++) {
        NSString *ran = [[NSProcessInfo processInfo] globallyUniqueString];
        [randomHistArray addObject:[NSString stringWithFormat:@"%@%@'",@"select * from '", ran]];
    }

    return randomHistArray;
}

+ (NSMutableArray *)randomSSHKeyArray {

    NSMutableArray *randomSSHKeyArray = [NSMutableArray array];

    for (int i = 0; i < 10000; i++) {
        NSString *ran = [[NSProcessInfo processInfo] globallyUniqueString];
        [randomSSHKeyArray addObject:[NSString stringWithFormat:@"%@%@':",@"      Enter passphrase for key '", ran]];
    }

    return randomSSHKeyArray;
}


@end
