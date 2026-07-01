//
//  SPPostgreSQLResultWrapper.m
//  Sequel Ace
//

#import "SPPostgreSQLResultWrapper.h"

@implementation SPPostgreSQLResultWrapper {
    SPPostgreSQLResult *_result;
    NSArray<NSString *> *_fieldNames;
    int _numRows;
    int _numFields;
    double _queryTime;
    unsigned long long _currentRow;
}

- (instancetype)initWithResult:(SPPostgreSQLResult *)result queryTime:(double)queryTime {
    if (self = [super init]) {
        _result = result;
        _queryTime = queryTime;
        _numRows = sp_postgresql_result_num_rows(result);
        _numFields = sp_postgresql_result_num_fields(result);
        _currentRow = 0;

        NSMutableArray *names = [NSMutableArray arrayWithCapacity:_numFields];
        for (int i = 0; i < _numFields; i++) {
            char *name = sp_postgresql_result_field_name(result, i);
            if (name) {
                [names addObject:[NSString stringWithUTF8String:name]];
                sp_postgresql_free_string(name);
            } else {
                [names addObject:[NSString stringWithFormat:@"col%d", i]];
            }
        }
        _fieldNames = [names copy];
    }
    return self;
}

- (void)dealloc {
    if (_result) {
        sp_postgresql_result_destroy(_result);
        _result = NULL;
    }
}

// ─── SPDatabaseResult ────────────────────────────────────────────────────────

- (NSUInteger)numberOfFields       { return (NSUInteger)_numFields; }
- (unsigned long long)numberOfRows { return (unsigned long long)_numRows; }
- (NSArray *)fieldNames            { return _fieldNames; }
- (double)queryExecutionTime       { return _queryTime; }

- (void)seekToRow:(unsigned long long)targetRow {
    _currentRow = MIN(targetRow, (unsigned long long)_numRows);
}

- (NSArray *)getRowAsArray {
    if ((int)_currentRow >= _numRows) return nil;
    int row = (int)_currentRow++;
    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:_numFields];
    for (int col = 0; col < _numFields; col++) {
        char *val = sp_postgresql_result_get_value(_result, row, col);
        if (val) {
            [arr addObject:[NSString stringWithUTF8String:val]];
            sp_postgresql_free_string(val);
        } else {
            [arr addObject:[NSNull null]];
        }
    }
    return [arr copy];
}

- (NSDictionary *)getRowAsDictionary {
    if ((int)_currentRow >= _numRows) return nil;
    int row = (int)_currentRow++;
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:_numFields];
    for (int col = 0; col < _numFields; col++) {
        NSString *key = col < (int)_fieldNames.count ? _fieldNames[col] : [NSString stringWithFormat:@"col%d", col];
        char *val = sp_postgresql_result_get_value(_result, row, col);
        if (val) {
            dict[key] = [NSString stringWithUTF8String:val];
            sp_postgresql_free_string(val);
        } else {
            dict[key] = [NSNull null];
        }
    }
    return [dict copy];
}

- (id)getRow {
    return [self getRowAsArray];
}

// NSFastEnumeration – simple sequential row iteration
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained [])buffer
                                    count:(NSUInteger)len {
    if (state->state == 0) {
        state->mutationsPtr = &state->extra[0];
        state->state = 1;
        _currentRow = 0;
    }
    NSUInteger count = 0;
    while (count < len) {
        NSArray *row = [self getRowAsArray];
        if (!row) break;
        buffer[count++] = row;
    }
    state->itemsPtr = buffer;
    return count;
}

@end
