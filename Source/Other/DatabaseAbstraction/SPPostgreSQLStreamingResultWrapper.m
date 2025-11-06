//
//  SPPostgreSQLStreamingResultWrapper.m
//  sequel-ace
//
//  Created by Sequel Ace on 2024.
//  Copyright (c) 2024 Sequel Ace. All rights reserved.
//

#import "SPPostgreSQLStreamingResultWrapper.h"
#import "SPPostgreSQLConnectionWrapper.h"
#import "SPPostgreSQLTypeMapper.h"
#import "sppostgresql_ffi.h"
#import <pthread.h>

@interface SPPostgreSQLStreamingResultWrapper () {
    pthread_mutex_t _dataLock;
    BOOL _loadStarted;
    BOOL _loadCancelled;
}

@property (nonatomic, strong) NSString *query;
@property (nonatomic, weak) SPPostgreSQLConnectionWrapper *connection;
@property (nonatomic, strong) NSArray<NSString *> *cachedFieldNames;
@property (nonatomic, strong) NSArray<NSNumber *> *cachedFieldTypeOIDs;
@property (nonatomic, assign) NSUInteger totalRows;
@property (nonatomic, assign) NSUInteger numFields;
@property (nonatomic, assign) NSUInteger currentRow;
@property (nonatomic, assign) BOOL dataDownloaded;
@property (nonatomic, strong) NSMutableArray<NSMutableArray *> *cachedRows;
@property (nonatomic, assign) NSUInteger batchSize;
@property (nonatomic, assign) SPPostgreSQLResult *pgResult; // Store result handle for async data loading

@end

@implementation SPPostgreSQLStreamingResultWrapper

@synthesize delegate = _delegate;

- (BOOL)dataDownloaded {
    pthread_mutex_lock(&_dataLock);
    BOOL downloaded = _dataDownloaded;
    pthread_mutex_unlock(&_dataLock);
    return downloaded;
}

- (instancetype)initWithQuery:(NSString *)query
                   connection:(SPPostgreSQLConnectionWrapper *)connection
                    batchSize:(NSUInteger)batchSize {
    if ((self = [super init])) {
        _query = [query copy];
        _connection = connection;
        _batchSize = batchSize;
        _currentRow = 0;
        _dataDownloaded = NO;
        _loadStarted = NO;
        _loadCancelled = NO;
        _pgResult = NULL;
        
        // Initialize mutex
        pthread_mutex_init(&_dataLock, NULL);
        
        // Initialize row storage
        _cachedRows = [NSMutableArray array];
        
        // Execute query with LIMIT 0 to get table structure/metadata synchronously
        // This is fast (returns no data) and needed for UI to know column info immediately
        SPPostgreSQLConnection *pgConnection = [connection pgConnection];
        if (pgConnection) {
            // Wrap the query in a subquery with LIMIT 0 to get just metadata (fast, no data)
            NSString *metadataQuery = [NSString stringWithFormat:@"SELECT * FROM (%@) AS metadata_query LIMIT 0", query];
            SPPostgreSQLResult *metadataResult = sp_postgresql_connection_execute_query(pgConnection, [metadataQuery UTF8String]);
            
            if (metadataResult) {
                // Extract field metadata
                _numFields = sp_postgresql_result_num_fields(metadataResult);
                
                NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:_numFields];
                NSMutableArray<NSNumber *> *typeOIDs = [NSMutableArray arrayWithCapacity:_numFields];
                for (NSUInteger i = 0; i < _numFields; i++) {
                    char *nameCStr = sp_postgresql_result_field_name(metadataResult, (int)i);
                    if (nameCStr) {
                        NSString *name = [NSString stringWithUTF8String:nameCStr];
                        [names addObject:name];
                        sp_postgresql_free_string(nameCStr);
                    } else {
                        [names addObject:[NSString stringWithFormat:@"column_%lu", (unsigned long)i]];
                    }
                    
                    uint32_t typeOID = sp_postgresql_result_field_type_oid(metadataResult, (int)i);
                    [typeOIDs addObject:@(typeOID)];
                }
                _cachedFieldNames = [names copy];
                _cachedFieldTypeOIDs = [typeOIDs copy];
                
                // Clean up metadata result
                sp_postgresql_result_destroy(metadataResult);
            } else {
                // Metadata query failed
                _numFields = 0;
                _cachedFieldNames = @[];
                _cachedFieldTypeOIDs = @[];
            }
        } else {
            // No connection
            _numFields = 0;
            _cachedFieldNames = @[];
            _cachedFieldTypeOIDs = @[];
        }
        
        // Total rows will be set when actual query executes in _downloadAllData
        _totalRows = 0;
    }
    return self;
}

