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
#import "/opt/homebrew/include/postgresql@17/libpq-fe.h"

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

- (NSArray *)getAllRows {
    NSMutableArray *allRows = [NSMutableArray arrayWithCapacity:numberOfRows];
    for (NSUInteger i = 0; i < numberOfRows; i++) {
        NSArray *row = [self getRowAtIndex:i];
        if (row) {
            [allRows addObject:row];
        }
    }
    return [NSArray arrayWithArray:allRows];
}

- (NSArray *)getRow {
    // Alias for getRowAsArray - returns current row and advances
    return [self getRowAsArray];
}

- (NSArray *)getRowsAsArray {
    // Alias for getAllRows
    return [self getAllRows];
}

- (void)setDefaultRowReturnType:(NSInteger)type {
    // This is a no-op for now - can be extended to change how getRow returns data
    // In the original MySQL implementation, this controlled whether rows were arrays or dictionaries
}

#pragma mark - Compatibility Methods

- (void)cancelResultLoad {
    // For PostgreSQL synchronous results, there's nothing to cancel
    // This is a no-op but maintains API compatibility with MySQL streaming results
}

- (NSArray *)fieldDefinitions {
    // Return field definitions as array of dictionaries
    if (!resultSet) return @[];
    
    NSMutableArray *definitions = [NSMutableArray array];
    int numFields = PQnfields(resultSet);
    
    for (int i = 0; i < numFields; i++) {
        NSMutableDictionary *fieldDef = [NSMutableDictionary dictionary];
        
        char *name = PQfname(resultSet, i);
        if (name) {
            [fieldDef setObject:[NSString stringWithUTF8String:name] forKey:@"name"];
        }
        
        Oid typeOid = PQftype(resultSet, i);
        [fieldDef setObject:@(typeOid) forKey:@"type_oid"];
        
        int mod = PQfmod(resultSet, i);
        [fieldDef setObject:@(mod) forKey:@"type_mod"];
        
        [definitions addObject:fieldDef];
    }
    
    return [NSArray arrayWithArray:definitions];
}

- (void)startDownload {
    // For synchronous PostgreSQL results, download happens immediately
    // This is a no-op but maintains API compatibility with MySQL streaming results
}

- (void)setReturnDataAsStrings:(BOOL)flag {
    returnDataAsStrings = flag;
}

@end
