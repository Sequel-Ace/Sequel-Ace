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

// Forward declaration of Rust FFI types (typedef in sppostgresql_ffi.h)
typedef struct SPPostgreSQLResult SPPostgreSQLResult;
typedef struct SPPostgreSQLStreamingResult SPPostgreSQLStreamingResult;

/**
 * SPPostgreSQLStreamingResultWrapper
 * 
 * Wrapper class that implements SPDatabaseResult protocol for streaming results.
 * Provides memory-efficient iteration over large PostgreSQL result sets by
 * processing data in batches instead of loading everything into memory at once.
 * 
 * Matches MySQL's pattern: receives a pre-executed result handle with metadata
 * available immediately, data fetching is deferred until startDownload is called.
 */
@interface SPPostgreSQLStreamingResultWrapper : NSObject <SPDatabaseResult>

/**
 * Initialize with a pre-executed PostgreSQL streaming result (uses TRUE cursor-based streaming)
 * @param pgStreamingResult Pre-executed streaming result handle from sp_postgresql_connection_execute_streaming_query
 * @param connection The connection wrapper
 * @param batchSize The batch size for fetching
 * @return Wrapper instance
 */
- (instancetype)initWithStreamingResult:(SPPostgreSQLStreamingResult *)pgStreamingResult
                             connection:(SPPostgreSQLConnectionWrapper *)connection
                              batchSize:(NSUInteger)batchSize;

/**
 * Indicates whether all data has been downloaded/loaded
 * For streaming results, this becomes YES once all batches are processed
 */
@property (nonatomic, readonly) BOOL dataDownloaded;

/**
 * Mark the underlying client as disconnected (prevents cursor cleanup on invalid client)
 * Called by connection wrapper before disconnecting
 */
- (void)markClientDisconnected;

/**
 * Replace existing result store data (for smoother table reloads)
 * Called by SPDataStorage when reloading table data
 */
- (void)replaceExistingResultStore:(id)previousResultStore;

@end

