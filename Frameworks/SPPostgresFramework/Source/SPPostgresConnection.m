//
//  SPPostgresConnection.m
//  SPPostgresFramework
//
//  Created by Sequel-PAce on 2025.
//

#import "SPPostgresConnection.h"

// Assuming libpq-fe.h is available in the include path
#include <libpq-fe.h>

@interface SPPostgresConnection ()
@property (nonatomic, assign) BOOL lastQueryErrored;
@end

@implementation SPPostgresConnection

- (instancetype)init {
    self = [super init];
    if (self) {
        _port = 5432; // Default Postgres port
        _useSSL = NO;
        _lastQueryErrored = NO;
    }
    return self;
}

- (BOOL)connect {
    if (_pgConnection) {
        PQfinish(_pgConnection);
        _pgConnection = NULL;
    }

    NSMutableString *connInfo = [NSMutableString string];
    if (self.host) [connInfo appendFormat:@"host='%@' ", self.host];
    if (self.port) [connInfo appendFormat:@"port='%lu' ", (unsigned long)self.port];
    if (self.database) [connInfo appendFormat:@"dbname='%@' ", self.database];
    if (self.username) [connInfo appendFormat:@"user='%@' ", self.username];
    if (self.password) [connInfo appendFormat:@"password='%@' ", self.password];
    if (self.useSSL) [connInfo appendString:@"sslmode='require' "];
    else [connInfo appendString:@"sslmode='disable' "];

    _pgConnection = PQconnectdb([connInfo UTF8String]);

    if (PQstatus(_pgConnection) != CONNECTION_OK) {
        NSString *errorMsg = [NSString stringWithUTF8String:PQerrorMessage(_pgConnection)];
        if ([self.delegate respondsToSelector:@selector(postgresConnection:didFailWithError:)]) {
            [self.delegate postgresConnection:self didFailWithError:errorMsg];
        }
        PQfinish(_pgConnection);
        _pgConnection = NULL;
        return NO;
    }

    return YES;
}

- (void)disconnect {
    if (_pgConnection) {
        PQfinish(_pgConnection);
        _pgConnection = NULL;
    }
}

- (BOOL)reconnect {
    [self disconnect];
    return [self connect];
}

- (BOOL)isConnected {
    return _pgConnection && PQstatus(_pgConnection) == CONNECTION_OK;
}

- (SPPostgresResult *)queryString:(NSString *)query {
    self.lastQueryErrored = NO;
    
    if (!self.isConnected) {
        self.lastQueryErrored = YES;
        return nil;
    }

    if ([self.delegate respondsToSelector:@selector(postgresConnection:willPerformQuery:)]) {
        [self.delegate postgresConnection:self willPerformQuery:query];
    }

    PGresult *res = PQexec(_pgConnection, [query UTF8String]);
    ExecStatusType status = PQresultStatus(res);

    if (status != PGRES_COMMAND_OK && status != PGRES_TUPLES_OK) {
        self.lastQueryErrored = YES;
        NSString *errorMsg = [NSString stringWithUTF8String:PQresultErrorMessage(res)];
        // Log error or notify delegate?
        PQclear(res);
        return nil;
    }

    int rows = PQntuples(res);
    int cols = PQnfields(res);

    NSMutableArray *resultRows = [NSMutableArray arrayWithCapacity:rows];
    NSMutableArray *fieldNames = [NSMutableArray arrayWithCapacity:cols];

    for (int j = 0; j < cols; j++) {
        [fieldNames addObject:[NSString stringWithUTF8String:PQfname(res, j)]];
    }

    for (int i = 0; i < rows; i++) {
        NSMutableDictionary *rowDict = [NSMutableDictionary dictionaryWithCapacity:cols];
        for (int j = 0; j < cols; j++) {
            char *val = PQgetvalue(res, i, j);
            NSString *key = fieldNames[j];
            id value = [NSNull null];
            
            if (!PQgetisnull(res, i, j)) {
                value = [NSString stringWithUTF8String:val];
            }
            
            [rowDict setObject:value forKey:key];
        }
        [resultRows addObject:rowDict];
    }

    PQclear(res);
    return [[SPPostgresResult alloc] initWithRows:resultRows fieldNames:fieldNames];
}

- (NSArray<NSString *> *)databases {
    SPPostgresResult *result = [self queryString:@"SELECT datname FROM pg_database WHERE datistemplate = false;"];
    if (!result) return @[];
    
    NSMutableArray *dbs = [NSMutableArray array];
    NSDictionary *row;
    while ((row = [result getRowAsDictionary])) {
        [dbs addObject:row[@"datname"]];
    }
    return dbs;
}

- (NSString *)serverVersionString {
    if (!self.isConnected) return @"";
    int version = PQserverVersion(_pgConnection);
    return [NSString stringWithFormat:@"%d.%d.%d", version / 10000, (version % 10000) / 100, version % 100];
}

- (NSUInteger)serverMajorVersion {
    if (!self.isConnected) return 0;
    return PQserverVersion(_pgConnection) / 10000;
}

- (NSUInteger)serverMinorVersion {
    if (!self.isConnected) return 0;
    return (PQserverVersion(_pgConnection) % 10000) / 100;
}

- (NSUInteger)serverReleaseVersion {
    if (!self.isConnected) return 0;
    return PQserverVersion(_pgConnection) % 100;
}

- (void)setEncoding:(NSString *)encoding {
    if (!self.isConnected) return;
    PQsetClientEncoding(_pgConnection, [encoding UTF8String]);
}

- (NSString *)encoding {
    if (!self.isConnected) return @"";
    int encoding = PQclientEncoding(_pgConnection);
    return [NSString stringWithUTF8String:pg_encoding_to_char(encoding)];
}

- (BOOL)queryErrored {
    return self.lastQueryErrored;
}

- (NSString *)escapeString:(NSString *)string {
    if (!string) return @"";
    if (!_pgConnection) return string;

    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    size_t length = [data length];
    char *buffer = malloc(length * 2 + 1);
    int error = 0;
    
    PQescapeStringConn(_pgConnection, buffer, [data bytes], length, &error);
    
    NSString *escaped = [NSString stringWithUTF8String:buffer];
    free(buffer);
    
    return escaped;
}

- (void)dealloc {
    [self disconnect];
}

@end