- (void)dealloc {
    // Ensure download is cancelled
    [self cancelResultLoad];
    
    // Clean up result if it wasn't already
    if (_pgResult) {
        sp_postgresql_result_destroy(_pgResult);
        _pgResult = NULL;
    }
    
    // Destroy mutex
    pthread_mutex_destroy(&_dataLock);
}

#pragma mark - Delegate

- (void)setDelegate:(id)delegate {
    _delegate = delegate;
    
    // If all data is already downloaded, notify delegate immediately
    if (_dataDownloaded && [_delegate respondsToSelector:@selector(resultStoreDidFinishLoadingData:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [_delegate performSelector:@selector(resultStoreDidFinishLoadingData:) withObject:self];
#pragma clang diagnostic pop
    }
}

#pragma mark - Result Metadata

- (NSUInteger)numberOfRows {
    // Return total rows - known immediately after init
    return _totalRows;
}

- (NSUInteger)numberOfFields {
    pthread_mutex_lock(&_dataLock);
    NSUInteger numFields = _numFields;
    pthread_mutex_unlock(&_dataLock);
    return numFields;
}

- (double)queryExecutionTime {
    // Not tracked for streaming results
    return 0.0;
}

#pragma mark - Field Information

- (NSArray<NSString *> *)fieldNames {
    pthread_mutex_lock(&_dataLock);
    NSArray *fieldNames = _cachedFieldNames;
    pthread_mutex_unlock(&_dataLock);
    return fieldNames;
}

- (NSArray<NSDictionary *> *)fieldDefinitions {
    // Create field definitions compatible with MySQL format
    // This ensures compatibility with SPCopyTable and other components
    pthread_mutex_lock(&_dataLock);
    NSUInteger numFields = _numFields;
    NSArray *fieldNames = _cachedFieldNames;
    NSArray *fieldTypeOIDs = _cachedFieldTypeOIDs;
    pthread_mutex_unlock(&_dataLock);
    
    NSMutableArray *definitions = [NSMutableArray arrayWithCapacity:numFields];
    for (NSUInteger i = 0; i < numFields; i++) {
        NSString *name = (i < [fieldNames count]) ? fieldNames[i] : @"";
        
        // Get actual PostgreSQL type information using OID
        uint32_t typeOID = 0;
        if (i < [fieldTypeOIDs count]) {
            typeOID = [fieldTypeOIDs[i] unsignedIntValue];
        }
        NSString *typeName = [SPPostgreSQLTypeMapper typeNameForOID:typeOID];
        NSString *typeGrouping = [SPPostgreSQLTypeMapper typeGroupingForOID:typeOID];
        
        // REQUIRED: datacolumnindex must never be nil
        [definitions addObject:@{
            @"datacolumnindex": [NSString stringWithFormat:@"%lu", (unsigned long)i],
            @"name": name,
            @"type": typeName,
            @"typegrouping": typeGrouping
        }];
    }
    return definitions;
}

#pragma mark - Data Retrieval

- (NSArray *)getRowAsArray {
    pthread_mutex_lock(&_dataLock);
    
    if (_currentRow >= [_cachedRows count]) {
        pthread_mutex_unlock(&_dataLock);
        return nil;
    }
    
    NSArray *row = _cachedRows[_currentRow];
    _currentRow++;
    
    pthread_mutex_unlock(&_dataLock);
    return row;
}

- (NSDictionary *)getRowAsDictionary {
    NSArray *row = [self getRowAsArray];
    if (!row) return nil;
    
    pthread_mutex_lock(&_dataLock);
    NSArray *fieldNames = _cachedFieldNames;
    NSUInteger numFields = _numFields;
    pthread_mutex_unlock(&_dataLock);
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:numFields];
    for (NSUInteger i = 0; i < numFields && i < row.count && i < fieldNames.count; i++) {
        NSString *fieldName = fieldNames[i];
        dict[fieldName] = row[i];
    }
    return dict;
}

- (NSArray<NSArray *> *)getAllRows {
    pthread_mutex_lock(&_dataLock);
    NSArray *allRows = [_cachedRows copy];
    pthread_mutex_unlock(&_dataLock);
    return allRows;
}

- (NSArray<NSDictionary *> *)getAllRowsAsDictionaries {
    NSArray *rows = [self getAllRows];
    
    pthread_mutex_lock(&_dataLock);
    NSArray *fieldNames = _cachedFieldNames;
    NSUInteger numFields = _numFields;
    pthread_mutex_unlock(&_dataLock);
    
    NSMutableArray *dicts = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSArray *row in rows) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:numFields];
        for (NSUInteger i = 0; i < numFields && i < row.count && i < fieldNames.count; i++) {
            NSString *fieldName = fieldNames[i];
            dict[fieldName] = row[i];
        }
        [dicts addObject:dict];
    }
    
    return dicts;
}

