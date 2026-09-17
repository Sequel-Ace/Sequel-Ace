//
//  Querying & Preparation.m
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

#import "SPMySQLConnection.h"
#import "SPMySQL Private APIs.h"
#import "SPMySQLArrayAdditions.h"
#import <SPMySQL/SPMySQL-Swift.h>

@interface SPMySQLConnection (Querying_and_Preparation_Internal)

- (id)queryString:(NSString *)theQueryString
     usingEncoding:(NSStringEncoding)theEncoding
    withResultType:(SPMySQLResultType)theReturnType
 assertingDatabase:(NSString *)databaseName
databaseContextIsRequired:(BOOL)databaseContextIsRequired;

@end

@implementation SPMySQLConnection (Querying_and_Preparation)

#pragma mark -
#pragma mark Data preparation

/**
 * See also the NSString methods mySQLTickQuotedString and mySQLBacktickQuotedString,
 * added via an NSString category; however these methods are safer and more complete
 * as they use the current connection encoding to quote characters.
 */

/**
 * Take a string, escapes any special character, and surrounds it with single quotes
 * for safe use within a query; correctly escapes any characters within the string
 * using the current connection encoding.
 */
- (NSString *)escapeAndQuoteString:(NSString *)theString
{
	return SPMySQLConnectionEscapeString(self, theString, YES);
}

/**
 * Take a string and escapes any special character for safe use within a query; correctly
 * escapes any characters within the string using the current connection encoding.
 * Allows control over whether to also wrap the string in single quotes.
 *
 * WARNING: This method may return nil if the current thread is cancelled!
 *          You MUST check the isCancelled flag before using the result!
 */
- (NSString *)escapeString:(NSString *)theString includingQuotes:(BOOL)includeQuotes
{
	// Return nil strings untouched
	if (!theString) return theString;

	// To correctly escape the string, an active connection is required, so verify.
	if (state == SPMySQLDisconnected || state == SPMySQLConnecting) {
		if ([delegate respondsToSelector:@selector(noConnectionAvailable:)]) {
			[delegate noConnectionAvailable:self];
		}
		return nil;
	}

	// Ensure per-thread variables are set up
	[self _validateThreadSetup];

	if (![self checkConnectionIfNecessary]) return nil;

	// A session marked for replacement may run in a different escaping mode than the session that
	// replaces it, which the value is going to be sent on. That session is set up first - unless
	// this thread holds the connection itself, reading a streaming result, and would wait for itself.
	if (sessionMustBeReplacedBeforeUse && ![inFlightQuery connectionIsHeldByCurrentThread]) {
		if (![self _replaceSessionMarkedForReplacement]) return nil;
	}

	// Perform a lossy conversion to bytes, using NSData to do the hard work.  Preserves
	// nul characters correctly.
	NSData *cData = [theString dataUsingEncoding:stringEncoding allowLossyConversion:YES];
	NSUInteger cDataLength = [cData length];

	// Create a buffer for mysql_real_escape_string to place the converted string into.
	// MySQL requires 2*length (if every character was quoted) + 1 (null terminator) bytes.
	// We add one more byte for the leading quote we're adding, and replace the null
	// terminator with the trailing quote.
	// Adding quotes in this way makes the logic below *slightly* harder to follow but
	// makes the addition of the quotes almost free, which is much nicer when building
	// lots of strings.
	NSUInteger mallocSize = (cDataLength * 2) + 2;
	char *escBuffer = (char *)malloc(mallocSize);

	// Escape starting one character in. The session's own handle is not used: work nobody waits for
	// any more can still be using it, or close it, while this runs. The escaper follows what the
	// session last reported - its character set and its NO_BACKSLASH_ESCAPES mode - and, for a
	// session about to be replaced, the character set on record, which the next session uses.
	NSInteger escapedLength = [valueEscaper escapeBytes:[cData bytes]
	                                            length:cDataLength
	                                              into:escBuffer+1
	                              characterSetOnRecord:encoding
	                            sessionIsBeingReplaced:sessionMustBeReplacedBeforeUse];
	if (escapedLength < 0) {
		SPLog(@"[escapeString:includingQuotes]: the value could not be escaped for character set %@", encoding);
		free(escBuffer);
		return nil;
	}

	// Set up an NSData object to allow conversion back to NSString while preserving
	// any nul characters contained in the string.
	NSData *escapedData;
	if (includeQuotes) {
		// The quotes are written as single raw bytes, which relies on the connection
		// encoding being ASCII-compatible.  That always holds: the server refuses ucs2,
		// utf16, utf16le and utf32 as client character sets (SET NAMES fails, so
		// stringEncoding is never updated to them), and every other charset MySQL
		// offers is a superset of ASCII.  Assert the invariant rather than pay for a
		// per-call conversion of the quote character.
		NSAssert(stringEncoding != NSUTF16StringEncoding && stringEncoding != NSUTF16BigEndianStringEncoding
		         && stringEncoding != NSUTF16LittleEndianStringEncoding && stringEncoding != NSUTF32StringEncoding
		         && stringEncoding != NSUTF32BigEndianStringEncoding && stringEncoding != NSUTF32LittleEndianStringEncoding,
		         @"escapeString: quoting requires an ASCII-compatible connection encoding");

		// Add quotes if requested
		escBuffer[0] = '\'';
		escBuffer[escapedLength+1] = '\'';

		escapedData = [NSData dataWithBytesNoCopy:escBuffer length:escapedLength+2 freeWhenDone:NO];
	} else {
		escapedData = [NSData dataWithBytesNoCopy:escBuffer+1 length:escapedLength freeWhenDone:NO];
	}

	// Convert to the string to return
	NSString *escapedString = [[NSString alloc] initWithData:escapedData encoding:stringEncoding];

	// Free up any memory and return
	free(escBuffer);
	return escapedString;
}

/**
 * Take NSData and hex-encodes the contents for safe transmission to a server,
 * preserving all bytes whatever the encoding. Surrounds the hex-encoded resulting
 * string with single quotes and precedes it with the hex-marker X for safe inclusion
 * in a query.
 */
- (NSString *)escapeAndQuoteData:(NSData *)theData
{
	return SPMySQLConnectionEscapeData(self, theData, YES);
}

/**
 * Takes NSData and hex-encodes the contents for safe transmission to a server,
 * preserving all bytes whatever the encoding.
 * Allows control over whether to also wrap the string in single quotes and a
 * preceding X (X'...') for safe use in queries.
 */
