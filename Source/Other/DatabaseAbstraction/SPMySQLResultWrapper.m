//
//  SPMySQLResultWrapper.m
//  Sequel Ace
//

#import "SPMySQLResultWrapper.h"
#import <SPMySQL/SPMySQL.h>

@implementation SPMySQLResultWrapper {
    SPMySQLResult *_result;
}

- (instancetype)initWithResult:(SPMySQLResult *)result {
    if (self = [super init]) {
        _result = result;
    }
    return self;
}

- (SPMySQLResult *)underlyingResult { return _result; }

// SPDatabaseResult

- (NSUInteger)numberOfFields             { return [_result numberOfFields]; }
- (unsigned long long)numberOfRows       { return [_result numberOfRows]; }
- (NSArray *)fieldNames                  { return [_result fieldNames]; }
- (void)seekToRow:(unsigned long long)r  { [_result seekToRow:r]; }
- (id)getRow                             { return [_result getRow]; }
- (NSArray *)getRowAsArray               { return [_result getRowAsArray]; }
- (NSDictionary *)getRowAsDictionary     { return [_result getRowAsDictionary]; }
- (double)queryExecutionTime             { return [_result queryExecutionTime]; }

// NSFastEnumeration
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len {
    return [_result countByEnumeratingWithState:state objects:buffer count:len];
}

@end
