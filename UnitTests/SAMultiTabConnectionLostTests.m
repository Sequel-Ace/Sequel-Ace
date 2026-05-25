//
//  SAMultiTabConnectionLostTests.m
//  Unit Tests
//

#import <XCTest/XCTest.h>
#import <SPMySQL/SPMySQL.h>
#import "SAMultiTabConnectionLostGate.h"

@interface SATestConnectionLostGateHandler : NSObject <SAMultiTabConnectionLostGateHandler>
@property (nonatomic) BOOL backgroundConnectionLost;
@property (nonatomic) BOOL sheetShown;
@property (nonatomic) BOOL sheetPresentationResult;
@property (nonatomic) BOOL reconnectFailurePresentationResult;
@property (nonatomic) BOOL lastAllowCancel;
@property (nonatomic) BOOL reconnectResult;
@property (nonatomic) BOOL userChoseDisconnect;
// Models SPDatabaseDocument's real behavior: its `connectionLost:completion:`
// path calls `closeAndDisconnect` itself on a user Disconnect click before
// the worker-thread `-reconnect` returns. Setting this to YES makes the fake
// handler increment `closeAndDisconnectCount` from inside
// `reconnectConnectionForGate`, so tests can assert the gate does NOT close
// a second time on the same user choice.
@property (nonatomic) BOOL handlerClosesInsideReconnect;
@property (nonatomic) NSUInteger reconnectCount;
@property (nonatomic) NSUInteger reconnectFailurePresentationCount;
@property (nonatomic) NSUInteger closeAndDisconnectCount;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *queuedReconnectResults;
@property (nonatomic, strong) XCTestExpectation *reconnectExpectation;
@property (nonatomic, strong) XCTestExpectation *reconnectFailureExpectation;
@property (nonatomic, copy) void (^capturedCompletion)(SPMySQLConnectionLostDecision decision, BOOL cancelled);
@property (nonatomic, copy) void (^capturedReconnectFailureCompletion)(BOOL retry);
- (void)observeBackgroundLossNotification:(NSNotification *)notification;
@end

@implementation SATestConnectionLostGateHandler

- (instancetype)init
{
	if ((self = [super init])) {
		_sheetPresentationResult = YES;
		_reconnectFailurePresentationResult = YES;
	}
	return self;
}

- (BOOL)backgroundConnectionLostForGate
{
	return self.backgroundConnectionLost;
}

- (void)setBackgroundConnectionLostForGate:(BOOL)lost
{
	self.backgroundConnectionLost = lost;
}

- (BOOL)showConnectionLostSheetAllowingCancelForGate:(BOOL)allowCancel completion:(void (^)(SPMySQLConnectionLostDecision decision, BOOL cancelled))completion
{
	self.sheetShown = YES;
	self.lastAllowCancel = allowCancel;
	self.capturedCompletion = completion;
	return self.sheetPresentationResult;
}

- (BOOL)reconnectConnectionForGate
{
	self.reconnectCount++;
	if (self.handlerClosesInsideReconnect) {
		// Mirror SPDatabaseDocument's connectionLost:completion: closing the
		// document itself on a user-clicked Disconnect before -reconnect returns.
		[self closeAndDisconnectForGate];
	}
	[self.reconnectExpectation fulfill];
	if ([self.queuedReconnectResults count]) {
		BOOL nextResult = [[self.queuedReconnectResults firstObject] boolValue];
		[self.queuedReconnectResults removeObjectAtIndex:0];
		return nextResult;
	}
	return self.reconnectResult;
}

- (BOOL)connectionGateUserChoseDisconnect
{
	return self.userChoseDisconnect;
}

- (BOOL)presentReconnectFailureAllowingRetryForGate:(void (^)(BOOL retry))completion
{
	self.reconnectFailurePresentationCount++;
	self.capturedReconnectFailureCompletion = completion;
	[self.reconnectFailureExpectation fulfill];
	return self.reconnectFailurePresentationResult;
}

- (void)closeAndDisconnectForGate
{
	self.closeAndDisconnectCount++;
}

- (void)observeBackgroundLossNotification:(NSNotification *)notification
{
	self.backgroundConnectionLost = YES;
}

@end

@interface SAMultiTabConnectionLostTests : XCTestCase
@end

@implementation SAMultiTabConnectionLostTests

- (void)testFrameworkNotificationForOwnConnectionSetsBackgroundLossFlag
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	SATestConnectionLostGateHandler *handler = [[SATestConnectionLostGateHandler alloc] init];
	id token = [[NSNotificationCenter defaultCenter] addObserverForName:SPMySQLConnectionLostInBackgroundNotification object:connection queue:nil usingBlock:^(NSNotification *note) {
		[handler observeBackgroundLossNotification:note];
	}];

	[[NSNotificationCenter defaultCenter] postNotificationName:SPMySQLConnectionLostInBackgroundNotification object:connection];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertTrue(handler.backgroundConnectionLost);
}

