//
//  SPThreadAdditions.h
//  sequel-pro
//
//  Created by Rowan Beentje on October 14th, 2012.
//  Copyright (c) 2012 Rowan Beentje. All rights reserved.
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

@interface NSThread (SPThreadAdditions)

// Provide a utility class method, providing functionality similar to
// +detachNewThreadSelector:toTarget:withObject: but allowing easy naming
+ (void)detachNewThreadWithName:(NSString *)aName target:(id)aTarget selector:(SEL)aSelector object:(id)anArgument;

@end

@protocol SPCountedObject <NSObject>
/**
 * @return An arbitrary number that is constant for this object (ie. it never changes after init)
 *         and unique for the class during the whole runtime of the application
 *
 * This is used with the SPCtxt() function to distinguish threaded operations.
 * While it would have been simpler to just use the object's memory address as
 * ID that is not unique enough (e.g. another object can malloc the same memory
 * freed by an earlier object)
 */
- (int64_t)instanceId;
@end

/** 
 * The string returned by this function should be passed to aName
 * above in order to distinguish multiple threads (operating on different data
 * sets) in the debugger / crash reports.
 * (e.g. two connection tabs doing the "same" stuff).
 * object should be a distinguishing object (ie. the SPDatabaseDocument *)
 */
NSString * SPCtxt(NSString *description,NSObject<SPCountedObject> *object);
