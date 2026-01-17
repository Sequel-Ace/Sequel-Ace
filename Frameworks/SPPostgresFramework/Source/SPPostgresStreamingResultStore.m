//
//  SPPostgresStreamingResultStore.m
//  SPPostgresFramework
//
//  Created by Mehmet Karabulut (mehmetik@gmail.com) on November 30, 2025.
//  Copyright (c) 2025 Mehmet Karabulut.
//  This software is released under the GPL License.
//  This is an open-source project forked from Sequel Ace.
//

#import "SPPostgresStreamingResultStore.h"
#import "SPDebugLogger.h"
#import <libpq-fe.h>

@implementation SPPostgresStreamingResultStore

@synthesize delegate;

- (instancetype)init {
    self = [super init];
    if (self) {
        dataStorage = [NSMutableArray array];
        dataDownloadStarted = NO;
    }
    return self;
}

- (instancetype)initWithPGResult:(PGresult *)result {
    NSLog(@"[PG-DEBUG] SPPostgresStreamingResultStore.initWithPGResult called with result=%p", result);
    self = [super initWithPGResult:result];
    if (self) {
        dataStorage = [NSMutableArray array];
        dataDownloadStarted = NO;
        // Log using PQntuples directly since [super numberOfRows] goes through
        // SPPostgresStreamingResult which returns currentRowIndex (0)
        NSLog(@"[PG-DEBUG] SPPostgresStreamingResultStore.init: PQntuples=%d", resultSet ? PQntuples(resultSet) : 0);
    }
    return self;
}

- (void)replaceExistingResultStore:(SPPostgresStreamingResultStore *)previousResultStore {
    // Basic implementation: copy data if needed, or just reset
    [dataStorage removeAllObjects];
}

- (void)startDownload {
    [SPDebugLogger log:@"[DATA] startDownload entered, dataDownloadStarted=%d", dataDownloadStarted];
    NSLog(@"[PG-DEBUG] startDownload entered, dataDownloadStarted=%d", dataDownloadStarted);

    // Guard against re-entry - only download once
    if (dataDownloadStarted) {
        [SPDebugLogger log:@"[DATA] Already started, skipping"];
        NSLog(@"[PG-DEBUG] startDownload: Already started, skipping");
        return;
    }

    // Get row count directly from PGresult using PQntuples, NOT from [super numberOfRows]
    // because SPPostgresStreamingResult overrides numberOfRows to return currentRowIndex
    // (for streaming mode) which would be 0 at this point.
    NSUInteger parentRowCount = resultSet ? (NSUInteger)PQntuples(resultSet) : 0;
    NSUInteger parentFieldCount = [super numberOfFields];
    [SPDebugLogger log:@"[DATA] Fetching %lu rows from libpq", (unsigned long)parentRowCount];
    NSLog(@"[PG-DEBUG] startDownload: parentRowCount=%lu, parentFieldCount=%lu",
          (unsigned long)parentRowCount, (unsigned long)parentFieldCount);

    // DEBUG: Check if parent row count is 0 - this is the problem we're investigating
    if (parentRowCount == 0) {
        NSLog(@"[PG-DEBUG] WARNING: parentRowCount is 0! Checking resultSet directly...");
        NSLog(@"[PG-DEBUG] fieldNames from super: %@", [super fieldNames]);
    }

    // Clear existing storage before populating
    [dataStorage removeAllObjects];

    // Fetch all rows from the underlying result set (which we inherit from)
    // SPPostgresResult uses libpq result which is already in memory
    // NOTE: We must call getRowAtIndex: directly instead of getRowAsArray because
    // SPPostgresStreamingResult overrides getRowAsArray to use streaming mode via PGconn*,
    // but we have a full PGresult* (initialized via initWithPGResult:), so we need
    // SPPostgresResult's implementation that reads from resultSet directly.
    for (NSUInteger i = 0; i < parentRowCount; i++) {
        // Call getRowAtIndex: directly - this is defined in SPPostgresResult and reads from resultSet
        NSArray *row = [self getRowAtIndex:i];
        if (row) {
            [dataStorage addObject:row];
            // DEBUG: Log first row to verify data is being read
            if (i == 0) {
                NSLog(@"[PG-DEBUG] First row data: %@", row);
            }
        } else {
            NSLog(@"[PG-DEBUG] WARNING: getRowAtIndex returned nil for row %lu", (unsigned long)i);
        }
    }

    // Mark download as complete AFTER populating data
    // This ensures dataDownloaded returns YES only when data is actually ready
    dataDownloadStarted = YES;

    [SPDebugLogger log:@"[DATA] Fetched %lu rows, calling delegate", (unsigned long)[dataStorage count]];
    NSLog(@"[PG-DEBUG] startDownload finished: dataStorage.count=%lu", (unsigned long)[dataStorage count]);

    // Notify delegate if set
    if (delegate && [delegate respondsToSelector:@selector(resultStoreDidFinishLoadingData:)]) {
        [delegate resultStoreDidFinishLoadingData:self];
        [SPDebugLogger log:@"[DATA] delegate resultStoreDidFinishLoadingData called"];
        NSLog(@"[PG-DEBUG] delegate resultStoreDidFinishLoadingData called");
    } else {
        // Delegate not set yet - this is OK because SPDataStorage.setDataStorage:
        // checks dataDownloaded and calls the callback directly
        [SPDebugLogger log:@"[DATA] delegate is nil (will be handled by SPDataStorage)"];
        NSLog(@"[PG-DEBUG] delegate is nil (will be handled by SPDataStorage)");
    }
}

