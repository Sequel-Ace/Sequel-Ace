//
//  SPPostgreSQLStreamingResultWrapper.h
//  Sequel Ace
//
//  Streaming result backed by a PostgreSQL server-side cursor via the Rust FFI.
//  Conforms to SPDatabaseResult; rows are fetched in batches.
//

#import <Foundation/Foundation.h>
#import "SPDatabaseResult.h"
#import "Frameworks/SPPostgreSQLFramework/Headers/sppostgresql_ffi.h"

@interface SPPostgreSQLStreamingResultWrapper : NSObject <SPDatabaseResult>

- (instancetype)initWithStreamingResult:(SPPostgreSQLStreamingResult *)result
                              queryTime:(double)queryTime;

/// Signals to the Rust layer that the underlying connection is being torn down.
- (void)markConnectionDisconnected;

@end
