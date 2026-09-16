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
#import <SPMySQL/SPMySQL-Swift.h>

/**
 * How many times, a tenth of a second apart, the lost-connection question waits for another modal
 * window to close before it is asked anyway.
 */
static NSUInteger const SPMySQLConnectionModalWindowChecks = 50;

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
	delegateSupportsConnectionCheckProgress = [delegate respondsToSelector:@selector(connection:waitForConnectionWorkUntilFinished:)];
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

		// Trigger a reconnect depending on connection usage recently.  If the connection has
		// actively been used in the last couple of minutes, trigger a full reconnection attempt.
		if (_timeIntervalSinceMonotonicTime(lastConnectionUsedTime) < 60 * 2) {
            SPLog(@"If the connection has actively been used in the last couple of minutes, trigger a full reconnection attempt");
            SPLog(@"create new reconnectionThread");
			reconnectionThread = [[NSThread alloc] initWithTarget:self selector:@selector(_reconnectAllowingRetries:) object:@YES];
			[reconnectionThread setName:@"SPMySQL reconnection thread (full)"];
			[reconnectionThread start];

		// If used within the last fifteen minutes, trigger a background/single reconnection attempt
		} else if (_timeIntervalSinceMonotonicTime(lastConnectionUsedTime) < 60 * 15) {
            SPLog(@"If used within the last fifteen minutes, trigger a background/single reconnection attempt");
			reconnectionThread = [[NSThread alloc] initWithTarget:self selector:@selector(_reconnectAfterBackgroundConnectionLoss) object:nil];
			[reconnectionThread setName:@"SPMySQL reconnection thread (limited)"];
			[reconnectionThread start];

		// Otherwise set the state to connection lost for automatic reconnect on next use
		} else {
            SPLog(@"Otherwise set the state to connection lost for automatic reconnect on next use");
			state = SPMySQLConnectionLostInBackground;
		}
	}

	// Update the state record
	previousProxyState = newState;
}

/**
 * Ask the delegate for the connection lost decision.  This can be called from
 * any thread, and will call itself on the main thread if necessary, updating a global
 * variable which is then returned on the child thread.
 */
- (SPMySQLConnectionLostDecision)_delegateDecisionForLostConnection
{
	// If on the main thread, ask the delegate directly. That is the thread the question is put
	// to the user on, so it never waits for anybody else's answer.
	if ([NSThread isMainThread]) {
		return [self _askDelegateForLostConnectionDecision];
	}

	// Otherwise the question goes to the main thread, and threads that lose the connection at the
	// same time share one answer rather than asking one dialog each.
	return (SPMySQLConnectionLostDecision)[delegateDecisionGate decisionAskingWith:^NSInteger{

		// First check whether the application is in a modal state; if so, wait.
		// The question goes to the main thread through its run loop rather than through its
		// queue: the work that led here can itself have been started from a block on that
		// queue, and a queue runs one block at a time. Waiting for that block to finish would
		// mean waiting for something that is waiting for this answer.
		// The question is a sheet on the document's window, and asking it while another modal
		// window is up would stack the two. It waits for that window to go, but not for ever: a
		// question that never comes is worse than one that comes while something else is open.
		for (NSUInteger check = 0; check < SPMySQLConnectionModalWindowChecks; check++) {
			[self performSelectorOnMainThread:@selector(_recordWhetherAModalWindowIsShowing) withObject:nil waitUntilDone:YES];
			if (!self->aModalWindowIsShowing) break;
			usleep(100000);
		}

		[self performSelectorOnMainThread:@selector(_askDelegateForLostConnectionDecision) withObject:nil waitUntilDone:YES];
		[self->delegateDecisionLock lock];
		SPMySQLConnectionLostDecision decision = self->lastDelegateDecisionForLostConnection;
		[self->delegateDecisionLock unlock];

		return decision;
	}];
}

/**
 * Records whether the application is currently showing something modal. Only called on the main
 * thread, which is the only place that can be asked.
 */
- (void)_recordWhetherAModalWindowIsShowing
{
	aModalWindowIsShowing = ([NSApp modalWindow] != nil);
}

/**
 * Asks the delegate what to do about the lost connection, and keeps the answer as the last
 * decision under the lock that guards it.
 *
 * @return The delegate's decision.
 */
- (SPMySQLConnectionLostDecision)_askDelegateForLostConnectionDecision
{
	[delegateDecisionLock lock];
	lastDelegateDecisionForLostConnection = [delegate connectionLost:self];
	SPMySQLConnectionLostDecision theDecision = lastDelegateDecisionForLostConnection;
	[delegateDecisionLock unlock];

	return theDecision;
}

@end
