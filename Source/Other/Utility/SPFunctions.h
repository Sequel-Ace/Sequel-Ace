//
//  SPFunctions.h
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

typedef void(^SAVoidCompletionBlock)(void);

void executeOnMainThreadAfterADelay(SAVoidCompletionBlock block, double delayInSeconds);

/**
 * Synchronously execute a block on the main thread.
 * This function can be called from a background thread as well as from
 * the main thread.
 */
void SPMainQSync(SAVoidCompletionBlock block);

/**
 * Asynchronously execute a block on the main run loop.
 * This function is equivalent to calling -[[NSRunLoop mainRunLoop] performBlock:] on 10.12+
 */
void SPMainLoopAsync(SAVoidCompletionBlock block);

/**
 * Helper to ensure code runs on main thread
 * @param predicate A predicate for use with dispatch_once - use a static var
 * @param block a block to execute
 */
void dispatch_once_on_main_thread(dispatch_once_t *predicate,
								  dispatch_block_t block);
/**
 * Copies count bytes into buf provided by caller
 * @param buf Base address to copy to
 * @param count Number of bytes to copy
 * @return 0 on success or -1 if something went wrong, check errno
 */
int SPBetterRandomBytes(uint8_t *buf, size_t count);

/**
 * Convert a signed integer into an unsigned integer or throw an exception if the values don't fit.
 * @param i a signed integer
 * @return the same value, casted to unsigned integer
 */
NSUInteger SPIntS2U(NSInteger i);

/**
 * Converts nil to NSNull for passing into arrays
 * @return The object that was passed in or [NSNull null] if object == nil
 * @see -[SPObjectAdditions unboxNull]
 */
id SPBoxNil(id object);
NSInteger intSortDesc(id num1, id num2, void *context);

void executeOnBackgroundThread(SAVoidCompletionBlock block);
void executeOnBackgroundThreadSync(SAVoidCompletionBlock block);

void SP_swizzleInstanceMethod(Class c, SEL original, SEL replacement);

id DumpObjCMethods(Class clz);

/*
 http://blog.wilshipley.com/2005/10/pimp-my-code-interlude-free-code.html
 Essentially, if you're wondering if an NSString or NSData or NSAttributedString
 or NSArray or NSSet has actual useful data in it, this is your macro.
 Instead of checking things like "if (inputString == nil || [inputString length] == 0)"
 you just say, "if (IsEmpty(inputString))".
 */
static inline __attribute__((always_inline)) BOOL IsEmpty(id thing) {
    return thing == nil ||
            ([thing respondsToSelector:@selector(length)] && [(NSData *)thing length] == 0) ||
            ([thing respondsToSelector:@selector(count)]  && [(NSArray *)thing count] == 0);
}
