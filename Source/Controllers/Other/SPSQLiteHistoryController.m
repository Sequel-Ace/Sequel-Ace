//
//  SPSQLiteHistoryController.m
//  Sequel Ace
//
//  Created by James on 17/11/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

#import "SPSQLiteHistoryController.h"
#import "SPFunctions.h"

#define FMDBQuickCheck(SomeBool) { if ((SomeBool)) { NSLog(@"Failure on line %d", __LINE__); /*abort();*/ } }

typedef void (^SASchemaBuilder)(FMDatabase *db, int *schemaVersion);

@interface SPSQLiteHistoryController ()

@property (readwrite, strong) NSUserDefaults *prefs;
@property (readwrite, strong) NSFileManager *fileManager;
@property (readwrite, copy) NSString *sqlitePath;
@property (readwrite, copy) NSString *dbSizeHumanReadable;
@property (nonatomic, assign) long dbSize;

@end

@implementation SPSQLiteHistoryController

@synthesize queue, prefs, fileManager, migratedPrefsToDB, queryHist, sqlitePath, dbSizeHumanReadable, dbSize;

static SPSQLiteHistoryController *sharedSQLiteHistoryControllerr = nil;

+ (SPSQLiteHistoryController *)sharedSQLiteHistoryController
{
	static dispatch_once_t onceToken;
	
	if (sharedSQLiteHistoryControllerr == nil) {
		dispatch_once_on_main_thread(&onceToken, ^{
			sharedSQLiteHistoryControllerr = [[SPSQLiteHistoryController alloc] init];
		});
	}
	
	return sharedSQLiteHistoryControllerr;
}

- (instancetype)init
{
	if ((self = [super init])) {
		
		prefs = [NSUserDefaults standardUserDefaults];
		fileManager = [NSFileManager defaultManager];
		queryHist = [[NSMutableDictionary alloc] init];
		dbSize = 0;
		dbSizeHumanReadable = nil;
		
		NSError *error = nil;
		sqlitePath = [NSString stringWithFormat:@"%@/%@",[fileManager applicationSupportDirectoryForSubDirectory:SPDataSupportFolder error:&error], @"queryHistory.db"];
		
		if(error != nil){
			SPLog(@"Problem opening db - %@ : %@",error.localizedDescription, error.localizedRecoverySuggestion);
			return self; // ??
		}
		
		SPLog(@"Is SQLite compiled with it's thread safe options turned on? %@!", [FMDatabase isSQLiteThreadSafe] ? @"Yes" : @"No");
		
		[self setupQueryHistoryDatabase];
		
		migratedPrefsToDB = user_defaults_get_bool_ud(SPMigratedQueriesFromPrefs, prefs);
		if(migratedPrefsToDB == NO){
			[self migrateQueriesFromPrefs]; // sets queryHist
		}
		else{
			[self loadQueryHistory];
		}
		
		[self getDBsize];
		
		SPLog(@"sqliteLibVersion = %@", [FMDatabase sqliteLibVersion]);
		
		return self;
	}
	
	return nil;
}

- (long)idForRowAlreadyInDB:(NSString*)query{
		
	if(!queue){
		SPLog(@"reopening queue");
		queue = [FMDatabaseQueue databaseQueueWithPath:sqlitePath];
	}
	
	long __block idForExistingRow = 0;
	
	[queue inDatabase:^(FMDatabase *db) {
		
		FMResultSet *rs = [db executeQuery:@"SELECT id FROM QueryHistory where query = ?", query];
		while ([rs next]) {
			idForExistingRow = [rs longForColumn:@"id"];
		}
		[rs close];
	}];
	
	return idForExistingRow;
}

- (void)updateQueryHistory:(NSArray*)newHist{
	
	executeOnBackgroundThread(^{
		
		if(!self->queue){
			SPLog(@"reopening queue");
			self->queue = [FMDatabaseQueue databaseQueueWithPath:self->sqlitePath];
		}
		
		BOOL __block success = NO;
		
		for(id obj in newHist){
			
			if([obj isKindOfClass:[NSString class]] && [(NSString *)obj length]){
				// JCS - not sure we need this check .. just insert or ignore....
				long idForExistingRow = [self idForRowAlreadyInDB:obj];
				
				if (idForExistingRow > 0){
					
					[self->queue inDatabase:^(FMDatabase *db) {
						//db.traceExecution = YES;
						
						success = [db executeUpdate:@"UPDATE QueryHistory set modifiedTime = ? where id = ?", [NSDate date], @(idForExistingRow)];
						
						if (!success) {
							FMDBQuickCheck([db hadError]);
							if ([db hadError]) {
								SPLog(@"Err %d: %@", [db lastErrorCode], [db lastErrorMessage]);
							}
						}
//						SPLog(@"UPDATED = %ld, %@", idForExistingRow, obj);
						// no else - nothing to update on the queryHist array
					}];
				}
				else{
					// if this is not unique then it's going to break
					// we could check, but max 100 items ... probability of clash is low.
					NSNumber *newKeyValue = [self primaryKeyValueForNewRow];
					
//					SPLog(@"newKeyValue: %@", newKeyValue);
					
					[self->queue inDatabase:^(FMDatabase *db) {
						success = [db executeUpdate:@"INSERT OR IGNORE INTO QueryHistory (id, query, createdTime) VALUES (?, ?, ?)", newKeyValue, obj, [NSDate date]];
						
						if (success) {
							[self->queryHist safeSetObject:obj forKey:newKeyValue];
//							SPLog(@"INSERTED = %@, %@", newKeyValue, obj);
						}
						else{
							FMDBQuickCheck([db hadError]);
							if ([db hadError]) {
								SPLog(@"Err %d: %@", [db lastErrorCode], [db lastErrorMessage]);
							}
						}
					}];
				}
			}
			
			if (!success) {
				break;
			}
		}
		if(success == YES){
			SPLog(@"query history updated");
		}
		
		[self vac];
		[self getDBsize];
		[self->queue close];
	});
}

