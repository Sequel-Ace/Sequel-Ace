//
//  SPMySQLConnectionLostTests.m
//  SPMySQL Unit Tests
//

#import <XCTest/XCTest.h>
#import <SPMySQL/SPMySQL.h>
#import "mysql.h"
#import "SPMySQL Private APIs.h"

@interface SPMySQLConnectionLostTestDelegate : NSObject <SPMySQLConnectionDelegate>
@property (nonatomic) NSUInteger asyncDecisionCount;
@property (nonatomic) NSUInteger syncDecisionCount;
@property (nonatomic) NSUInteger backgroundDecisionCount;
@property (nonatomic) NSUInteger restoredAfterLossCount;
@end

@implementation SPMySQLConnectionLostTestDelegate

- (void)connectionLost:(id)connection completion:(void (^)(SPMySQLConnectionLostDecision decision))completion
{
	self.asyncDecisionCount++;
	completion(SPMySQLConnectionLostReconnect);
}

- (SPMySQLConnectionLostDecision)connectionLost:(id)connection
{
	self.syncDecisionCount++;
	return SPMySQLConnectionLostDisconnect;
}

- (void)connectionLostInBackground:(id)connection
{
	self.backgroundDecisionCount++;
}

- (void)connectionRestoredAfterLoss:(id)connection
{
	self.restoredAfterLossCount++;
}

@end

@interface SPMySQLConnectionLostLegacyDelegate : NSObject <SPMySQLConnectionDelegate>
@property (nonatomic) NSUInteger syncDecisionCount;
@end

@implementation SPMySQLConnectionLostLegacyDelegate

- (SPMySQLConnectionLostDecision)connectionLost:(id)connection
{
	self.syncDecisionCount++;
	return SPMySQLConnectionLostReconnect;
}

@end

@interface SPMySQLConnectionLostDelayedDelegate : NSObject <SPMySQLConnectionDelegate>
@property (nonatomic) NSUInteger asyncDecisionCount;
@property (nonatomic) NSTimeInterval firstCompletionDelay;
@property (nonatomic) SPMySQLConnectionLostDecision firstDecision;
@property (nonatomic) SPMySQLConnectionLostDecision laterDecision;
@property (nonatomic, strong) XCTestExpectation *lateCompletionExpectation;
@end

@implementation SPMySQLConnectionLostDelayedDelegate

- (void)connectionLost:(id)connection completion:(void (^)(SPMySQLConnectionLostDecision decision))completion
{
	self.asyncDecisionCount++;
	NSUInteger decisionNumber = self.asyncDecisionCount;

	if (decisionNumber == 1) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.firstCompletionDelay * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			completion(self.firstDecision);
			[self.lateCompletionExpectation fulfill];
		});
		return;
	}

	completion(self.laterDecision);
}

@end

@interface SPMySQLConnectionRestoreSnapshotTestConnection : SPMySQLConnection
@property (nonatomic) BOOL nextConnectResult;
@property (nonatomic, copy) NSString *restoredDatabase;
@property (nonatomic, copy) NSString *restoredEncoding;
@property (nonatomic) BOOL restoredLatin1Transport;
@end

@implementation SPMySQLConnectionRestoreSnapshotTestConnection

- (BOOL)_connect
{
	[self _setStateForTesting:self.nextConnectResult ? SPMySQLConnected : SPMySQLDisconnected];
	return self.nextConnectResult;
}

- (void)_disconnect
{
}

- (void)_restoreSessionStateAfterReconnectWithDatabase:(NSString *)databaseName
                                              encoding:(NSString *)encodingName
                      encodingUsesLatin1Transport:(BOOL)useLatin1Transport
                                 timeZoneIdentifier:(NSString *)timeZoneIdentifier
{
	self.restoredDatabase = databaseName;
	self.restoredEncoding = encodingName;
	self.restoredLatin1Transport = useLatin1Transport;
}

@end

@interface SPMySQLConnectionCancelledReconnectTestConnection : SPMySQLConnection
@end

@implementation SPMySQLConnectionCancelledReconnectTestConnection

- (void)_disconnect
{
}

- (BOOL)_waitForNetworkConnectionWithTimeout:(double)timeoutSeconds
{
	[[NSThread currentThread] cancel];
	return NO;
}

@end

