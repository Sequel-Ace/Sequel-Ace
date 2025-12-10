//
//  SPPostgresStreamingResult.h
//  SPPostgresFramework
//
//  Created by Mehmet Karabulut (mehmetik@gmail.com) on November 30, 2025.
//  Copyright (c) 2025 Mehmet Karabulut.
//  This software is released under the GPL License.
//  This is an open-source project forked from Sequel Ace.
//

#import "SPPostgresResult.h"

@interface SPPostgresStreamingResult : SPPostgresResult {
    void *params; // PGconn
    BOOL isFinished;
}

- (instancetype)initWithConnection:(void *)connection;
- (void)cancelResultLoad;

@end
