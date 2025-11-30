//
//  SPPostgresConnection.m
//  SPPostgresFramework
//
//  Created by Mehmet Karabulut (mehmetik@gmail.com) on November 30, 2025.
//  Copyright (c) 2025 Mehmet Karabulut.
//  This software is released under the GPL License.
//  This is an open-source project forked from Sequel Ace.
//

#import "SPPostgresConnection.h"
#import <libpq-fe.h>

@implementation SPPostgresConnection

- (instancetype)init {
    self = [super init];
    if (self) {
        connection = NULL;
        isConnected = NO;
        stringEncoding = NSUTF8StringEncoding;
    }
    return self;
}

- (void)setConnectionDetailsWithHost:(NSString *)theHost username:(NSString *)theUsername password:(NSString *)thePassword port:(NSUInteger)thePort database:(NSString *)theDatabase {
    host = [theHost copy];
    username = [theUsername copy];
    password = [thePassword copy];
    port = thePort;
    database = [theDatabase copy];
}

- (BOOL)connect {
    if (isConnected) [self disconnect];

    NSMutableString *connInfo = [NSMutableString string];
    if (host) [connInfo appendFormat:@"host='%@' ", host];
    if (port) [connInfo appendFormat:@"port='%lu' ", (unsigned long)port];
    if (database) [connInfo appendFormat:@"dbname='%@' ", database];
    if (username) [connInfo appendFormat:@"user='%@' ", username];
    if (password) [connInfo appendFormat:@"password='%@' ", password];
    
    // Set client encoding to UTF8 by default
    [connInfo appendString:@"client_encoding='UTF8'"];

    connection = PQconnectdb([connInfo UTF8String]);

    if (PQstatus(connection) != CONNECTION_OK) {
        lastErrorMessage = [NSString stringWithUTF8String:PQerrorMessage(connection)];
        PQfinish(connection);
        connection = NULL;
        isConnected = NO;
        return NO;
    }

    isConnected = YES;
    
    // Get server version
    int version = PQserverVersion(connection);
    serverMajorVersion = version / 10000;
    serverMinorVersion = (version % 10000) / 100;
    serverReleaseVersion = version % 100;
    serverVersion = [NSString stringWithFormat:@"%d.%d.%d", (int)serverMajorVersion, (int)serverMinorVersion, (int)serverReleaseVersion];

    return YES;
}

- (void)disconnect {
    if (connection) {
        PQfinish(connection);
        connection = NULL;
    }
    isConnected = NO;
}

- (SPPostgresResult *)queryString:(NSString *)query {
    if (!isConnected || !connection) return nil;

    PGresult *res = PQexec(connection, [query UTF8String]);
    
    SPPostgresResult *result = [[SPPostgresResult alloc] initWithPGResult:res];
    
    if (PQresultStatus(res) != PGRES_TUPLES_OK && PQresultStatus(res) != PGRES_COMMAND_OK) {
        lastErrorMessage = [NSString stringWithUTF8String:PQresultErrorMessage(res)];
    } else {
        lastErrorMessage = nil;
    }
    
    return result;
}

- (SPPostgresStreamingResult *)streamingQueryString:(NSString *)query useLowMemoryBlockingStreaming:(BOOL)lowMemory {
    // Basic implementation: just run normal query and wrap it. 
    // Real streaming would use PQsendQuery and PQsetSingleRowMode.
    if (!isConnected || !connection) return nil;
    
    // For now, return a dummy or non-streaming result wrapped as streaming
    // TODO: Implement real streaming
    return (SPPostgresStreamingResult *)[self queryString:query];
}

- (void)setEncoding:(NSString *)encoding {
    if (!isConnected) return;
    // Map encoding name to Postgres encoding if needed
    PQsetClientEncoding(connection, [encoding UTF8String]);
}

- (NSStringEncoding)encoding {
    return stringEncoding;
}

- (NSString *)escapeAndQuoteString:(NSString *)string {
    if (!string) return @"NULL";
    if (!isConnected) return [NSString stringWithFormat:@"'%@'", string]; // Fallback
    
    char *escaped = malloc(string.length * 2 + 1);
    int error;
    PQescapeStringConn(connection, escaped, [string UTF8String], string.length, &error);
    NSString *result = [NSString stringWithFormat:@"'%s'", escaped];
    free(escaped);
    return result;
}

- (id)delegate { return nil; }
- (void)setDelegate:(id)delegate {}

- (BOOL)queryErrored {
    return lastErrorMessage != nil;
}

- (BOOL)lastQueryWasCancelled {
    return NO; // TODO
}

- (void)cancelCurrentQuery {
    // TODO
}

- (NSString *)database {
    return database;
}

- (void)selectDatabase:(NSString *)db {
    // Postgres doesn't support "USE db", need to reconnect.
    // For now, just update the property, assuming caller will reconnect or this is just for tracking.
    database = [db copy];
}

@end
