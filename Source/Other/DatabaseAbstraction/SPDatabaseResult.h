//
//  SPDatabaseResult.h
//  Sequel Ace
//
//  Protocol abstracting SPMySQLResult and SPPostgreSQLResultWrapper so
//  controllers need not import a concrete result class.
//

#import <Foundation/Foundation.h>

@protocol SPDatabaseResult <NSObject, NSFastEnumeration>

// Result shape
- (NSUInteger)numberOfFields;
- (unsigned long long)numberOfRows;
- (NSArray *)fieldNames;

// Row retrieval
- (void)seekToRow:(unsigned long long)targetRow;
- (id)getRow;
- (NSArray *)getRowAsArray;
- (NSDictionary *)getRowAsDictionary;

// Timing
- (double)queryExecutionTime;

@end
