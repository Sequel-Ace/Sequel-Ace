//
//  SPPostgreSQLResultWrapper.h
//  Sequel Ace
//
//  Created for PostgreSQL abstraction support
//

#import <Foundation/Foundation.h>
#import "SPDatabaseResult.h"

// Forward declare the C result handle from Rust FFI
typedef struct SPPostgreSQLResult SPPostgreSQLResult;

@class SPPostgreSQLConnectionWrapper;

@interface SPPostgreSQLResultWrapper : NSObject <SPDatabaseResult>

/**
 * Designated initializer
 */
- (instancetype)initWithPGResult:(SPPostgreSQLResult *)result connection:(SPPostgreSQLConnectionWrapper *)connection;

/**
 * Get the underlying PostgreSQL result handle (for internal use)
 */
@property (nonatomic, readonly) SPPostgreSQLResult *pgResult;

@end

