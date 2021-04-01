//
//  SPNSMutableDictionaryAdditions.h
//  Sequel Ace
//
//  Created by James on 31/10/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSMutableDictionary (SPNSMutableDictionaryAdditions)


- (nullable id)safeObjectForKey:(id)key;
- (void)safeSetObject:(id)obj forKey:(id)key;
- (void)safeRemoveObjectForKey:(nullable id)key;

@end

@interface NSDictionary (SPNSDictionaryAdditions)

/*If obj or key are nil, does nothing. No exception thrown.*/
- (nullable id)safeObjectForKey:(id)key;

@end

NS_ASSUME_NONNULL_END