- (NSString *)escapeData:(NSData *)theData includingQuotes:(BOOL)includeQuotes
{
	// Return nil datas as nil strings
	if (!theData) return nil;

	NSUInteger dataLength = [theData length];

	// Create a buffer for mysql_real_escape_string to place the converted string into;
	// the max length is 2*length (if every character was quoted) + 3 (quotes/terminator).
	// Adding quotes in this way makes the logic below *slightly* harder to follow but
	// makes the addition of the quotes almost free, which is much nicer when building
	// lots of strings.
	char *hexBuffer = (char *)malloc((dataLength * 2) + 3);

	// Use mysql_hex_string to perform the escape, starting two characters in
	NSUInteger hexLength = mysql_hex_string(hexBuffer+2, [theData bytes], dataLength);

	// Set up the return NSString
	NSString *hexString;
	if (includeQuotes) {

		// Add quotes if requested
		hexBuffer[0] = 'X';
		hexBuffer[1] = '\'';
		hexBuffer[hexLength+2] = '\'';

		hexString = [[NSString alloc] initWithBytes:hexBuffer length:hexLength+3 encoding:NSASCIIStringEncoding];
	} else {
		hexString = [[NSString alloc] initWithBytes:hexBuffer+2 length:hexLength encoding:NSASCIIStringEncoding];
	}

	// Free up any memory and return
	free(hexBuffer);
	return hexString;
}

#pragma mark -
#pragma mark Queries

/**
 * Run a query, provided as a string, on the active connection in the current connection
 * encoding.  Stores all the results before returning the complete result set.
 */
- (SPMySQLResult *)queryString:(NSString *)theQueryString
{
	return [self queryString:theQueryString assertingDatabase:nil];
}

- (SPMySQLResult *)queryString:(NSString *)theQueryString assertingDatabase:(NSString *)databaseName
{
	return [self queryString:theQueryString usingEncoding:stringEncoding withResultType:SPMySQLResultAsResult assertingDatabase:databaseName];
}

- (SPMySQLResult *)queryString:(NSString *)theQueryString assertingDatabaseContext:(NSString *)databaseName
{
	return [self queryString:theQueryString usingEncoding:stringEncoding withResultType:SPMySQLResultAsResult assertingDatabaseContext:databaseName];
}

/**
 * Run a query, provided as a string, on the active connection in the current connection
 * encoding.  Returns the result as a fast streaming query set, where not all the results
 * may be available at time of return.
 */
- (SPMySQLFastStreamingResult *)streamingQueryString:(NSString *)theQueryString
{
	return [self streamingQueryString:theQueryString assertingDatabase:nil];
}

- (SPMySQLFastStreamingResult *)streamingQueryString:(NSString *)theQueryString assertingDatabase:(NSString *)databaseName
{
	return [self queryString:theQueryString usingEncoding:stringEncoding withResultType:SPMySQLResultAsFastStreamingResult assertingDatabase:databaseName];
}

/**
 * Run a query, provided as a string, on the active connection in the current connection
 * encoding.  Returns the result as a result set which also handles data storage.  Note
 * that the donwloading of results will not occur until -[resultSet startDownload] is called.
 */
- (SPMySQLStreamingResultStore *)resultStoreFromQueryString:(NSString *)theQueryString
{
	return [self resultStoreFromQueryString:theQueryString assertingDatabase:nil];
}

- (SPMySQLStreamingResultStore *)resultStoreFromQueryString:(NSString *)theQueryString assertingDatabase:(NSString *)databaseName
{
	return [self queryString:theQueryString usingEncoding:stringEncoding withResultType:SPMySQLResultAsStreamingResultStore assertingDatabase:databaseName];
}

- (SPMySQLStreamingResultStore *)resultStoreFromQueryString:(NSString *)theQueryString assertingDatabaseContext:(NSString *)databaseName
{
	return [self queryString:theQueryString usingEncoding:stringEncoding withResultType:SPMySQLResultAsStreamingResultStore assertingDatabaseContext:databaseName];
}

/**
 * Run a query, provided as a string, on the active connection in the current connection
 * encoding.  Returns the result as a streaming query set, where not all the results may
 * be available at time of return.
 * Supports a flag specifying whether streaming should be low-memory blocking (results are
 * read from the server as the code retrives them, possibly blocking other queries on the
 * server) or fast streaming (results are cached in the result object as fast as possible,
 * freeing up the server even in the local rows are still being read from the result object).
 * Will return a SPMySQLStreamingResult or SPMySQLFastStreamingResult as appropriate.
 */
- (id)streamingQueryString:(NSString *)theQueryString useLowMemoryBlockingStreaming:(BOOL)fullStreaming
{
	return [self streamingQueryString:theQueryString useLowMemoryBlockingStreaming:fullStreaming assertingDatabase:nil];
}

- (id)streamingQueryString:(NSString *)theQueryString useLowMemoryBlockingStreaming:(BOOL)fullStreaming assertingDatabase:(NSString *)databaseName
{
	return [self queryString:theQueryString usingEncoding:stringEncoding withResultType:fullStreaming?SPMySQLResultAsLowMemStreamingResult:SPMySQLResultAsFastStreamingResult assertingDatabase:databaseName];
}

/**
 * Run a query, provided as a string, on the active connection.  The query and its result
 * set are interpreted according to the supplied encoding, which should usually match
 * the connection encoding.
 * The result type desired can be specified, supporting either standard or streaming
 * result sets.
 *
 * WARNING: This method may return nil if the current thread is cancelled!
 *          You MUST check the isCancelled flag before using the result!
 */
- (id)queryString:(NSString *)theQueryString usingEncoding:(NSStringEncoding)theEncoding withResultType:(SPMySQLResultType)theReturnType
{
	return [self queryString:theQueryString usingEncoding:theEncoding withResultType:theReturnType assertingDatabase:nil];
}

- (id)queryString:(NSString *)theQueryString usingEncoding:(NSStringEncoding)theEncoding withResultType:(SPMySQLResultType)theReturnType assertingDatabase:(NSString *)databaseName
{
	return [self queryString:theQueryString
	            usingEncoding:theEncoding
	           withResultType:theReturnType
	        assertingDatabase:databaseName
	 databaseContextIsRequired:[databaseName length] > 0];
}

