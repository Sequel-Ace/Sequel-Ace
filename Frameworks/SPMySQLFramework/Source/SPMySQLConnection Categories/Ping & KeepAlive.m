//
//  Ping & KeepAlive.m
//  SPMySQLFramework
//
//  Created by Rowan Beentje (rowan.beent.je) on January 14, 2012
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

#import "Ping & KeepAlive.h"
#import "SPMySQL Private APIs.h"
#import "Locking.h"
#import <pthread.h>
#include <stdio.h>

typedef struct {
	MYSQL *mySQLConnection;
	volatile BOOL *keepAlivePingThreadActivePointer;
	volatile BOOL *keepAliveLastPingSuccessPointer;
	void *parentId;
} SPMySQLConnectionPingDetails;

@implementation SPMySQLConnection (Ping_and_KeepAlive)

#pragma mark -
#pragma mark Keepalive ping initialisation

/**
 * Keeps the connection alive by running a ping.
 * This method is called every ten seconds and spawns a thread which determines
 * whether or not it should perform a ping.
 */
- (void)_keepAlive
{

    SPLog(@"_keepAlive");

	// Do nothing if not connected, if keepalive is disabled, or a keepalive is in
	// progress.
    if (state != SPMySQLConnected || !useKeepAlive) {
        SPLog(@"not connected. returning, state: %@. useKeepAlive: %d", [self connectionStateStringForState], useKeepAlive);
        return;
    }

	// Check to see whether a ping is required.  First, compare the last query
	// and keepalive times against the keepalive interval.
	// Compare against interval-1 to allow default keepalive intervals to repeat
	// at the correct intervals (eg no timer interval delay).
	uint64_t currentTime = _monotonicTime();
	if (_timeIntervalSinceMonotonicTime(lastConnectionUsedTime) < keepAliveInterval - 1
		|| _timeIntervalSinceMonotonicTime(lastKeepAliveTime) < keepAliveInterval - 1)
	{
        SPLog(@"ping is NOT required");
        SPLog(@"lastConnectionUsedTime: %llu", lastConnectionUsedTime);
        SPLog(@"lastKeepAliveTime: %llu", lastKeepAliveTime);
        SPLog(@"_timeIntervalSinceMonotonicTime(lastConnectionUsedTime): %f", _timeIntervalSinceMonotonicTime(lastConnectionUsedTime));
        SPLog(@"_timeIntervalSinceMonotonicTime(lastKeepAliveTime): %f", _timeIntervalSinceMonotonicTime(lastKeepAliveTime));
        SPLog(@"keepAliveInterval: %f", keepAliveInterval);

        /*
         MySQLConnection(Ping_and_KeepAlive) _keepAlive]:76: lastKeepAliveTime: 0
         2021-01-27 18:53:30.589236+0800 Sequel Ace[82522:3755269] -[SPMySQLConnection(Ping_and_KeepAlive) _keepAlive]:77: _timeIntervalSinceMonotonicTime(lastConnectionUsedTime): 18.960916
         2021-01-27 18:53:30.589279+0800 Sequel Ace[82522:3755269] -[SPMySQLConnection(Ping_and_KeepAlive) _keepAlive]:78: _timeIntervalSinceMonotonicTime(lastKeepAliveTime): 500786.905401
         2021-01-27 18:53:30.589312+0800 Sequel Ace[82522:3755269] -[SPMySQLConnection(Ping_and_KeepAlive) _keepAlive]:79: keepAliveInterval: 60.000000
         */
		return;
	}

	// Attempt to lock the connection. If the connection is currently busy,
    // we don't need a ping.
    if (![self _tryLockConnection]){
        SPLog(@"! _tryLockConnection. ping is NOT required");
        return;
    }
	[self _unlockConnection];

	// Store the ping time
	lastKeepAliveTime = currentTime;

	[NSThread detachNewThreadSelector:@selector(_threadedKeepAlive) toTarget:self withObject:nil];
}

/**
 * A threaded keepalive to avoid blocking the interface.  Performs safety
 * checks, and then creates a child pthread to actually ping the connection,
 * forcing the thread to close after the timeout if it hasn't closed already.
 */
