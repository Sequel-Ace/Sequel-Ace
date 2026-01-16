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
    self = [super initWithPGResult:result];
    if (self) {
        dataStorage = [NSMutableArray array];
        dataDownloadStarted = NO;
    }
    return self;
}

- (void)replaceExistingResultStore:(SPPostgresStreamingResultStore *)previousResultStore {
    // Basic implementation: copy data if needed, or just reset
    [dataStorage removeAllObjects];
}

- (void)startDownload {
    // IMPORTANT: Use [super numberOfRows] to get the actual row count from the PGresult,
    // NOT [self numberOfRows] which returns dataStorage count (would be 0 here)
    NSUInteger parentRowCount = [super numberOfRows];
    NSLog(@"SPPostgresStreamingResultStore: startDownload called. parentRowCount=%lu", (unsigned long)parentRowCount);

    // Mark download as started
    dataDownloadStarted = YES;

    // Clear existing storage before populating
    [dataStorage removeAllObjects];

    // Fetch all rows from the underlying result set (which we inherit from)
    // SPPostgresResult uses libpq result which is already in memory
    for (NSUInteger i = 0; i < parentRowCount; i++) {
        [self seekToRow:i]; // SPPostgresResult has seekToRow
        NSArray *row = [self getRowAsArray]; // This method is in SPPostgresResult
        if (row) {
            [dataStorage addObject:row];
        }
    }

    NSLog(@"SPPostgresStreamingResultStore: startDownload finished populating %lu rows", (unsigned long)[dataStorage count]);

    if ([delegate respondsToSelector:@selector(resultStoreDidFinishLoadingData:)]) {
        [delegate resultStoreDidFinishLoadingData:self];
        NSLog(@"SPPostgresStreamingResultStore: delegate resultStoreDidFinishLoadingData called");
    } else {
        NSLog(@"SPPostgresStreamingResultStore: delegate is nil or doesn't respond!");
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

// Override numberOfRows to return our storage count after download, or parent count before
- (NSUInteger)numberOfRows {
    if (dataDownloadStarted) {
        // After download, return local storage count (can be modified by add/remove operations)
        return [dataStorage count];
    } else {
        // Before download, return the actual row count from the PGresult
        return [super numberOfRows];
    }
}

- (BOOL)dataDownloaded {
    // Returns YES if data has been downloaded to the store
    return dataDownloadStarted;
}

@end
