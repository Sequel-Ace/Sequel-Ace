//
//  SPPostgreSQLResultWrapper.h
//  Sequel Ace
//
//  Conforms to SPDatabaseResult; backed by the Rust FFI result object.
//

#import <Foundation/Foundation.h>
#import "SPDatabaseResult.h"
#import "Frameworks/SPPostgreSQLFramework/Headers/sppostgresql_ffi.h"

@interface SPPostgreSQLResultWrapper : NSObject <SPDatabaseResult>

- (instancetype)initWithResult:(SPPostgreSQLResult *)result queryTime:(double)queryTime;

@end