@interface SPMySQLConnectionLostTestProxy : NSObject <SPMySQLConnectionProxy>
@property (nonatomic) SPMySQLConnectionProxyState state;
@property (nonatomic) NSUInteger connectCount;
@property (nonatomic) NSUInteger disconnectCount;
@property (nonatomic) NSUInteger localPort;
@property (nonatomic, weak) id delegate;
@property (nonatomic) SEL stateChangeSelector;
- (void)simulateState:(SPMySQLConnectionProxyState)newState;
@end

@implementation SPMySQLConnectionLostTestProxy

- (instancetype)init
{
	if ((self = [super init])) {
		_state = SPMySQLProxyConnected;
		_localPort = 3307;
	}
	return self;
}

- (void)connect
{
	self.connectCount++;
	self.state = SPMySQLProxyConnected;
}

- (void)disconnect
{
	self.disconnectCount++;
	self.state = SPMySQLProxyIdle;
}

- (BOOL)setConnectionStateChangeSelector:(SEL)theStateChangeSelector delegate:(id)theDelegate
{
	self.stateChangeSelector = theStateChangeSelector;
	self.delegate = theDelegate;
	return YES;
}

- (void)simulateState:(SPMySQLConnectionProxyState)newState
{
	self.state = newState;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	[self.delegate performSelector:self.stateChangeSelector withObject:self];
#pragma clang diagnostic pop
}

@end

@interface SPMySQLConnectionLostTests : XCTestCase
@end

@implementation SPMySQLConnectionLostTests

- (void)testIsConnectedWithBackgroundLostStateReturnsNoWithoutDelegateDecision
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	SPMySQLConnectionLostTestDelegate *delegate = [[SPMySQLConnectionLostTestDelegate alloc] init];
	[connection setDelegate:delegate];
	[connection _setStateForTesting:SPMySQLConnectionLostInBackground];

	XCTAssertFalse([connection isConnected]);
	XCTAssertEqual(delegate.asyncDecisionCount, 0U);
	XCTAssertEqual(delegate.syncDecisionCount, 0U);
}

- (void)testCheckConnectionIfNecessaryOnMainThreadPostsNotificationWithoutDelegateDecision
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	SPMySQLConnectionLostTestDelegate *delegate = [[SPMySQLConnectionLostTestDelegate alloc] init];
	[connection setDelegate:delegate];
	[connection _setStateForTesting:SPMySQLConnectionLostInBackground];

	XCTestExpectation *notificationExpectation = [self expectationWithDescription:@"lost notification"];
	id token = [[NSNotificationCenter defaultCenter] addObserverForName:SPMySQLConnectionLostInBackgroundNotification object:connection queue:nil usingBlock:^(NSNotification *note) {
		[notificationExpectation fulfill];
	}];

	XCTAssertFalse([connection checkConnectionIfNecessary]);
	[self waitForExpectationsWithTimeout:1 handler:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqual(delegate.asyncDecisionCount, 0U);
	XCTAssertEqual(delegate.syncDecisionCount, 0U);
}

- (void)testCheckConnectionIfNecessaryOnMainThreadCoalescesBackgroundLossNotification
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	SPMySQLConnectionLostTestDelegate *delegate = [[SPMySQLConnectionLostTestDelegate alloc] init];
	[connection setDelegate:delegate];
	[connection _setStateForTesting:SPMySQLConnectionLostInBackground];
	__block NSUInteger notificationCount = 0;
	id token = [[NSNotificationCenter defaultCenter] addObserverForName:SPMySQLConnectionLostInBackgroundNotification object:connection queue:nil usingBlock:^(NSNotification *note) {
		notificationCount++;
	}];

	XCTAssertFalse([connection checkConnectionIfNecessary]);
	XCTAssertFalse([connection checkConnectionIfNecessary]);

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqual(notificationCount, 1U);
	XCTAssertEqual(delegate.backgroundDecisionCount, 1U);
}

- (void)testBackgroundLossNotificationCoalescingResetsAfterStateLeavesLost
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	[connection _setStateForTesting:SPMySQLConnectionLostInBackground];
	__block NSUInteger notificationCount = 0;
	id token = [[NSNotificationCenter defaultCenter] addObserverForName:SPMySQLConnectionLostInBackgroundNotification object:connection queue:nil usingBlock:^(NSNotification *note) {
		notificationCount++;
	}];

	XCTAssertFalse([connection checkConnectionIfNecessary]);
	[connection _setStateForTesting:SPMySQLConnected];
	[connection _setStateForTesting:SPMySQLConnectionLostInBackground];
	XCTAssertFalse([connection checkConnectionIfNecessary]);

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqual(notificationCount, 2U);
}

