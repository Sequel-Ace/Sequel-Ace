//
//  SPPostgresFastStreamingResult.h
//  SPPostgresFramework
//
//  Created by Mehmet Karabulut (mehmetik@gmail.com) on November 30, 2025.
//  Copyright (c) 2025 Mehmet Karabulut.
//  This software is released under the GPL License.
//  This is an open-source project forked from Sequel Ace.
//

#import "SPPostgresStreamingResult.h"

/**
 * SPPostgresFastStreamingResult provides optimized streaming for large result sets.
 * It extends SPPostgresStreamingResult with performance optimizations for
 * data export and large query operations.
 */
@interface SPPostgresFastStreamingResult : SPPostgresStreamingResult

/**
 * Initialize with a PostgreSQL result and connection
 */
- (instancetype)initWithResult:(PGresult *)result connection:(void *)connection;

/**
 * Enable/disable row-by-row fetching for memory efficiency
 */
- (void)setStreamingEnabled:(BOOL)enabled;

/**
 * Set the fetch size for streaming (number of rows per fetch)
 */
- (void)setStreamingFetchSize:(NSUInteger)fetchSize;

@end
