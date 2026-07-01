//
//  SPMySQLResultWrapper.h
//  Sequel Ace
//
//  Wraps SPMySQLResult to conform to SPDatabaseResult.
//

#import <Foundation/Foundation.h>
#import "SPDatabaseResult.h"

@class SPMySQLResult;

@interface SPMySQLResultWrapper : NSObject <SPDatabaseResult>

- (instancetype)initWithResult:(SPMySQLResult *)result;

@property (nonatomic, readonly) SPMySQLResult *underlyingResult;

@end