- (void)seekToRow:(NSUInteger)targetRow {
    pthread_mutex_lock(&_dataLock);
    _currentRow = targetRow;
    pthread_mutex_unlock(&_dataLock);
}

#pragma mark - Data Type Configuration

- (void)setReturnDataAsStrings:(BOOL)returnAsStrings {
    // PostgreSQL wrapper always returns strings
}

- (void)setDefaultRowReturnType:(SPDatabaseResultRowType)returnType {
    // Not applicable for PostgreSQL
}

#pragma mark - Streaming Result Methods

- (void)startDownload {
    if (_loadStarted) {
        [NSException raise:NSInternalInconsistencyException 
                    format:@"Data download has already been started"];
        return;
    }
    
    _loadStarted = YES;
    
    // Use dispatch instead of NSThread for better control and integration
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self _downloadAllData];
    });
}

- (void)cancelResultLoad {
    // Mark as cancelled
    pthread_mutex_lock(&_dataLock);
    _loadCancelled = YES;
    BOOL wasStarted = _loadStarted;
    pthread_mutex_unlock(&_dataLock);
    
    // If not started, mark as completed immediately
    if (!wasStarted) {
        pthread_mutex_lock(&_dataLock);
        _dataDownloaded = YES;
        pthread_mutex_unlock(&_dataLock);
        return;
    }
    
    // Wait for download to complete (with timeout)
    int timeout = 5000; // 5 seconds
    int elapsed = 0;
    BOOL downloaded = NO;
    while (!downloaded && elapsed < timeout) {
        usleep(1000);
        elapsed++;
        pthread_mutex_lock(&_dataLock);
        downloaded = _dataDownloaded;
        pthread_mutex_unlock(&_dataLock);
    }
    
    // If still not downloaded after timeout, force it
    if (!downloaded) {
        pthread_mutex_lock(&_dataLock);
        _dataDownloaded = YES;
        pthread_mutex_unlock(&_dataLock);
    }
}