- (id)queryString:(NSString *)theQueryString usingEncoding:(NSStringEncoding)theEncoding withResultType:(SPMySQLResultType)theReturnType assertingDatabaseContext:(NSString *)databaseName
{
	return [self queryString:theQueryString
	            usingEncoding:theEncoding
	           withResultType:theReturnType
	        assertingDatabase:databaseName
	 databaseContextIsRequired:YES];
}

/**
 * Runs a query, optionally in a database the connection makes sure of first. On the main
 * thread the query is handed to the connection's worker thread, so the interface keeps
 * answering while the server is waited for.
 *
 * @param theQueryString The query to run.
 * @param theEncoding The encoding to send the query in.
 * @param theReturnType The kind of result to return.
 * @param databaseName The database the query must run in, or nil.
 * @param databaseContextIsRequired Whether the query must not run without that database selected.
 * @return The result, or nil if the query failed or the wait for it ended.
 */
- (id)queryString:(NSString *)theQueryString
     usingEncoding:(NSStringEncoding)theEncoding
    withResultType:(SPMySQLResultType)theReturnType
 assertingDatabase:(NSString *)databaseName
databaseContextIsRequired:(BOOL)databaseContextIsRequired
{
	// A query waits for a server, and on a route that has gone away it waits for a timeout.
	// The main thread must not be the one waiting: the query runs on the connection's worker
	// thread instead, and the interface keeps drawing while it does. The same call is made
	// again from there, where this test no longer holds and the query simply runs.
	if ([self _workShouldRunOffMainThread]) {
		return [self _runWorkKeepingInterfaceAlive:^id{
			return [self queryString:theQueryString
			           usingEncoding:theEncoding
			          withResultType:theReturnType
			       assertingDatabase:databaseName
			databaseContextIsRequired:databaseContextIsRequired];
		}];
	}

	double queryExecutionTime;
	NSString *theErrorMessage;
	NSUInteger theErrorID;
	NSString *theSqlstate;
	lastQueryWasCancelled = NO;

	// If a disconnect was requested, cancel the action
	if (userTriggeredDisconnect) {
		return nil;
	}

	// Check the connection state - if no connection is available, log an
	// error and return.
	if (state == SPMySQLDisconnected || state == SPMySQLConnecting) {
		if ([delegate respondsToSelector:@selector(queryGaveError:connection:)]) {
			[delegate queryGaveError:@"No connection available!" connection:self];
		}
		if ([delegate respondsToSelector:@selector(noConnectionAvailable:)]) {
			[delegate noConnectionAvailable:self];
		}
		return nil;
	}

	// Ensure per-thread variables are set up
	[self _validateThreadSetup];

	// Check the connection if necessary, returning nil if the state couldn't be validated
	// The same goes for reconnecting on behalf of work that nobody is waiting for any more.
	if ([SAConnectionWorkCoordinator currentWorkHasBeenAbandoned]) return nil;

	if (![self checkConnectionIfNecessary]) return nil;

	// Determine whether a maximum query size needs to be restored from a previous query
	if (queryActionShouldRestoreMaxQuerySize != NSNotFound) {
		[self _restoreMaximumQuerySizeAfterQuery];
	}

	// If delegate logging is enabled, and the protocol is implemented, inform the delegate
	if (delegateQueryLogging && delegateSupportsWillQueryString) {
		[delegate willQueryString:theQueryString connection:self];
	}

	// Retrieve a byte buffer from the supplied NSString
	NSData *queryData = [theQueryString dataUsingEncoding:theEncoding allowLossyConversion:YES];
	NSUInteger queryBytesLength = [queryData length];
	const char *queryBytes = [queryData bytes];

	// Check the query length against the current maximum query length.  If it is
	// larger, the query would error (and probably cause a disconnect), so if
	// the maximum size is editable, increase it and reconnect.
	if (queryBytesLength > maxQuerySize) {
		queryActionShouldRestoreMaxQuerySize = maxQuerySize;
		if (![self _attemptMaxQuerySizeIncreaseTo:(queryBytesLength + 1024)]) {
			queryActionShouldRestoreMaxQuerySize = NSNotFound;
			return nil;
		}
	}

	// Prepare to enter a loop to run the query, allowing reattempts if appropriate
	NSUInteger queryAttemptsAllowed = 1;
	if (retryQueriesOnConnectionFailure) queryAttemptsAllowed++;
	int queryStatus;

	// Lock the connection while it's actively in use
	if (![self _lockUsableConnectionForQuery]) return nil;

	// Work the user stopped waiting for can get the connection long after the caller was told it
	// was cancelled. Sending it now would run a statement - possibly one that changes data - that
	// was reported as not having run. Nothing is recorded either: the connection's state belongs
	// to whatever runs next. Work that goes ahead records whether a transaction was open before it
	// first used the session; stopping it later decides by that.
	if (![SAConnectionWorkCoordinator currentWorkMaySendWithOpenTransaction:(mySQLConnection->server_status & SERVER_STATUS_IN_TRANS) != 0]) {
		[self _unlockConnection];
		return nil;
	}

	// A session dropped with a transaction open, or with autocommit turned off, took uncommitted
	// work with it. On this session the statement could run as if nothing had happened, so it is
	// refused instead, once, and says why.
	if ([self _refusesStatementForLostUncommittedWork:theQueryString]) {
		[self _unlockConnection];

		// Releasing the connection can find a request to stop the query before; this one is refused,
		// not cancelled, and its caller has to see why.
		lastQueryWasCancelled = NO;
		[self _updateLastErrorMessage:NSLocalizedString(@"The connection to the server was lost while a transaction was open or autocommit was off. The server rolled back whatever had not been committed, and the new connection commits each statement on its own. This statement was not run.", @"Error for the next statement a user runs after the connection was lost while a transaction was open or autocommit was off")];
		[self _updateLastErrorID:2013];
		[self _updateLastSqlstate:@"HY000"];
		return nil;
	}

	// From here this is "the query that is running". Anything acting on that later - a
	// cancellation, say - has to be able to tell whether it is still this one, and counting
	// any earlier would count queries that never got the connection.
	NSUInteger thisQueryGeneration = ++queryGeneration;

	// The statements a reconnect sends belong to whichever query is reconnecting; any other query,
	// and its retries, belongs to itself. A request to stop a query another thread runs meanwhile is
	// then not taken for a request to stop this one.
	NSUInteger generationOwner = [self _currentThreadIsReconnecting] ? 0 : thisQueryGeneration;
	[inFlightQuery noteLatestGeneration:thisQueryGeneration ownedByQueryStartedAt:generationOwner];

	// A retry runs under a new number. A request to stop this query names the number it had when
	// the request was made, so the query keeps its first one to ask with.
	NSUInteger originalQueryGeneration = thisQueryGeneration;
	runningQueryFirstGeneration = originalQueryGeneration;

	// Whether the query was cancelled is this query's to say from here. Anything that finished late
	// and wrote to it did so before this point, under the same lock.
	lastQueryWasCancelled = NO;
	if (!databaseAssertionState) {
		databaseAssertionState = [[SADatabaseAssertionState alloc] init];
	}

	unsigned long long theAffectedRowCount = (unsigned long long)~0;
	do {
		BOOL databaseAssertionFailed = NO;

		// While recording the overall execution time (including network lag!), run
		// the raw query. If the caller supplied an expected database, assert it
		// under the same lock as the query so another thread cannot interleave a
		// different USE between database selection and execution.
		uint64_t queryStartTime = _monotonicTime();
		queryStatus = 0;

		// Waiting on the server starts here; a cancellation that finds the server gone can end
		// this wait, and only this one, until it is marked as over.
		[inFlightQuery beginWaitingForGeneration:thisQueryGeneration onSocket:mySQLConnection->net.fd serverThread:mySQLConnection->thread_id];

		SADatabaseAssertionError *databaseAssertionError = [databaseAssertionState
			assertDatabase:databaseName
			required:databaseContextIsRequired
			onMySQLConnection:mySQLConnection
			errorStringEncodingValue:stringEncoding
			stringEncodingProvider:^NSUInteger(NSString *characterSetName) {
				return [SPMySQLConnection stringEncodingForMySQLCharset:[characterSetName UTF8String]];
			}];

		if (databaseAssertionError) {
			queryStatus = 1;
			databaseAssertionFailed = YES;
			theErrorID = databaseAssertionError.errorID;
			theErrorMessage = databaseAssertionError.message;
			theSqlstate = databaseAssertionError.sqlState;
		}

		if (!queryStatus) {

			// Selecting the database can take a while on a slow server, and starting to wait can
			// itself wait for a kill request meant for the query before. The user can stop waiting,
			// or ask for this query to stop, meanwhile. This is the last point at which the
			// statement has not been sent.
			if ([SAConnectionWorkCoordinator currentWorkHasBeenAbandoned]) {
				[inFlightQuery endWaitingForGeneration:thisQueryGeneration];
				[self _unlockConnection];
				return nil;
			}
			if ([inFlightQuery cancellationWasRequestedForGenerationsFrom:originalQueryGeneration through:thisQueryGeneration]) {
				lastQueryWasCancelled = YES;
				[inFlightQuery endWaitingForGeneration:thisQueryGeneration];
				[self _unlockConnection];
				[self _updateLastErrorMessage:NSLocalizedString(@"Query cancelled.", @"Query cancelled error")];
				[self _updateLastErrorID:1317];
				[self _updateLastSqlstate:@"70100"];
				return nil;
			}

			queryStatus = mysql_real_query(mySQLConnection, queryBytes, queryBytesLength);
		}
		queryExecutionTime = _timeIntervalSinceMonotonicTime(queryStartTime);
		lastConnectionUsedTime = _monotonicTime();
		
		if (!queryStatus) {
			// The statement may have changed the character set or the escaping mode; values are
			// escaped the way the session reports it reads them now.
			[valueEscaper recordSessionCharacterSet:[NSString stringWithUTF8String:mysql_character_set_name(mySQLConnection)]
			                     noBackslashEscapes:(mySQLConnection->server_status & SERVER_STATUS_NO_BACKSLASH_ESCAPES) != 0
			                        openTransaction:(mySQLConnection->server_status & SERVER_STATUS_IN_TRANS) != 0
			                            isHandshake:NO];
			[databaseAssertionState recordSuccessfulQuery:theQueryString onMySQLConnection:mySQLConnection];
			// "An integer greater than zero indicates the number of rows affected or retrieved.
			//  Zero indicates that no records were updated for an UPDATE statement, no rows matched the WHERE clause in the query or that no query has yet been executed.
			//  -1 indicates that the query returned an error or that, for a SELECT query, mysql_affected_rows() was called prior to calling mysql_store_result()."
			theAffectedRowCount = mysql_affected_rows(mySQLConnection);
		}

		// If the query succeeded, no need to re-attempt.
		if (!queryStatus) {
			theErrorMessage = nil;
			theErrorID = 0;
			theSqlstate = nil;
			break;

		// If the query failed, determine whether to reattempt the query
		} else {

			// Store query errors here. Assertion errors are captured before the
			// original character set is restored, so restoration cannot hide them.
			if (!databaseAssertionFailed) {
				theErrorMessage = [self _stringForCString:mysql_error(mySQLConnection)];
				theErrorID = mysql_errno(mySQLConnection);
				// sqlstate is always an ASCII string, regardless of charset (but use latin1 anyway as that is less picky about invalid bytes)
				theSqlstate = _stringForCStringWithEncoding(mysql_sqlstate(mySQLConnection), NSISOLatin1StringEncoding);
			}

			// A request to stop can arrive while the query is losing its connection, before anything
			// has reached the server; it still means the statement must not be sent again.
			if ([inFlightQuery cancellationWasRequestedForGenerationsFrom:originalQueryGeneration through:thisQueryGeneration]) {
				lastQueryWasCancelled = YES;
			}

			// Prevent retries if the query was cancelled or not a connection error
			if (lastQueryWasCancelled || ![SPMySQLConnection isErrorIDConnectionError:theErrorID]) {
				break;
			}
		}

		// Query has failed - check the connection. The socket may change on the way, so this
		// wait is over and the next attempt marks its own.
		[inFlightQuery endWaitingForGeneration:thisQueryGeneration];
		[self _unlockConnection];
		if (![self checkConnection]) {
			[self _updateLastErrorMessage:theErrorMessage];
			[self _updateLastErrorID:theErrorID];
			[self _updateLastSqlstate:theSqlstate];
			return nil;
		}
		if (![self _lockUsableConnectionForQuery]) {
			[self _updateLastErrorMessage:theErrorMessage];
			[self _updateLastErrorID:theErrorID];
			[self _updateLastSqlstate:theSqlstate];
			return nil;
		}
		NSAssert(mySQLConnection != NULL, @"mySQLConnection has disappeared while checking it!");

		// Reconnecting ran queries of their own, each starting from its own number. What holds the
		// connection now is this query again.
		runningQueryFirstGeneration = originalQueryGeneration;

		// The user can stop waiting while the connection is checked, and the check can still
		// succeed. A retry is a new chance for the statement to run, so it asks again whether
		// anybody still wants it.
		if ([SAConnectionWorkCoordinator currentWorkHasBeenAbandoned]) {
			[self _unlockConnection];
			return nil;
		}

		// Stopping can also have been asked for while the connection was being checked.
		if ([inFlightQuery cancellationWasRequestedForGenerationsFrom:originalQueryGeneration through:thisQueryGeneration]) {
			lastQueryWasCancelled = YES;
			[self _unlockConnection];
			[self _updateLastErrorMessage:NSLocalizedString(@"Query cancelled.", @"Query cancelled error")];
			[self _updateLastErrorID:1317];
			[self _updateLastSqlstate:@"70100"];
			return nil;
		}

		// The reconnect may have dropped uncommitted work. The statement is then not tried again on
		// the new session, where it would run as if nothing had happened; its error says why. Work
		// nobody waits for, or that was asked to stop, has returned above and leaves the report.
		if ([self _refusesStatementForLostUncommittedWork:theQueryString]) {
			[self _unlockConnection];
			lastQueryWasCancelled = NO;
			[self _updateLastErrorMessage:[NSString stringWithFormat:@"%@\n\n%@", theErrorMessage ?: @"", NSLocalizedString(@"A transaction was open or autocommit was off: the server rolled back whatever had not been committed, and the new connection commits each statement on its own.", @"Note added to the error of a statement that lost the connection while a transaction was open or autocommit was off")]];
			[self _updateLastErrorID:theErrorID];
			[self _updateLastSqlstate:theSqlstate];
			return nil;
		}

		// Reconnecting ran queries of its own, each with its own number and each saying whether it
		// was cancelled. The retry is what runs now: it starts out not cancelled, and a cancellation
		// has to be able to find it under the current number.
		lastQueryWasCancelled = NO;
		thisQueryGeneration = ++queryGeneration;
		[inFlightQuery noteLatestGeneration:thisQueryGeneration ownedByQueryStartedAt:generationOwner];

	} while (--queryAttemptsAllowed > 0);

	SPMySQLResult *theResult = nil;

	// On success, if there is a query result, retrieve the result data type
	if (!queryStatus) {
		if (mysql_field_count(mySQLConnection)) {
			MYSQL_RES *mysqlResult;

			switch (theReturnType) {

				// For standard result sets, retrieve all the results now, and afterwards
				// update the affected row count.
				case SPMySQLResultAsResult:
					mysqlResult = mysql_store_result(mySQLConnection);
					theResult = [[SPMySQLResult alloc] initWithMySQLResult:mysqlResult stringEncoding:theEncoding version:self.serverMajorVersion];
					theAffectedRowCount = mysql_affected_rows(mySQLConnection);
					break;

				// For fast streaming and low memory streaming result sets, set up the result
				case SPMySQLResultAsLowMemStreamingResult:
					mysqlResult = mysql_use_result(mySQLConnection);
					theResult = [[SPMySQLStreamingResult alloc] initWithMySQLResult:mysqlResult stringEncoding:theEncoding connection:self];
					break;

				case SPMySQLResultAsFastStreamingResult:
					mysqlResult = mysql_use_result(mySQLConnection);
					theResult = [[SPMySQLFastStreamingResult alloc] initWithMySQLResult:mysqlResult stringEncoding:theEncoding connection:self];
					break;

				// Also set up the result for streaming result data stores, but note the data download does not start yet
				case SPMySQLResultAsStreamingResultStore:
					mysqlResult = mysql_use_result(mySQLConnection);
					theResult = [[SPMySQLStreamingResultStore alloc] initWithMySQLResult:mysqlResult stringEncoding:theEncoding connection:self];
					break;
			}

			// Update the error message, if appropriate, to reflect result store errors or overall success
			theErrorMessage = [self _stringForCString:mysql_error(mySQLConnection)];
			theErrorID = mysql_errno(mySQLConnection);
			// sqlstate is always an ASCII string, regardless of charset (but use latin1 anyway as that is less picky about invalid bytes)
			theSqlstate = _stringForCStringWithEncoding(mysql_sqlstate(mySQLConnection), NSISOLatin1StringEncoding);
		} else {
			theResult = [[SPMySQLEmptyResult alloc] init];
		}
	}


	// Update the connection's stored insert ID if available
	if (mySQLConnection->insert_id) {
		lastQueryInsertID = mySQLConnection->insert_id;
	}

	// A request to stop can reach a query that then finishes before the server acts on it. It
	// still counts as cancelled, as it always has - callers running a batch stop on this.
	if ([inFlightQuery cancellationWasRequestedForGenerationsFrom:originalQueryGeneration through:thisQueryGeneration]) {
		lastQueryWasCancelled = YES;
	}

	// If the query was cancelled, override the error state
	if (lastQueryWasCancelled) {
		theErrorMessage = NSLocalizedString(@"Query cancelled.", @"Query cancelled error");
		theErrorID = 1317;
		theSqlstate = @"70100";
	}

	// A query nobody waited for finished anyway. Its caller was told it was cancelled, and what it
	// did may have changed the session - a character set, say - without the connection's record of
	// the session changing along. The session is closed while this query still holds the
	// connection, so nothing can use it in between; the next query reconnects and restores it.
	// The caller's view of the outcome was settled when the waiting ended, so nothing is recorded.
	// A session whose transaction was open before the work first used it is kept: closing it would
	// roll that transaction back. A transaction this work opened itself is not.
	BOOL queryWasAbandoned = [SAConnectionWorkCoordinator currentWorkHasBeenAbandoned];
	if (queryWasAbandoned && ![theResult isKindOfClass:[SPMySQLStreamingResult class]]
	    && [SAConnectionCancellation closesSessionOfAbandonedWorkWithSessionUse:[SAConnectionWorkCoordinator currentWorkSessionUse]
	                                                  sessionHasOpenTransaction:mySQLConnection && (mySQLConnection->server_status & SERVER_STATUS_IN_TRANS) != 0
	                                                       markedForReplacement:sessionMustBeReplacedBeforeUse]) {
		[self _closeSessionOfAbandonedQuery];
	}

	// Unlock the connection if appropriate - if not a streaming result type.
	if (![theResult isKindOfClass:[SPMySQLStreamingResult class]]) {
		[self _tryLockConnection];
		[self _unlockConnection];

		// Also perform restore if appropriate
		if (queryActionShouldRestoreMaxQuerySize != NSNotFound) {
			[self _restoreMaximumQuerySizeAfterQuery];
		}
	}

	if (queryWasAbandoned) return nil;

	// Update error string and ID, and the rows affected
	[self _updateLastErrorMessage:theErrorMessage];
	[self _updateLastErrorID:theErrorID];
	[self _updateLastSqlstate:theSqlstate];
	lastQueryAffectedRowCount = theAffectedRowCount;

	// Store the result time on the response object
	[theResult _setQueryExecutionTime:queryExecutionTime];

	return theResult;
}

