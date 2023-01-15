//
//  SPMySQLMutableDictionaryAdditions.h
//  Sequel Ace
//
//  Created by James on 21/1/2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSMutableDictionary (SPMySQLMutableDictionaryAdditions)

- (void)SPsafeSetObject:(id)obj forKey:(id)key;
- (void)SPsafeRemoveObjectForKey:(nullable id)key;

@end

@interface NSDictionary (SPMySQLDictionaryAdditions)

/*If obj or key are nil, does nothing. No exception thrown.*/
- (id)SPsafeObjectForKey:(id)key;

@end

NS_ASSUME_NONNULL_END
