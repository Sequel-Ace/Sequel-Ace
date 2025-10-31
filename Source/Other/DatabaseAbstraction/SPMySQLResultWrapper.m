//
//  SPMySQLResultWrapper.m
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

#import "SPMySQLResultWrapper.h"
#import <SPMySQL/SPMySQL.h>

@implementation SPMySQLResultWrapper {
    SPMySQLResult *_mysqlResult;
    __weak id _delegate;
}

@synthesize underlyingMySQLResult = _mysqlResult;

#pragma mark - Initialization

- (instancetype)initWithMySQLResult:(SPMySQLResult *)result {
    if ((self = [super init])) {
        _mysqlResult = result;
    }
    return self;
}

#pragma mark - Delegate

- (id)delegate {
    return _delegate;
}

- (void)setDelegate:(id)delegate {
    NSLog(@"SPMySQLResultWrapper setDelegate:%@ on result:%@", delegate, _mysqlResult);
    _delegate = delegate;
    
    // If the underlying result supports delegates (like SPMySQLStreamingResultStore),
    // set ourselves as the delegate to forward callbacks
    if ([_mysqlResult respondsToSelector:@selector(setDelegate:)]) {
        NSLog(@"  forwarding setDelegate to underlying result");
        [(id)_mysqlResult setDelegate:self];
    } else {
        NSLog(@"  underlying result does not support setDelegate");
    }
}

// Forward delegate callback from underlying result
- (void)resultStoreDidFinishLoadingData:(id)resultStore {
    NSLog(@"SPMySQLResultWrapper resultStoreDidFinishLoadingData called, underlying=%@, wrapper delegate=%@", resultStore, _delegate);
    if ([_delegate respondsToSelector:@selector(resultStoreDidFinishLoadingData:)]) {
        NSLog(@"  forwarding to wrapper delegate");
        // Forward to our delegate, but pass ourselves (the wrapper) instead of the underlying result
        [_delegate resultStoreDidFinishLoadingData:self];
    } else {
        NSLog(@"  delegate does not respond to resultStoreDidFinishLoadingData:");
    }
}

- (BOOL)dataDownloaded {
    BOOL downloaded;
    // Forward to underlying result if it has this property (streaming results)
    if ([_mysqlResult respondsToSelector:@selector(dataDownloaded)]) {
        downloaded = [(id)_mysqlResult dataDownloaded];
    } else {
        // For non-streaming results, all data is immediately available
        downloaded = YES;
    }
    NSLog(@"SPMySQLResultWrapper dataDownloaded -> %d", downloaded);
    return downloaded;
}

#pragma mark - Result Metadata

- (NSUInteger)numberOfRows {
    return [_mysqlResult numberOfRows];
}

- (NSUInteger)numberOfFields {
    return [_mysqlResult numberOfFields];
}

- (double)queryExecutionTime {
    return [_mysqlResult queryExecutionTime];
}

#pragma mark - Field Information

- (NSArray<NSString *> *)fieldNames {
    return [_mysqlResult fieldNames];
}

- (NSArray<NSDictionary *> *)fieldDefinitions {
    return [_mysqlResult fieldDefinitions];
}

#pragma mark - Data Retrieval

- (NSArray *)getRowAsArray {
    return [_mysqlResult getRowAsArray];
}

- (NSDictionary *)getRowAsDictionary {
    return [_mysqlResult getRowAsDictionary];
}

- (NSArray<NSArray *> *)getAllRows {
    return [_mysqlResult getAllRows];
}

- (NSArray<NSDictionary *> *)getAllRowsAsDictionaries {
    NSMutableArray *rows = [NSMutableArray array];
    NSDictionary *row;
    while ((row = [_mysqlResult getRowAsDictionary])) {
        [rows addObject:row];
    }
    return rows;
}

#pragma mark - Result Navigation

- (void)seekToRow:(NSUInteger)row {
    [_mysqlResult seekToRow:row];
}

#pragma mark - Data Format Options

- (void)setReturnDataAsStrings:(BOOL)asStrings {
    [_mysqlResult setReturnDataAsStrings:asStrings];
}

