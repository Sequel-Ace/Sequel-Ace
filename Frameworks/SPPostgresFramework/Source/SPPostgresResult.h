//
//  SPPostgresResult.h
//  SPPostgresFramework
//
//  Created by Mehmet Karabulut (mehmetik@gmail.com) on November 30, 2025.
//  Copyright (c) 2025 Mehmet Karabulut.
//  This software is released under the GPL License.
//  This is an open-source project forked from Sequel Ace.
//

#import <Foundation/Foundation.h>

typedef void PGresult;

@interface SPPostgresResult : NSObject <NSFastEnumeration> {
    PGresult *resultSet;
    NSUInteger numberOfRows;
    NSUInteger numberOfFields;
    NSArray *fieldNames;
    BOOL returnDataAsStrings;
    NSUInteger currentRowIndex;
}

@property (readwrite, assign) BOOL returnDataAsStrings;

- (instancetype)initWithPGResult:(PGresult *)result;

- (NSUInteger)numberOfFields;
- (NSUInteger)numberOfRows;
- (NSArray *)fieldNames;

- (NSArray *)getRowAsArray;
- (NSDictionary *)getRowAsDictionary;
- (void)seekToRow:(NSUInteger)index;

@end
