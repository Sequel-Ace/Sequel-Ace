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
    }
    return self;
}

- (instancetype)initWithPGResult:(PGresult *)result {
    self = [super initWithPGResult:result];
    if (self) {
        dataStorage = [NSMutableArray array];
    }
    return self;
}

- (void)replaceExistingResultStore:(SPPostgresStreamingResultStore *)previousResultStore {
    // Basic implementation: copy data if needed, or just reset
    [dataStorage removeAllObjects];
}

- (void)startDownload {
    NSLog(@"SPPostgresStreamingResultStore: startDownload called. numberOfRows=%lu", (unsigned long)[self numberOfRows]);
    
    // Simulate download or just trigger delegate
    // In a real implementation, this would fetch rows from the result set
    // For now, let's assume data is already in the result set or we fetch it all
    
    // Fetch all rows from the underlying result set (which we inherit from)
    // Since we are inheriting from SPPostgresResult (via StreamingResult), we can use its methods
    // But wait, SPPostgresResult uses libpq result which is already in memory usually.
    
    // Let's populate dataStorage from the result set
    NSUInteger count = [self numberOfRows];
    for (NSUInteger i = 0; i < count; i++) {
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

// Override numberOfRows to return our storage count if we are managing it
- (NSUInteger)numberOfRows {
    return [dataStorage count];
}

- (BOOL)dataDownloaded {
    // Returns YES if data has been downloaded to the store
    // For this implementation, we consider data downloaded if we have rows OR
    // if we've attempted to download (even if result was empty)
    return YES; // Simplified - always return YES since data is fetched synchronously
}

@end