- (void)_downloadAllData {
    @autoreleasepool {
        [[NSThread currentThread] setName:@"SPPostgreSQLStreamingResultStore data download thread"];
        
        @try {
            // Execute the query on the background thread
            SPPostgreSQLConnection *pgConnection = [_connection pgConnection];
            if (!pgConnection) {
                NSLog(@"[PG Streaming] No connection available");
                return;  // @finally will still run
            }
            
            _pgResult = sp_postgresql_connection_execute_query(pgConnection, [_query UTF8String]);
            
            if (!_pgResult) {
                NSLog(@"[PG Streaming] Query execution failed");
                return;  // @finally will still run
            }
            
            // Get total rows and number of fields
            NSUInteger totalRows = sp_postgresql_result_num_rows(_pgResult);
            NSUInteger numFields = sp_postgresql_result_num_fields(_pgResult);
            
            // Extract field metadata
            NSMutableArray<NSString *> *fieldNames = [NSMutableArray arrayWithCapacity:numFields];
            NSMutableArray<NSNumber *> *fieldTypeOIDs = [NSMutableArray arrayWithCapacity:numFields];
            for (NSUInteger i = 0; i < numFields; i++) {
                char *nameCStr = sp_postgresql_result_field_name(_pgResult, (int)i);
                if (nameCStr) {
                    NSString *name = [NSString stringWithUTF8String:nameCStr];
                    [fieldNames addObject:name];
                    sp_postgresql_free_string(nameCStr);
                } else {
                    [fieldNames addObject:[NSString stringWithFormat:@"column_%lu", (unsigned long)i]];
                }
                
                uint32_t typeOID = sp_postgresql_result_field_type_oid(_pgResult, (int)i);
                [fieldTypeOIDs addObject:@(typeOID)];
            }
            
            // Update metadata atomically
            pthread_mutex_lock(&_dataLock);
            _totalRows = totalRows;
            _numFields = numFields;
            _cachedFieldNames = [fieldNames copy];
            _cachedFieldTypeOIDs = [fieldTypeOIDs copy];
            [_cachedRows removeAllObjects];
            pthread_mutex_unlock(&_dataLock);
            
            // Fetch all rows
            for (NSUInteger rowIndex = 0; rowIndex < totalRows; rowIndex++) {
                // Check if cancelled
                if (_loadCancelled) {
                    NSLog(@"[PG Streaming] Load cancelled at row %lu", (unsigned long)rowIndex);
                    break;
                }
                
                NSMutableArray *row = [NSMutableArray arrayWithCapacity:numFields];
                
                for (NSUInteger colIndex = 0; colIndex < numFields; colIndex++) {
                    char *valueCStr = sp_postgresql_result_get_value(_pgResult, (int)rowIndex, (int)colIndex);
                    if (valueCStr) {
                        NSString *value = [NSString stringWithUTF8String:valueCStr];
                        [row addObject:value];
                        sp_postgresql_free_string(valueCStr);
                    } else {
                        [row addObject:[NSNull null]];
                    }
                }
                
                pthread_mutex_lock(&_dataLock);
                [_cachedRows addObject:row];
                pthread_mutex_unlock(&_dataLock);
            }
            
            // Clean up result
            if (_pgResult) {
                sp_postgresql_result_destroy(_pgResult);
                _pgResult = NULL;
            }
            
        } @catch (NSException *exception) {
            NSLog(@"PostgreSQL streaming exception: %@", exception);
        } @finally {
            // ALWAYS mark as complete, even if there was an error
            pthread_mutex_lock(&_dataLock);
            _dataDownloaded = YES;
            pthread_mutex_unlock(&_dataLock);
            
            // Capture weak reference to avoid retain cycle and crashes
            __weak SPPostgreSQLStreamingResultWrapper *weakSelf = self;
            
            // Notify delegate on main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong SPPostgreSQLStreamingResultWrapper *strongSelf = weakSelf;
                
                if (!strongSelf) {
                    return;
                }
                
                id delegate = strongSelf->_delegate;
                if (delegate && [delegate respondsToSelector:@selector(resultStoreDidFinishLoadingData:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [delegate performSelector:@selector(resultStoreDidFinishLoadingData:) withObject:strongSelf];
#pragma clang diagnostic pop
                }
            });
        }
    }
}

