//
//  SPPostgreSQLStreamingResultWrapper.m
//  Sequel Ace
//

#import "SPPostgreSQLStreamingResultWrapper.h"

@implementation SPPostgreSQLStreamingResultWrapper {
    SPPostgreSQLStreamingResult *_result;
    NSArray<NSString *> *_fieldNames;
    int _numFields;
    double _queryTime;
    unsigned long long _totalRowsFetched;

    // Current in-memory batch state
    int _currentBatchSize;
    int _batchRowIndex;
}

- (instancetype)initWithStreamingResult:(SPPostgreSQLStreamingResult *)result
                              queryTime:(double)queryTime {
    if (self = [super init]) {
        _result = result;
        _queryTime = queryTime;
        _numFields = sp_postgresql_streaming_result_num_fields(result);
        _totalRowsFetched = 0;
        _currentBatchSize = 0;
        _batchRowIndex = 0;

        NSMutableArray *names = [NSMutableArray arrayWithCapacity:_numFields];
        for (int i = 0; i < _numFields; i++) {
            char *name = sp_postgresql_streaming_result_field_name(result, i);
            if (name) {
                [names addObject:[NSString stringWithUTF8String:name]];
                sp_postgresql_free_string(name);
            } else {
                [names addObject:[NSString stringWithFormat:@"col%d", i]];
            }
        }
        _fieldNames = [names copy];

        // Prime the first batch
        [self _fetchNextBatch];
    }
    return self;
}

- (void)dealloc {
    if (_result) {
        sp_postgresql_streaming_result_destroy(_result);
        _result = NULL;
    }
}

- (void)markConnectionDisconnected {
    if (_result) {
        sp_postgresql_streaming_result_mark_disconnected(_result);
    }
}

// ─── Batch management ─────────────────────────────────────────────────────────

- (void)_fetchNextBatch {
    if (!_result || !sp_postgresql_streaming_result_has_more(_result)) {
        _currentBatchSize = 0;
        return;
    }
    // The callback is unused in our API (values fetched via get_batch_value)
    extern int sp_postgresql_streaming_result_next_batch(SPPostgreSQLStreamingResult*, void*, void*);
    int rows = sp_postgresql_streaming_result_next_batch(_result, NULL, NULL);
    _currentBatchSize = MAX(rows, 0);
    _batchRowIndex = 0;
}

// ─── SPDatabaseResult ────────────────────────────────────────────────────────

- (NSUInteger)numberOfFields { return (NSUInteger)_numFields; }

- (unsigned long long)numberOfRows {
    // For streaming results, total rows are unknown until exhausted.
    long long total = _result ? sp_postgresql_streaming_result_total_rows(_result) : 0;
    return total >= 0 ? (unsigned long long)total : _totalRowsFetched;
}

- (NSArray *)fieldNames    { return _fieldNames; }
- (double)queryExecutionTime { return _queryTime; }
- (void)seekToRow:(unsigned long long)row { /* Streaming results cannot seek backwards. */ }

- (NSArray *)getRowAsArray {
    if (!_result) return nil;

    // Advance to the next batch when we run out of rows in the current one.
    while (_batchRowIndex >= _currentBatchSize) {
        if (!sp_postgresql_streaming_result_has_more(_result)) return nil;
        [self _fetchNextBatch];
        if (_currentBatchSize == 0) return nil;
    }

    int batchRow = _batchRowIndex++;
    _totalRowsFetched++;

    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:_numFields];
    for (int col = 0; col < _numFields; col++) {
        char *val = sp_postgresql_streaming_result_get_batch_value(_result, batchRow, col);
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
    NSArray *row = [self getRowAsArray];
    if (!row) return nil;
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:_numFields];
    for (NSUInteger i = 0; i < row.count && i < _fieldNames.count; i++) {
        dict[_fieldNames[i]] = row[i];
    }
    return [dict copy];
}

- (id)getRow { return [self getRowAsArray]; }

// NSFastEnumeration
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained [])buffer
                                    count:(NSUInteger)len {
    if (state->state == 0) {
        state->mutationsPtr = &state->extra[0];
        state->state = 1;
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
