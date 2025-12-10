//
//  SPPostgresConnection.h
//  SPPostgresFramework
//
//  Created by Mehmet Karabulut (mehmetik@gmail.com) on November 30, 2025.
//  Copyright (c) 2025 Mehmet Karabulut.
//  This software is released under the GPL License.
//  This is an open-source project forked from Sequel Ace.
//

#import <Foundation/Foundation.h>
#import "SPPostgresResult.h"
#import "SPPostgresStreamingResult.h"

// Forward declaration of PGconn - actual definition comes from libpq
typedef struct pg_conn PGconn;

@class SPPostgresConnection;

/**
 * SPPostgresConnectionDelegate protocol
 * Classes implementing this protocol can receive notifications about connection events.
 */
@protocol SPPostgresConnectionDelegate <NSObject>
@optional
- (void)connectionSucceeded:(SPPostgresConnection *)connection;
- (void)connectionFailed:(SPPostgresConnection *)connection;
- (void)queryGaveError:(NSString *)error connection:(SPPostgresConnection *)connection;
- (BOOL)keychainPasswordForConnection:(SPPostgresConnection *)connection;
- (NSString *)keychainPasswordForSSHConnection:(SPPostgresConnection *)connection;
@end


@interface SPPostgresConnection : NSObject {
    PGconn *connection;
    NSString *host;
    NSString *username;
    NSString *password;
    NSUInteger port;
    NSString *database;
    BOOL isConnected;
    NSString *lastErrorMessage;
    NSString *serverVersion;
    NSUInteger serverMajorVersion;
    NSUInteger serverMinorVersion;
    NSUInteger serverReleaseVersion;
    NSStringEncoding stringEncoding;
    NSString *storedEncoding;
}

@property (readonly) BOOL isConnected;
@property (readonly) NSString *lastErrorMessage;
@property (readonly) NSString *serverVersionString;
@property (readonly) NSUInteger serverMajorVersion;
@property (readonly) NSUInteger serverMinorVersion;
@property (readonly) NSUInteger serverReleaseVersion;

- (void)setConnectionDetailsWithHost:(NSString *)theHost username:(NSString *)theUsername password:(NSString *)thePassword port:(NSUInteger)thePort database:(NSString *)theDatabase;
- (BOOL)connect;
- (BOOL)reconnectWithNewDatabase:(NSString *)databaseName;
- (void)disconnect;

- (SPPostgresResult *)queryString:(NSString *)query;
- (SPPostgresStreamingResult *)streamingQueryString:(NSString *)query useLowMemoryBlockingStreaming:(BOOL)lowMemory;

- (void)setEncoding:(NSString *)encoding;
- (NSStringEncoding)encoding;

- (NSString *)escapeAndQuoteString:(NSString *)string;
- (id)delegate;
- (void)setDelegate:(id)delegate;

- (BOOL)queryErrored;
- (BOOL)lastQueryWasCancelled;
- (void)cancelCurrentQuery;
- (id)getFirstFieldFromQuery:(NSString *)query;
- (NSUInteger)lastErrorID;
- (NSString *)escapeAndQuoteData:(NSData *)data;
- (BOOL)isNotMariadb103;
- (BOOL)isMariaDB;
- (BOOL)userTriggeredDisconnect;

- (NSString *)database;
- (NSString *)host;
- (NSArray *)databases;
- (void)selectDatabase:(NSString *)database;
- (void)storeEncodingForRestoration;
- (void)restoreStoredEncoding;

// Additional methods needed for compatibility
- (SPPostgresResult *)resultStoreFromQueryString:(NSString *)query;
- (NSString *)lastSqlstate;
- (NSUInteger)rowsAffectedByLastQuery;
- (NSString *)escapeString:(NSString *)string includingQuotes:(BOOL)includeQuotes;
- (NSString *)escapeData:(NSData *)data includingQuotes:(BOOL)includeQuotes;
- (NSStringEncoding)stringEncoding;
- (unsigned long long)lastInsertID;
- (BOOL)isConnected;
- (NSArray *)tablesFromDatabase:(NSString *)database;

@end
