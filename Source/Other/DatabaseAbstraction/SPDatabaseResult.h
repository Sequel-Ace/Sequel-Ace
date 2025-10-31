//
//  SPDatabaseResult.h
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

// Result set row types
typedef NS_ENUM(NSUInteger, SPDatabaseResultRowType) {
    SPDatabaseResultRowAsDefault    = 0,
    SPDatabaseResultRowAsArray      = 1,
    SPDatabaseResultRowAsDictionary = 2
};

/**
 * SPDatabaseResult protocol
 * 
 * This protocol defines a common interface for database query results,
 * abstracting the underlying database implementation.
 */
@protocol SPDatabaseResult <NSObject, NSFastEnumeration>

#pragma mark - Delegate

/**
 * Set a delegate for the result (for streaming/progress callbacks)
 */
@property (readwrite, weak) id delegate;

/**
 * Whether all data has been downloaded from the server (for streaming results)
 * For non-streaming results, this is always YES
 */
@property (readonly, assign) BOOL dataDownloaded;

#pragma mark - Result Metadata

/**
 * Get number of rows in result set
 * @return Row count (or NSNotFound for streaming results)
 */
- (NSUInteger)numberOfRows;

/**
 * Get number of fields/columns in result set
 * @return Field count
 */
- (NSUInteger)numberOfFields;

/**
 * Get execution time of the query that produced this result
 * @return Time in seconds
 */
- (double)queryExecutionTime;

#pragma mark - Field Information

/**
 * Get array of field names
 * @return Array of NSString field names
 */
- (NSArray<NSString *> *)fieldNames;

/**
 * Get field definitions
 * @return Array of NSDictionary objects with field metadata
 */
- (NSArray<NSDictionary *> *)fieldDefinitions;

#pragma mark - Data Retrieval

/**
 * Get next row as array
 * @return Array of values or nil if no more rows
 */
- (NSArray *)getRowAsArray;

/**
 * Get next row as dictionary
 * @return Dictionary with field names as keys or nil if no more rows
 */
- (NSDictionary *)getRowAsDictionary;

/**
 * Get all rows as array of arrays
 * @return Array of row arrays
 */
- (NSArray<NSArray *> *)getAllRows;

/**
 * Get all rows as array of dictionaries
 * @return Array of row dictionaries
 */
- (NSArray<NSDictionary *> *)getAllRowsAsDictionaries;

#pragma mark - Result Navigation

/**
 * Seek to specific row
 * @param row Row index to seek to
 */
- (void)seekToRow:(NSUInteger)row;

#pragma mark - Data Format Options

/**
 * Set whether to return data as strings
 * @param asStrings YES to return as strings, NO for native types
 */
- (void)setReturnDataAsStrings:(BOOL)asStrings;

/**
 * Set default row return type
 * @param defaultRowReturnType The row return type (SPDatabaseResultRowType enum)
 */
- (void)setDefaultRowReturnType:(SPDatabaseResultRowType)defaultRowReturnType;

#pragma mark - Streaming Result Methods

/**
 * Start downloading result data (for streaming results)
 */
- (void)startDownload;

/**
 * Cancel result loading (for streaming results)
 */
- (void)cancelResultLoad;

#pragma mark - Row-Level Access (for result stores)

/**
 * Get row contents at specific index
 */
- (NSMutableArray *)rowContentsAtIndex:(NSUInteger)rowIndex;

/**
 * Get cell data at specific row and column
 */
- (id)cellDataAtRow:(NSUInteger)rowIndex column:(NSUInteger)columnIndex;

/**
 * Get cell preview at specific row and column
 */
- (id)cellPreviewAtRow:(NSUInteger)rowIndex column:(NSUInteger)columnIndex previewLength:(NSUInteger)previewLength;

/**
 * Check if cell is NULL at specific row and column
 */
- (BOOL)cellIsNullAtRow:(NSUInteger)rowIndex column:(NSUInteger)columnIndex;

#pragma mark - Row Manipulation (for mutable result stores)

/**
 * Add a dummy row
 */
- (void)addDummyRow;

/**
 * Insert a dummy row at specific index
 */
- (void)insertDummyRowAtIndex:(NSUInteger)anIndex;

/**
 * Remove row at specific index
 */
- (void)removeRowAtIndex:(NSUInteger)anIndex;

/**
 * Remove multiple rows in a range
 */
- (void)removeRowsInRange:(NSRange)rangeToRemove;

/**
 * Remove all rows
 */
- (void)removeAllRows;

@end

