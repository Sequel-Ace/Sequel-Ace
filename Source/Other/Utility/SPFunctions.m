//
//  SPFunctions.m
//  sequel-pro
//
//  Created by Max Lohrmann on 01.10.15.
//  Copyright (c) 2015 Max Lohrmann. All rights reserved.
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

#import "SPFunctions.h"
#import <Security/SecRandom.h>
#import <objc/runtime.h>

void SPMainQSync(SAVoidCompletionBlock block)
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		dispatch_queue_set_specific(dispatch_get_main_queue(), &onceToken, &onceToken, NULL);
	});
	
	if (dispatch_get_specific(&onceToken) == &onceToken) {
		block();
	}
	else {
		dispatch_sync(dispatch_get_main_queue(), block);
	}
}

void executeOnMainThreadAfterADelay(SAVoidCompletionBlock block, double delayInSeconds){

    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (dispatch_time_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void) {
        if (block) {
            block();
        }
    });
}


void SPMainLoopAsync(SAVoidCompletionBlock block)
{
	CFRunLoopPerformBlock(CFRunLoopGetMain(), NSDefaultRunLoopMode, block);
}

void dispatch_once_on_main_thread(dispatch_once_t *predicate,
								  dispatch_block_t block) {
	
	if ([NSThread isMainThread]) {
		dispatch_once(predicate, block);
	}
	else {
		if (DISPATCH_EXPECT(*predicate == 0L, NO)) {
			dispatch_sync(dispatch_get_main_queue(), ^{
				dispatch_once(predicate, block);
			});
		}
	}
}

void executeOnBackgroundThreadSync(SAVoidCompletionBlock block)
{
	static dispatch_once_t onceToken5;
	   dispatch_once(&onceToken5, ^{
		   dispatch_queue_set_specific(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), &onceToken5, &onceToken5, NULL);
	   });
	
   if (dispatch_get_specific(&onceToken5) == &onceToken5) {
		block();
	}
	else {
		dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), block);
	}
}

void executeOnBackgroundThread(SAVoidCompletionBlock block)
{
	static dispatch_once_t onceToken3;
	dispatch_once(&onceToken3, ^{
		dispatch_queue_set_specific(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), &onceToken3, &onceToken3, NULL);
	});

	if (dispatch_get_specific(&onceToken3) == &onceToken3) {
		block();
	} else {
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), block);
	}
}

int SPBetterRandomBytes(uint8_t *buf, size_t count)
{
	return SecRandomCopyBytes(kSecRandomDefault, count, buf);
}

NSUInteger SPIntS2U(NSInteger i)
{
	if(i < 0) [NSException raise:NSRangeException format:@"NSInteger %ld does not fit in NSUInteger",i];
	
	return (NSUInteger)i;
}

id SPBoxNil(id object)
{
	if(object == nil) return [NSNull null];
	
	return object;
}

void SP_swizzleInstanceMethod(Class c, SEL original, SEL replacement)
{
	Method a = class_getInstanceMethod(c, original);
	Method b = class_getInstanceMethod(c, replacement);
	if (class_addMethod(c, original, method_getImplementation(b), method_getTypeEncoding(b)))
	{
		class_replaceMethod(c, replacement, method_getImplementation(a), method_getTypeEncoding(a));
	}
	else
	{
		method_exchangeImplementations(a, b);
	}
}

id DumpObjCMethods(Class clz) {
    
    unsigned int i=0;
    unsigned int mc = 0;
    Method * mlist = class_copyMethodList(object_getClass(clz), &mc);
    
    NSMutableArray *arr = [[NSMutableArray alloc] initWithCapacity:mc];
    
    SPLog(@"%d class methods", mc);
    for(i=0;i<mc;i++){
        SPLog(@"Class Method no #%d: %s", i, sel_getName(method_getName(mlist[i])));
        [arr addObject:[[NSString alloc] initWithCString:sel_getName(method_getName(mlist[i])) encoding:NSUTF8StringEncoding]];
    }
    
    free(mlist);
    
    return arr;
}

