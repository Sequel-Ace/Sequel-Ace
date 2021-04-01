//
//  SPMutableArrayAdditions.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on February 2, 2011.
//  Copyright (c) 2011 Stuart Connolly. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  More info at <https://github.com/sequelpro/sequelpro>

#import "SPMutableArrayAdditions.h"
#import "SPArrayAdditions.h"

@implementation NSMutableArray (SPMutableArrayAdditions)

- (instancetype _Nullable )unique{

    return [self valueForKeyPath:@"@distinctUnionOfObjects.self"];
}

- (void)reverse
{
	NSUInteger count = [self count];
	
	for (NSUInteger i = 0; i < (count / 2); i++) 
	{
		NSUInteger j = ((count - i) - 1);
		
		id obj = [self safeObjectAtIndex:i];
		
		[self replaceObjectAtIndex:i withObject:[self safeObjectAtIndex:j]];
		[self replaceObjectAtIndex:j withObject:obj];
	}
}

- (id)safeObjectAtIndex:(NSUInteger)idx{
	return idx < self.count ? [self objectAtIndex:idx] : nil;
}

- (void)safeAddObject:(id)obj{
	if (obj != nil) {
		[self addObject:obj];
	}
}

- (void)addObjectIfNotContains:(id)obj{
    if (obj != nil && [self containsObject:obj] == NO) {
        [self addObject:obj];
    }
}

- (void)safeReplaceObjectAtIndex:(NSUInteger)index withObject:(nullable id)anObject{
    if (anObject != nil && index < self.count) {
        [self replaceObjectAtIndex:index withObject:anObject];
    }
}

- (void)safeRemoveObjectAtIndex:(NSUInteger)index{
    id object = [self safeObjectAtIndex:index];
    if (object != nil && object != [NSNull null]) {
        [self removeObjectAtIndex:index];
    }
}

- (void)safeSetArray:(NSArray*)arr{
    if (arr != nil) {
        [self setArray:arr];
    }
}

@end
