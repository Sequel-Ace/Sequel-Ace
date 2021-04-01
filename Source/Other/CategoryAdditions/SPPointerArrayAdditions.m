//
//  SPPointerArrayAdditions.m
//  Sequel Ace
//
//  Created by James on 1/1/2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SPPointerArrayAdditions.h"

@implementation NSPointerArray (SPPointerArrayAdditions)

// O(1); NULL item is okay; index must be < count
- (void)safeReplacePointerAtIndex:(NSUInteger)index withPointer:(nullable void *)item{

    if(index < self.count){
        [self replacePointerAtIndex:index withPointer:item];
    }
}

@end
