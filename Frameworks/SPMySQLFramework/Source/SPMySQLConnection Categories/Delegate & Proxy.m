//
//  Delegate & Proxy.m
//  SPMySQLFramework
//
//  Created by Rowan Beentje (rowan.beent.je) on February 9, 2012
//  Copyright (c) 2012 Rowan Beentje. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  More info at <https://github.com/sequelpro/sequelpro>

#import "Delegate & Proxy.h"
#import "SPMySQL Private APIs.h"

@implementation SPMySQLConnection (Delegate_and_Proxy)

#pragma mark -
#pragma mark Connection delegate

/**
 * Set the delegate of the connection object, precaching availability of
 * oft-called methods to allow optimisation.
 */
- (void)setDelegate:(NSObject <SPMySQLConnectionDelegate> *)aDelegate
{
	delegate = aDelegate;

	// Cache whether the delegate implements certain delegate methods
	delegateSupportsWillQueryString = [delegate respondsToSelector:@selector(willQueryString:connection:)];
	delegateSupportsConnectionLost = [delegate respondsToSelector:@selector(connectionLost:)];
	delegateSupportsConnectionLostAsync = [delegate respondsToSelector:@selector(connectionLost:completion:)];
	delegateSupportsConnectionLostBackground = [delegate respondsToSelector:@selector(connectionLostInBackground:)];
}

/**
 * Return the current instance delegate.
 */
- (NSObject <SPMySQLConnectionDelegate> *)delegate
{
	return delegate;
}

#pragma mark -
#pragma mark Connection proxy

/**
 * Set the connection proxy, used by the class to set up a connection pre-requisite, and
 * monitored for state changes.  This allows the MySQL connection to be routed over
 * another helper class providing a port or socket.  This method also records the initial
 * state and sets the state change selector.
 */
- (void)setProxy:(NSObject <SPMySQLConnectionProxy> *)aProxy
{
	proxy = aProxy;
	previousProxyState = [aProxy state];

	[proxy setConnectionStateChangeSelector:@selector(_proxyStateChange:) delegate:self];
}

/**
 * Return the current instance proxy.
 */
- (NSObject <SPMySQLConnectionProxy> *)proxy
{
	return proxy;
}

@end

#pragma mark -

@implementation SPMySQLConnection (Delegate_and_Proxy_Private_API)

/**
 * Handle any state changes in the associated connection proxy.
 */
- (void)_proxyStateChange:(NSObject <SPMySQLConnectionProxy> *)aProxy
{
    SPLog(@"_proxyStateChange");

	NSThread *reconnectionThread;

	// Perform no actions if this isn't the current connection proxy, or if notifications
	// are currently set to be ignored
    if (aProxy != proxy || proxyStateChangeNotificationsIgnored){
        SPLog(@"aProxy != proxy || proxyStateChangeNotificationsIgnored, returning");
        return;
    }

	SPMySQLConnectionProxyState newState = [aProxy state];

    SPLog(@"state = %i", newState);

	// If the connection proxy disconnects, trigger a reconnect; use a new thread to allow the
	// main thread to process events as required.
	if (state == SPMySQLConnected && newState == SPMySQLProxyIdle && previousProxyState == SPMySQLProxyConnected) {

        SPLog(@"state == SPMySQLConnected && newState == SPMySQLProxyIdle && previousProxyState == SPMySQLProxyConnected");

		// Clear the state change selector on the proxy until a connection is re-established
		proxyStateChangeNotificationsIgnored = YES;

		// If used within the last fifteen minutes, trigger a silent single reconnect attempt.
		if (_timeIntervalSinceMonotonicTime(lastConnectionUsedTime) < 60 * 15) {
            SPLog(@"If used within the last fifteen minutes, trigger a silent background reconnection attempt");
			reconnectionThread = [[NSThread alloc] initWithTarget:self selector:@selector(_silentReconnectForProxyLoss) object:nil];
			[reconnectionThread setName:@"SPMySQL silent proxy reconnect"];
			[reconnectionThread start];

		// Otherwise set the state to connection lost for automatic reconnect on next use
		} else {
            SPLog(@"Otherwise set the state to connection lost for automatic reconnect on next use");
			state = SPMySQLConnectionLostInBackground;
			proxyStateChangeNotificationsIgnored = NO;
			[self _postLostInBackgroundNotification];
		}
	}

	// Update the state record
	previousProxyState = newState;
}

- (void)_silentReconnectForProxyLoss
{
	@autoreleasepool {
		BOOL reconnectSucceeded = [self _silentReconnectAttempt];

		reconnectingThread = NULL;
		proxyStateChangeNotificationsIgnored = NO;

		if (!reconnectSucceeded) {
			state = SPMySQLConnectionLostInBackground;
			[self _postLostInBackgroundNotification];
		}
	}
}

/**
 * Ask the delegate for the connection lost decision. This must be called from
 * a worker thread; main-thread callers default to disconnect to avoid blocking UI.
 */
- (SPMySQLConnectionLostDecision)_delegateDecisionForLostConnection
{
	SPMySQLConnectionLostDecision theDecision = SPMySQLConnectionLostDisconnect;

	if ([NSThread isMainThread]) {
		SPLog(@"Suppressing connectionLost: delegate decision on main thread; defaulting to disconnect");
		return SPMySQLConnectionLostDisconnect;
	}

	if (delegateSupportsConnectionLostAsync) {
		dispatch_semaphore_t decisionSemaphore = dispatch_semaphore_create(0);

		[delegate connectionLost:self completion:^(SPMySQLConnectionLostDecision decision) {
			[self->delegateDecisionLock lock];
			self->lastDelegateDecisionForLostConnection = decision;
			[self->delegateDecisionLock unlock];

			dispatch_semaphore_signal(decisionSemaphore);
		}];

		if (dispatch_semaphore_wait(decisionSemaphore, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)) != 0) {
			SPLog(@"Timed out waiting for async connectionLost:completion: delegate decision; defaulting to disconnect");
			return SPMySQLConnectionLostDisconnect;
		}

		[delegateDecisionLock lock];
		theDecision = lastDelegateDecisionForLostConnection;
		[delegateDecisionLock unlock];
		return theDecision;
	}

	if (delegateSupportsConnectionLost) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		[delegateDecisionLock lock];
		lastDelegateDecisionForLostConnection = [delegate connectionLost:self];
		theDecision = lastDelegateDecisionForLostConnection;
		[delegateDecisionLock unlock];
#pragma clang diagnostic pop
	}

	return theDecision;
}

@end