- (void)testCheckConnectionIfNecessaryOnWorkerThreadRunsReconnectPathForBackgroundLoss
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	[connection _setStateForTesting:SPMySQLConnectionLostInBackground];
	__weak SPMySQLConnection *weakConnection = connection;

	XCTestExpectation *reconnectExpectation = [self expectationWithDescription:@"worker reconnect"];
	__block NSUInteger reconnectCount = 0;
	[connection _setReconnectAttemptForTesting:^BOOL(BOOL canRetry) {
		reconnectCount++;
		XCTAssertTrue(canRetry);
		[weakConnection _setStateForTesting:SPMySQLConnected];
		[reconnectExpectation fulfill];
		return YES;
	}];

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		XCTAssertTrue([connection checkConnectionIfNecessary]);
	});

	[self waitForExpectationsWithTimeout:1 handler:nil];
	XCTAssertEqual(reconnectCount, 1U);
}

// Regression for Codex review on PR #2419:
// "This branch now returns immediately on the main thread after queueing reconnect
//  work, but existing synchronous callers (not updated in this commit) still depend
//  on -_reconnectAllowingRetries: completing before they continue."
//
// The 1-arg `_reconnectAllowingRetries:` wrapper used by cancelCurrentQuery,
// checkConnectionIfNecessary, etc. must run the reconnect SYNCHRONOUSLY even on
// the main thread; the unlock → reconnect → lock pattern depends on it.
// Callers that explicitly want the main-thread fast-return behavior must use the
// 2-arg form with `dispatchOnMainThread:YES`.
- (void)testLegacyOneArgReconnectIsSynchronousOnMainThread
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	__block NSUInteger reconnectCount = 0;
	[connection _setReconnectAttemptForTesting:^BOOL(BOOL canRetry) {
		reconnectCount++;
		return YES;
	}];

	XCTAssertTrue([NSThread isMainThread], @"test runs on the main thread");
	BOOL result = [connection _reconnectAllowingRetries:YES];

	XCTAssertEqual(reconnectCount, 1U,
		@"1-arg _reconnectAllowingRetries: must run the reconnect synchronously on main thread.");
	XCTAssertTrue(result, @"sync reconnect should return the real outcome, not an early NO");
}

// Companion test: callers that explicitly want main-thread fast-return semantics
// can still get them via the 2-arg form.
- (void)testTwoArgReconnectWithDispatchOnMainThreadYesQueuesAndFastReturns
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	XCTestExpectation *queuedReconnectExpectation = [self expectationWithDescription:@"queued reconnect"];
	__block NSUInteger reconnectCount = 0;
	[connection _setReconnectAttemptForTesting:^BOOL(BOOL canRetry) {
		reconnectCount++;
		[queuedReconnectExpectation fulfill];
		return YES;
	}];

	XCTAssertFalse([connection _reconnectAllowingRetries:YES dispatchOnMainThread:YES]);
	[self waitForExpectationsWithTimeout:1 handler:nil];
	[connection _drainReconnectQueueForTesting];
	XCTAssertEqual(reconnectCount, 1U);
}

- (void)testPublicReconnectOnWorkerThreadReturnsReconnectResult
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	XCTestExpectation *reconnectExpectation = [self expectationWithDescription:@"public reconnect"];
	__block NSUInteger reconnectCount = 0;
	[connection _setReconnectAttemptForTesting:^BOOL(BOOL canRetry) {
		reconnectCount++;
		XCTAssertTrue(canRetry);
		return YES;
	}];

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		XCTAssertTrue([connection reconnect]);
		[reconnectExpectation fulfill];
	});

	[self waitForExpectationsWithTimeout:1 handler:nil];
	XCTAssertEqual(reconnectCount, 1U);
}

