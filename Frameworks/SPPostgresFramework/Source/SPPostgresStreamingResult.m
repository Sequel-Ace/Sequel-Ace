//
//  SPPostgresStreamingResult.m
//  SPPostgresFramework
//
//  Created by Mehmet Karabulut (mehmetik@gmail.com) on November 30, 2025.
//  Copyright (c) 2025 Mehmet Karabulut.
//  This software is released under the GPL License.
//  This is an open-source project forked from Sequel Ace.
//

#import "SPPostgresStreamingResult.h"

#import "/opt/homebrew/include/postgresql@17/libpq-fe.h"

@implementation SPPostgresStreamingResult

- (instancetype)initWithConnection:(void *)connection {
    self = [super init]; // Don't call initWithPGResult because we don't have a result yet
    if (self) {
        params = connection;
        isFinished = NO;
        currentRowIndex = 0;
        // The first result from PQgetResult might be command status or the first row,
        // but typically in single-row mode, we just start calling getRow.
    }
    return self;
}

- (void)dealloc {
    // Ensure we drain the connection if we are destroyed before finishing
    if (!isFinished && params) {
        [self cancelResultLoad];
    }
}

- (void)cancelResultLoad {
    if (params) {
        // Drain remaining results
        PGresult *res;
        while ((res = PQgetResult((PGconn *)params))) {
            PQclear(res);
        }
        isFinished = YES;
    }
}

- (NSArray *)getRowAsArray {
    if (isFinished || !params) return nil;
    
    PGresult *res = PQgetResult((PGconn *)params);
    
    if (!res) {
        isFinished = YES;
        return nil;
    }
    
    ExecStatusType status = PQresultStatus(res);
    
    if (status == PGRES_SINGLE_TUPLE) {
        // We have a row!
        // We need fields info if we haven't got it yet (populate on first row)
        if (numberOfFields == 0) {
            numberOfFields = PQnfields(res);
            
            // Populate fieldNames array from the result metadata
            NSMutableArray *names = [NSMutableArray arrayWithCapacity:numberOfFields];
            for (int i = 0; i < numberOfFields; i++) {
                char *fname = PQfname(res, i);
                if (fname) {
                    [names addObject:[NSString stringWithUTF8String:fname]];
                } else {
                    [names addObject:[NSString stringWithFormat:@"column%d", i]];
                }
            }
            fieldNames = [NSArray arrayWithArray:names];
        }
        
        // Use the superclass or helper method to parse this single-row result
        // Since SPPostgresResult is designed for a full result set, we need to be careful.
        // We can create a temporary lightweight result or simple parsing here.
        
        NSMutableArray *row = [NSMutableArray arrayWithCapacity:numberOfFields];
        for (int i = 0; i < numberOfFields; i++) {
            if (PQgetisnull(res, 0, i)) {
                [row addObject:[NSNull null]];
            } else {
                char *val = PQgetvalue(res, 0, i);
                [row addObject:[NSString stringWithUTF8String:val]]; // Assuming UTF8Strings for now
            }
        }
        
        PQclear(res);
        currentRowIndex++;
        return row;
    }
    else if (status == PGRES_TUPLES_OK) {
        // End of stream
        PQclear(res);
        isFinished = YES;
        // Drain any remaining null result
        while ((res = PQgetResult((PGconn *)params))) { PQclear(res); }
        return nil;
    }
    else {
        // Error or other status
        PQclear(res);
        isFinished = YES; // Treat error as end of stream for safety
        return nil;
    }
}

- (NSUInteger)numberOfRows {
    // In streaming, we don't know the total. Return current count or -1?
    return currentRowIndex;
}

@end
