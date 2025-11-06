//
//  SPPostgreSQLResultWrapper.m
//  Sequel Ace
//
//  Created for PostgreSQL abstraction support
//

#import "SPPostgreSQLResultWrapper.h"
#import "SPPostgreSQLConnectionWrapper.h"
#import "SPPostgreSQLTypeMapper.h"
#import "sppostgresql_ffi.h"

@interface SPPostgreSQLResultWrapper ()
{
    SPPostgreSQLResult *_pgResult;
    __weak SPPostgreSQLConnectionWrapper *_connection;
    NSUInteger _currentRow;
    BOOL _returnDataAsStrings;
    NSArray *_fieldDefinitions;
    NSArray *_cachedFieldNames; // Cache for field names
    NSArray *_cachedRows; // Cache for enumeration
    BOOL _returnRowsAsDictionaries; // Whether to return rows as dictionaries or arrays
}
@end

@implementation SPPostgreSQLResultWrapper

@synthesize pgResult = _pgResult;

#pragma mark - Initialization

- (instancetype)initWithPGResult:(SPPostgreSQLResult *)result connection:(SPPostgreSQLConnectionWrapper *)connection {
    self = [super init];
    if (self) {
        _pgResult = result;
        _connection = connection;
        _currentRow = 0;
        _returnDataAsStrings = NO;
        _fieldDefinitions = nil;
        _returnRowsAsDictionaries = NO; // Default to arrays, like MySQL
    }
    return self;
}

- (void)dealloc {
    if (_pgResult != NULL) {
        sp_postgresql_result_destroy(_pgResult);
        _pgResult = NULL;
    }
}

#pragma mark - Delegate

- (id)delegate {
    return nil; // Delegate not used in PostgreSQL results
}

- (void)setDelegate:(id)delegate {
    // No-op for PostgreSQL results
    // Delegate callbacks aren't needed for our implementation
}

- (BOOL)dataDownloaded {
    // PostgreSQL results don't stream, all data is available immediately
    return YES;
}

#pragma mark - Result Navigation

- (void)seekToRow:(NSUInteger)row {
    _currentRow = row;
}

#pragma mark - Data Format Options

- (void)setReturnDataAsStrings:(BOOL)asStrings {
    _returnDataAsStrings = asStrings;
}

- (void)setDefaultRowReturnType:(SPDatabaseResultRowType)defaultRowReturnType {
    // SPDatabaseResultRowAsDefault = 0 -> dictionary
    // SPDatabaseResultRowAsArray = 1 -> array
    // SPDatabaseResultRowAsDictionary = 2 -> dictionary
    if (defaultRowReturnType == SPDatabaseResultRowAsArray) {
        _returnRowsAsDictionaries = NO;
    } else {
        _returnRowsAsDictionaries = YES;
    }
}

#pragma mark - Result Information

- (unsigned long long)numberOfRows {
    if (_pgResult == NULL) {
        return 0;
    }
    return (unsigned long long)sp_postgresql_result_num_rows(_pgResult);
}

- (NSUInteger)numberOfFields {
    if (_pgResult == NULL) {
        return 0;
    }
    return (NSUInteger)sp_postgresql_result_num_fields(_pgResult);
}

- (double)queryExecutionTime {
    // Not tracked in the FFI for now
    return 0.0;
}

#pragma mark - Fetching Data

- (NSArray *)getRowAsArray {
    if (_pgResult == NULL || _currentRow >= [self numberOfRows]) {
        return nil;
    }
    
    NSUInteger fieldCount = [self numberOfFields];
    NSMutableArray *row = [NSMutableArray arrayWithCapacity:fieldCount];
    
    for (NSUInteger col = 0; col < fieldCount; col++) {
        char *valueCStr = sp_postgresql_result_get_value(_pgResult, (int)_currentRow, (int)col);
        
        if (valueCStr == NULL) {
            [row addObject:[NSNull null]];
        } else {
            NSString *value = [NSString stringWithUTF8String:valueCStr];
            sp_postgresql_free_string(valueCStr);
            
            // If not returning as strings, try to convert to appropriate type
            if (!_returnDataAsStrings) {
                // For now, return as string. In a full implementation, we'd check
                // the PostgreSQL type and convert accordingly
                [row addObject:value];
            } else {
                [row addObject:value];
            }
        }
    }
    
    _currentRow++;
    return row;
}

- (NSDictionary *)getRowAsDictionary {
    if (_pgResult == NULL || _currentRow >= [self numberOfRows]) {
        return nil;
    }
    
    NSArray *fields = [self fieldNames];
    NSArray *values = [self getRowAsArray];
    
    if (!fields || !values || [fields count] != [values count]) {
        return nil;
    }
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:[fields count]];
    for (NSUInteger i = 0; i < [fields count]; i++) {
        dict[fields[i]] = values[i];
    }
    
    return [dict copy];
}

- (id)getRow {
    return [self getRowAsArray];
}

