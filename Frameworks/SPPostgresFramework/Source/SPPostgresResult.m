//
//  SPPostgresResult.m
//  SPPostgresFramework
//
//  Created by Sequel-PAce on 2025.
//

#import "SPPostgresResult.h"

@interface SPPostgresResult ()
@property (nonatomic, strong) NSArray<NSDictionary *> *rows;
@property (nonatomic, strong) NSArray<NSString *> *fieldNames;
@property (nonatomic, assign) NSUInteger currentRowIndex;
@end

@implementation SPPostgresResult

- (instancetype)initWithRows:(NSArray<NSDictionary *> *)rows fieldNames:(NSArray<NSString *> *)fieldNames {
    self = [super init];
    if (self) {
        _rows = rows;
        _fieldNames = fieldNames;
        _currentRowIndex = 0;
    }
    return self;
}

- (NSUInteger)numberOfRows {
    return self.rows.count;
}

- (NSUInteger)numberOfFields {
    return self.fieldNames.count;
}

- (NSDictionary *)getRowAsDictionary {
    if (self.currentRowIndex < self.rows.count) {
        return self.rows[self.currentRowIndex++];
    }
    return nil;
}

- (NSArray *)getRowAsArray {
    if (self.currentRowIndex < self.rows.count) {
        NSDictionary *row = self.rows[self.currentRowIndex++];
        NSMutableArray *array = [NSMutableArray arrayWithCapacity:self.fieldNames.count];
        for (NSString *field in self.fieldNames) {
            id val = row[field];
            [array addObject:val ? val : [NSNull null]];
        }
        return array;
    }
    return nil;
}

- (void)setReturnDataAsStrings:(BOOL)asStrings {
    // No-op for now, assuming strings are returned by default
}

@end
