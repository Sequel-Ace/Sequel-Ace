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
	[self.reconnectExpectation fulfill];
	if ([self.queuedReconnectResults count]) {
		BOOL nextResult = [[self.queuedReconnectResults firstObject] boolValue];
		[self.queuedReconnectResults removeObjectAtIndex:0];
		return nextResult;
	}
	return self.reconnectResult;
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

@end
