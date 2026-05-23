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

- (void)testReconnectAllowingRetriesOnMainThreadFastReturnsAndDispatchesPrivateQueue
{
	SPMySQLConnection *connection = [[SPMySQLConnection alloc] init];
	XCTestExpectation *queuedReconnectExpectation = [self expectationWithDescription:@"queued reconnect"];
	__block NSUInteger reconnectCount = 0;
	[connection _setReconnectAttemptForTesting:^BOOL(BOOL canRetry) {
		reconnectCount++;
		[queuedReconnectExpectation fulfill];
		return YES;
	}];

	XCTAssertFalse([connection _reconnectAllowingRetries:YES]);
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

@end
