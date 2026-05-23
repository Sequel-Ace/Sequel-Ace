//
//  SAMultiTabConnectionLostGate.h
//  sequel-ace
//

#import <Foundation/Foundation.h>
#import <SPMySQL/SPMySQL.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SAMultiTabConnectionLostGateHandler <NSObject>

- (BOOL)backgroundConnectionLostForGate;
- (void)setBackgroundConnectionLostForGate:(BOOL)lost;
- (BOOL)showConnectionLostSheetAllowingCancelForGate:(BOOL)allowCancel completion:(void (^)(SPMySQLConnectionLostDecision decision, BOOL cancelled))completion;
- (BOOL)reconnectConnectionForGate;
- (void)closeAndDisconnectForGate;

@end

@interface SAMultiTabConnectionLostGate : NSObject

+ (void)runAction:(void (^ _Nullable)(void))action forHandler:(id<SAMultiTabConnectionLostGateHandler>)handler;

@end

NS_ASSUME_NONNULL_END