- (void)_threadedKeepAlive
{

    SPLog(@"_threadedKeepAlive");


	@autoreleasepool {
		@synchronized(self) {
			if(keepAliveThread) {
				NSLog(@"warning: overwriting existing keepAliveThread: %@, results may be unpredictable!",keepAliveThread);
			}
			keepAliveThread = [NSThread currentThread];
		}

		[keepAliveThread setName:[NSString stringWithFormat:@"SPMySQL connection keepalive monitor thread (id=%p)", self]];

		// If the maximum number of ping failures has been reached, determine whether to reconnect.
		if (keepAliveLastPingBlocked || keepAlivePingFailures >= 3) {

			// If the connection has been used within the last fifteen minutes,
			// attempt a single reconnection in the background
			if (_timeIntervalSinceMonotonicTime(lastConnectionUsedTime) < 60 * 15) {
                SPLog(@"calling _reconnectAfterBackgroundConnectionLoss");

				[self _reconnectAfterBackgroundConnectionLoss];
			}
			// Otherwise set the state to connection lost for automatic reconnect on
			// next use.
			else {
				state = SPMySQLConnectionLostInBackground;
			}

			// Return as no further ping action required this cycle.
			goto end_cleanup;
		}

		// Otherwise, perform a background ping.
        SPLog(@"perform a background ping");

		BOOL pingResult = [self _pingConnectionUsingLoopDelay:10000];
		if (pingResult) {
			keepAlivePingFailures = 0;
		} else {
			keepAlivePingFailures++;
		}
end_cleanup:
		@synchronized(self) {
			keepAliveThread = nil;
		}
	}
}

#pragma mark -
#pragma mark Master ping method

/**
 * This function provides a method of pinging the remote server while also enforcing
 * the specified connection time.  This is required because low-level net reads can
 * block indefinitely if the remote server disappears or on network issues - setting
 * the MYSQL_OPT_READ_TIMEOUT (and the WRITE equivalent) would "fix" ping, but cause
 * long queries to be terminated.
 * The supplied loop delay number controls how tight the thread checking loop is, in
 * microseconds, to allow differentiating foreground and background pings.
 * Unlike mysql_ping, this function returns FALSE on failure and TRUE on success.
 */
- (BOOL)_pingConnectionUsingLoopDelay:(NSUInteger)loopDelay
{
    SPLog(@"_pingConnectionUsingLoopDelay");

	if (state != SPMySQLConnected) return NO;

	uint64_t pingStartTime_t;
	double pingElapsedTime;
	BOOL threadCancelled = NO;

	// Set up a query lock
	[self _lockConnection];
	//we might find ourselves at the losing end of a contest with -[self _disconnect]
	if(!mySQLConnection) {
        SPLog(@"!mySQLConnection, calling _unlockConnection, return NO");
		[self _unlockConnection];
		return NO;
	}

	volatile BOOL keepAliveLastPingSuccess = NO;
	keepAliveLastPingBlocked = NO;
	keepAlivePingThreadActive = YES;

	// Use a ping timeout defaulting to thirty seconds, but using the connection timeout if set
	NSUInteger pingTimeout = 30;
	if (timeout > 0) pingTimeout = timeout;

	// Set up a struct containing details the ping task will need
	// we can do this on the stack since this method makes sure to outlive the ping thread
	SPMySQLConnectionPingDetails pingDetails = {
		.mySQLConnection = mySQLConnection,
		.keepAliveLastPingSuccessPointer = &keepAliveLastPingSuccess,
		.keepAlivePingThreadActivePointer = &keepAlivePingThreadActive,
        .parentId = (__bridge void *)(self)
	};


	// Create a pthread for the ping
	pthread_t keepAlivePingThread_t;
	
	pthread_attr_t attr;
	pthread_attr_init(&attr);
	pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_JOINABLE);
	pthread_create(&keepAlivePingThread_t, &attr, (void *)&_backgroundPingTask, &pingDetails);

	// Record the ping start time
	pingStartTime_t = _monotonicTime();

	// Loop until the ping completes
	do {
		usleep((useconds_t)loopDelay);
		pingElapsedTime = _timeIntervalSinceMonotonicTime(pingStartTime_t);

		// If the ping timeout has been exceeded, or the ping thread has been
		// cancelled, force a timeout; double-check that the thread is still active.
		if (
			([[NSThread currentThread] isCancelled] || pingElapsedTime > pingTimeout)
			&& keepAlivePingThreadActive
			&& !threadCancelled
		) {
			pthread_cancel(keepAlivePingThread_t);
			threadCancelled = YES;

		// If the timeout has been exceeded by an additional two seconds, and the thread is
		// still active, kill the thread.  This can occur in certain network conditions causing
		// a blocking read.
		} else if (pingElapsedTime > (pingTimeout + 2) && keepAlivePingThreadActive) {
			pthread_kill(keepAlivePingThread_t, SIGUSR1);	
			keepAlivePingThreadActive = NO;
			keepAliveLastPingBlocked = YES;
		}
	} while (keepAlivePingThreadActive);


    SPLog(@"threadCancelled: %d", threadCancelled);
    SPLog(@"pingElapsedTime: %f", pingElapsedTime);

	//wait for thread to go away, otherwise pingDetails may go away before _pingThreadCleanup() finishes
	pthread_join(keepAlivePingThread_t, NULL);

	// Clean up
	keepAlivePingThread_t = NULL;
	pthread_attr_destroy(&attr);

	// Unlock the connection
	[self _unlockConnection];

    SPLog(@"keepAliveLastPingSuccess: %d", keepAliveLastPingSuccess);

	return keepAliveLastPingSuccess;
}

