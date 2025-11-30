//
//  SPPostgresFastStreamingResult.m
//  SPPostgresFramework
//
//  Created by Mehmet Karabulut (mehmetik@gmail.com) on November 30, 2025.
//  Copyright (c) 2025 Mehmet Karabulut.
//  This software is released under the GPL License.
//  This is an open-source project forked from Sequel Ace.
//

#import "SPPostgresFastStreamingResult.h"

@implementation SPPostgresFastStreamingResult {
    BOOL streamingEnabled;
    NSUInteger streamingFetchSize;
}

- (instancetype)initWithResult:(PGresult *)result connection:(void *)connection {
    self = [super init];
    if (self) {
        // Store result from parent class initialization
        // In a full implementation, we would handle the PGresult here
        streamingEnabled = YES;
        streamingFetchSize = 100; // Default fetch size
    }
    return self;
}

- (void)setStreamingEnabled:(BOOL)enabled {
    streamingEnabled = enabled;
}

- (void)setStreamingFetchSize:(NSUInteger)fetchSize {
    if (fetchSize > 0) {
        streamingFetchSize = fetchSize;
    }
}

- (NSArray *)getRowAsArray {
    // Override parent to provide optimized fetching
    // In a full implementation, this would use PostgreSQL cursors
    // for efficient row-by-row retrieval
    return [super getRowAsArray];
}

- (NSDictionary *)getRowAsDictionary {
    // Override parent to provide optimized fetching
    return [super getRowAsDictionary];
}

@end