#pragma mark -
#pragma mark Query convenience functions

/**
 * Run a query and retrieve the entire result set as an array of dictionaries.
 * Returns nil if there was a problem running the query or retrieving any results.
 */
- (NSArray *)getAllRowsFromQuery:(NSString *)theQueryString
{
	return [self getAllRowsFromQuery:theQueryString assertingDatabase:nil];
}

- (NSArray *)getAllRowsFromQuery:(NSString *)theQueryString assertingDatabase:(NSString *)databaseName
{
	return [[self queryString:theQueryString assertingDatabase:databaseName] getAllRows];
}

/**
 * Run a query and retrieve the first field of any response.  Returns nil if there
 * was a problem running the query or retrieving any results.
 */
- (id)getFirstFieldFromQuery:(NSString *)theQueryString
{
	return [self getFirstFieldFromQuery:theQueryString assertingDatabase:nil];
}

- (id)getFirstFieldFromQuery:(NSString *)theQueryString assertingDatabase:(NSString *)databaseName
{
	return [[[self queryString:theQueryString assertingDatabase:databaseName] getRowAsArray] firstObject];
}

#pragma mark -
#pragma mark Query information

/**
 * Returns the number of rows changed, deleted, inserted, or selected by
 * the last query.
 */
- (unsigned long long)rowsAffectedByLastQuery
{
	return lastQueryAffectedRowCount;
}

