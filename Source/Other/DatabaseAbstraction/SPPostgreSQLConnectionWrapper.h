//
//  SPPostgreSQLConnectionWrapper.h
//  Sequel Ace
//
//  Created for PostgreSQL abstraction support
//

#import <Foundation/Foundation.h>
#import "SPDatabaseConnection.h"

// Forward declare the C connection handle from Rust FFI
typedef struct SPPostgreSQLConnection SPPostgreSQLConnection;

@interface SPPostgreSQLConnectionWrapper : NSObject <SPDatabaseConnection>

/**
 * Designated initializer
 */
- (instancetype)init;

/**
 * Get the underlying PostgreSQL connection handle (for internal use)
 */
@property (nonatomic, readonly) SPPostgreSQLConnection *pgConnection;

@end

