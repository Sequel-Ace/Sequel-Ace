//
//  SPPostgreSQLStreamingResultWrapper.h
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

@class SPPostgreSQLConnectionWrapper;

// Forward declaration of Rust FFI type
typedef struct SPPostgreSQLStreamingResult SPPostgreSQLStreamingResult;

/**
 * SPPostgreSQLStreamingResultWrapper
 * 
 * Wrapper class that implements SPDatabaseResult protocol for streaming results.
 * Provides memory-efficient iteration over large PostgreSQL result sets by
 * processing data in batches instead of loading everything into memory at once.
 */
@interface SPPostgreSQLStreamingResultWrapper : NSObject <SPDatabaseResult>

/**
 * Initialize with a query to execute asynchronously
 * @param query The SQL query to execute
 * @param connection The connection wrapper to execute the query on
 * @param batchSize The batch size for fetching (for compatibility, currently unused)
 * @return Wrapper instance
 */
- (instancetype)initWithQuery:(NSString *)query
                   connection:(SPPostgreSQLConnectionWrapper *)connection
                    batchSize:(NSUInteger)batchSize;

/**
 * Indicates whether all data has been downloaded/loaded
 * For streaming results, this becomes YES once all batches are processed
 */
@property (nonatomic, readonly) BOOL dataDownloaded;

@end