/**
 * Returns the insert ID for the previous query which inserted a row.  Note that
 * this value persists through other SELECT/UPDATE etc queries.
 */
- (unsigned long long)lastInsertID
{
	return lastQueryInsertID;
}

#pragma mark -
#pragma mark Retrieving connection and query error state

/**
 * Return whether the last query errored or not.
 */
- (BOOL)queryErrored
{
	return (queryErrorMessage)?YES:NO;
}

/**
 * If the last query (or connection) triggered an error, returns the error
 * message as a string; if the last query did not error, nil is returned.
 */
- (NSString *)lastErrorMessage
{
	if (!queryErrorMessage) return nil;
	return [NSString stringWithString:queryErrorMessage];
}

- (NSString *)lastSqlstate
{
	if(!querySqlstate) return nil;
	return [NSString stringWithString:querySqlstate];
}

/**
 * If the last query (or connection) triggered an error, returns the error
 * ID; if the last query did not error, 0 is returned.
 */
- (NSUInteger)lastErrorID
{
	return queryErrorID;
}

/**
 * Determines whether a supplied error ID can be classed as a connection error.
 */
+ (BOOL)isErrorIDConnectionError:(NSUInteger)theErrorID
{
	switch (theErrorID) {
		case 2001: // CR_SOCKET_CREATE_ERROR
		case 2002: // CR_CONNECTION_ERROR
		case 2003: // CR_CONN_HOST_ERROR
		case 2004: // CR_IPSOCK_ERROR
		case 2005: // CR_UNKNOWN_HOST
		case 2006: // CR_SERVER_GONE_ERROR
		case 2007: // CR_VERSION_ERROR
		case 2009: // CR_WRONG_HOST_INFO
		case 2012: // CR_SERVER_HANDSHAKE_ERR
		case 2013: // CR_SERVER_LOST
		case 2027: // CR_MALFORMED_PACKET
		case 2032: // CR_DATA_TRUNCATED
		case 2047: // CR_CONN_UNKNOW_PROTOCOL
		case 2048: // CR_INVALID_CONN_HANDLE
		case 2050: // CR_FETCH_CANCELED
		case 2055: // CR_SERVER_LOST_EXTENDED
			return YES;
	}

	return NO;
}	