- (NSMutableArray *)rowContentsAtIndex:(NSUInteger)rowIndex {
    if (rowIndex < [dataStorage count]) {
        return [NSMutableArray arrayWithArray:[dataStorage objectAtIndex:rowIndex]];
    }
    return nil;
}

- (id)cellDataAtRow:(NSUInteger)rowIndex column:(NSUInteger)columnIndex {
    NSArray *row = [self rowContentsAtIndex:rowIndex];
    if (row && columnIndex < [row count]) {
        return [row objectAtIndex:columnIndex];
    }
    return nil;
}

- (id)cellPreviewAtRow:(NSUInteger)rowIndex column:(NSUInteger)columnIndex previewLength:(NSUInteger)previewLength {
    id data = [self cellDataAtRow:rowIndex column:columnIndex];
    if ([data isKindOfClass:[NSString class]]) {
        NSString *str = (NSString *)data;
        if ([str length] > previewLength) {
            return [str substringToIndex:previewLength];
        }
    }
    return data;
}

- (BOOL)cellIsNullAtRow:(NSUInteger)rowIndex column:(NSUInteger)columnIndex {
    id data = [self cellDataAtRow:rowIndex column:columnIndex];
    return (data == nil || [data isKindOfClass:[NSNull class]]);
}

- (void)addDummyRow {
    [dataStorage addObject:[NSMutableArray array]];
}

- (void)insertDummyRowAtIndex:(NSUInteger)anIndex {
    if (anIndex <= [dataStorage count]) {
        [dataStorage insertObject:[NSMutableArray array] atIndex:anIndex];
    }
}

- (void)removeRowAtIndex:(NSUInteger)anIndex {
    if (anIndex < [dataStorage count]) {
        [dataStorage removeObjectAtIndex:anIndex];
    }
}

- (void)removeRowsInRange:(NSRange)rangeToRemove {
    if (NSMaxRange(rangeToRemove) <= [dataStorage count]) {
        [dataStorage removeObjectsInRange:rangeToRemove];
    }
}

- (void)removeAllRows {
    [dataStorage removeAllObjects];
}

// Override numberOfRows to return our storage count after download, or PGresult count before
- (NSUInteger)numberOfRows {
    NSUInteger result;
    if (dataDownloadStarted) {
        // After download, return local storage count (can be modified by add/remove operations)
        result = [dataStorage count];
        NSLog(@"[PG-DEBUG] SPPostgresStreamingResultStore.numberOfRows (after download): dataStorage.count=%lu", (unsigned long)result);
    } else {
        // Before download, get row count directly from PGresult using PQntuples.
        // NOT [super numberOfRows] because SPPostgresStreamingResult overrides it
        // to return currentRowIndex (for streaming mode) which would be 0 here.
        if (resultSet) {
            result = (NSUInteger)PQntuples(resultSet);
        } else {
            result = 0;
        }
        NSLog(@"[PG-DEBUG] SPPostgresStreamingResultStore.numberOfRows (before download): PQntuples=%lu", (unsigned long)result);
    }
    return result;
}

// Override getRowAsArray to read from dataStorage instead of streaming via PGconn*.
// SPPostgresStreamingResult.getRowAsArray() expects params (PGconn*) but we use initWithPGResult:
// which sets resultSet, not params. So params is nil and the parent would return nil immediately.
// After startDownload populates dataStorage, we iterate through it using currentRowIndex.
- (NSArray *)getRowAsArray {
    if (!dataDownloadStarted) {
        // Before download, fallback to SPPostgresResult's implementation which reads from resultSet
        // We can't call [super getRowAsArray] because SPPostgresStreamingResult expects params
        // Instead, call getRowAtIndex directly (defined in SPPostgresResult, reads from resultSet)
        if (currentRowIndex >= (resultSet ? (NSUInteger)PQntuples(resultSet) : 0)) {
            return nil;
        }
        return [self getRowAtIndex:currentRowIndex++];
    }

    // After download, read from dataStorage
    if (currentRowIndex >= [dataStorage count]) {
        return nil;
    }

    NSLog(@"[PG-DEBUG] SPPostgresStreamingResultStore.getRowAsArray: returning row %lu of %lu",
          (unsigned long)currentRowIndex, (unsigned long)[dataStorage count]);
    return [dataStorage objectAtIndex:currentRowIndex++];
}

// Override getRowAsDictionary to use our getRowAsArray override
- (NSDictionary *)getRowAsDictionary {
    NSArray *row = [self getRowAsArray];
    if (!row) return nil;

    NSArray *names = [self fieldNames];
    if (!names || [names count] != [row count]) {
        NSLog(@"[PG-DEBUG] SPPostgresStreamingResultStore.getRowAsDictionary: field name mismatch - names=%lu, row=%lu",
              (unsigned long)[names count], (unsigned long)[row count]);
        return nil;
    }

    return [NSDictionary dictionaryWithObjects:row forKeys:names];
}

- (BOOL)dataDownloaded {
    // Returns YES if data has been downloaded to the store
    return dataDownloadStarted;
}

@end