- (void)testConcurrentReconnectRequestsShareSingleSilentAttempt
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	[connection _setStateForTesting:SPMySQLConnectionLostInBackground];
	__weak SPMySQLConnection *weakConnection = connection;

	dispatch_group_t reconnectGroup = dispatch_group_create();
	dispatch_semaphore_t firstAttemptStarted = dispatch_semaphore_create(0);
	dispatch_semaphore_t releaseFirstAttempt = dispatch_semaphore_create(0);
	__block NSUInteger reconnectCount = 0;
	__block BOOL firstResult = NO;
	__block BOOL secondResult = NO;
	[connection _setSilentReconnectAttemptForTesting:^BOOL{
		reconnectCount++;
		dispatch_semaphore_signal(firstAttemptStarted);
		dispatch_semaphore_wait(releaseFirstAttempt, DISPATCH_TIME_FOREVER);
		[weakConnection _setStateForTesting:SPMySQLConnected];
		return YES;
	}];

	dispatch_group_async(reconnectGroup, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		firstResult = [connection _reconnectAllowingRetries:YES];
	});
	dispatch_semaphore_wait(firstAttemptStarted, DISPATCH_TIME_FOREVER);
	dispatch_group_async(reconnectGroup, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		secondResult = [connection _reconnectAllowingRetries:YES];
	});
	dispatch_semaphore_signal(releaseFirstAttempt);

	long waitResult = dispatch_group_wait(reconnectGroup, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)));
	XCTAssertEqual(waitResult, 0L);
	XCTAssertTrue(firstResult);
	XCTAssertTrue(secondResult);
	XCTAssertEqual(reconnectCount, 1U);
}

- (void)testDelegateDrivenReconnectSuccessNotifiesDelegateAfterRestoration
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	SPMySQLConnectionLostTestDelegate *delegate = [[SPMySQLConnectionLostTestDelegate alloc] init];
	[connection setDelegate:delegate];
	__weak SPMySQLConnection *weakConnection = connection;
	__block NSUInteger reconnectCount = 0;
	[connection _setSilentReconnectAttemptForTesting:^BOOL{
		reconnectCount++;
		if (reconnectCount == 2) {
			[weakConnection _setStateForTesting:SPMySQLConnected];
			return YES;
		}
		[weakConnection _setStateForTesting:SPMySQLDisconnected];
		return NO;
	}];

	XCTestExpectation *reconnectExpectation = [self expectationWithDescription:@"delegate reconnect completed"];
	__block BOOL reconnectResult = NO;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		reconnectResult = [connection _reconnectAllowingRetries:YES];
		[reconnectExpectation fulfill];
	});

	[self waitForExpectations:@[reconnectExpectation] timeout:1];
	XCTAssertTrue(reconnectResult);
	XCTAssertEqual(delegate.asyncDecisionCount, 1U);
	XCTAssertEqual(delegate.restoredAfterLossCount, 1U);
	XCTAssertEqual(reconnectCount, 2U);
}

- (void)testCancelledSilentReconnectRestoresProxyNotificationFlag
{
	SPMySQLConnectionCancelledReconnectTestConnection *connection = [[SPMySQLConnectionCancelledReconnectTestConnection alloc] init];
	SPMySQLConnectionLostTestProxy *proxy = [[SPMySQLConnectionLostTestProxy alloc] init];
	[connection setProxy:proxy];

	XCTestExpectation *reconnectExpectation = [self expectationWithDescription:@"cancelled silent reconnect"];
	NSThread *reconnectThread = [[NSThread alloc] initWithBlock:^{
		XCTAssertFalse([connection _silentReconnectAttempt]);
		[reconnectExpectation fulfill];
	}];
	[reconnectThread start];

	[self waitForExpectations:@[reconnectExpectation] timeout:1];
	XCTAssertFalse([connection _proxyStateChangeNotificationsIgnoredForTesting]);
}

- (void)testSilentReconnectRecapturesRestoreSnapshotAfterFailure
{
	SPMySQLConnectionRestoreSnapshotTestConnection *connection = [[SPMySQLConnectionRestoreSnapshotTestConnection alloc] init];
	connection.database = @"first";
	[connection setValue:@"utf8mb4" forKey:@"encoding"];
	[connection setValue:@NO forKey:@"encodingUsesLatin1Transport"];
	connection.nextConnectResult = NO;

	XCTAssertFalse([connection _silentReconnectAttempt]);

	connection.database = @"second";
	[connection setValue:@"latin1" forKey:@"encoding"];
	[connection setValue:@NO forKey:@"encodingUsesLatin1Transport"];
	connection.nextConnectResult = YES;

	XCTAssertTrue([connection _silentReconnectAttempt]);
	XCTAssertEqualObjects(connection.restoredDatabase, @"second");
	XCTAssertEqualObjects(connection.restoredEncoding, @"latin1");
	XCTAssertFalse(connection.restoredLatin1Transport);
}

