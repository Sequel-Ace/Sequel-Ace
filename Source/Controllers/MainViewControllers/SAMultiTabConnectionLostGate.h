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

/// YES iff the user clicked the Disconnect button in the framework's
/// lost-connection sheet during the just-finished `reconnectConnectionForGate`
/// attempt. Implementations MUST distinguish a genuine button-click from the
/// non-user defaults the framework also maps to its Disconnect enum (timeout,
/// no-window fallback, main-thread suppression, retry exhaustion).
///
/// Implementations that report YES MUST have already performed the close
/// (typically inside the framework's `-connectionLost:completion:` handler).
/// The gate uses this signal to skip a redundant Retry/Disconnect prompt AND
/// to avoid calling `closeAndDisconnectForGate` a second time, so the close
/// flow runs exactly once per user click.
- (BOOL)connectionGateUserChoseDisconnect;

- (BOOL)presentReconnectFailureAllowingRetryForGate:(void (^)(BOOL retry))completion;
- (void)closeAndDisconnectForGate;

@end

@interface SAMultiTabConnectionLostGate : NSObject

+ (void)runAction:(void (^ _Nullable)(void))action forHandler:(id<SAMultiTabConnectionLostGateHandler>)handler;

@end

NS_ASSUME_NONNULL_END
