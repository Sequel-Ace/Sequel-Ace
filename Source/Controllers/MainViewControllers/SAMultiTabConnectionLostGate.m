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
			dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
				BOOL reconnected = [handler reconnectConnectionForGate];

				dispatch_async(dispatch_get_main_queue(), ^{
					if (reconnected) {
						[handler setBackgroundConnectionLostForGate:NO];
						if (action) action();
					} else {
						BOOL failureShown = [handler presentReconnectFailureAllowingRetryForGate:^(BOOL retry) {
							if (retry) {
								[self runAction:action forHandler:handler];
							} else {
								[handler closeAndDisconnectForGate];
							}
						}];

						if (!failureShown) {
							[handler closeAndDisconnectForGate];
						}
					}
				});
			});
		} else if (decision == SPMySQLConnectionLostDisconnect) {
			[handler closeAndDisconnectForGate];
		}
	}];

	if (!sheetShown) {
		[handler closeAndDisconnectForGate];
	}
}

@end
