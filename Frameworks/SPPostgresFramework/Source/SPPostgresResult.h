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

// Forward declaration for PGresult - actual definition comes from libpq
typedef struct pg_result PGresult;

@interface SPPostgresResult : NSObject <NSFastEnumeration> {
    PGresult *resultSet;
    NSUInteger numberOfRows;
    NSUInteger numberOfFields;
    NSArray *fieldNames;
    BOOL returnDataAsStrings;
    NSUInteger currentRowIndex;
    NSMutableArray *cachedRows; // Retains rows during enumeration to prevent deallocation
}

@property (readwrite, assign) BOOL returnDataAsStrings;

- (instancetype)initWithPGResult:(PGresult *)result;

- (NSUInteger)numberOfFields;
- (NSUInteger)numberOfRows;
- (NSArray *)fieldNames;

- (NSArray *)getRowAsArray;
- (NSDictionary *)getRowAsDictionary;
- (void)seekToRow:(NSUInteger)index;
- (NSArray *)getAllRows;
- (NSArray *)getRow;
- (NSArray *)getRowsAsArray;
- (NSArray *)getAllRowsAsDictionaries;
- (void)setDefaultRowReturnType:(NSInteger)type;

// Additional methods for compatibility
- (void)cancelResultLoad;
- (NSArray *)fieldDefinitions;
- (void)startDownload;
- (void)setReturnDataAsStrings:(BOOL)flag;
- (double)queryExecutionTime;

// Delegate support
@property (nonatomic, weak) id delegate;
- (void)setDelegate:(id)aDelegate;

// Data loading status
- (BOOL)dataDownloaded;

@end

// Row return type constants
typedef NS_ENUM(NSInteger, SPPostgresResultRowType) {
    SPPostgresResultRowAsArray = 0,
    SPPostgresResultRowAsDictionary = 1
};

// Result return type constants
typedef NS_ENUM(NSInteger, SPPostgresResultType) {
    SPPostgresResultAsResult = 0,
    SPPostgresResultAsArray = 1,
    SPPostgresResultAsDictionary = 2
};