- (NSArray *)getAllRows {
    if (_pgResult == NULL) {
        return @[];
    }
    
    NSUInteger totalRows = [self numberOfRows];
    NSMutableArray *allRows = [NSMutableArray arrayWithCapacity:totalRows];
    NSUInteger savedRow = _currentRow;
    
    _currentRow = 0;
    while (_currentRow < [self numberOfRows]) {
        NSArray *row = [self getRowAsArray];
        if (row) {
            [allRows addObject:row];
        }
    }
    
    _currentRow = savedRow;
    return [allRows copy];
}

- (NSArray<NSDictionary *> *)getAllRowsAsDictionaries {
    if (_pgResult == NULL) {
        return @[];
    }
    
    NSUInteger totalRows = [self numberOfRows];
    NSMutableArray *allRows = [NSMutableArray arrayWithCapacity:totalRows];
    NSUInteger savedRow = _currentRow;
    
    _currentRow = 0;
    while (_currentRow < [self numberOfRows]) {
        NSDictionary *row = [self getRowAsDictionary];
        if (row) {
            [allRows addObject:row];
        }
    }
    
    _currentRow = savedRow;
    return [allRows copy];
}

#pragma mark - Field Information

- (NSArray *)fieldNames {
    // Cache field names since they don't change
    if (_cachedFieldNames) {
        return _cachedFieldNames;
    }
    
    if (_pgResult == NULL) {
        return @[];
    }
    
    NSUInteger fieldCount = [self numberOfFields];
    NSMutableArray *names = [NSMutableArray arrayWithCapacity:fieldCount];
    
    for (NSUInteger i = 0; i < fieldCount; i++) {
        char *nameCStr = sp_postgresql_result_field_name(_pgResult, (int)i);
        if (nameCStr) {
            [names addObject:[NSString stringWithUTF8String:nameCStr]];
            sp_postgresql_free_string(nameCStr);
        } else {
            [names addObject:@""];
        }
    }
    
    _cachedFieldNames = [names copy];
    return _cachedFieldNames;
}

- (NSArray *)fieldDefinitions {
    if (_fieldDefinitions) {
        return _fieldDefinitions;
    }
    
    if (_pgResult == NULL) {
        return @[];
    }
    
    NSUInteger fieldCount = [self numberOfFields];
    NSMutableArray *definitions = [NSMutableArray arrayWithCapacity:fieldCount];
    
    for (NSUInteger i = 0; i < fieldCount; i++) {
        char *nameCStr = sp_postgresql_result_field_name(_pgResult, (int)i);
        NSString *name = @"";
        if (nameCStr) {
            name = [NSString stringWithUTF8String:nameCStr];
            sp_postgresql_free_string(nameCStr);
        }
        
        // Create a field definition dictionary compatible with MySQL format
        // This ensures compatibility with SPCopyTable and other components that expect MySQL-style metadata
        NSMutableDictionary *definition = [NSMutableDictionary dictionary];
        
        // REQUIRED: Record the original column position within the result set (must never be nil)
        [definition setObject:[NSString stringWithFormat:@"%lu", (unsigned long)i] forKey:@"datacolumnindex"];
        
        // REQUIRED: Record the column name (must never be nil, but can be empty string)
        [definition setObject:name forKey:@"name"];
        
        // Get actual PostgreSQL type information using OID
        uint32_t typeOID = sp_postgresql_result_field_type_oid(_pgResult, (int)i);
        NSString *typeName = [SPPostgreSQLTypeMapper typeNameForOID:typeOID];
        NSString *typeGrouping = [SPPostgreSQLTypeMapper typeGroupingForOID:typeOID];
        
        [definition setObject:typeName forKey:@"type"];
        [definition setObject:typeGrouping forKey:@"typegrouping"];
        
        // Length information
        [definition setObject:@(0) forKey:@"byte_length"];
        [definition setObject:@(0) forKey:@"char_length"];
        [definition setObject:@(0) forKey:@"max_byte_length"];
        [definition setObject:@(0) forKey:@"decimals"];
        
        // Charset information - PostgreSQL uses UTF8
        [definition setObject:@(0) forKey:@"charsetnr"];
        [definition setObject:@"UTF8" forKey:@"charset_name"];
        [definition setObject:@"UTF8" forKey:@"charset_collation"];
        
        // Flag information - default to permissive values
        [definition setObject:@(0) forKey:@"flags"];
        [definition setObject:@(NO) forKey:@"null"];
        [definition setObject:@(NO) forKey:@"PRI_KEY_FLAG"];
        [definition setObject:@(NO) forKey:@"UNIQUE_KEY_FLAG"];
        [definition setObject:@(NO) forKey:@"MULTIPLE_KEY_FLAG"];
        [definition setObject:@(NO) forKey:@"BLOB_FLAG"];
        [definition setObject:@(NO) forKey:@"UNSIGNED_FLAG"];
        [definition setObject:@(NO) forKey:@"ZEROFILL_FLAG"];
        [definition setObject:@(NO) forKey:@"BINARY_FLAG"];
        [definition setObject:@(NO) forKey:@"ENUM_FLAG"];
        [definition setObject:@(NO) forKey:@"AUTO_INCREMENT_FLAG"];
        [definition setObject:@(NO) forKey:@"SET_FLAG"];
        [definition setObject:@(NO) forKey:@"NUM_FLAG"];
        [definition setObject:@(NO) forKey:@"PART_KEY_FLAG"];
        
        [definitions addObject:[definition copy]];
    }
    
    _fieldDefinitions = [definitions copy];
    return _fieldDefinitions;
}

