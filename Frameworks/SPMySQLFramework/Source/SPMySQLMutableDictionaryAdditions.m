//
//  SPMySQLMutableDictionaryAdditions.m
//  Sequel Ace
//
//  Created by James on 21/1/2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

#import "SPMySQLMutableDictionaryAdditions.h"

@implementation NSMutableDictionary (SPMySQLMutableDictionaryAdditions)

#pragma mark -
#pragma mark NSMutableDictionary methods

- (void)SPsafeSetObject:(id)obj forKey:(id)key {
	if (obj != nil & key != nil) {
		[self setObject:obj forKey:key];
	}
}

- (void)SPsafeRemoveObjectForKey:(nullable id)key{
	id object = [self SPsafeObjectForKey:key];
	if (object != nil && object != [NSNull null]) {
		[self removeObjectForKey:key];
	}
}

@end

@implementation NSDictionary (SPMySQLDictionaryAdditions)

#pragma mark -
#pragma mark NSDictionary method

- (id)SPsafeObjectForKey:(id)key {
	id object = [self objectForKey:key];
	if (object != nil && object == [NSNull null]) {
		return nil;
	}
	return object;
}

@end