#pragma mark -
#pragma mark Query cancellation

/**
 * Cancel the currently running query.  This tries to kill the current query,
 * and if that isn't possible - for example, on MySQL < 5 or if the current user
 * does not have the relevant permissions - resets the connection.
 */
- (void)cancelCurrentQuery
{
	[self _cancelCurrentQueryRecordingRequest:YES];
}

@end

#pragma mark -
#pragma mark Private API

@implementation SPMySQLConnection (Querying_and_Preparation_Private_API)

/**
 * Cancels the running query; see -cancelCurrentQuery.
 *
 * @param recordRequest Whether the query is also recorded as asked to stop. A stop the application
 *                      asked for is; the connection's own teardown before a reconnect is not, since
 *                      the query it interrupts may be the one that is about to retry.
 */
- (void)_cancelCurrentQueryRecordingRequest:(BOOL)recordRequest
{
    SPLog(@"cancelCurrentQuery");
	// If not connected, no action is required
	if (state != SPMySQLConnected && state != SPMySQLDisconnecting) return;

	// Check whether a query is actually being performed - if not, return
	if ([self _tryLockConnection]) {
		[self _unlockConnection];
		return;
	}

	// Mark that the last query was cancelled to prevent query retries from occurring
	lastQueryWasCancelled = YES;

	// Also as a request for the query that is running now. A query that is reconnecting before its
	// retry resets its own mark once the reconnect is done, and finds the request instead - under
	// the number of whichever of its queries was running.
	if (recordRequest) [inFlightQuery requestCancellationOfGeneration:[inFlightQuery latestGeneration]];

	// If the server could be reached and killed the query, the active query was cancelled.
	if ([self _killQueryOverSideConnectionForGeneration:0]) return;

	// A full reconnect is required at this point to force a cancellation.  As the
	// connection may have finished processing the query at this point (depending how
	// long the connection attempt took), check whether we can skip the reconnect.
	if ([self _tryLockConnection]) {
		[self _unlockConnection];
		return;
	}

	if (state == SPMySQLDisconnecting || state == SPMySQLDisconnected) return;

	// Reset the connection with a reconnect.  Unlock the connection beforehand,
	// to allow the reconnect, but lock it again afterwards to restore the expected
	// state (query execution process should unlock as appropriate).
	[self _unlockConnection];
	[self _reconnectAllowingRetries:YES];
	[self _lockConnection];

	// Reset tracking bools to cover encompassed queries
	lastQueryWasCancelled = YES;
}