- (void)testFrameworkNotificationForOtherConnectionDoesNotSetBackgroundLossFlag
{
	SPMySQLConnection *ownConnection = [[SPMySQLConnection alloc] init];
	SPMySQLConnection *otherConnection = [[SPMySQLConnection alloc] init];
	SATestConnectionLostGateHandler *handler = [[SATestConnectionLostGateHandler alloc] init];
	id token = [[NSNotificationCenter defaultCenter] addObserverForName:SPMySQLConnectionLostInBackgroundNotification object:ownConnection queue:nil usingBlock:^(NSNotification *note) {
		[handler observeBackgroundLossNotification:note];
	}];

	[[NSNotificationCenter defaultCenter] postNotificationName:SPMySQLConnectionLostInBackgroundNotification object:otherConnection];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertFalse(handler.backgroundConnectionLost);
}

- (void)testGateFastPathRunsActionSynchronouslyWithoutSheet
{
	SATestConnectionLostGateHandler *handler = [[SATestConnectionLostGateHandler alloc] init];
	__block NSUInteger actionCount = 0;

	[SAMultiTabConnectionLostGate runAction:^{
		actionCount++;
	} forHandler:handler];

	XCTAssertEqual(actionCount, 1U);
	XCTAssertFalse(handler.sheetShown);
}

- (void)testGateSlowPathShowsCancellableSheetAndDoesNotRunActionImmediately
{
	SATestConnectionLostGateHandler *handler = [[SATestConnectionLostGateHandler alloc] init];
	handler.backgroundConnectionLost = YES;
	__block NSUInteger actionCount = 0;

	[SAMultiTabConnectionLostGate runAction:^{
		actionCount++;
	} forHandler:handler];

	XCTAssertTrue(handler.sheetShown);
	XCTAssertTrue(handler.lastAllowCancel);
	XCTAssertEqual(actionCount, 0U);
	XCTAssertNotNil(handler.capturedCompletion);
}

- (void)testGateClosesWithoutRunningActionWhenSheetCannotBePresented
{
	SATestConnectionLostGateHandler *handler = [[SATestConnectionLostGateHandler alloc] init];
	handler.backgroundConnectionLost = YES;
	handler.sheetPresentationResult = NO;
	__block NSUInteger actionCount = 0;

	[SAMultiTabConnectionLostGate runAction:^{
		actionCount++;
	} forHandler:handler];

	XCTAssertTrue(handler.sheetShown);
	XCTAssertEqual(actionCount, 0U);
	XCTAssertEqual(handler.closeAndDisconnectCount, 1U);
	XCTAssertTrue(handler.backgroundConnectionLost);
}

- (void)testReconnectCompletionClearsFlagAndRunsAction
{
	SATestConnectionLostGateHandler *handler = [[SATestConnectionLostGateHandler alloc] init];
	handler.backgroundConnectionLost = YES;
	handler.reconnectResult = YES;
	handler.reconnectExpectation = [self expectationWithDescription:@"reconnect invoked"];
	XCTestExpectation *actionExpectation = [self expectationWithDescription:@"action invoked"];

	[SAMultiTabConnectionLostGate runAction:^{
		[actionExpectation fulfill];
	} forHandler:handler];
	handler.capturedCompletion(SPMySQLConnectionLostReconnect, NO);

	[self waitForExpectationsWithTimeout:1 handler:nil];
	XCTAssertEqual(handler.reconnectCount, 1U);
	XCTAssertFalse(handler.backgroundConnectionLost);
	XCTAssertEqual(handler.closeAndDisconnectCount, 0U);
}

- (void)testReconnectFailurePresentsFailureHandlingWithoutRunningAction
{
	SATestConnectionLostGateHandler *handler = [[SATestConnectionLostGateHandler alloc] init];
	handler.backgroundConnectionLost = YES;
	handler.reconnectResult = NO;
	handler.reconnectExpectation = [self expectationWithDescription:@"reconnect invoked"];
	handler.reconnectFailureExpectation = [self expectationWithDescription:@"reconnect failure presented"];
	__block NSUInteger actionCount = 0;

	[SAMultiTabConnectionLostGate runAction:^{
		actionCount++;
	} forHandler:handler];
	handler.capturedCompletion(SPMySQLConnectionLostReconnect, NO);

	[self waitForExpectationsWithTimeout:1 handler:nil];
	XCTAssertEqual(handler.reconnectCount, 1U);
	XCTAssertEqual(handler.reconnectFailurePresentationCount, 1U);
	XCTAssertNotNil(handler.capturedReconnectFailureCompletion);
	XCTAssertEqual(actionCount, 0U);
	XCTAssertEqual(handler.closeAndDisconnectCount, 0U);
	XCTAssertTrue(handler.backgroundConnectionLost);
}