- (void)vac{
	
	executeOnBackgroundThread(^{
		if(!self->queue){
			SPLog(@"reopening queue");
			self->queue = [FMDatabaseQueue databaseQueueWithPath:self->sqlitePath];
		}
		[self->queue inDatabase:^(FMDatabase *db) {
			[db executeUpdate:@"vacuum"];
			FMDBQuickCheck([db hadError]);
			if ([db hadError]) {
				SPLog(@"Err %d: %@", [db lastErrorCode], [db lastErrorMessage]);
			}
		}];
	});
}

- (void)deleteQueryHistory{
	
	executeOnBackgroundThread(^{
		SPLog(@"JIMMY deleteQueryHistory");
		
		if(!self->queue){
			SPLog(@"reopening queue");
			self->queue = [FMDatabaseQueue databaseQueueWithPath:self->sqlitePath];
		}
		[self->queue inDatabase:^(FMDatabase *db) {
			if([db executeUpdate:@"DELETE FROM QueryHistory"]){
				[self->queryHist removeAllObjects];
			}
			
			if ([db hadError]) {
				SPLog(@"Err %d: %@", [db lastErrorCode], [db lastErrorMessage]);
			}
		}];
		
		[self vac];
		[self getDBsize];
		[self->queue close];
	});
	
}

- (void)reloadQueryHistory{
	
	executeOnBackgroundThread(^{
		[self->queryHist removeAllObjects];
		[self loadQueryHistory];
	});
}

- (void)loadQueryHistory{
	
	SPLog(@"JIMMY loadQueryHistory");
	
	if(!queue){
		SPLog(@"reopening queue");
		queue = [FMDatabaseQueue databaseQueueWithPath:sqlitePath];
	}
	
	[queue inDatabase:^(FMDatabase *db) {
		
		FMResultSet *rs = [db executeQuery:@"SELECT id, query FROM QueryHistory order by createdTime"];
		while ([rs next]) {
			//retrieve values for each record
			[queryHist safeSetObject:[rs stringForColumn:@"query"] forKey:@([rs longForColumn:@"id"])];
		}
		[rs close];
	}];
	// i'm going to close this here
	[queue close];
}

- (void)setupQueryHistoryDatabase{
	
	if (![fileManager fileExistsAtPath:sqlitePath isDirectory:nil]) {
		SPLog(@"db doesn't exist, they can't have migrated");
			user_defaults_set_bool(SPMigratedQueriesFromPrefs, NO, self->prefs);
			self->migratedPrefsToDB = NO;
	}
	
	queue = [FMDatabaseQueue databaseQueueWithPath:self->sqlitePath];
	
	// this block creates the database, if needed
	// can also be used to modify schema
	SASchemaBuilder schemaBlock = ^(FMDatabase *db, int *schemaVersion) {
		
		//		[db setCrashOnErrors:YES];
		[db beginTransaction];
		
		void (^failedAt)(int statement) = ^(int statement){
			int lastErrorCode = db.lastErrorCode;
			NSString *lastErrorMessage = db.lastErrorMessage;
			[db rollback];
			NSAssert3(0, @"Migration statement %d failed, code %d: %@", statement, lastErrorCode, lastErrorMessage);
		};
		
		if (*schemaVersion < 1) {
			SPLog(@"schemaVersion < 1, creating database");
			if (! [db executeUpdate:
				   @"CREATE TABLE QueryHistory ("
				   @"    id           INTEGER PRIMARY KEY,"
				   @"    query        TEXT NOT NULL DEFAULT '',"
				   @"    createdTime  REAL NOT NULL,"
				   @"    modifiedTime REAL"
				   @");"
				   ]) failedAt(1);
			
			if (! [db executeUpdate:@"CREATE UNIQUE INDEX IF NOT EXISTS query_idx ON QueryHistory (query);"]) failedAt(2);
			
			*schemaVersion = 1;
			
			SPLog(@"database created successfully");
		}
		else{
			SPLog(@"schemaVersion >= 1, not creating database");
		}
		
		// If you wanted to change the schema in a later app version, you'd add something like this here:
		/*
		 if (*schemaVersion < 2) {
		 if (! [db executeUpdate:@"ALTER TABLE QueryHistory ADD COLUMN lastModified INTEGER NULL"]) failedAt(3);
		 *schemaVersion = 2;
		 }
		 */
		
		[db commit];
	};
	
	[queue inDatabase:^(FMDatabase *db) {
		
		int startingSchemaVersion = 0;
		FMResultSet *rs = [db executeQuery:@"PRAGMA user_version"];
		if ([rs next]) startingSchemaVersion = [rs intForColumnIndex:0];
		[rs close];
		
		SPLog(@"startingSchemaVersion = %d", startingSchemaVersion);
		
		int newSchemaVersion = startingSchemaVersion;
		
		schemaBlock(db, &newSchemaVersion);
		
		if (newSchemaVersion != startingSchemaVersion) {
			[db executeUpdate:[NSString stringWithFormat:@"PRAGMA user_version = %d", newSchemaVersion]];
		}
		else{
			SPLog(@"db schema did not need an update");
		}
	}];
}

