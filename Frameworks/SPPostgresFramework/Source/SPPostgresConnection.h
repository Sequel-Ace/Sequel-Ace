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

// Forward declaration of PGconn to avoid including libpq-fe.h in header if possible,
// but usually it's needed for types. For now, using void* to abstract it.
typedef void PGconn;

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
}

@property (readonly) BOOL isConnected;
@property (readonly) NSString *lastErrorMessage;
@property (readonly) NSString *serverVersionString;
@property (readonly) NSUInteger serverMajorVersion;
@property (readonly) NSUInteger serverMinorVersion;
@property (readonly) NSUInteger serverReleaseVersion;

- (void)setConnectionDetailsWithHost:(NSString *)theHost username:(NSString *)theUsername password:(NSString *)thePassword port:(NSUInteger)thePort database:(NSString *)theDatabase;
- (BOOL)connect;
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

- (NSString *)database;
- (void)selectDatabase:(NSString *)database;

@end