/**
 * Closes the session of a query that finished after nobody was waiting for it any more.
 * Called while the connection is held - by that query, or by the cleanup after it. The connection then counts as lost in the
 * background, which makes the next query reconnect and restore the session from the record the
 * connection keeps of it - the same way it does after any lost connection.
 */
- (void)_closeSessionOfAbandonedQuery
{
	// The socket number is free for reuse the moment the handle is closed. The waiting record must
	// not name it any more by then, or a cancellation arriving later could shut down whatever
	// socket gets that number next.
	[inFlightQuery endWaitingForGeneration:queryGeneration];

	[self _noteUncommittedWorkLostWithSession];
	if (mySQLConnection) {
		mysql_close(mySQLConnection);
		mySQLConnection = NULL;
	}
	state = SPMySQLConnectionLostInBackground;
	sessionWasClosedWithoutItsProxy = YES;

	// Until the next session connects, values follow the record, which its handshake uses.
	[valueEscaper forgetSession];
}

/**
 * Whether a statement is refused because a session before it was dropped with uncommitted work,
 * using up the report it is refused with. The decision is SAConnectionCancellation's; the statement
 * is only looked at when it matters. Called while the connection is held.
 *
 * @param query The statement about to be sent.
 * @return Whether to refuse it.
 */
- (BOOL)_refusesStatementForLostUncommittedWork:(NSString *)query
{
	if (!lostWorkReportPendingForEditor && !lostWorkReportPendingForWrites) return NO;

	// SQL from outside the application counts as a write whatever it starts with: a SELECT can call a
	// function that changes data. Only the application's own statements are judged by their keyword.
	BOOL leavesDataAlone = retryQueriesOnConnectionFailure && lostWorkReportPendingForWrites && mySQLConnection
		&& ![SAOutsideStatements areRunningOnCurrentThread]
		&& [SADatabaseAssertionState statementLeavesDataAlone:query onMySQLConnection:mySQLConnection];
	BOOL sentByConnection = [self _currentThreadIsReconnecting] || [SAConnectionUpkeepStatements areRunningOnCurrentThread];
	SALostWorkRefusal refusal = [SAConnectionCancellation lostWorkRefusalWithReportPendingForEditor:lostWorkReportPendingForEditor
	                                                                         reportPendingForWrites:lostWorkReportPendingForWrites
	                                                                              retriesStatements:retryQueriesOnConnectionFailure
	                                                                               sentByConnection:sentByConnection
	                                                                        statementLeavesDataAlone:leavesDataAlone];
	switch (refusal) {
		case SALostWorkRefusalEditorStatement:
			lostWorkReportPendingForEditor = NO;
			lostWorkReportPendingForWrites = NO;
			return YES;
		case SALostWorkRefusalApplicationWrite:
			lostWorkReportPendingForWrites = NO;
			return YES;
		case SALostWorkRefusalNone:
			break;
	}
	return NO;
}

/**
 * Notes that the session about to be dropped takes uncommitted work with it - a transaction it has
 * open, or autocommit it had turned off - so that the next statement the user runs is not run as if
 * nothing had happened. A handle whose connection is gone still reports its last status, which is
 * what counts. Called while the connection is held, before the handle is closed.
 */
- (void)_noteUncommittedWorkLostWithSession
{
	if (!mySQLConnection) return;

	unsigned int status = mySQLConnection->server_status;
	if ([SAConnectionCancellation droppingSessionLosesUncommittedWorkWithOpenTransaction:(status & SERVER_STATUS_IN_TRANS) != 0
	                                                                         autocommit:(status & SERVER_STATUS_AUTOCOMMIT) != 0
	                                                                autocommitAtConnect:sessionAutocommitAtConnect]) {
		lostWorkReportPendingForEditor = YES;
		lostWorkReportPendingForWrites = YES;
	}
}

/**
 * Replaces a session that was marked to be replaced before its next use, without sending anything
 * over it. It waits for the connection the way a query does - off the main thread, where that
 * applies.
 *
 * @return Whether a usable session is in place.
 */
- (BOOL)_replaceSessionMarkedForReplacement
{
	return [self _runConnectionWorkKeepingInterfaceAlive:^BOOL{
		if (![self _lockUsableConnectionForQuery]) return NO;
		[self _unlockConnection];
		return YES;
	}];
}

/**
 * Takes the connection for a query, and makes sure there is a connection to take.
 *
 * Between checking the connection and getting hold of it, a query can find it closed: the cleanup
 * after work that nobody waited for closes the session once that work finishes, and it can be the
 * one that gets hold of the connection first. A query that finds it closed reconnects, as it would
 * after any lost connection, and takes it again.
 *
 * @return Whether the connection is held and usable. If it is not usable, it is not held either.
 */
- (BOOL)_lockUsableConnectionForQuery
{
	[self _lockConnection];

	for (NSUInteger attempt = 0; attempt < 2; attempt++) {
		if (mySQLConnection && state != SPMySQLConnectionLostInBackground) {
			if (!sessionMustBeReplacedBeforeUse) return YES;

			// The character set on record was changed for the next session only. This one is closed
			// like the session of abandoned work, and the reconnect below sets up the next one.
			[self _closeSessionOfAbandonedQuery];
		}

		[self _unlockConnection];

		// Reconnecting is not something to do for work nobody waits for any more.
		if ([SAConnectionWorkCoordinator currentWorkHasBeenAbandoned]) return NO;
		if (![self checkConnectionIfNecessary]) return NO;

		[self _lockConnection];
	}

	if (mySQLConnection && state != SPMySQLConnectionLostInBackground) return YES;

	[self _unlockConnection];
	return NO;
}

/**
 * Asks the server to kill a query this connection is running, over a second connection opened
 * for the purpose. The query cancellation cannot occur on the connection actively running it.
 *
 * Nothing else is tried if the server cannot be reached: a caller that needs the query ended
 * regardless decides for itself what that is worth.
 *
 * @param generation The query to kill, or 0 for whatever the connection is running. A query
 *                   that is named is only killed while it is still waiting on the server: opening
 *                   the second connection takes time, and by the end of it the connection can be
 *                   running a different query in the same server session.
 * @return Whether the server accepted the request.
 */
