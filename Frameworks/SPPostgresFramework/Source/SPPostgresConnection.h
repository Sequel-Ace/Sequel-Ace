//
//  SPPostgresConnection.h
//  SPPostgresFramework
//
//  Created by Sequel-PAce on 2025.
//

#import <Foundation/Foundation.h>

// Forward declaration for libpq connection struct
typedef struct pg_conn PGconn;

@class SPPostgresConnection;
#import "SPPostgresResult.h"

@protocol SPPostgresConnectionDelegate <NSObject>
@optional
- (void)postgresConnection:(SPPostgresConnection *)connection willPerformQuery:(NSString *)query;
- (void)postgresConnection:(SPPostgresConnection *)connection didFailWithError:(NSString *)error;
@end

@interface SPPostgresConnection : NSObject

@property (nonatomic, weak) id<SPPostgresConnectionDelegate> delegate;

// Connection Details
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *password;
@property (nonatomic, copy) NSString *database;
@property (nonatomic, assign) NSUInteger port;
@property (nonatomic, assign) BOOL useSSL;

// State
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) PGconn *pgConnection;

// Methods
- (BOOL)connect;
- (void)disconnect;
- (BOOL)reconnect;

// Query Execution
- (SPPostgresResult *)queryString:(NSString *)query;

// Helper Methods
- (NSArray<NSString *> *)databases;
- (NSString *)serverVersionString;
- (NSUInteger)serverMajorVersion;
- (NSUInteger)serverMinorVersion;
- (NSUInteger)serverReleaseVersion;

- (void)setEncoding:(NSString *)encoding;
- (NSString *)encoding;
- (BOOL)queryErrored;

// Utility
- (NSString *)escapeString:(NSString *)string;

@end