- (void)testKeepAlivePingFailurePostsBackgroundNotificationWithoutDelegateDecision
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	SPMySQLConnectionLostTestDelegate *delegate = [[SPMySQLConnectionLostTestDelegate alloc] init];
	[connection setDelegate:delegate];
	[connection _setStateForTesting:SPMySQLConnected];
	[connection _setKeepAlivePingFailuresForTesting:3];

	XCTestExpectation *notificationExpectation = [self expectationWithDescription:@"keepalive notification"];
	id token = [[NSNotificationCenter defaultCenter] addObserverForName:SPMySQLConnectionLostInBackgroundNotification object:connection queue:nil usingBlock:^(NSNotification *note) {
		[notificationExpectation fulfill];
	}];

	[connection _threadedKeepAlive];
	[self waitForExpectationsWithTimeout:1 handler:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqual([connection _stateForTesting], SPMySQLConnectionLostInBackground);
	XCTAssertEqual(delegate.asyncDecisionCount, 0U);
	XCTAssertEqual(delegate.syncDecisionCount, 0U);
	XCTAssertEqual(delegate.backgroundDecisionCount, 1U);
}

- (void)testAsyncConnectionLostDelegateIsPreferredOverDeprecatedDelegate
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	SPMySQLConnectionLostTestDelegate *delegate = [[SPMySQLConnectionLostTestDelegate alloc] init];
	[connection setDelegate:delegate];

	XCTestExpectation *decisionExpectation = [self expectationWithDescription:@"async decision"];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		SPMySQLConnectionLostDecision decision = [connection _delegateDecisionForLostConnection];
		XCTAssertEqual(decision, SPMySQLConnectionLostReconnect);
		[decisionExpectation fulfill];
	});

	[self waitForExpectationsWithTimeout:1 handler:nil];
	XCTAssertEqual(delegate.asyncDecisionCount, 1U);
	XCTAssertEqual(delegate.syncDecisionCount, 0U);
}

- (void)testDeprecatedConnectionLostDelegateIsNotCalledOnMainThread
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	SPMySQLConnectionLostLegacyDelegate *delegate = [[SPMySQLConnectionLostLegacyDelegate alloc] init];
	[connection setDelegate:delegate];

	SPMySQLConnectionLostDecision decision = [connection _delegateDecisionForLostConnection];

	XCTAssertEqual(decision, SPMySQLConnectionLostDisconnect);
	XCTAssertEqual(delegate.syncDecisionCount, 0U);
}

- (void)testAsyncDelegateLateCompletionDoesNotPolluteNextDecision
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	SPMySQLConnectionLostDelayedDelegate *delegate = [[SPMySQLConnectionLostDelayedDelegate alloc] init];
	delegate.firstCompletionDelay = 0.15;
	delegate.firstDecision = SPMySQLConnectionLostReconnect;
	delegate.laterDecision = SPMySQLConnectionLostDisconnect;
	delegate.lateCompletionExpectation = [self expectationWithDescription:@"late completion"];
	[connection setDelegate:delegate];
	[connection _setDelegateDecisionTimeoutForTesting:0.05];

	XCTestExpectation *firstDecisionExpectation = [self expectationWithDescription:@"first decision"];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		SPMySQLConnectionLostDecision decision = [connection _delegateDecisionForLostConnection];
		XCTAssertEqual(decision, SPMySQLConnectionLostDisconnect);
		[firstDecisionExpectation fulfill];
	});

	[self waitForExpectations:@[firstDecisionExpectation] timeout:1];
	[connection _setDelegateDecisionTimeoutForTesting:1];

	XCTestExpectation *secondDecisionExpectation = [self expectationWithDescription:@"second decision"];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		SPMySQLConnectionLostDecision decision = [connection _delegateDecisionForLostConnection];
		XCTAssertEqual(decision, SPMySQLConnectionLostDisconnect);
		[secondDecisionExpectation fulfill];
	});

	[self waitForExpectations:@[secondDecisionExpectation, delegate.lateCompletionExpectation] timeout:1];
	XCTAssertEqual(delegate.asyncDecisionCount, 2U);
}

