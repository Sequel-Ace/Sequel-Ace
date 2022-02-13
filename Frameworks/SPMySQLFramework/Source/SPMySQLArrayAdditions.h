//
//  SPMySQLArrayAdditions.h
//  Sequel Ace
//
//  Created by James on 21/1/2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//


@interface NSArray (SPMySQLArrayAdditions)

/**
 * Variant of objectAtIndex: that avoids the "index out of bounds" exception by
 * just returning nil instead.
 *
 * @warning This method is NOT thread-safe.
 * @param idx  An index
 * @return The object located at index or nil.
 */
- (nullable id)SPsafeObjectAtIndex:(NSUInteger)idx;
@end

@interface NSMutableArray (SPMutableArrayAdditions)

- (void)SPsafeAddObject:(nullable id)obj;

@end