- (void)setDefaultRowReturnType:(SPDatabaseResultRowType)defaultRowReturnType {
    // Map SPDatabaseResultRowType to SPMySQLResultRowType
    // They have the same values: 0 = default, 1 = array, 2 = dictionary
    [_mysqlResult setDefaultRowReturnType:(SPMySQLResultRowType)defaultRowReturnType];
}

#pragma mark - NSFastEnumeration

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained *)stackbuf count:(NSUInteger)len {
    return [_mysqlResult countByEnumeratingWithState:state objects:stackbuf count:len];
}

#pragma mark - Streaming Result Methods

- (void)startDownload {
    NSLog(@"SPMySQLResultWrapper startDownload on result:%@", _mysqlResult);
    if ([_mysqlResult respondsToSelector:@selector(startDownload)]) {
        NSLog(@"  forwarding startDownload to underlying result");
        [(id)_mysqlResult startDownload];
    } else {
        NSLog(@"  underlying result does not support startDownload");
    }
}

- (void)cancelResultLoad {
    if ([_mysqlResult respondsToSelector:@selector(cancelResultLoad)]) {
        [(id)_mysqlResult cancelResultLoad];
    }
}

#pragma mark - Row-Level Access

- (NSMutableArray *)rowContentsAtIndex:(NSUInteger)rowIndex {
    if ([_mysqlResult respondsToSelector:@selector(rowContentsAtIndex:)]) {
        NSMutableArray *row = [(id)_mysqlResult rowContentsAtIndex:rowIndex];
        
        // If the underlying result returns nil (e.g., for a dummy row),
        // create an array of NSNull values to represent an empty row
        if (row == nil) {
            NSUInteger fieldCount = [self numberOfFields];
            NSMutableArray *emptyRow = [NSMutableArray arrayWithCapacity:fieldCount];
            for (NSUInteger i = 0; i < fieldCount; i++) {
                [emptyRow addObject:[NSNull null]];
            }
            return emptyRow;
        }
        
        return row;
    }
    return nil;
}

- (id)cellDataAtRow:(NSUInteger)rowIndex column:(NSUInteger)columnIndex {
    if ([_mysqlResult respondsToSelector:@selector(cellDataAtRow:column:)]) {
        id cellData = [(id)_mysqlResult cellDataAtRow:rowIndex column:columnIndex];
        // Return NSNull for nil cells (dummy rows)
        return cellData ?: [NSNull null];
    }
    return [NSNull null];
}

- (id)cellPreviewAtRow:(NSUInteger)rowIndex column:(NSUInteger)columnIndex previewLength:(NSUInteger)previewLength {
    if ([_mysqlResult respondsToSelector:@selector(cellPreviewAtRow:column:previewLength:)]) {
        return [(id)_mysqlResult cellPreviewAtRow:rowIndex column:columnIndex previewLength:previewLength];
    }
    return nil;
}

- (BOOL)cellIsNullAtRow:(NSUInteger)rowIndex column:(NSUInteger)columnIndex {
    if ([_mysqlResult respondsToSelector:@selector(cellIsNullAtRow:column:)]) {
        return [(id)_mysqlResult cellIsNullAtRow:rowIndex column:columnIndex];
    }
    return NO;
}

#pragma mark - Row Manipulation

- (void)addDummyRow {
    if ([_mysqlResult respondsToSelector:@selector(addDummyRow)]) {
        [(id)_mysqlResult addDummyRow];
    }
}

- (void)insertDummyRowAtIndex:(NSUInteger)anIndex {
    if ([_mysqlResult respondsToSelector:@selector(insertDummyRowAtIndex:)]) {
        [(id)_mysqlResult insertDummyRowAtIndex:anIndex];
    }
}

- (void)removeRowAtIndex:(NSUInteger)anIndex {
    if ([_mysqlResult respondsToSelector:@selector(removeRowAtIndex:)]) {
        [(id)_mysqlResult removeRowAtIndex:anIndex];
    }
}

- (void)removeRowsInRange:(NSRange)rangeToRemove {
    if ([_mysqlResult respondsToSelector:@selector(removeRowsInRange:)]) {
        [(id)_mysqlResult removeRowsInRange:rangeToRemove];
    }
}

- (void)removeAllRows {
    if ([_mysqlResult respondsToSelector:@selector(removeAllRows)]) {
        [(id)_mysqlResult removeAllRows];
    }
}

@end

