//
//  SPMySQLArrayAdditions.m
//  Sequel Ace
//
//  Created by James on 21/1/2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

#import "SPMySQLArrayAdditions.h"

@implementation NSArray (SPMySQLArrayAdditions)

- (nullable id)SPsafeObjectAtIndex:(NSUInteger)idx
{
    return idx < self.count ? [self objectAtIndex:idx] : nil;
}

@end

@implementation NSMutableArray (SPMySQLMutableArrayAdditions)

- (void)SPsafeAddObject:(nullable id)obj{
    if (obj != nil) {
        [self addObject:obj];
    }
}

@end
