//
//  SPMySQLResultWrapper.h
//  sequel-ace
//
//  Created by Sequel Ace on 2024.
//  Copyright (c) 2024 Sequel Ace. All rights reserved.
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

#import <Foundation/Foundation.h>
#import "SPDatabaseResult.h"

@class SPMySQLResult;

/**
 * SPMySQLResultWrapper
 * 
 * Wrapper class that implements SPDatabaseResult protocol
 * and forwards calls to the underlying SPMySQLResult instance.
 */
@interface SPMySQLResultWrapper : NSObject <SPDatabaseResult>

/**
 * Initialize with a MySQL result
 * @param result The SPMySQLResult to wrap
 * @return Wrapper instance
 */
- (instancetype)initWithMySQLResult:(SPMySQLResult *)result;

/**
 * Access the underlying MySQL result object
 * This is needed for code that directly works with MySQL-specific objects
 */
@property (readonly, strong) SPMySQLResult *underlyingMySQLResult;

@end

