//
//  Server Info.m
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

#import "Server Info.h"
#import "SPMySQL Private APIs.h"

@implementation SPMySQLConnection (Server_Info)

#pragma mark -
#pragma mark Server version information

/**
 * Return the server version string, or nil on failure.
 */
- (NSString *)serverVersionString
{
	if (serverVariableVersion) {
		return [NSString stringWithString:serverVariableVersion];
	}

	return nil;
}

/**
 * Return the server major version or 0 on failure
 */
- (NSUInteger)serverMajorVersion
{
	// 5.5.33 => 50533 / 10'000 => 5.0533 => 5
	return (serverVersionNumber / 10000);
}

/**
 * Return the server minor version or 0 on failure
 */
- (NSUInteger)serverMinorVersion
{
	// 5.5.33 => 50533 - (5*10'000) => 533 / 100 => 5.33 => 5
	return ((serverVersionNumber - [self serverMajorVersion]*10000) / 100);
}

/**
 * Return the server release version or 0 on failure
 */
- (NSUInteger)serverReleaseVersion
{
	// 5.5.33 => 50533 - (5*10'000 + 5*100) => 33
	return (serverVersionNumber - ([self serverMajorVersion]*10000 + [self serverMinorVersion]*100));
}

#pragma mark -
#pragma mark Server version comparisons

/**
 * Returns whether the connected server version is greater than or equal to the
 * supplied version number.  Returns NO if no connection is active.
 */
- (BOOL)serverVersionIsGreaterThanOrEqualTo:(NSUInteger)aMajorVersion minorVersion:(NSUInteger)aMinorVersion releaseVersion:(NSUInteger)aReleaseVersion
{
	unsigned long myver = aMajorVersion * 10000 + aMinorVersion * 100 + aReleaseVersion;

	return (serverVersionNumber >= myver);
}

#pragma mark -
#pragma mark Server tasks & processes

/**
 * Returns a result set describing the current server threads and their tasks.  Note that
 * the resulting process list defaults to the short form; run a manual SHOW FULL PROCESSLIST
 * to retrieve tasks in non-truncated form.
 * Returns nil on error.
 *
 * WARNING: This method may return nil if the current thread is cancelled!
 *          You MUST check the isCancelled flag before using the result!
 */
- (SPMySQLResult *)listProcesses
{
	if (state != SPMySQLConnected) return nil;

	// Check the connection if appropriate
	if (![self checkConnectionIfNecessary]) return nil;

	// Lock the connection before using it
	[self _lockConnection];

	// Ensure per-thread variables are set up
	[self _validateThreadSetup];

	// Get the process list
	MYSQL_RES *mysqlResult = mysql_list_processes(mySQLConnection);
	lastConnectionUsedTime = _monotonicTime();

	// Convert to SPMySQLResult
	SPMySQLResult *theResult = [[SPMySQLResult alloc] initWithMySQLResult:mysqlResult stringEncoding:stringEncoding];

	// Unlock and return
	[self _unlockConnection];
	return theResult;
}

/**
 * Kill the process with the supplied thread ID.  On MySQL version 5 or later, this kills
 * the query; on older servers this kills the entire connection.  Note that the SUPER
 * privilege is required to kill queries and processes not belonging to the currently
 * connected user, while only PROCESS is required to see other user's processes.
 * Returns a boolean indicating success or failure.
 */
- (BOOL)killQueryOnThreadID:(unsigned long)theThreadID
{
	// Note that mysql_kill has been deprecated, so use a query to perform this task.
	NSMutableString *killQuery = [NSMutableString stringWithString:@"KILL"];
    
    //Special suppot for TiDB SQL variant
	if ([[self serverVersionString] rangeOfString:@"TiDB"].location != NSNotFound) {
		[killQuery appendString:@" TIDB"];
	}

	[killQuery appendFormat:@" QUERY %lu", theThreadID];

	// Run the query
	[self queryString:killQuery];

	// Return a value based on whether the query errored or not
	return ![self queryErrored];
}

- (BOOL)serverShutdown
{
	if([self checkConnectionIfNecessary]) {
		[self _lockConnection];
		// Ensure per-thread variables are set up
		[self _validateThreadSetup];
		//only SHUTDOWN_DEFAULT is supported right now
		int res = mysql_shutdown(mySQLConnection, SHUTDOWN_DEFAULT);
		//update or clear error
		[self _updateLastErrorInfos];
		[self _unlockConnection];
		
		return (res == 0);
	}
	return NO;
}

- (BOOL)updateServerStatusBits:(SPMySQLServerStatusBits *)bits
{
	if(state != SPMySQLConnected || !mySQLConnection) return NO;

	unsigned int ss = mySQLConnection->server_status;

	unsigned int (^isSet)(unsigned int) =  ^unsigned int(unsigned int cmp) {
		return ((ss & cmp) != 0 ? 1 : 0);
	};

	bits->inTransaction        = isSet(SERVER_STATUS_IN_TRANS); // 1 << 0
	bits->autocommit           = isSet(SERVER_STATUS_AUTOCOMMIT); // 1 << 1
	bits->_reserved1           = isSet(4); // 1 << 2
	bits->moreResultsExists    = isSet(SERVER_MORE_RESULTS_EXISTS); // 1 << 3
	bits->queryNoGoodIndexUsed = isSet(SERVER_QUERY_NO_GOOD_INDEX_USED); // 1 << 4
	bits->queryNoIndexUsed     = isSet(SERVER_QUERY_NO_INDEX_USED); // 1 << 5
	bits->cursorExists         = isSet(SERVER_STATUS_CURSOR_EXISTS); // 1 << 6
	bits->lastRowSent          = isSet(SERVER_STATUS_LAST_ROW_SENT); // 1 << 7
	bits->dbDropped            = isSet(SERVER_STATUS_DB_DROPPED); // 1 << 8
	bits->noBackslashEscapes   = isSet(SERVER_STATUS_NO_BACKSLASH_ESCAPES); // 1 << 9
	bits->metadataChanged      = isSet(SERVER_STATUS_METADATA_CHANGED); // 1 << 10
	bits->queryWasSlow         = isSet(SERVER_QUERY_WAS_SLOW); // 1 << 11
	bits->psOutParams          = isSet(SERVER_PS_OUT_PARAMS); // 1 << 12
	//TODO the following two flags were added after the 5.5 branch we are currently using
	bits->inTransReadonly      = isSet(1 << 13); // 1 << 13
	bits->sessionStateChanged  = isSet(1 << 14); // 1 << 14
	// currently unused bits (protocol V10 uses 16 bit status on the wire)
	bits->_reserved2           = isSet(1 << 15); // 1 << 15

	return YES;
}

@end
