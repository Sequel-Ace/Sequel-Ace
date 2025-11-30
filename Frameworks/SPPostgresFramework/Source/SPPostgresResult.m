//
//  SPPostgresResult.m
//  SPPostgresFramework
//
//  Created by Mehmet Karabulut (mehmetik@gmail.com) on November 30, 2025.
//  Copyright (c) 2025 Mehmet Karabulut.
//  This software is released under the GPL License.
//  This is an open-source project forked from Sequel Ace.
//

#import "SPPostgresResult.h"
#import <libpq-fe.h>

@implementation SPPostgresResult

@synthesize returnDataAsStrings;

- (instancetype)initWithPGResult:(PGresult *)result {
    self = [super init];
    if (self) {
        resultSet = result;
        currentRowIndex = 0;
        if (resultSet) {
            numberOfRows = PQntuples(resultSet);
            numberOfFields = PQnfields(resultSet);
            
            NSMutableArray *names = [NSMutableArray arrayWithCapacity:numberOfFields];
            for (int i = 0; i < numberOfFields; i++) {
                [names addObject:[NSString stringWithUTF8String:PQfname(resultSet, i)]];
            }
            fieldNames = [NSArray arrayWithArray:names];
        }
    }
    return self;
}

- (void)dealloc {
    if (resultSet) {
        PQclear(resultSet);
    }
}

- (NSUInteger)numberOfFields {
    return numberOfFields;
}

- (NSUInteger)numberOfRows {
    return numberOfRows;
}

- (NSArray *)fieldNames {
    return fieldNames;
}

- (void)seekToRow:(NSUInteger)index {
    currentRowIndex = index;
}

- (id)getRowAtIndex:(NSUInteger)index {
    if (index >= numberOfRows) return nil;
    
    NSMutableArray *row = [NSMutableArray arrayWithCapacity:numberOfFields];
    for (int i = 0; i < numberOfFields; i++) {
        if (PQgetisnull(resultSet, (int)index, i)) {
            [row addObject:[NSNull null]];
        } else {
            char *val = PQgetvalue(resultSet, (int)index, i);
            [row addObject:[NSString stringWithUTF8String:val]];
        }
    }
    return row;
}

- (NSArray *)getRowAsArray {
    return [self getRowAtIndex:currentRowIndex++];
}

- (NSDictionary *)getRowAsDictionary {
    NSArray *row = [self getRowAsArray];
    if (!row) return nil;
    
    return [NSDictionary dictionaryWithObjects:row forKeys:fieldNames];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len {
    if (state->state >= numberOfRows) return 0;
    
    state->itemsPtr = buffer;
    state->mutationsPtr = &state->extra[0];
    
    NSUInteger count = 0;
    while (state->state < numberOfRows && count < len) {
        buffer[count] = [self getRowAtIndex:state->state];
        state->state++;
        count++;
    }
    return count;
}

@end
