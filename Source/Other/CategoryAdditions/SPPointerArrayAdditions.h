//
//  SPPointerArrayAdditions.h
//  Sequel Ace
//
//  Created by James on 1/1/2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSPointerArray (SPPointerArrayAdditions)

- (void)safeReplacePointerAtIndex:(NSUInteger)index withPointer:(nullable void *)item;  // O(1); NULL item is okay; index must be < count

@end

NS_ASSUME_NONNULL_END