- (void)migrateQueriesFromPrefs{
	
	if(!queue){
		SPLog(@"reopening queue");
		queue = [FMDatabaseQueue databaseQueueWithPath:sqlitePath];
	}
	
	BOOL __block success = NO;
	
	if ([prefs objectForKey:SPQueryHistory]) {
		
		NSArray *arr = [NSArray arrayWithArray:[prefs objectForKey:SPQueryHistory]];
		
		for(id obj in arr){
						
			if([obj isKindOfClass:[NSString class]] && [(NSString *)obj length]){
				
				// if this is not unique then it's going to break
				// we could check, but max 100 items ... probability of clash is low.
				NSNumber *newKeyValue = [self primaryKeyValueForNewRow];
				
				[queue inDatabase:^(FMDatabase *db) {
					
					success = [db executeUpdate:@"INSERT INTO QueryHistory (id, query, createdTime) VALUES (?, ?, ?)", newKeyValue, obj, [NSDate date]];
					if (success) {
						[queryHist safeSetObject:obj forKey:newKeyValue];
					}
					else{
						FMDBQuickCheck([db hadError]);
						if ([db hadError]) {
							SPLog(@"Err %d: %@", [db lastErrorCode], [db lastErrorMessage]);
						}
					}
				}];
			}
			
			if (!success) {
				break;
			}
		}
		
		if(success == YES){
			SPLog(@"migrated prefs to db");
			user_defaults_set_bool(SPMigratedQueriesFromPrefs, YES, prefs);
			migratedPrefsToDB = YES;
		}
		else{
			SPLog(@"FAILED to migrate prefs to db");
			user_defaults_set_bool(SPMigratedQueriesFromPrefs, NO, prefs);
			migratedPrefsToDB = NO;
		}
	}
}

- (void)getDBsize{
	
	executeOnBackgroundThread(^{
		if(!self->queue){
			SPLog(@"reopening queue");
			self->queue = [FMDatabaseQueue databaseQueueWithPath:self->sqlitePath];
		}
		
		[self->queue inDatabase:^(FMDatabase *db) {
			FMResultSet *rs = [db executeQuery:@"SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()"];
			while ([rs next]) {
				//retrieve values for each record
				self->dbSize = [rs longForColumn:@"size"];
				self->dbSizeHumanReadable = [NSByteCountFormatter stringFromByteCount:self->dbSize countStyle:NSByteCountFormatterCountStyleFile];
			}
			[rs close];
		}];
		
		SPLog(@"JIMMY db size = %ld", self.dbSize);
		SPLog(@"JIMMY db size2 = %@", self.dbSizeHumanReadable);
	});
}

- (NSNumber*)primaryKeyValueForNewRow
{
	// Issue random 64-bit signed ints
	uint64_t urandom;
	if (0 != SecRandomCopyBytes(kSecRandomDefault, sizeof(uint64_t), (uint8_t *) (&urandom))) {
		arc4random_stir();
		urandom = ( ((uint64_t) arc4random()) << 32) | (uint64_t) arc4random();
	}
	
	int64_t random = (int64_t) (urandom & 0x7FFFFFFFFFFFFFFF);
	return @(random);
}

// future - when file is massive, maybe we can zip?
//- (void)applicationWillTerminate:(NSNotification *)notification{
//
//	NSError *error = nil;
//	NSData *zippedContent = [NSData gul_dataByGzippingData:[NSData dataWithContentsOfFile:sqlitePath] error:&error];
//	NSString *gzPath = [NSString stringWithFormat:@"%@%@",sqlitePath, @".gz"];
//	[zippedContent writeToFile:gzPath atomically:NO];
//}


- (void)dealloc{
	
	SPLog(@"JIMMY dealloc");
	[queue close];
}

@end