#pragma mark - NSFastEnumeration

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained *)stackbuf count:(NSUInteger)len {
    // On first call (state->state == 0), cache all rows
    if (state->state == 0) {
        // Use the default row return type to determine whether to return arrays or dictionaries
        if (_returnRowsAsDictionaries) {
            _cachedRows = [self getAllRowsAsDictionaries];
        } else {
            _cachedRows = [self getAllRows];
        }
        state->mutationsPtr = &state->extra[0];
    }
    
    // Check if we've enumerated all rows
    if (state->state >= [_cachedRows count]) {
        return 0;
    }
    
    // Calculate how many items we can return in this batch
    NSUInteger remaining = [_cachedRows count] - state->state;
    NSUInteger batchSize = MIN(remaining, len);
    
    // Copy items from cached rows to the stack buffer
    for (NSUInteger i = 0; i < batchSize; i++) {
        stackbuf[i] = _cachedRows[state->state + i];
    }
    
    // Update state
    state->itemsPtr = stackbuf;
    state->state += batchSize;
    
    return batchSize;
}

#pragma mark - Streaming Result Methods

- (void)startDownload {
    // PostgreSQL results don't stream, no-op
}

- (void)cancelResultLoad {
    // PostgreSQL results don't stream, no-op
}

#pragma mark - Row-Level Access

- (NSMutableArray *)rowContentsAtIndex:(NSUInteger)rowIndex {
    [self seekToRow:rowIndex];
    NSArray *row = [self getRowAsArray];
    if (row) {
        return [row mutableCopy];
    }
    
    // Return an array of NSNull values for empty/dummy rows
    NSUInteger fieldCount = [self numberOfFields];
    NSMutableArray *emptyRow = [NSMutableArray arrayWithCapacity:fieldCount];
    for (NSUInteger i = 0; i < fieldCount; i++) {
        [emptyRow addObject:[NSNull null]];
    }
    return emptyRow;
}

- (id)cellDataAtRow:(NSUInteger)rowIndex column:(NSUInteger)columnIndex {
    if (_pgResult == NULL || rowIndex >= [self numberOfRows] || columnIndex >= [self numberOfFields]) {
        return [NSNull null];
    }
    
    char *valueCStr = sp_postgresql_result_get_value(_pgResult, (int)rowIndex, (int)columnIndex);
    
    if (valueCStr == NULL) {
        return [NSNull null];
    }
    
    NSString *value = [NSString stringWithUTF8String:valueCStr];
    sp_postgresql_free_string(valueCStr);
    
    return value;
}

- (id)cellPreviewAtRow:(NSUInteger)rowIndex column:(NSUInteger)columnIndex previewLength:(NSUInteger)previewLength {
    id cellData = [self cellDataAtRow:rowIndex column:columnIndex];
    if ([cellData isKindOfClass:[NSString class]]) {
        NSString *str = (NSString *)cellData;
        if ([str length] > previewLength) {
            return [str substringToIndex:previewLength];
        }
    }
    return cellData;
}

- (BOOL)cellIsNullAtRow:(NSUInteger)rowIndex column:(NSUInteger)columnIndex {
    id cellData = [self cellDataAtRow:rowIndex column:columnIndex];
    return cellData == nil || cellData == [NSNull null];
}

#pragma mark - Row Manipulation

- (void)addDummyRow {
    // Not implemented for PostgreSQL - would need mutable result storage
    NSLog(@"Warning: addDummyRow not implemented for PostgreSQL results");
}

- (void)insertDummyRowAtIndex:(NSUInteger)anIndex {
    // Not implemented for PostgreSQL
    NSLog(@"Warning: insertDummyRowAtIndex not implemented for PostgreSQL results");
}

- (void)removeRowAtIndex:(NSUInteger)anIndex {
    // Not implemented for PostgreSQL
    NSLog(@"Warning: removeRowAtIndex not implemented for PostgreSQL results");
}

- (void)removeRowsInRange:(NSRange)rangeToRemove {
    // Not implemented for PostgreSQL
    NSLog(@"Warning: removeRowsInRange not implemented for PostgreSQL results");
}

- (void)removeAllRows {
    // Not implemented for PostgreSQL
    NSLog(@"Warning: removeAllRows not implemented for PostgreSQL results");
}

- (unsigned long long)affectedRows {
    if (_pgResult == NULL) {
        return 0;
    }
    return sp_postgresql_result_affected_rows(_pgResult);
}

@end