#pragma mark -
#pragma mark Ping thread internals

/**
 * Actually perform a keepalive ping - intended for use within a pthread.
 */
void _backgroundPingTask(void *ptr)
{
    SPLog(@"_backgroundPingTask");

	SPMySQLConnectionPingDetails *pingDetails = (SPMySQLConnectionPingDetails *)ptr;
	
	char threadNameBuf[80];
	snprintf(threadNameBuf, sizeof(threadNameBuf), "SPMySQL _backgroundPingTask() worker thread (id=%p)", pingDetails->parentId);
	pthread_setname_np(threadNameBuf);

	// Set up a cleanup routine
	pthread_cleanup_push(_pingThreadCleanup, pingDetails);

	// Initialise MySQL variables and handling on this thread
	mysql_thread_init();

	// Set up a signal handler for SIGUSR1, to handle forced timeouts.
	signal(SIGUSR1, _forceThreadExit);

//#ifdef DEBUG
    int ret = mysql_ping(pingDetails->mySQLConnection);
    SPLog(@"mysql_ping retcode = %i", ret);
//#endif

	// Perform a ping
	*(pingDetails->keepAliveLastPingSuccessPointer) = (BOOL)(!mysql_ping(pingDetails->mySQLConnection));

	// Call the cleanup routine
	pthread_cleanup_pop(1);
}

/**
 * Support forcing a thread to exit as a result of a signal.
 */
void _forceThreadExit(int signalNumber)
{
	pthread_exit(NULL);
}

/**
 * A thread cleanup routine.  This is added to the thread using a
 * pthread_cleanup_push call; a pthread_exit or a pthread_cleanup_pop
 * both execute this function.
 */
void _pingThreadCleanup(void *pingDetails)
{
	SPMySQLConnectionPingDetails *pingDetailsStruct = pingDetails;
	*(pingDetailsStruct->keepAlivePingThreadActivePointer) = NO;

	// Clean up MySQL variables and handlers
	mysql_thread_end();
}

#pragma mark -
#pragma mark Cancellation

/**
 * If a keepalive thread is active, cancel it, and wait a short time for it
 * to exit.
 *
 * @return YES, if the thread exited within 10 seconds after canceling it
 */
- (BOOL)_cancelKeepAlives
{
    SPLog(@"_cancelKeepAlives");

	// If no keepalive thread is active, return
	if (keepAliveThread) {

		// Mark the thread as cancelled
		@synchronized(self) {
			// the synchronized is neccesary here, because we don't retain keepAliveThread.
			// If it were ommitted, for example this could happen:
			//
			//   this thread                                 keepalive thread
			//   --------------                              -----------------
			// 1 fetch value of keepAliveThread to register
			// 2                                             keepAliveThread = nil
			// 3                                             [[NSThread currentThread] release]
			// 4 objc_msgSend() <-- invalid memory accessed
			//
			// With synchronized we are guaranteed to either message nil or block the keepAliveThread from exiting
			// (and thus releasing the NSThread object) until this call finishes.
			//
			// We can omit it in the other 2 cases, since keepAliveThread is already volatile and we are only
			// checking for NULL, not dereferencing it.
			[keepAliveThread cancel];
		}

		// Wait inside a time limit of ten seconds for it to exit
		uint64_t threadCancelStartTime_t = _monotonicTime();
		do {
			usleep(100000);
			if (_timeIntervalSinceMonotonicTime(threadCancelStartTime_t) > 10) return NO;
		} while (keepAliveThread);
	
	}
	
	return YES;
}

@end
