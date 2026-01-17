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
@synthesize delegate = _delegate;

- (instancetype)initWithPGResult:(PGresult *)result {
    self = [super init];
    if (self) {
        resultSet = result;
        currentRowIndex = 0;

        // DEBUG: Log PGresult details
        if (resultSet) {
            int tuples = PQntuples(resultSet);
            int fields = PQnfields(resultSet);
            NSLog(@"[PG-DEBUG] SPPostgresResult.init: tuples=%d, fields=%d, resultSet=%p", tuples, fields, resultSet);

            numberOfRows = (tuples < 0) ? 0 : (NSUInteger)tuples;
            numberOfFields = (fields < 0) ? 0 : (NSUInteger)fields;

            NSMutableArray *names = [NSMutableArray arrayWithCapacity:numberOfFields];
            for (int i = 0; i < (int)numberOfFields; i++) {
                char *fname = PQfname(resultSet, i);
                if (fname) {
                    [names addObject:[NSString stringWithUTF8String:fname]];
                } else {
                    [names addObject:[NSString stringWithFormat:@"column_%d", i]];
                }
            }
            fieldNames = [NSArray arrayWithArray:names];
            NSLog(@"[PG-DEBUG] SPPostgresResult.init: fieldNames=%@", fieldNames);
        } else {
            NSLog(@"[PG-DEBUG] SPPostgresResult.init: resultSet is NULL!");
            numberOfRows = 0;
            numberOfFields = 0;
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
    if (!resultSet) {
        NSLog(@"[PG-DEBUG] SPPostgresResult.numberOfRows called but resultSet is NULL, returning %lu", (unsigned long)numberOfRows);
    }
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
            // Safety check: PQgetvalue can return NULL in edge cases
            if (val == NULL) {
                [row addObject:[NSNull null]];
                continue;
            }
            NSString *strVal = [NSString stringWithUTF8String:val];
            if (strVal) {
                [row addObject:strVal];
            } else {
                // Invalid UTF-8, try Latin1 or fallback to data
                strVal = [NSString stringWithCString:val encoding:NSISOLatin1StringEncoding];
                if (strVal) {
                    [row addObject:strVal];
                } else {
                    // Fallback to storing as NSData or string representation of data for now
                    // Sequel Ace tables expect strings mostly
                    [row addObject:[[NSData dataWithBytes:val length:strlen(val)] description]];
                }
            }
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

- (NSDictionary *)getRowAsDictionaryAtIndex:(NSUInteger)index {
    if (index >= numberOfRows) return nil;
    
    NSMutableArray *row = [NSMutableArray arrayWithCapacity:numberOfFields];
    for (int i = 0; i < numberOfFields; i++) {
        if (PQgetisnull(resultSet, (int)index, i)) {
            [row addObject:[NSNull null]];
        } else {
            char *val = PQgetvalue(resultSet, (int)index, i);
            // Safety check: PQgetvalue can return NULL in edge cases
            if (val == NULL) {
                [row addObject:[NSNull null]];
                continue;
            }
            NSString *strVal = [NSString stringWithUTF8String:val];
            if (strVal) {
                [row addObject:strVal];
            } else {
                strVal = [NSString stringWithCString:val encoding:NSISOLatin1StringEncoding];
                if (strVal) {
                    [row addObject:strVal];
                } else {
                    [row addObject:[[NSData dataWithBytes:val length:strlen(val)] description]];
                }
            }
        }
    }
    return [NSDictionary dictionaryWithObjects:row forKeys:fieldNames];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len {
    // On first call (state == 0), pre-cache all rows to ensure they stay alive
    if (state->state == 0) {
        if (!cachedRows) {
            cachedRows = [[NSMutableArray alloc] initWithCapacity:numberOfRows];
            for (NSUInteger i = 0; i < numberOfRows; i++) {
                NSDictionary *row = [self getRowAsDictionaryAtIndex:i];
                if (row) {
                    [cachedRows addObject:row];
                }
            }
        }
    }
    
    if (state->state >= [cachedRows count]) return 0;
    
    state->itemsPtr = buffer;
    state->mutationsPtr = &state->extra[0];
    
    NSUInteger count = 0;
    while (state->state < [cachedRows count] && count < len) {
        // Use cached rows which are retained by the array
        buffer[count] = [cachedRows objectAtIndex:state->state];
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
    // Alias for getAllRows - returns array of arrays
    return [self getAllRows];
}

- (NSArray *)getAllRowsAsDictionaries {
    // Returns array of dictionaries for code expecting NSDictionary rows
    NSMutableArray *allRows = [NSMutableArray arrayWithCapacity:numberOfRows];
    for (NSUInteger i = 0; i < numberOfRows; i++) {
        NSDictionary *row = [self getRowAsDictionaryAtIndex:i];
        if (row) {
            [allRows addObject:row];
        }
    }
    return [NSArray arrayWithArray:allRows];
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
    if (!resultSet) {
        NSLog(@"[PG-DEBUG] fieldDefinitions: resultSet is NULL, returning empty array");
        return @[];
    }

    int numFields = PQnfields(resultSet);
    NSLog(@"[PG-DEBUG] fieldDefinitions: Building definitions for %d fields", numFields);

    NSMutableArray *definitions = [NSMutableArray array];

    for (int i = 0; i < numFields; i++) {
        NSMutableDictionary *fieldDef = [NSMutableDictionary dictionary];

        // Column name
        char *name = PQfname(resultSet, i);
        NSString *columnName = name ? [NSString stringWithUTF8String:name] : @"";
        [fieldDef setObject:columnName forKey:@"name"];
        [fieldDef setObject:columnName forKey:@"org_name"];

        // Column index (as string, used as table column identifier)
        [fieldDef setObject:[NSString stringWithFormat:@"%d", i] forKey:@"datacolumnindex"];

        // Type OID and modifier
        Oid typeOid = PQftype(resultSet, i);
        [fieldDef setObject:@(typeOid) forKey:@"type_oid"];

        int mod = PQfmod(resultSet, i);
        [fieldDef setObject:@(mod) forKey:@"type_mod"];

        // Map OID to type name and typegrouping
        NSString *typeName = [self typeNameForOid:typeOid];
        NSString *typegrouping = [self typegroupingForOid:typeOid];
        [fieldDef setObject:typeName forKey:@"type"];
        [fieldDef setObject:typegrouping forKey:@"typegrouping"];

        // Calculate char_length from type modifier for varchar/char types
        NSString *charLength = @"";
        if (typeOid == 1043 || typeOid == 1042) { // varchar or char
            if (mod > 4) {
                charLength = [NSString stringWithFormat:@"%d", mod - 4];
            }
        } else if (typeOid == 1700) { // numeric
            if (mod >= 4) {
                int precision = ((mod - 4) >> 16) & 0xFFFF;
                int scale = (mod - 4) & 0xFFFF;
                charLength = [NSString stringWithFormat:@"%d,%d", precision, scale];
            }
        }
        [fieldDef setObject:charLength forKey:@"char_length"];

        // Table and database info (may not be available for computed columns)
        Oid tableOid = PQftable(resultSet, i);
        if (tableOid != 0) {
            [fieldDef setObject:@(tableOid) forKey:@"table_oid"];
        }
        [fieldDef setObject:@"" forKey:@"org_table"];
        [fieldDef setObject:@"" forKey:@"db"];

        [definitions addObject:fieldDef];
    }

    NSLog(@"[PG-DEBUG] fieldDefinitions: Returning %lu definitions", (unsigned long)[definitions count]);
    return [NSArray arrayWithArray:definitions];
}

// Map PostgreSQL OID to type name
- (NSString *)typeNameForOid:(Oid)oid {
    switch (oid) {
        case 16: return @"boolean";
        case 17: return @"bytea";
        case 20: return @"bigint";
        case 21: return @"smallint";
        case 23: return @"integer";
        case 25: return @"text";
        case 700: return @"real";
        case 701: return @"double precision";
        case 1042: return @"char";
        case 1043: return @"varchar";
        case 1082: return @"date";
        case 1083: return @"time";
        case 1114: return @"timestamp";
        case 1184: return @"timestamptz";
        case 1700: return @"numeric";
        case 2950: return @"uuid";
        case 114: return @"json";
        case 3802: return @"jsonb";
        case 1007: return @"integer[]";
        case 1009: return @"text[]";
        default: return @"unknown";
    }
}

// Map PostgreSQL OID to typegrouping (used for UI formatting)
- (NSString *)typegroupingForOid:(Oid)oid {
    switch (oid) {
        // Integers
        case 20: case 21: case 23: case 26: // bigint, smallint, int, oid
        case 1005: case 1007: case 1016:    // int arrays
            return @"integer";
        // Floats
        case 700: case 701: case 1700:      // real, double, numeric
            return @"float";
        // Strings
        case 1042: case 1043:               // char, varchar
            return @"string";
        // Text data
        case 25:                            // text
        case 114: case 3802:                // json, jsonb
            return @"textdata";
        // Binary
        case 17:                            // bytea
            return @"blobdata";
        // Boolean
        case 16:                            // boolean
            return @"bit";
        // Date/time
        case 1082: case 1083: case 1114: case 1184: // date, time, timestamp
            return @"date";
        default:
            return @"string";
    }
}

- (void)startDownload {
    // For synchronous PostgreSQL results, download happens immediately
    // This is a no-op but maintains API compatibility with MySQL streaming results
}

- (void)setReturnDataAsStrings:(BOOL)flag {
    returnDataAsStrings = flag;
}

- (double)queryExecutionTime {
    // PostgreSQL doesn't provide query execution time in the result
    // Would need to be tracked at query execution time in SPPostgresConnection
    return 0.0;
}

- (void)setDelegate:(id)aDelegate {
    _delegate = aDelegate;
}

- (BOOL)dataDownloaded {
    // PostgreSQL results are synchronous - data is always fully downloaded
    return YES;
}

@end