- (void)testReconnectFailureClosesWhenFailureSheetCannotBePresented
{
	SATestConnectionLostGateHandler *handler = [[SATestConnectionLostGateHandler alloc] init];
	handler.backgroundConnectionLost = YES;
	handler.reconnectResult = NO;
	handler.reconnectFailurePresentationResult = NO;
	handler.reconnectExpectation = [self expectationWithDescription:@"reconnect invoked"];
	handler.reconnectFailureExpectation = [self expectationWithDescription:@"reconnect failure presentation attempted"];
	__block NSUInteger actionCount = 0;

	[SAMultiTabConnectionLostGate runAction:^{
		actionCount++;
	} forHandler:handler];
	handler.capturedCompletion(SPMySQLConnectionLostReconnect, NO);

	[self waitForExpectationsWithTimeout:1 handler:nil];
	XCTAssertEqual(handler.reconnectCount, 1U);
	XCTAssertEqual(handler.reconnectFailurePresentationCount, 1U);
	XCTAssertEqual(actionCount, 0U);
	XCTAssertEqual(handler.closeAndDisconnectCount, 1U);
	XCTAssertTrue(handler.backgroundConnectionLost);
}

- (void)testReconnectFailureRetryReconnectsDirectlyAndRunsAction
{
	SATestConnectionLostGateHandler *handler = [[SATestConnectionLostGateHandler alloc] init];
	handler.backgroundConnectionLost = YES;
	handler.queuedReconnectResults = [@[@NO, @YES] mutableCopy];
	handler.reconnectExpectation = [self expectationWithDescription:@"reconnect invoked"];
	handler.reconnectFailureExpectation = [self expectationWithDescription:@"reconnect failure presented"];
	XCTestExpectation *actionExpectation = [self expectationWithDescription:@"action invoked"];

	[SAMultiTabConnectionLostGate runAction:^{
		[actionExpectation fulfill];
	} forHandler:handler];
	handler.capturedCompletion(SPMySQLConnectionLostReconnect, NO);

	[self waitForExpectations:@[handler.reconnectExpectation, handler.reconnectFailureExpectation] timeout:1];
	handler.sheetShown = NO;
	handler.reconnectExpectation = [self expectationWithDescription:@"retry reconnect invoked"];
	handler.reconnectFailureExpectation = nil;
	handler.capturedReconnectFailureCompletion(YES);

	[self waitForExpectations:@[handler.reconnectExpectation, actionExpectation] timeout:1];

	XCTAssertFalse(handler.sheetShown);
	XCTAssertEqual(handler.reconnectCount, 2U);
	XCTAssertEqual(handler.closeAndDisconnectCount, 0U);
	XCTAssertFalse(handler.backgroundConnectionLost);
}

- (void)testReconnectFailureRetryDoesNotShowInitialSheet
{
	SATestConnectionLostGateHandler *handler = [[SATestConnectionLostGateHandler alloc] init];
	handler.backgroundConnectionLost = YES;
	handler.queuedReconnectResults = [@[@NO, @YES] mutableCopy];
	handler.reconnectExpectation = [self expectationWithDescription:@"reconnect invoked"];
	handler.reconnectFailureExpectation = [self expectationWithDescription:@"reconnect failure presented"];
	XCTestExpectation *actionExpectation = [self expectationWithDescription:@"action invoked"];

	[SAMultiTabConnectionLostGate runAction:^{
		[actionExpectation fulfill];
	} forHandler:handler];
	handler.capturedCompletion(SPMySQLConnectionLostReconnect, NO);

	[self waitForExpectations:@[handler.reconnectExpectation, handler.reconnectFailureExpectation] timeout:1];
	handler.sheetShown = NO;
	handler.reconnectExpectation = [self expectationWithDescription:@"retry reconnect invoked"];
	handler.reconnectFailureExpectation = nil;
	handler.capturedReconnectFailureCompletion(YES);

	[self waitForExpectations:@[handler.reconnectExpectation, actionExpectation] timeout:1];

	XCTAssertFalse(handler.sheetShown);
	XCTAssertEqual(handler.reconnectCount, 2U);
	XCTAssertEqual(handler.closeAndDisconnectCount, 0U);
	XCTAssertFalse(handler.backgroundConnectionLost);
}

