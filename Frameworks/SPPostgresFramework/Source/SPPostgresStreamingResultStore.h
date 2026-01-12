//
//  SPPostgresStreamingResultStore.h
//  SPPostgresFramework
//
//  Created by Mehmet Karabulut (mehmetik@gmail.com) on November 30, 2025.
//  Copyright (c) 2025 Mehmet Karabulut.
//  This software is released under the GPL License.
//  This is an open-source project forked from Sequel Ace.
//

#import "SPPostgresStreamingResult.h"
#import "SPPostgresStreamingResultStoreDelegate.h"

@interface SPPostgresStreamingResultStore : SPPostgresStreamingResult {
    id <SPPostgresStreamingResultStoreDelegate> __unsafe_unretained delegate;
    NSMutableArray *dataStorage; // Simplified storage for now
}

@property (readwrite, unsafe_unretained) id <SPPostgresStreamingResultStoreDelegate> delegate;

/* Setup and teardown */
- (void)replaceExistingResultStore:(SPPostgresStreamingResultStore *)previousResultStore;
- (void)startDownload;
- (BOOL)dataDownloaded;

/* Data retrieval */
- (NSMutableArray *)rowContentsAtIndex:(NSUInteger)rowIndex;
- (id)cellDataAtRow:(NSUInteger)rowIndex column:(NSUInteger)columnIndex;
- (id)cellPreviewAtRow:(NSUInteger)rowIndex column:(NSUInteger)columnIndex previewLength:(NSUInteger)previewLength;
- (BOOL)cellIsNullAtRow:(NSUInteger)rowIndex column:(NSUInteger)columnIndex;

/* Deleting rows and addition of placeholder rows */
- (void) addDummyRow;
- (void) insertDummyRowAtIndex:(NSUInteger)anIndex;
- (void) removeRowAtIndex:(NSUInteger)anIndex;
- (void) removeRowsInRange:(NSRange)rangeToRemove;
- (void) removeAllRows;

@end

#pragma mark -
#pragma mark Cached method calls

static inline unsigned long long SPPostgresResultStoreGetRowCount(SPPostgresStreamingResultStore* self)
{
    typedef unsigned long long (*SPMSRSRowCountMethodPtr)(SPPostgresStreamingResultStore*, SEL);
    static SPMSRSRowCountMethodPtr SPMSRSRowCount;
    if (!SPMSRSRowCount) SPMSRSRowCount = (SPMSRSRowCountMethodPtr)[SPPostgresStreamingResultStore instanceMethodForSelector:@selector(numberOfRows)];
    return SPMSRSRowCount(self, @selector(numberOfRows));
}

static inline id SPPostgresResultStoreGetRow(SPPostgresStreamingResultStore* self, NSUInteger rowIndex)
{
    typedef id (*SPMSRSRowFetchMethodPtr)(SPPostgresStreamingResultStore*, SEL, NSUInteger);
    static SPMSRSRowFetchMethodPtr SPMSRSRowFetch;
    if (!SPMSRSRowFetch) SPMSRSRowFetch = (SPMSRSRowFetchMethodPtr)[SPPostgresStreamingResultStore instanceMethodForSelector:@selector(rowContentsAtIndex:)];
    return SPMSRSRowFetch(self, @selector(rowContentsAtIndex:), rowIndex);
}

static inline id SPPostgresResultStoreObjectAtRowAndColumn(SPPostgresStreamingResultStore* self, NSUInteger rowIndex, NSUInteger colIndex)
{
    typedef id (*SPMSRSObjectFetchMethodPtr)(SPPostgresStreamingResultStore*, SEL, NSUInteger, NSUInteger);
    static SPMSRSObjectFetchMethodPtr SPMSRSObjectFetch;
    if (!SPMSRSObjectFetch) SPMSRSObjectFetch = (SPMSRSObjectFetchMethodPtr)[SPPostgresStreamingResultStore instanceMethodForSelector:@selector(cellDataAtRow:column:)];
    return SPMSRSObjectFetch(self, @selector(cellDataAtRow:column:), rowIndex, colIndex);
}

static inline id SPPostgresResultStorePreviewAtRowAndColumn(SPPostgresStreamingResultStore* self, NSUInteger rowIndex, NSUInteger colIndex, NSUInteger previewLength)
{
    typedef id (*SPMSRSObjectPreviewMethodPtr)(SPPostgresStreamingResultStore*, SEL, NSUInteger, NSUInteger, NSUInteger);
    static SPMSRSObjectPreviewMethodPtr SPMSRSObjectPreview;
    if (!SPMSRSObjectPreview) SPMSRSObjectPreview = (SPMSRSObjectPreviewMethodPtr)[SPPostgresStreamingResultStore instanceMethodForSelector:@selector(cellPreviewAtRow:column:previewLength:)];
    return SPMSRSObjectPreview(self, @selector(cellPreviewAtRow:column:previewLength:), rowIndex, colIndex, previewLength);
}
