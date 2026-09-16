//
//  SPMySQLConnection.h
//  SPMySQLFramework
//
//  Created by Rowan Beentje (rowan.beent.je) on January 8, 2012
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

@class SAConnectionCancellation, SAConnectionEscaper, SAConnectionLostDecisionGate, SAConnectionWorkCoordinator, SADatabaseAssertionState, SAInFlightQuery, SPMySQLKeepAliveTimer;

@interface SPMySQLConnection : NSObject {

	// Delegate
    __weak NSObject <SPMySQLConnectionDelegate> *delegate;
	BOOL delegateSupportsWillQueryString;
	BOOL delegateSupportsConnectionLost;
	BOOL delegateSupportsConnectionCheckProgress;
	BOOL delegateQueryLogging; // Defaults to YES if protocol implemented

	// Basic connection details
	NSString *host;
	NSString *username;
	NSString *password;
	NSUInteger port;
	BOOL useSocket;
	NSString *socketPath;

	//Special connection settings
	BOOL allowDataLocalInfile;

	// Clear text plugin
	BOOL enableClearTextPlugin;

	// Server public key request for caching_sha2_password over non-TLS connections
	BOOL requestServerPublicKey;

	// SSL connection details
	BOOL useSSL;
	NSString *sslKeyFilePath;
	NSString *sslCertificatePath;
	NSString *sslCACertificatePath;
	NSString *sslCipherList;

	// MySQL connection details and state
	struct MYSQL *mySQLConnection;
	SPMySQLConnectionState state;
	BOOL connectedWithSSL;
	BOOL userTriggeredDisconnect;
	pthread_t reconnectingThread;
	uint64_t initialConnectTime;
	unsigned long mysqlConnectionThreadId;

	// Connection proxy
	NSObject <SPMySQLConnectionProxy> *proxy;
	SPMySQLConnectionProxyState previousProxyState;
	BOOL proxyStateChangeNotificationsIgnored;

	// Connection lock to prevent non-thread-safe query misuse
	NSConditionLock *connectionLock;

	// Currently selected database
	NSString *database, *databaseToRestore;
	SADatabaseAssertionState *databaseAssertionState;

	// Delegate connection lost decisions
	NSUInteger reconnectionRetryAttempts;
	SPMySQLConnectionLostDecision lastDelegateDecisionForLostConnection;
	NSLock *delegateDecisionLock;

	// One lost-connection question at a time, and whether a modal window was showing last time
	// anybody looked.
	SAConnectionLostDecisionGate *delegateDecisionGate;
	BOOL aModalWindowIsShowing;

	// Timeout and keep-alive
	NSUInteger timeout;

	// Set while the connection is being re-established after a check found it
	// gone: that first attempt runs on short budgets so the user is asked what
	// to do instead of waiting out the full timeouts.
	BOOL reconnectingAfterFailedCheck;
	// Connect timeout for that attempt, in seconds; 0 while the normal one applies.
	NSUInteger connectTimeoutOverride;

	// Where connection work runs when the main thread must not wait for it, and how many waits
	// for it are currently nested.
	SAConnectionWorkCoordinator *connectionWorkCoordinator;
	NSUInteger connectionWorkWaitDepth;

	// Whether the user has ended a wait, which the next attempt is not allowed to spend again
	BOOL userEndedPendingWork;
	uint64_t userEndedPendingWorkTime;

	// Whether the main thread stopped waiting for the work it ran last, whose session is then on its
	// way out; and whether the character set on record was changed for the next session only, so
	// the current one must not be used any more
	BOOL lastWorkWasAbandoned;
	BOOL sessionMustBeReplacedBeforeUse;

	// Whether the last session was closed while its proxy was left running
	BOOL sessionWasClosedWithoutItsProxy;

	// What escapes values without touching the session, and the escaping mode the latest session
	// reported (NO_BACKSLASH_ESCAPES), recorded while the connection was held
	SAConnectionEscaper *valueEscaper;
	BOOL sessionUsesNoBackslashEscapes;

	// Which query is running, so that anything acting on "the query" later can tell whether it
	// is still the same one, and which query is waiting on the server right now
	NSUInteger queryGeneration;
	SAInFlightQuery *inFlightQuery;
	SAConnectionCancellation *connectionCancellation;

	BOOL useKeepAlive;
	SPMySQLKeepAliveTimer *keepAliveTimer;
	CGFloat keepAliveInterval;
	uint64_t lastKeepAliveTime;
	NSUInteger keepAlivePingFailures;
	volatile NSThread *keepAliveThread;
	volatile BOOL keepAlivePingThreadActive;
	BOOL keepAliveLastPingBlocked;