- (void)testReconnectFailureDisconnectCloses
{
	SATestConnectionLostGateHandler *handler = [[SATestConnectionLostGateHandler alloc] init];
	handler.backgroundConnectionLost = YES;
	handler.reconnectResult = NO;
	handler.reconnectExpectation = [self expectationWithDescription:@"reconnect invoked"];
	handler.reconnectFailureExpectation = [self expectationWithDescription:@"reconnect failure presented"];
	__block NSUInteger actionCount = 0;

	[SAMultiTabConnectionLostGate runAction:^{
		actionCount++;
	} forHandler:handler];
	handler.capturedCompletion(SPMySQLConnectionLostReconnect, NO);

	[self waitForExpectationsWithTimeout:1 handler:nil];
	handler.capturedReconnectFailureCompletion(NO);

	XCTAssertEqual(actionCount, 0U);
	XCTAssertEqual(handler.closeAndDisconnectCount, 1U);
	XCTAssertTrue(handler.backgroundConnectionLost);
}

- (void)testDisconnectCompletionClosesWithoutRunningAction
{
	SATestConnectionLostGateHandler *handler = [[SATestConnectionLostGateHandler alloc] init];
	handler.backgroundConnectionLost = YES;
	__block NSUInteger actionCount = 0;

	[SAMultiTabConnectionLostGate runAction:^{
		actionCount++;
	} forHandler:handler];
	handler.capturedCompletion(SPMySQLConnectionLostDisconnect, NO);

	XCTAssertEqual(handler.closeAndDisconnectCount, 1U);
	XCTAssertEqual(actionCount, 0U);
	XCTAssertTrue(handler.backgroundConnectionLost);
}

- (void)testCancelCompletionDoesNotRunActionAndLeavesFlagSet
{
	SATestConnectionLostGateHandler *handler = [[SATestConnectionLostGateHandler alloc] init];
	handler.backgroundConnectionLost = YES;
	__block NSUInteger actionCount = 0;

	[SAMultiTabConnectionLostGate runAction:^{
		actionCount++;
	} forHandler:handler];
	handler.capturedCompletion(SPMySQLConnectionLostDisconnect, YES);

	XCTAssertEqual(actionCount, 0U);
	XCTAssertEqual(handler.closeAndDisconnectCount, 0U);
	XCTAssertTrue(handler.backgroundConnectionLost);
}

// When the underlying `-reconnect` already ran the framework's async lost-
// connection sheet and the user picked Disconnect, SPDatabaseDocument's
// `connectionLost:completion:` already calls `-closeAndDisconnect` for that
// click. `-reconnect` then returns NO and `connectionGateUserChoseDisconnect`
// reports YES via the sheet-level flag. The gate MUST:
//   (1) skip the second Retry/Disconnect failure sheet, AND
//   (2) NOT call `closeAndDisconnectForGate` a second time —
// otherwise `-closeAndDisconnect` runs twice (non-idempotent: window close is
// re-scheduled, query history is re-persisted, the `wasConnected` branch
// flips, observers are removed again).
- (void)testReconnectFailureWithUserChosenDisconnectDoesNotDoubleClose
{
	__block NSUInteger actionCount = 0;
	SATestConnectionLostGateHandler *handler = [[SATestConnectionLostGateHandler alloc] init];
	handler.backgroundConnectionLost = YES;
	handler.reconnectResult = NO;                 // reconnect fails
	handler.userChoseDisconnect = YES;            // user picked Disconnect inside the framework sheet
	handler.handlerClosesInsideReconnect = YES;   // mirrors SPDatabaseDocument's first close
	handler.reconnectExpectation = [self expectationWithDescription:@"reconnect attempted"];

	[SAMultiTabConnectionLostGate runAction:^{
		actionCount++;
	} forHandler:handler];
	handler.capturedCompletion(SPMySQLConnectionLostReconnect, NO);
	[self waitForExpectationsWithTimeout:1 handler:nil];

	// Wait one main-queue turn so the failure-path branch can run on main.
	XCTestExpectation *mainTurn = [self expectationWithDescription:@"main turn"];
	dispatch_async(dispatch_get_main_queue(), ^{ [mainTurn fulfill]; });
	[self waitForExpectations:@[mainTurn] timeout:1];

	XCTAssertEqual(handler.reconnectCount, 1U, @"only one reconnect attempt should have run");
	XCTAssertEqual(handler.reconnectFailurePresentationCount, 0U,
		@"Retry/Disconnect failure sheet must NOT appear once user already chose Disconnect");
	XCTAssertEqual(handler.closeAndDisconnectCount, 1U,
		@"close must run exactly once (from SPDatabaseDocument's own delegate path), not twice");
	XCTAssertEqual(actionCount, 0U, @"original action must not run");
}

@end
