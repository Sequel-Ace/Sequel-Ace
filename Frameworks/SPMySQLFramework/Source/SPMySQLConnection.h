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

@class SAConnectionCancellation, SAConnectionEscaper, SAConnectionLostDecisionGate, SAConnectionSetupDeadline, SAConnectionWorkCoordinator, SADatabaseAssertionState, SAStatementReport, SPMySQLKeepAliveTimer;

/**
 * How a session is to be replaced before its next use. One word, so that a reader sees the whole
 * mark or none of it - never half of a mark somebody is still publishing.
 */
typedef NS_ENUM(NSInteger, SASessionReplacementMark) {
	/// The session is in step with what the connection knows of it.
	SASessionReplacementMarkNotMarked = 0,
	/// Replaced before its next use, once nothing is open in it.
	SASessionReplacementMarkWhenNothingIsOpen = 1,
	/// Replaced before its next use whatever is open in it: an answer nobody read may still be on
	/// its way, and the next statement would read it as its own result.
	SASessionReplacementMarkRegardless = 2,
};

/**
 * Which session a value escaped now is escaped for.
 */
typedef NS_ENUM(NSInteger, SAEscapingSession) {
	/// The session the connection has.
	SAEscapingSessionTheSessionThere = 0,
	/// The session that replaces it before the next statement.
	SAEscapingSessionTheReplacement = 1,
	/// Cannot be told: the session goes unless something is open in it, and a statement running
	/// right now may open something. The value is refused rather than escaped for a guess.
	SAEscapingSessionUndecidable = 2,
};

@interface SPMySQLConnection : NSObject {

	// Delegate
    __weak NSObject <SPMySQLConnectionDelegate> *delegate;
	BOOL delegateSupportsWillQueryString;
	BOOL delegateSupportsConnectionLost;
	// Whether the delegate shows a wait for connection work and lets the user end it - which is
	// what makes the connection hand a main thread's work to its worker at all.
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
	// Set when a marked session was closed over a proxy that was left as it was, so the
	// reconnect that follows - and a retry after a handshake that failed - connects through it
	// instead of waiting for it to go idle. Cleared when a disconnect asks the proxy to go, and
	// when a session comes up through it.
	BOOL proxyUntouchedBySessionReplacement;

	// Connection lock to prevent non-thread-safe query misuse
	NSConditionLock *connectionLock;

	// Currently selected database
	NSString *database, *databaseToRestore;
	SADatabaseAssertionState *databaseAssertionState;

	// Delegate connection lost decisions
	NSUInteger reconnectionRetryAttempts;
	SPMySQLConnectionLostDecision lastDelegateDecisionForLostConnection;
	NSLock *delegateDecisionLock;
	// Threads that lose the connection at the same time share one answer instead of each
	// opening its own dialog; the gate decides who asks and who waits for that answer.
	SAConnectionLostDecisionGate *delegateDecisionGate;
	// Set on the main thread while the lost-connection question waits for another modal window.
	BOOL aModalWindowIsShowing;
	// Escapes values from what the session last reported instead of from the connection's own
	// handle, which work nobody waits for any more can be using or closing.
	SAConnectionEscaper *valueEscaper;
	// The deadline on the statements that set the session up, or restore it, while they run: a
	// statement that loses the session under it fails the attempt rather than starting another.
	SAConnectionSetupDeadline *activeSetupDeadline;
	// How a query is stopped: recorded first, the server asked, the socket shut down after a
	// grace period. The lease keeps the books; this holds the policy.
	SAConnectionCancellation *connectionCancellation;
	// Where a main thread's connection work runs, so that the window keeps answering while the
	// work waits for a server, and the delegate can show the wait and let the user end it.
	SAConnectionWorkCoordinator *connectionWorkCoordinator;
	// How the session is to be replaced before its next use - a SASessionReplacementMark: not at
	// all; once nothing is open in it; or regardless, because a ping cut off before its answer
	// came may still get that answer, which the next statement would read as its own result. One
	// word, so a reader never sees half of a mark being published, and only ever touched through
	// -sessionReplacementMark and -markSessionReplacement:, which read and write it atomically:
	// the keepalive writes it from its own thread, and escaping reads it without the connection lock.
	NSInteger sessionReplacement;
	// Set when the session was lost to a failed check - a keepalive ping cut off before its answer
	// came - and closed for replacement: whoever restores it reconnects on the check's limits, not
	// on the configured timeout; a reconnect the user asks for takes the plain form, which does not
	// read it. Cleared by the next session.
	BOOL sessionLostAfterFailedCheck;

	// Timeout and keep-alive
	NSUInteger timeout;
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
	// The character set the server reads statements in, which `character_set_results` - what the
	// record above follows, because results are decoded with it - does not have to agree with.
	NSString *sqlInputEncoding;
	// Whether any result packet of the statement being finished carried the server's report of
	// the session's character set. Collected across packets, because fetching one replaces the
	// items of the one before.
	BOOL characterSetReportedInAResultPacket;
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

	// The report of the statement that still holds the session - a streaming statement, whose rows
	// are read after its report was taken - which what the connection writes meanwhile goes into;
	// nil once the session is released.
	SAStatementReport *currentStatementReport;
	// Whether the statement just run keeps the session for its result's rows.
	BOOL statementHoldsSession;

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

/** Whether the connection is in the connected state. */
- (BOOL)isConnected;
/** Whether the connection is in the connected state and its session is encrypted. */
- (BOOL)isConnectedViaSSL;
/** Whether the connection answers; a failed check's error is the calling thread's to read, like a statement's report. */
- (BOOL)checkConnection;
- (BOOL)checkConnectionIfNecessary;
/** Ends the delegate's wait for connection work and stops that work: the thread it runs on, and the query it may have waiting on the server. */
- (void)cancelConnectionCheck;
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
