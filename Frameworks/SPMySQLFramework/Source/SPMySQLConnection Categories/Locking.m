//
//  Locking.m
//  SPMySQLFramework
//
//  Created by Rowan Beentje (rowan.beent.je) on January 22, 2012
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

// This class is private to the framework.

#import "Locking.h"
#import <SPMySQL/SPMySQL-Swift.h>
#import "SPMySQL Private APIs.h"
#import <SPMySQL/SPMySQL-Swift.h>

@implementation SPMySQLConnection (Locking)

/**
 * Lock the connection. This must be done before performing any operation
 * that is not thread safe, eg. performing queries or pinging.
 */
- (void)_lockConnection
{
	// We can only start a query when the condition is SPMySQLConnectionIdle
	[connectionLock lockWhenCondition:SPMySQLConnectionIdle];

	// Set the condition to SPMySQLConnectionBusy
	[inFlightQuery noteConnectionHeldByCurrentThread:YES];
	[connectionLock unlockWithCondition:SPMySQLConnectionBusy];
}

/**
 * Attempt to lock the connection. If the connection is idle (unlocked), this method
 * locks the connection and returns YES for success. The connection must afterward
 * be unlocked using unlockConnection. If the connection is currently busy (locked),
 * this method immediately returns NO and doesn't lock the connection.
 */
- (BOOL)_tryLockConnection
{
	// If the connection is already is use, return failure
	if (![connectionLock tryLockWhenCondition:SPMySQLConnectionIdle]) {
		return NO;
	}

	// We're allowed to use the connection; set it to busy, and return success
	[inFlightQuery noteConnectionHeldByCurrentThread:YES];
	[connectionLock unlockWithCondition:SPMySQLConnectionBusy];
	return YES;
}

/**
 * Unlock the connection.
 */
- (void)_unlockConnection
{
	// Always lock the conditional lock before proceeding
	[connectionLock lock];

	// Check if the connection actually was busy. If it wasn't busy,
	// it means the connection may have been unlocked twice. This is
	// potentially dangerous, so we log this to the console
	if ([connectionLock condition] != SPMySQLConnectionBusy) {
		SPLog(@"SPMySQLConnection: Tried to unlock the connection, but it wasn't locked.");
	}

	// Each packet carries its own session-state items, and fetching the next one replaces them -
	// so a report that came with an earlier result would be gone by the time the session is
	// recorded. This packet's is taken now, and the ones the flush below walks past are added to
	// it as it goes.
	characterSetReportedInAResultPacket = characterSetReportedInAResultPacket || [self _currentResultPacketReportsTheCharacterSet];

	// Since we connected with CLIENT_MULTI_RESULT, we must make sure there are not more results!
	// This is still a bit of a dirty hack
	if (
		state == SPMySQLConnected &&
		mySQLConnection &&
		mySQLConnection->net.vio &&
		mySQLConnection->net.buff &&
		mysql_more_results(mySQLConnection)
	) {
		SPLog(@"SPMySQLConnection: Discarding unretrieved results. This is currently normal when using CALL.");
		[self _flushMultipleResultSets];
	}

	// Record what the session reports, now that everything the statement produced has been read.
	// This is the only point at which that is true for every path: a statement's own result is
	// read after the statement returns - stored at once, or streamed while this lock is held -
	// and a session-state change the server reports arrives with the last of those packets. The
	// connection is still held here, so nothing else can be using the handle, and no further
	// lock is needed.
	if (state == SPMySQLConnected && mySQLConnection) {
		[valueEscaper recordSessionCharacterSet:[NSString stringWithUTF8String:mysql_character_set_name(mySQLConnection)]
		                     noBackslashEscapes:(mySQLConnection->server_status & SERVER_STATUS_NO_BACKSLASH_ESCAPES) != 0
		                        openTransaction:(mySQLConnection->server_status & SERVER_STATUS_IN_TRANS) != 0
		                            isHandshake:NO
		                characterSetWasReported:characterSetReportedInAResultPacket];
	}
	characterSetReportedInAResultPacket = NO;

	// A streaming result gets here only once its download is over. If stopping it was asked for
	// meanwhile, it counts as cancelled even if it finished first - callers running a batch stop
	// on this. The request can name the number of any of the query's attempts.
	if ([inFlightQuery cancellationWasRequestedForGenerationsFrom:runningQueryFirstGeneration through:queryGeneration]) {
		lastQueryWasCancelled = YES;
	}

	// Whatever held the connection is no longer waiting on the server, and a cancellation can
	// reach it until now.
	[inFlightQuery endWaitingForGeneration:queryGeneration];
	[self.sessionAccess endNativeQuery];

	// Tell everyone that the connection is available again
	[inFlightQuery noteConnectionHeldByCurrentThread:NO];
	[connectionLock unlockWithCondition:SPMySQLConnectionIdle];
}

/**
 * Whether the result packet the connection is on carries the server's own report of the
 * session's character set.
 *
 * The client library keeps the session-state items of one OK packet, and asking it is the only
 * way to tell a report that arrived from one that did not: the character set's *name* cannot,
 * because a session whose reports have stopped keeps naming what it was last told, which can be
 * the same name a later report would carry.
 *
 * Only the items are pulled out here; what they mean is `SASessionStateTracking`'s. Valid only
 * while the connection is held and before the next packet is fetched.
 */
- (BOOL)_currentResultPacketReportsTheCharacterSet
{
	if (state != SPMySQLConnected || !mySQLConnection) {
		return NO;
	}

	return [SASessionStateTracking characterSetIsNamedInTheCurrentResultPacketOf:mySQLConnection];
}


@end
