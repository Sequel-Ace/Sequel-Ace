//
//  SAMultiTabConnectionLostGate.m
//  sequel-ace
//

#import "SAMultiTabConnectionLostGate.h"

@implementation SAMultiTabConnectionLostGate

+ (void)runAction:(void (^ _Nullable)(void))action forHandler:(id<SAMultiTabConnectionLostGateHandler>)handler
{
	if (![handler backgroundConnectionLostForGate]) {
		if (action) action();
		return;
	}

	BOOL sheetShown = [handler showConnectionLostSheetAllowingCancelForGate:YES completion:^(SPMySQLConnectionLostDecision decision, BOOL cancelled) {
		if (cancelled) return;

		if (decision == SPMySQLConnectionLostReconnect) {
			[self _attemptReconnectForAction:action handler:handler];
		} else if (decision == SPMySQLConnectionLostDisconnect) {
			[handler closeAndDisconnectForGate];
		}
	}];

	if (!sheetShown) {
		[handler closeAndDisconnectForGate];
	}
}

+ (void)_attemptReconnectForAction:(void (^ _Nullable)(void))action handler:(id<SAMultiTabConnectionLostGateHandler>)handler
{
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		BOOL reconnected = [handler reconnectConnectionForGate];

		dispatch_async(dispatch_get_main_queue(), ^{
			if (reconnected) {
				[handler setBackgroundConnectionLostForGate:NO];
				if (action) action();
				return;
			}

			// Honor a Disconnect already chosen by the user inside the framework's
			// async lost-connection sheet (which the underlying `-reconnect` ran
			// on the worker thread). The handler's own delegate path
			// (`-connectionLost:completion:`) already closes the document on the
			// user's Disconnect click, so do NOT call `closeAndDisconnectForGate`
			// here — that would invoke `-closeAndDisconnect` a second time, which
			// is non-idempotent (window close is rescheduled, query history is
			// re-persisted, and the `wasConnected` branch flips). Showing another
			// Retry/Disconnect prompt would also contradict the user's choice
			// and even let them "retry" past it.
			if ([handler connectionGateUserChoseDisconnect]) {
				return;
			}

			BOOL failureShown = [handler presentReconnectFailureAllowingRetryForGate:^(BOOL retry) {
				if (retry) {
					[self _attemptReconnectForAction:action handler:handler];
				} else {
					[handler closeAndDisconnectForGate];
				}
			}];

			if (!failureShown) {
				[handler closeAndDisconnectForGate];
			}
		});
	});
}

@end
