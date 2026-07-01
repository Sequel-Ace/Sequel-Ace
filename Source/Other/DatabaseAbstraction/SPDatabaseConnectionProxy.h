//
//  SPDatabaseConnectionProxy.h
//  Sequel Ace
//
//  Minimal delegate/proxy protocol that SPDatabaseDocument and friends
//  must implement so both MySQL and PostgreSQL wrappers can call back
//  into them without importing SPMySQLConnectionDelegate directly.
//

#import <Foundation/Foundation.h>

@protocol SPDatabaseConnectionProxy <NSObject>
@optional
- (void)connectionLost:(id)connection;
- (NSInteger)connectionLostDecisionForConnection:(id)connection;
@end
