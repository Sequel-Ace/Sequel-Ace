//
//  SPMySQLConnectionWrapper.h
//  Sequel Ace
//
//  Wraps an SPMySQLConnection so it conforms to SPDatabaseConnection,
//  allowing it to be used anywhere an id<SPDatabaseConnection> is expected.
//

#import <Foundation/Foundation.h>
#import "SPDatabaseConnection.h"

@class SPMySQLConnection;

@interface SPMySQLConnectionWrapper : NSObject <SPDatabaseConnection>

- (instancetype)initWithConnection:(SPMySQLConnection *)connection;

/// The underlying connection for callers that need MySQL-specific APIs.
@property (nonatomic, readonly) SPMySQLConnection *underlyingConnection;

/// Default MySQL port (3306).
+ (NSUInteger)defaultPort;

@end