	// Encoding details - and also a record of any previous encoding to allow
	// switching back and forth
	NSString *encoding, *encodingToRestore;
	NSStringEncoding stringEncoding;
	BOOL encodingUsesLatin1Transport, encodingUsesLatin1TransportToRestore;
	NSString *previousEncoding;
	BOOL previousEncodingUsesLatin1Transport;

	// Server details
	NSString *serverVariableVersion;
	unsigned long serverVersionNumber;

	// Error state for the last query or connection state
	NSUInteger queryErrorID;
	NSString *queryErrorMessage;
	NSString *querySqlstate;

	// Query details
	unsigned long long lastQueryAffectedRowCount;
	unsigned long long lastQueryInsertID;

	// Query cancellation details
	BOOL lastQueryWasCancelled;

	// Timing details
	uint64_t lastConnectionUsedTime;
	double lastQueryExecutionTime;

	// Maximum query size
	NSUInteger maxQuerySize;
	BOOL maxQuerySizeIsEditable;
	BOOL maxQuerySizeEditabilityChecked;
	NSUInteger queryActionShouldRestoreMaxQuerySize;

	// Queries
	BOOL retryQueriesOnConnectionFailure;
	
	SPMySQLClientFlags clientFlags;
	
	NSString *_debugLastConnectedEvent;
}

#pragma mark -
#pragma mark Synthesized properties

@property (readwrite, copy) NSString *host;
@property (readwrite, copy) NSString *username;
@property (readwrite, copy) NSString *password;
@property (readwrite, copy) NSString *database;
@property (readwrite) NSUInteger port;
@property (readwrite) BOOL useSocket;
@property (readwrite, copy) NSString *socketPath;

@property (readonly, copy) NSString *timeZoneIdentifier;

@property (readwrite) BOOL allowDataLocalInfile;

@property (readwrite) BOOL enableClearTextPlugin;

@property (readwrite) BOOL requestServerPublicKey;

@property (readwrite) BOOL useSSL;
@property (readwrite, copy) NSString *sslKeyFilePath;
@property (readwrite, copy) NSString *sslCertificatePath;
@property (readwrite, copy) NSString *sslCACertificatePath;

/**
 * List of pre-TLS 1.3 ciphers for SSL/TLS connections.
 * This is a colon-separated string of names as used by
 * `openssl ciphers`. The order of entries specifies
 * their preference (earlier = better).
 * A value of nil (default) means SPMySQLConnection will use its built-in
 * pre-TLS 1.3 cipher list when calling `mysql_ssl_set()`.
 *
 * TLS 1.3 ciphersuites are configured separately via `MYSQL_OPT_TLS_CIPHERSUITES`
 * using SPMySQLConnection's built-in `_defaultTLSSuiteListString` and are not
 * currently overridden by `sslCipherList`.
 */
@property (readwrite, copy) NSString *sslCipherList;

@property (readwrite, assign) NSUInteger timeout;
@property (readwrite, assign) BOOL useKeepAlive;
@property (readwrite, assign) CGFloat keepAliveInterval;

@property (readonly) unsigned long mysqlConnectionThreadId;
@property (readwrite, assign) BOOL retryQueriesOnConnectionFailure;

@property (readwrite, assign) BOOL delegateQueryLogging;

@property (readwrite, assign) BOOL lastQueryWasCancelled;

/**
 * The mysql client capability flags to set when connecting.
 * See CLIENT_* in mysql.h
 */
@property (readwrite, assign, nonatomic) SPMySQLClientFlags clientFlags;
- (void)addClientFlags:(SPMySQLClientFlags)opts;
- (void)removeClientFlags:(SPMySQLClientFlags)opts;

#pragma mark -
#pragma mark Connection and disconnection

- (BOOL)connect;
- (BOOL)reconnect;
- (void)disconnect;

#pragma mark -
#pragma mark Connection state

- (BOOL)isConnected;
- (BOOL)isConnectedViaSSL;
- (BOOL)checkConnection;
/** Ends the interface's wait for connection work, and asks that work to stop. */
- (void)cancelConnectionCheck;
/** Stops a query, provided it is still the one running: marks it, asks the server, and closes its socket if the server does not answer. */
- (void)cancelQueryIfStillRunning:(NSUInteger)generation;
/** Identifies the query the connection is running, and changes whenever another one takes over. */
- (NSUInteger)currentQueryGeneration;
- (BOOL)checkConnectionIfNecessary;
- (double)timeConnected;
- (BOOL)userTriggeredDisconnect;
- (BOOL)isNotMariadb103;
- (BOOL)isMariaDB;

#pragma mark -
#pragma mark Connection utility

+ (NSString *)findSocketPath;

#pragma mark -
#pragma mark Timezone
- (void)updateTimeZoneIdentifier:(NSString *)timeZoneIdentifier;

@end