- (void)testDelegateDecisionSourceHasNoLegacyMainThreadDoWhileWaitBlock
{
	NSString *testFilePath = [NSString stringWithUTF8String:__FILE__];
	NSString *sourceRoot = [testFilePath stringByDeletingLastPathComponent];
	sourceRoot = [sourceRoot stringByDeletingLastPathComponent];
	NSString *sourcePath = [sourceRoot stringByAppendingPathComponent:@"Source/SPMySQLConnection Categories/Delegate & Proxy.m"];
	NSString *source = [NSString stringWithContentsOfFile:sourcePath encoding:NSUTF8StringEncoding error:nil];

	XCTAssertNotNil(source);
	XCTAssertFalse([source containsString:@"while (0)"]);
	XCTAssertFalse([source containsString:@"performSelectorOnMainThread:@selector(_delegateDecisionForLostConnection)"]);
}

- (void)testDisconnectFromBackgroundLostStateStillDisconnectsProxy
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	SPMySQLConnectionLostTestProxy *proxy = [[SPMySQLConnectionLostTestProxy alloc] init];
	[connection setProxy:proxy];
	[connection _setStateForTesting:SPMySQLConnectionLostInBackground];

	[connection _disconnect];

	XCTAssertEqual([connection _stateForTesting], SPMySQLDisconnected);
	XCTAssertEqual(proxy.disconnectCount, 1U);
}

- (void)testDisconnectSourceHasNoBlockingProxyMainThreadSelector
{
	NSString *testFilePath = [NSString stringWithUTF8String:__FILE__];
	NSString *sourceRoot = [testFilePath stringByDeletingLastPathComponent];
	sourceRoot = [sourceRoot stringByDeletingLastPathComponent];
	NSString *sourcePath = [sourceRoot stringByAppendingPathComponent:@"Source/SPMySQLConnection.m"];
	NSString *source = [NSString stringWithContentsOfFile:sourcePath encoding:NSUTF8StringEncoding error:nil];

	XCTAssertNotNil(source);
	XCTAssertFalse([source containsString:@"performSelectorOnMainThread:@selector(disconnect)"]);
	XCTAssertFalse([source containsString:@"waitUntilDone:YES"]);
}

- (void)testProxyIdleWithinTwoMinutesSilentReconnectSuccessDoesNotNotifyOrAskDelegate
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	SPMySQLConnectionLostTestProxy *proxy = [[SPMySQLConnectionLostTestProxy alloc] init];
	SPMySQLConnectionLostTestDelegate *delegate = [[SPMySQLConnectionLostTestDelegate alloc] init];
	[connection setDelegate:delegate];
	[connection setProxy:proxy];
	[connection _setStateForTesting:SPMySQLConnected];
	[connection _setLastConnectionUsedTimeForTestingWithSecondsAgo:120];
	__weak SPMySQLConnection *weakConnection = connection;

	XCTestExpectation *reconnectExpectation = [self expectationWithDescription:@"silent reconnect"];
	[connection _setSilentReconnectAttemptForTesting:^BOOL{
		[weakConnection _setStateForTesting:SPMySQLConnected];
		[reconnectExpectation fulfill];
		return YES;
	}];

	id token = [[NSNotificationCenter defaultCenter] addObserverForName:SPMySQLConnectionLostInBackgroundNotification object:connection queue:nil usingBlock:^(NSNotification *note) {
		XCTFail(@"silent reconnect success should not post background loss notification");
	}];

	[proxy simulateState:SPMySQLProxyIdle];
	[self waitForExpectationsWithTimeout:1 handler:nil];
	[connection _drainReconnectQueueForTesting];
	[[NSNotificationCenter defaultCenter] removeObserver:token];

	XCTAssertEqual([connection _stateForTesting], SPMySQLConnected);
	XCTAssertFalse([connection _proxyStateChangeNotificationsIgnoredForTesting]);
	XCTAssertEqual(delegate.asyncDecisionCount, 0U);
	XCTAssertEqual(delegate.syncDecisionCount, 0U);
}

