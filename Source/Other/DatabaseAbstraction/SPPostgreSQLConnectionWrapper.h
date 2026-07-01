//
//  SPPostgreSQLConnectionWrapper.h
//  Sequel Ace
//
//  Implements id<SPDatabaseConnection> by talking to the Rust PostgreSQL library
//  via the C FFI in SPPostgreSQLFramework.
//

#import <Foundation/Foundation.h>
#import "SPDatabaseConnection.h"

@interface SPPostgreSQLConnectionWrapper : NSObject <SPDatabaseConnection>

- (instancetype)init;

/// Default PostgreSQL port (5432).
+ (NSUInteger)defaultPort;

@end