- (BOOL)_killQueryOverSideConnectionForGeneration:(NSUInteger)generation
{
	MYSQL *killerConnection = [self _makeRawMySQLConnectionWithEncoding:@"utf8mb4" isMasterConnection:NO];

	// If the new connection could not be set up, the server cannot be asked.
	if (!killerConnection) {
		if (!userTriggeredDisconnect) {
			SPLog(@"SPMySQL Framework: query cancellation failed because connection failed");
		}
		return NO;
	}

	NSStringEncoding aStringEncoding = [SPMySQLConnection stringEncodingForMySQLCharset:mysql_character_set_name(killerConnection)];
	BOOL isTiDB = [[self serverVersionString] rangeOfString:@"TiDB"].location != NSNotFound;
	__block int killQueryStatus = -1;

	void (^sendKill)(NSUInteger) = ^(NSUInteger serverThread) {
		// Build the kill query
		NSMutableString *killQuery = [NSMutableString stringWithString:@"KILL"];
		if (isTiDB) {
			[killQuery appendString:@" TIDB"];
			NSLog(@"SPMySQL Framework: Killing Query in TIDB Mode");
		}
		[killQuery appendFormat:@" QUERY %lu", (unsigned long)serverThread];

		// Convert to a byte buffer in the killer connection's encoding.  mysql_real_query takes
		// an explicit length, so no terminator is appended (see the main query path).
		NSData *killQueryData = [killQuery dataUsingEncoding:aStringEncoding allowLossyConversion:YES];
		killQueryStatus = mysql_real_query(killerConnection, [killQueryData bytes], [killQueryData length]);
	};

	if (generation) {
		// The query is reserved while the request is on its way, so no other query can start in
		// the same session meanwhile; nothing is locked while the request goes over the network.
		NSUInteger serverThread = [inFlightQuery beginKillIfGenerationIsWaiting:generation];
		if (serverThread) {
			sendKill(serverThread);
			[inFlightQuery endKillForGeneration:generation succeeded:(killQueryStatus == 0) whileStillWaiting:^{
				// Ensure the tracking bool is re-set to cover encompassed queries
				self->lastQueryWasCancelled = YES;
			}];
		}
	} else if (mySQLConnection && mySQLConnection->thread_id) {
		sendKill(mySQLConnection->thread_id);

		// Ensure the tracking bool is re-set to cover encompassed queries
		if (killQueryStatus == 0) lastQueryWasCancelled = YES;
	}

	// Close the temporary connection
	mysql_close(killerConnection);

	if (killQueryStatus != 0) {
		SPLog(@"SPMySQL Framework: query cancellation did not reach the query (status %d)", killQueryStatus);
		return NO;
	}

	return YES;
}

/**
 * Retrieves all remaining results and discards them.
 * This is necessary to correctly process multiple result sets on the connection - as
 * we currently don't fully support multiple result, this at least allows the connection
 * to function after running statements with multiple result sets.
 */
- (void)_flushMultipleResultSets
{
	// Repeat as long as there are results
	while (!mysql_next_result(mySQLConnection)) {
		MYSQL_RES *eachResult = mysql_use_result(mySQLConnection);

		// Ensure the result is really a result
		if (eachResult) {

			// Retrieve and discard all rows
			while (mysql_fetch_row(eachResult));

			// Free the result set
			mysql_free_result(eachResult);
		}
	}
}

/**
 * Update lastErrorID, lastErrorMessage and lastSqlstate from connection
 */
- (void)_updateLastErrorInfos
{
	[self _updateLastErrorID:NSNotFound];
	[self _updateLastErrorMessage:nil];
	[self _updateLastSqlstate:nil];
}

/**
 * Update the MySQL error message for this connection.  If an error is supplied
 * it will be stored and returned to anything asking the instance for the last
 * error; if no error is supplied, the connection will be used to derive (or clear)
 * the error string.
 */
- (void)_updateLastErrorMessage:(NSString *)theErrorMessage
{
	// If an error message wasn't supplied, select one from the connection
	if (!theErrorMessage) {
		theErrorMessage = [self _stringForCString:mysql_error(mySQLConnection)];
	}

	// If we have an error message *with a length*, update the instance error message
	if (theErrorMessage && [theErrorMessage length]) {
		queryErrorMessage = [[NSString alloc] initWithString:theErrorMessage];
	}
    else {
        // VERY IMPORTANT to set to nil here
        // DO NOT remove
        queryErrorMessage = nil;
    }
}

/**
 * Update the MySQL error ID for this connection.  If an error ID is supplied,
 * it will be stored and returned to anything asking the instance for the last
 * error; if an NSNotFound error ID is supplied, the connection will be used to
 * set the error ID.  Note that an error ID of 0 corresponds to no error.
 */
- (void)_updateLastErrorID:(NSUInteger)theErrorID
{
	// If NSNotFound was supplied as the ID, ask the connection for the last error
	if (theErrorID == NSNotFound) {
		queryErrorID = mysql_errno(mySQLConnection);

	// Otherwise, update the error ID with the supplied ID
	} else {
		queryErrorID = theErrorID;
	}
}

/**
 * Update the MySQL SQLSTATE for this connection.
 * @param thSqlstate If a SQLSTATE is supplied it will be stored and returned to 
 *                   anything asking the instance for the last SQLSTATE; 
 *                   if nil is supplied, the connection will be used to derive
 *                   (or clear) the SQLSTATE string; 
 *                   if @"" is supplied the SQLSTATE will only be cleared.
 */
- (void)_updateLastSqlstate:(NSString *)theSqlstate
{
	// If a SQLSTATE wasn't supplied, select one from the connection
	if(!theSqlstate) {
		// sqlstate is always an ASCII string, regardless of charset (but use latin1 anyway as that is less picky about invalid bytes)
		theSqlstate = _stringForCStringWithEncoding(mysql_sqlstate(mySQLConnection), NSISOLatin1StringEncoding);
	}

	// If we have a SQLSTATE *with a length*, update the instance SQLSTATE
	if(theSqlstate && [theSqlstate length]) {
		querySqlstate = [[NSString alloc] initWithString:theSqlstate];
	}
}

@end