- (void)testProxyIdleWithinFifteenMinutesSilentReconnectFailurePostsOnceAndResetsFlag
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	SPMySQLConnectionLostTestProxy *proxy = [[SPMySQLConnectionLostTestProxy alloc] init];
	SPMySQLConnectionLostTestDelegate *delegate = [[SPMySQLConnectionLostTestDelegate alloc] init];
	[connection setDelegate:delegate];
	[connection setProxy:proxy];
	[connection _setStateForTesting:SPMySQLConnected];
	[connection _setLastConnectionUsedTimeForTestingWithSecondsAgo:14 * 60];

	XCTestExpectation *notificationExpectation = [self expectationWithDescription:@"proxy failure notification"];
	notificationExpectation.expectedFulfillmentCount = 1;
	id token = [[NSNotificationCenter defaultCenter] addObserverForName:SPMySQLConnectionLostInBackgroundNotification object:connection queue:nil usingBlock:^(NSNotification *note) {
		[notificationExpectation fulfill];
	}];

	[connection _setSilentReconnectAttemptForTesting:^BOOL{
		return NO;
	}];

	[proxy simulateState:SPMySQLProxyIdle];
	[self waitForExpectationsWithTimeout:1 handler:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:token];

	XCTAssertEqual([connection _stateForTesting], SPMySQLConnectionLostInBackground);
	XCTAssertFalse([connection _proxyStateChangeNotificationsIgnoredForTesting]);
	XCTAssertEqual(delegate.asyncDecisionCount, 0U);
	XCTAssertEqual(delegate.syncDecisionCount, 0U);
}

- (void)testProxyIdleAfterFifteenMinutesDoesNotSilentReconnectAndPostsNotification
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	SPMySQLConnectionLostTestProxy *proxy = [[SPMySQLConnectionLostTestProxy alloc] init];
	[connection setProxy:proxy];
	[connection _setStateForTesting:SPMySQLConnected];
	[connection _setLastConnectionUsedTimeForTestingWithSecondsAgo:16 * 60];

	__block NSUInteger silentReconnectCount = 0;
	[connection _setSilentReconnectAttemptForTesting:^BOOL{
		silentReconnectCount++;
		return YES;
	}];

	XCTestExpectation *notificationExpectation = [self expectationWithDescription:@"old proxy notification"];
	id token = [[NSNotificationCenter defaultCenter] addObserverForName:SPMySQLConnectionLostInBackgroundNotification object:connection queue:nil usingBlock:^(NSNotification *note) {
		[notificationExpectation fulfill];
	}];

	[proxy simulateState:SPMySQLProxyIdle];
	[self waitForExpectationsWithTimeout:1 handler:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:token];

	XCTAssertEqual(silentReconnectCount, 0U);
	XCTAssertEqual([connection _stateForTesting], SPMySQLConnectionLostInBackground);
	XCTAssertFalse([connection _proxyStateChangeNotificationsIgnoredForTesting]);
}

// Regression for Codex review on PR #2419 P2:
// "Restoration callbacks are gated on `delegateReconnectDecisionRequested`, so
//  successful silent reconnects (worker-thread recovery from
//  SPMySQLConnectionLostInBackground) do not emit `connectionRestoredAfterLoss:`."
//
// Silent worker-thread recovery from Lost-in-Background MUST notify the delegate
// so SPDatabaseDocument can clear its backgroundConnectionLost flag.
- (void)testSilentReconnectFromLostInBackgroundFiresRestorationCallback
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	SPMySQLConnectionLostTestDelegate *delegate = [[SPMySQLConnectionLostTestDelegate alloc] init];
	[connection setDelegate:delegate];

	// Set up the lost-in-background state that worker-thread silent reconnect handles.
	[connection _setStateForTesting:SPMySQLConnectionLostInBackground];

	[connection _setSilentReconnectAttemptForTesting:^BOOL{
		return YES;
	}];

	// Run on a worker thread so the main-thread fast-return guard does not apply.
	XCTestExpectation *done = [self expectationWithDescription:@"silent recovery"];
	__block BOOL succeeded = NO;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		succeeded = [connection _reconnectAllowingRetries:YES];
		[done fulfill];
	});
	[self waitForExpectationsWithTimeout:5 handler:nil];

	XCTAssertTrue(succeeded);
	XCTAssertEqual(delegate.restoredAfterLossCount, 1U,
		@"Silent worker-thread recovery from Lost-in-Background must fire connectionRestoredAfterLoss: "
		@"so app-layer observers can clear their backgroundConnectionLost flag.");
}

@end