#pragma mark - Row-Level Access

- (NSMutableArray *)rowContentsAtIndex:(NSUInteger)rowIndex {
    pthread_mutex_lock(&_dataLock);
    
    if (rowIndex >= [_cachedRows count]) {
        pthread_mutex_unlock(&_dataLock);
        return nil;
    }
    
    NSMutableArray *row = [_cachedRows[rowIndex] mutableCopy];
    pthread_mutex_unlock(&_dataLock);
    
    return row;
}

- (id)cellDataAtRow:(NSUInteger)rowIndex column:(NSUInteger)columnIndex {
    pthread_mutex_lock(&_dataLock);
    
    if (rowIndex >= [_cachedRows count]) {
        pthread_mutex_unlock(&_dataLock);
        return [NSNull null];
    }
    
    NSArray *row = _cachedRows[rowIndex];
    id cellData = (columnIndex < [row count]) ? row[columnIndex] : [NSNull null];
    
    pthread_mutex_unlock(&_dataLock);
    
    return cellData ?: [NSNull null];
}

- (id)cellPreviewAtRow:(NSUInteger)rowIndex column:(NSUInteger)columnIndex previewLength:(NSUInteger)previewLength {
    id cellData = [self cellDataAtRow:rowIndex column:columnIndex];
    
    if (!cellData || cellData == [NSNull null]) {
        return cellData;
    }
    
    if ([cellData isKindOfClass:[NSString class]]) {
        NSString *stringData = (NSString *)cellData;
        if ([stringData length] > previewLength) {
            return [stringData substringToIndex:previewLength];
        }
    }
    
    return cellData;
}

- (BOOL)cellIsNullAtRow:(NSUInteger)rowIndex column:(NSUInteger)columnIndex {
    pthread_mutex_lock(&_dataLock);
    
    if (rowIndex >= [_cachedRows count]) {
        pthread_mutex_unlock(&_dataLock);
        return YES;
    }
    
    NSArray *row = _cachedRows[rowIndex];
    id cellData = (columnIndex < [row count]) ? row[columnIndex] : nil;
    
    pthread_mutex_unlock(&_dataLock);
    
    return cellData == nil || cellData == [NSNull null];
}

#pragma mark - Row Manipulation

- (void)addDummyRow {
    NSLog(@"Warning: addDummyRow called on read-only PostgreSQL streaming result");
}

- (void)insertDummyRowAtIndex:(NSUInteger)anIndex {
    NSLog(@"Warning: insertDummyRowAtIndex: called on read-only PostgreSQL streaming result");
}

- (void)removeRowAtIndex:(NSUInteger)anIndex {
    NSLog(@"Warning: removeRowAtIndex: called on read-only PostgreSQL streaming result");
}

- (void)removeRowsInRange:(NSRange)rangeToRemove {
    NSLog(@"Warning: removeRowsInRange: called on read-only PostgreSQL streaming result");
}

- (void)removeAllRows {
    NSLog(@"Warning: removeAllRows called on read-only PostgreSQL streaming result");
}

#pragma mark - NSFastEnumeration

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state 
                                  objects:(id __unsafe_unretained [])buffer 
                                    count:(NSUInteger)len {
    if (state->state == 0) {
        state->mutationsPtr = &state->extra[0];
    }
    
    pthread_mutex_lock(&_dataLock);
    
    if (state->state >= [_cachedRows count]) {
        pthread_mutex_unlock(&_dataLock);
        return 0;
    }
    
    NSUInteger remaining = [_cachedRows count] - state->state;
    NSUInteger count = MIN(remaining, len);
    
    for (NSUInteger i = 0; i < count; i++) {
        buffer[i] = _cachedRows[state->state + i];
    }
    
    state->itemsPtr = buffer;
    state->state += count;
    
    pthread_mutex_unlock(&_dataLock);
    
    return count;
}

@end
