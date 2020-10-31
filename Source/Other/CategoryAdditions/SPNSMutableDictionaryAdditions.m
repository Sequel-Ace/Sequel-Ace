//
//  SPNSMutableDictionaryAdditions.m
//  Sequel Ace
//
//  Created by James on 31/10/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

#import "SPNSMutableDictionaryAdditions.h"

@implementation NSMutableDictionary (SPNSMutableDictionaryAdditions)


- (void)safeSetObject:(id)obj forKey:(id)key {
	if (obj != nil & key != nil) {
		[self setObject:obj forKey:key];
	}
}

- (id)safeObjectForKey:(id)key {
	id object = [self objectForKey:key];
	if (object == [NSNull null]) {
		return nil;
	}
	return object;
}

- (void)safeRemoveObjectForKey:(nullable id)key{
	id object = [self objectForKey:key];
	if (object != [NSNull null]) {
		[self removeObjectForKey:key];
	}
}


@end
