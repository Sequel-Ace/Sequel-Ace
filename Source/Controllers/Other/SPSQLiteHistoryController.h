//
//  SPSQLiteHistoryController.h
//  Sequel Ace
//
//  Created by James on 17/11/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <fmdb/FMDB.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPSQLiteHistoryController : NSObject

@property (atomic, assign) BOOL migratedPrefsToDB;
@property (readwrite, strong) NSMutableDictionary *queryHist;
@property (readwrite, strong) FMDatabaseQueue *queue;

+ (SPSQLiteHistoryController *)sharedSQLiteHistoryController;
- (void)setupQueryHistoryDatabase;
- (void)migrateQueriesFromPrefs;
- (NSNumber*)primaryKeyValueForNewRow;
- (void)loadQueryHistory;
- (void)deleteQueryHistory;
- (void)updateQueryHistory:(NSArray*)newHist;
- (long)idForRowAlreadyInDB:(NSString*)query;
- (void)reloadQueryHistory;

@end

NS_ASSUME_NONNULL_END
