//
//  SPMySQLConnection.m
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

#import "SPMySQL Private APIs.h"
#import "SPMySQLKeepAliveTimer.h"
#include <arpa/inet.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <SystemConfiguration/SCNetworkReachability.h>
#include <sys/socket.h>
#import "SPMySQLUtilities.h"
#import "SPMySQLArrayAdditions.h"
#import "SPMySQLMutableDictionaryAdditions.h"
#import <SPMySQL/SPMySQL-Swift.h>

@interface SPMySQLConnection () <SAConnectionCancellationHost>

@property (readwrite, copy) NSString *timeZoneIdentifier;
@property (readonly, strong) SAProxyReconnectCoordinator *proxyReconnectCoordinator;

@end

// Thread flag constant
static pthread_key_t mySQLThreadInitFlagKey;
static void *mySQLThreadFlag;

static BOOL SPHostIsLoopbackIPv4Address(NSString *normalizedHost)
{
	struct in_addr ipv4Address;
	if (inet_pton(AF_INET, [normalizedHost UTF8String], &ipv4Address) == 1) {
		return ((ntohl(ipv4Address.s_addr) >> 24) == 127);
	}

	NSArray<NSString *> *components = [normalizedHost componentsSeparatedByString:@"."];
	if (![components count] || [components count] > 4) return NO;
	if (![[components firstObject] isEqualToString:@"127"]) return NO;

	NSCharacterSet *nonDigitCharacters = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
	for (NSString *component in components) {
		if (![component length] || [component rangeOfCharacterFromSet:nonDigitCharacters].location != NSNotFound) return NO;
	}

	return YES;
}

#pragma mark Class constants

// The default connection options for MySQL connections
const SPMySQLClientFlags SPMySQLConnectionOptions =
					SPMySQLClientFlagCompression |  // Enable protocol compression - almost always a win
					SPMySQLClientFlagInteractive |  // Mark ourselves as an interactive client
					SPMySQLClientFlagMultiResults;  // Multiple result support (very basic, but present)

@implementation SPMySQLConnection

#pragma mark -
#pragma mark Synthesized properties

@synthesize host;
@synthesize username;
@synthesize password;
@synthesize database;
@synthesize port;
@synthesize useSocket;
@synthesize socketPath;
@synthesize allowDataLocalInfile;
@synthesize enableClearTextPlugin;
@synthesize requestServerPublicKey;
@synthesize useSSL;
@synthesize sslKeyFilePath;
@synthesize sslCertificatePath;
@synthesize sslCACertificatePath;
@synthesize sslCipherList;
@synthesize timeout;
@synthesize useKeepAlive;
@synthesize keepAliveInterval;
@synthesize mysqlConnectionThreadId;
@synthesize retryQueriesOnConnectionFailure;
@synthesize delegateQueryLogging;
@synthesize lastQueryWasCancelled;

/**
 * Identifies the query the connection is running, or ran last. It changes whenever a query takes
 * over the connection, so something that acts on "the running query" later can check that it is
 * still the one it meant.
 *
 * @return The current query's number.
 */
- (NSUInteger)currentQueryGeneration
{
	// Read from the in-flight record, which never waits: the connection's own counter is written
	// by the query's thread while it holds the connection.
	return [inFlightQuery latestGeneration];
}
@synthesize clientFlags = clientFlags;

#pragma mark -
#pragma mark Getters and Setters

- (void)addClientFlags:(SPMySQLClientFlags)opts
{
	[self setClientFlags:([self clientFlags] | opts)];
}

- (void)removeClientFlags:(SPMySQLClientFlags)opts
{
	[self setClientFlags:([self clientFlags] & ~opts)];
}

#pragma mark -
#pragma mark Initialisation and teardown

/**
 * In the one-off class initialisation, set up MySQL as necessary
 */
+ (void)initialize
{
	// Set up a pthread thread-specific data key to be used across all classes and threads
	pthread_key_create(&mySQLThreadInitFlagKey, NULL);
	mySQLThreadFlag = malloc(1);

	// MySQL requires mysql_library_init() to be called before any other MySQL
	// functions are used; although mysql_init() will call it automatically, it
	// won't do so in a thread-safe manner, so setting it up first is safer.
	// No arguments are required.
	// Note that this will install MySQL's SIGPIPE handler.
	mysql_library_init(0, NULL, NULL);
}

+ (NSArray<NSString *> *)defaultSSLCipherList
{
	static dispatch_once_t onceToken;
	static NSArray<NSString *> *defaultSSLCipherList = nil;

	dispatch_once(&onceToken, ^{
		defaultSSLCipherList = @[
			@"ECDHE-ECDSA-AES256-GCM-SHA384",
			@"ECDHE-ECDSA-AES128-GCM-SHA256",
			@"ECDHE-RSA-AES256-GCM-SHA384",
			@"ECDHE-RSA-AES128-GCM-SHA256",
			@"ECDHE-ECDSA-CHACHA20-POLY1305",
			@"ECDHE-RSA-CHACHA20-POLY1305",
			@"DHE-RSA-AES256-GCM-SHA384",
			@"DHE-RSA-AES128-GCM-SHA256",
			@"DHE-RSA-CHACHA20-POLY1305",
			@"ECDHE-ECDSA-AES256-SHA384",
			@"ECDHE-ECDSA-AES128-SHA256",
			@"ECDHE-RSA-AES256-SHA384",
			@"ECDHE-RSA-AES128-SHA256",
			@"DHE-RSA-AES256-SHA256",
			@"DHE-RSA-AES128-SHA256",
			@"AES256-GCM-SHA384",
			@"AES128-GCM-SHA256",
			@"AES256-SHA256",
			@"AES128-SHA256",
			@"DHE-RSA-AES256-SHA",
			@"DHE-RSA-AES128-SHA",
			@"AES256-SHA",
			@"AES128-SHA",
		];
	});

	return defaultSSLCipherList;
}

+ (NSArray<NSString *> *)legacySSLCipherList
{
	static dispatch_once_t onceToken;
	static NSArray<NSString *> *legacySSLCipherList = nil;

	dispatch_once(&onceToken, ^{
		legacySSLCipherList = @[
			@"CAMELLIA128-SHA",
			@"CAMELLIA256-SHA",
			@"DH-DSS-AES128-GCM-SHA256",
			@"DH-DSS-AES128-SHA",
			@"DH-DSS-AES128-SHA256",
			@"DH-DSS-AES256-GCM-SHA384",
			@"DH-DSS-AES256-SHA",
			@"DH-DSS-AES256-SHA256",
			@"DH-RSA-AES128-GCM-SHA256",
			@"DH-RSA-AES128-SHA",
			@"DH-RSA-AES128-SHA256",
			@"DH-RSA-AES256-GCM-SHA384",
			@"DH-RSA-AES256-SHA",
			@"DH-RSA-AES256-SHA256",
			@"DHE-DSS-AES256-GCM-SHA384",
			@"DHE-DSS-AES128-GCM-SHA256",
			@"DHE-DSS-AES128-SHA256",
			@"DHE-DSS-AES256-SHA256",
			@"DHE-DSS-AES128-SHA",
			@"DHE-DSS-AES256-SHA",
			@"ECDH-ECDSA-AES128-GCM-SHA256",
			@"ECDH-ECDSA-AES128-SHA",
			@"ECDH-ECDSA-AES128-SHA256",
			@"ECDH-ECDSA-AES256-GCM-SHA384",
			@"ECDH-ECDSA-AES256-SHA",
			@"ECDH-ECDSA-AES256-SHA384",
			@"ECDH-RSA-AES128-GCM-SHA256",
			@"ECDH-RSA-AES128-SHA",
			@"ECDH-RSA-AES128-SHA256",
			@"ECDH-RSA-AES256-GCM-SHA384",
			@"ECDH-RSA-AES256-SHA",
			@"ECDH-RSA-AES256-SHA384",
			@"ECDHE-ECDSA-AES128-SHA",
			@"ECDHE-ECDSA-AES256-SHA",
			@"ECDHE-RSA-AES128-SHA",
			@"ECDHE-RSA-AES256-SHA",
			@"AES256-RMD",
			@"AES128-RMD",
			@"DES-CBC3-RMD",
			@"DHE-RSA-AES256-RMD",
			@"DHE-RSA-AES128-RMD",
			@"DHE-RSA-DES-CBC3-RMD",
			@"RC4-SHA",
			@"RC4-MD5",
			@"DES-CBC3-SHA",
			@"DES-CBC-SHA",
			@"EDH-RSA-DES-CBC3-SHA",
			@"EDH-RSA-DES-CBC-SHA",
		];
	});

	return legacySSLCipherList;
}

+ (NSString *)_defaultSSLCipherListString
{
	static dispatch_once_t onceToken;
	static NSString *defaultSSLCipherListString = nil;

	dispatch_once(&onceToken, ^{
		defaultSSLCipherListString = [[self defaultSSLCipherList] componentsJoinedByString:@":"];
	});

	return defaultSSLCipherListString;
}

+ (NSString *)_defaultTLSSuiteListString
{
	static dispatch_once_t onceToken;
	static NSString *defaultTLSSuiteListString = nil;

	dispatch_once(&onceToken, ^{
		defaultTLSSuiteListString = @"TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256";
	});

	return defaultTLSSuiteListString;
}

+ (NSArray<NSString *> *)_mergedSSLCipherPreferenceListFromSavedCipherString:(NSString *)savedCipherString disabledMarker:(NSString *)disabledMarker
{
	NSMutableArray<NSString *> *enabledCiphers = [NSMutableArray array];
	NSMutableArray<NSString *> *disabledCiphers = [NSMutableArray array];
	NSMutableSet<NSString *> *validCiphers = [NSMutableSet setWithArray:[self defaultSSLCipherList]];
	BOOL inDisabledSection = NO;

	[validCiphers addObjectsFromArray:[self legacySSLCipherList]];

	for (NSString *savedCipher in [savedCipherString componentsSeparatedByString:@":"]) {
		if ([savedCipher isEqualToString:disabledMarker]) {
			inDisabledSection = YES;
			continue;
		}
		if (![validCiphers containsObject:savedCipher]) continue;
		if ([enabledCiphers containsObject:savedCipher] || [disabledCiphers containsObject:savedCipher]) continue;
		[(inDisabledSection ? disabledCiphers : enabledCiphers) addObject:savedCipher];
	}

	NSUInteger enabledInsertIndex = 0;
	for (NSString *cipher in [self defaultSSLCipherList]) {
		if (![enabledCiphers containsObject:cipher] && ![disabledCiphers containsObject:cipher]) {
			[enabledCiphers insertObject:cipher atIndex:enabledInsertIndex++];
		}
	}

	NSUInteger disabledInsertIndex = 0;
	for (NSString *cipher in [self legacySSLCipherList]) {
		if (![enabledCiphers containsObject:cipher] && ![disabledCiphers containsObject:cipher]) {
			[disabledCiphers insertObject:cipher atIndex:disabledInsertIndex++];
		}
	}

	NSMutableArray<NSString *> *mergedCiphers = [NSMutableArray arrayWithArray:enabledCiphers];
	[mergedCiphers addObject:disabledMarker];
	[mergedCiphers addObjectsFromArray:disabledCiphers];

	return mergedCiphers;
}

+ (NSString *)_reachabilityProbeHostForHost:(NSString *)aHost useSocket:(BOOL)shouldUseSocket hasProxy:(BOOL)hasProxy
{
	if (hasProxy || shouldUseSocket || ![aHost length]) return nil;

	NSString *trimmedHost = [aHost stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([trimmedHost hasPrefix:@"["] && [trimmedHost hasSuffix:@"]"] && [trimmedHost length] > 2) {
		trimmedHost = [trimmedHost substringWithRange:NSMakeRange(1, [trimmedHost length] - 2)];
	}

	if (![trimmedHost length]) return nil;

	NSString *normalizedHost = [trimmedHost lowercaseString];
	if ([normalizedHost isEqualToString:@"localhost"] || [normalizedHost isEqualToString:@"::1"] || SPHostIsLoopbackIPv4Address(normalizedHost)) {
		return nil;
	}

	return trimmedHost;
}

/**
 * Initialise the SPMySQLConnection object, setting up class defaults.
 *
 * Typically initialisation would be followed by setting the connection details
 * and then calling -connect.
 */
- (instancetype)init
{
	if ((self = [super init])) {
		mySQLConnection = NULL;
		state = SPMySQLDisconnected;
		userTriggeredDisconnect = NO;
		reconnectingThread = NULL;
		mysqlConnectionThreadId = 0;
		initialConnectTime = 0;

		port = 3306;

		_timeZoneIdentifier = @"";

		// Default to socket connections if no other details have been provided
		useSocket = YES;

		// Start with no proxy
		proxy = nil;
		proxyStateChangeNotificationsIgnored = NO;
		_proxyReconnectCoordinator = [[SAProxyReconnectCoordinator alloc] init];

		// Start with no selected database
		database = nil;
		databaseToRestore = nil;

		// Set a timeout of 30 seconds, with keepalive on and acting every sixty seconds
		timeout = 30;
		useKeepAlive = YES;
		keepAliveInterval = 60;
		keepAlivePingFailures = 0;
		lastKeepAliveTime = 0;
		keepAliveThread = nil;
		keepAlivePingThreadActive = NO;
		keepAliveLastPingBlocked = NO;

		// Set up default encoding variables
        encoding = @"utf8mb4";
		stringEncoding = NSUTF8StringEncoding;
		encodingUsesLatin1Transport = NO;
		encodingToRestore = nil;
		encodingUsesLatin1TransportToRestore = NO;
		previousEncoding = nil;
		previousEncodingUsesLatin1Transport = NO;

		// Initialise default delegate settings
		delegate = nil;
		delegateSupportsWillQueryString = NO;
		delegateSupportsConnectionLost = NO;
		delegateQueryLogging = YES;

		// Delegate disconnection decisions
		reconnectionRetryAttempts = 0;
		lastDelegateDecisionForLostConnection = SPMySQLConnectionLostDisconnect;
		delegateDecisionLock = [[NSLock alloc] init];
		delegateDecisionGate = [[SAConnectionLostDecisionGate alloc] init];
		inFlightQuery = [[SAInFlightQuery alloc] init];
		valueEscaper = [[SAConnectionEscaper alloc] init];
		connectionCancellation = [[SAConnectionCancellation alloc] initWithHost:self inFlightQuery:inFlightQuery];

		// Set up the connection lock
		connectionLock = [[NSConditionLock alloc] initWithCondition:SPMySQLConnectionIdle];
		[connectionLock setName:@"SPMySQLConnection query lock"];

		// Ensure the server detail records are initialised
		serverVariableVersion = nil;
		serverVersionNumber = 0;

		// Start with a blank error state
		queryErrorID = 0;
		queryErrorMessage = nil;
		querySqlstate = nil;

		// Start with empty cancellation details
		lastQueryWasCancelled = NO;

		// Empty or reset the timing variables
		lastConnectionUsedTime = 0;
		lastQueryExecutionTime = 0;

		// Default to editable query size of 1MB
		maxQuerySize = 1048576;
		maxQuerySizeIsEditable = YES;
		maxQuerySizeEditabilityChecked = NO;
		queryActionShouldRestoreMaxQuerySize = NSNotFound;

		// Default to allowing queries to be automatically retried if the connection drops
		// while running them
		retryQueriesOnConnectionFailure = YES;

		_debugLastConnectedEvent = nil;

		// Start the ping keepalive timer
		keepAliveTimer = [[SPMySQLKeepAliveTimer alloc] initWithInterval:10 target:self selector:@selector(_keepAlive)];
		
		[self setClientFlags:SPMySQLConnectionOptions];
	}

	return self;
}

/**
 * Object deallocation.
 */
- (void) dealloc
{
	userTriggeredDisconnect = YES;

	// Unset the delegate
	[self setDelegate:nil];

	// Clear the keepalive timer
	[keepAliveTimer invalidate];

	// If a keepalive thread is active, cancel it
	[self _cancelKeepAlives];

	// Disconnect if appropriate (which should also disconnect any proxy)
	[self _disconnect];

	// Clean up the connection proxy, if any
	if (proxy) {
		[proxy setConnectionStateChangeSelector:NULL delegate:nil];
	}
	
	[self setSslCipherList:nil];

	// Ensure the query lock is unlocked, thereafter setting to nil in case of pending calls
	if ([connectionLock condition] != SPMySQLConnectionIdle) {
		[self _unlockConnection];
	}

	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

#pragma mark -
#pragma mark Connection and disconnection

/**
 * Trigger a connection to the specified host, if any, using any connection details
 * that have been set.
 * Returns whether the connection was successful.
 */
- (BOOL)connect
{
    SPLog(@"connect");

	userTriggeredDisconnect = NO;
	return [self _connect];
}

/**
 * Reconnect to the currently "active" - but possibly disconnected - connection, using the
 * stored details.  Calls the private _reconnectAllowingRetries to do this.
 * Error checks extensively - if this method fails, it will ask how to proceed and loop depending
 * on the status, not returning control until either a connection has been established or
 * the connection and document have been closed.
 *
 * WARNING: This method may exit early returning NO if the current thread is cancelled!
 *          You MUST check the isCancelled flag before using the result!
 */
- (BOOL)reconnect
{
    SPLog(@"reconnect");
	userTriggeredDisconnect = NO;
	return [self _reconnectAllowingRetries:YES];
}

/**
 * Trigger a disconnection if the connection is currently active.
 */
- (void)disconnect
{
    SPLog(@"calling _disconnect");
	userTriggeredDisconnect = YES;
	[self _disconnect];
}

#pragma mark -
#pragma mark Connection state

/**
 * Retrieve whether the connection instance is connected to the remote host.
 * Returns NO if the connection is still in process, YES if a disconnection is
 * being actively performed.
 */
- (BOOL)isConnected
{
	// If the connection has been allowed to drop in the background, restore it if posslbe.
	// Not on the main thread: that would freeze the interface for as long as the network takes -
	// after a stopped wait, whose session is closed on purpose, as much as after a dropped route.
	// There the connection still counts as connected, and the next query restores the session
	// while the interface keeps answering.
	if (state == SPMySQLConnectionLostInBackground) {
		if (![SAConnectionCancellation restoresLostSessionWhenAskedIfConnectedOnMainThread:[NSThread isMainThread]]) {
			return YES;
		}
        SPLog(@"SPMySQLConnectionLostInBackground, reconnecting");
		[self _reconnectAllowingRetries:YES];
	}

	return (state == SPMySQLConnected || state == SPMySQLDisconnecting);
}

/**
 * Returns YES if the SPMySQLConnection is connected to a server via SSL, NO otherwise.
 */
- (BOOL)isConnectedViaSSL
{
	return ([self isConnected] && connectedWithSSL);
}

/**
 * Checks whether the connection to the server is still active.  This verifies
 * the connection using a ping, and if the connection is found to be down attempts
 * to quickly restore it, including the previous state.
 *
 * WARNING: This method may return NO if the current thread is cancelled!
 *          You MUST check the isCancelled flag before using the result!
 *
 * NOTE: In general -checkConnectionIfNecessary should be used instead!
 */
- (BOOL)checkConnection
{
    SPLog(@"checkConnection");

	// If the connection is not seen as active, don't proceed
    if (state != SPMySQLConnected){
        SPLog(@"state != SPMySQLConnected, returning NO");
        return NO;
    }

	// Similarly, if the connection is currently locked, that indicates it's in use.  This
	// could be because queries are actively being run, or that a ping is running.
	if ([connectionLock condition] == SPMySQLConnectionBusy) {
        SPLog(@"SPMySQLConnectionBusy");

		// If a ping thread is not active queries are being performed - return success.
		if (!keepAlivePingThreadActive) return YES;

		// If a ping thread is active, wait for it to complete before checking the connection
        SPLog(@"ping thread is active, wait for it to complete before checking the connection");

		while (keepAlivePingThreadActive) {
			usleep(10000);
		}
	}

    SPLog(@"calling _pingConnectionUsingLoopDelay");
	// Confirm whether the connection is still responding by using a ping
	// A connection configured with a shorter timeout keeps it; the budget only caps.
	NSUInteger checkPingTimeout = [SAConnectionCheckBudget pingTimeoutForConfiguredTimeout:timeout];
	BOOL connectionVerified = [self _pingConnectionUsingLoopDelay:400 timeout:checkPingTimeout];
    SPLog(@"_pingConnectionUsingLoopDelay finished");

	// If the connection didn't respond, trigger a reconnect.  This will automatically
	// attempt to reconnect once, and if that fails will ask the user how to proceed - whether
	// to keep reconnecting, or whether to disconnect.
	if (!connectionVerified) {
        SPLog(@"!connectionVerified, calling _reconnectAllowingRetries");
		// The connection is gone as far as the check can tell. Keep the first
		// automatic attempt short so the "connection lost" question reaches the
		// user in seconds rather than after a minute of blocked interface.
		reconnectingAfterFailedCheck = YES;
		connectionVerified = [self _reconnectAllowingRetries:YES];
		reconnectingAfterFailedCheck = NO;
	}

	// Update the connection tracking use variable if the connection was confirmed,
	// as at least a mysql_ping will have been used.
	if (connectionVerified) {
        lastConnectionUsedTime = _monotonicTime();
	}

	return connectionVerified;
}

/**
 * If thirty seconds have passed since the last time the connection was
 * used, check the connection.
 * This minimises the impact of continuous additional connection checks -
 * each of which requires a round trip to the server - but handles most
 * network issues.
 * Returns whether the connection is considered still valid.
 *
 * WARNING: This method may return NO if the current thread is cancelled!
 *          You MUST check the isCancelled flag before using the result!
 */
- (BOOL)checkConnectionIfNecessary
{
	// If the connection has been dropped in the background, trigger a
	// reconnect and return the success state here
	if (state == SPMySQLConnectionLostInBackground) {
        SPLog(@"SPMySQLConnectionLostInBackground, calling _reconnectAllowingRetries");
		return [self _runConnectionWorkKeepingInterfaceAlive:^BOOL{
			return [self _reconnectAllowingRetries:YES];
		}];
	}
	
	// If the connection was recently used, return success - unless its socket
	// already knows the peer is gone, which a dropped route does not announce.
	double idleTime = _timeIntervalSinceMonotonicTime(lastConnectionUsedTime);
	if (idleTime < 30) {
		if (![self _shouldVerifyRecentlyUsedConnectionIdleFor:idleTime]) return YES;
		SPLog(@"connection socket reports the peer is gone; checking despite recent use");
	}
	
	// Otherwise check the connection
	return [self _runConnectionWorkKeepingInterfaceAlive:^BOOL{
		return [self checkConnection];
	}];
}

/**
 * Ends the interface's wait for connection work, and stops that work: the thread it runs on, and
 * the query it may have waiting on the server.
 */
- (void)cancelConnectionCheck
{
	[connectionCancellation userStoppedWaitingWithWorkCoordinator:connectionWorkCoordinator];
}

/**
 * Stops a query, provided it is still the one running. The query is marked at once, the server is
 * asked to kill it, and its socket is closed if it is still waiting shortly afterwards. Off the
 * main thread the request to the server goes out before this returns, for callers that rely on it.
 *
 * @param generation The query to stop, as -currentQueryGeneration named it.
 */
- (void)cancelQueryIfStillRunning:(NSUInteger)generation
{
	[connectionCancellation requestCancellationOfGeneration:generation synchronously:![NSThread isMainThread]];
}


/**
 * Retrieve the time elapsed since the connection was established, in seconds.
 * This time is retrieved in a monotonically increasing fashion and is high
 * precision; it is used internally for query timing, and is reset on reconnections.
 * If no connection is currently active, returns -1.
 */
- (double)timeConnected
{
	if (initialConnectTime == 0) return -1;

	return _timeIntervalSinceMonotonicTime(initialConnectTime);
}

/**
 * Returns YES if the user chose to disconnect at the last "connection failure"
 * prompt, NO otherwise.  This can be used to alter behaviour in response to state
 * changes.
 */
- (BOOL)userTriggeredDisconnect
{
	return userTriggeredDisconnect;
}

/**
 * Returns true if the connected server runs MariaDB > 10.2, false Otherwise
 */
- (BOOL)isNotMariadb103
{
    // The version was recorded when the session was set up. The session's handle is not read here:
    // it is gone while a session closed after a stopped wait waits for the next query to replace it.
    NSString *version = [[self serverVersionString] lowercaseString];
    NSString *someRegexp = @"(.*)10(\\.[3-9]+[0-9]*(\\.[0-9]*))*-(mariadb)(.*)";
    NSPredicate *myTest = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", someRegexp];
    
    if ([myTest evaluateWithObject: version]){
        return false;
    }
    return true;
}

- (BOOL) isMariaDB
{
  // The version recorded when the session was set up; see -isNotMariadb103.
  NSString *version = [[self serverVersionString] lowercaseString];
  // See more: https://regex101.com/r/0QRlsG/1
  NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", @"(^.*)-[mariadb].*"];
  if ([predicate evaluateWithObject: version]){
    return true;
  }
  
  return false;
}

#pragma mark -
#pragma mark General connection utilities

+ (NSString *)findSocketPath
{
	NSFileManager *fileManager = [NSFileManager defaultManager];

	NSArray *possibleSocketLocations = @[
		@"/tmp/mysql.sock",                                     // Default
		@"/Applications/MAMP/tmp/mysql/mysql.sock",             // MAMP default location
		@"/Applications/xampp/xamppfiles/var/mysql/mysql.sock", // XAMPP default location
		@"/var/mysql/mysql.sock",                               // Mac OS X Server default
		@"/opt/local/var/run/mysqld/mysqld.sock",               // MacPorts MySQL
		@"/opt/local/var/run/mysql4/mysqld.sock",               // MacPorts MySQL 4
		@"/opt/local/var/run/mysql5/mysqld.sock",               // MacPorts MySQL 5
		@"/opt/local/var/run/mariadb-10.0/mysqld.sock",         // MacPorts MariaDB 10.0
		@"/opt/local/var/run/mariadb-10.1/mysqld.sock",         // MacPorts MariaDB 11.0
		@"/usr/local/zend/mysql/tmp/mysql.sock",                // Zend Server CE (see Issue #1251)
		@"/var/run/mysqld/mysqld.sock",                         // As used on Debian/Gentoo
		@"/var/tmp/mysql.sock",                                 // As used on FreeBSD
		@"/var/lib/mysql/mysql.sock",                           // As used by Fedora
		@"/opt/local/lib/mysql/mysql.sock"
	];

	for(NSString *path in possibleSocketLocations) {
		if([fileManager fileExistsAtPath:path]) return path;
	}

	return nil;
}

/**
 * Sets the session time zone, or the server's global one for an empty identifier, and reports
 * a failure to the delegate.
 *
 * @param timeZoneIdentifier The time zone to use, or nil/empty for the server default.
 */
- (void)updateTimeZoneIdentifier:(NSString *)timeZoneIdentifier {
    if ([timeZoneIdentifier isEqualToString:self.timeZoneIdentifier]) {
        return;
    }

    self.timeZoneIdentifier = nil;
    if (!timeZoneIdentifier || [timeZoneIdentifier isEqualToString:@""]) {
        [self queryString:[NSString stringWithFormat:@"SET time_zone = @@GLOBAL.time_zone"]];
    } else {
        [self queryString:[NSString stringWithFormat:@"SET time_zone = %@", [timeZoneIdentifier mySQLTickQuotedString]]];
        if ([self lastErrorMessage] == nil) {
            self.timeZoneIdentifier = timeZoneIdentifier;
        }
        else{
            NSMutableString *lastErrorMessage = [[NSMutableString alloc] init];
            [lastErrorMessage setString:[self lastErrorMessage]];
            SPLog(@"Failed to set time_zone. Error: %@", lastErrorMessage);
            self.timeZoneIdentifier = nil;
            if (delegate && [delegate respondsToSelector:@selector(queryGaveError:connection:)]) {
                [delegate queryGaveError:lastErrorMessage connection:self];
            }
            if ([delegate respondsToSelector:@selector(showErrorWithTitle:message:)]) {
                [lastErrorMessage appendString:NSLocalizedString(@"\n\ntime_zone will be set to SYSTEM.", @"\n\ntime_zone will be set to SYSTEM.")];
                [delegate showErrorWithTitle:NSLocalizedString(@"Error", @"error") message:lastErrorMessage];
            }
        }
    }
}

#pragma mark -
#pragma mark Cancellation host

/**
 * Keeps the next connection attempt short, because the user has said they will not wait.
 */
- (void)noteUserEndedWait
{
	userEndedPendingWork = YES;
	userEndedPendingWorkTime = _monotonicTime();
}

/**
 * Marks the query that holds the connection as cancelled.
 */
- (void)markRunningQueryCancelled
{
	lastQueryWasCancelled = YES;
}

/**
 * Asks the server to kill a query over a connection of its own.
 *
 * @param generation The query to kill.
 * @return Whether the server accepted the request.
 */
- (BOOL)killQueryOverSideConnectionForGeneration:(NSUInteger)generation
{
	return [self _killQueryOverSideConnectionForGeneration:generation];
}

/**
 * Whether the session last reported an open transaction.
 */
- (BOOL)sessionHasOpenTransaction
{
	return [valueEscaper sessionReportedOpenTransaction];
}

/**
 * Takes the connection, provided nothing else holds it.
 *
 * @return Whether the connection is now held.
 */
- (BOOL)holdConnectionIfFree
{
	return [self _tryLockConnection];
}

/**
 * Gives back a connection taken with -holdConnectionIfFree.
 */
- (void)releaseHeldConnection
{
	[self _unlockConnection];
}

/**
 * Records that the work on the connection was cancelled.
 */
- (void)recordWorkAsCancelled
{
	[self _recordWorkAsCancelled];
}

/**
 * Closes the session the connection holds, if it holds one. Only called while the connection is held.
 */
- (void)closeSessionIfConnected
{
	// A session with a transaction that was open before the stopped statement is kept: closing it
	// would roll that transaction back. One that was marked for replacement when the work was given
	// up on is not.
	if (state == SPMySQLConnected && mySQLConnection
	    && ![SAConnectionCancellation keepsSessionOfAbandonedWorkWithOpenTransaction:(mySQLConnection->server_status & SERVER_STATUS_IN_TRANS) != 0
	                                                            markedForReplacement:sessionMustBeReplacedBeforeUse]) {
		[self _closeSessionOfAbandonedQuery];
	}
}

@end

#pragma mark -
#pragma mark Private API

//http://alastairs-place.net/blog/2013/01/10/interesting-os-x-crash-report-tidbits/
/* CrashReporter info */
char *__crashreporter_info__ = NULL;
asm(".desc ___crashreporter_info__, 0x10");

@implementation SPMySQLConnection (PrivateAPI)

/**
 * Handle a connection using previously set parameters, returning success or failure.
 */
- (BOOL)_connect
{
    SPLog(@"_connect");

	// If a connection is already active in some form, throw an exception
	if (state != SPMySQLDisconnected && state != SPMySQLConnectionLostInBackground) {
		@synchronized (self) {
			double diff = _timeIntervalSinceMonotonicTime(initialConnectTime);
			asprintf(&__crashreporter_info__, "Attempted to connect a connection that is not disconnected (SPMySQLConnectionState=%d).\nIf state==2: Previous connection made %lfs ago from: %s", state, diff, [_debugLastConnectedEvent cStringUsingEncoding:NSUTF8StringEncoding]);
            SPLog(@"Attempted to connect a connection that is not disconnected (SPMySQLConnectionState=%d).\nIf state==2: Previous connection made %lfs ago from: %s", state, diff, [_debugLastConnectedEvent cStringUsingEncoding:NSUTF8StringEncoding]);
		}

		[NSException raise:NSInternalInconsistencyException format:@"Attempted to connect a connection that is not disconnected (SPMySQLConnectionState=%d).", state];
		return NO;
	}
	state = SPMySQLConnecting;

	if (userTriggeredDisconnect) {
		return NO;
	}

	// Lock the connection for safety
	[self _lockConnection];

	// Attempt the connection
	mySQLConnection = [self _makeRawMySQLConnectionWithEncoding:encoding isMasterConnection:YES];

	// If the connection failed, reset state and return
	if (!mySQLConnection) {
        SPLog(@"!mySQLConnection, unlock");

		[self _unlockConnection];
		state = SPMySQLDisconnected;
		return NO;
	}

	// Bound how long the kernel waits on a peer that has stopped answering entirely, so a
	// query sent onto a route that disappeared ends in an error rather than in a wait that
	// outlasts anyone's patience.
	[SAConnectionSocketTimeouts applyToSocket:mySQLConnection->net.fd];

	// If the connection was cancelled, clean up and don't continue
	if (userTriggeredDisconnect) {
		mysql_close(mySQLConnection);
		mySQLConnection = NULL;
		[self _unlockConnection];
		return NO;
	}

	// Successfully connected - record connected state and reset tracking variables
	state = SPMySQLConnected;
	// What the new session reports is recorded before the old one stops counting as being replaced,
	// so that no value is escaped for the old session in between.
	[valueEscaper recordSessionCharacterSet:[NSString stringWithUTF8String:mysql_character_set_name(mySQLConnection)]
	                     noBackslashEscapes:(mySQLConnection->server_status & SERVER_STATUS_NO_BACKSLASH_ESCAPES) != 0
	                        openTransaction:(mySQLConnection->server_status & SERVER_STATUS_IN_TRANS) != 0
	                            isHandshake:YES];
	sessionMustBeReplacedBeforeUse = NO;
	sessionWasClosedWithoutItsProxy = NO;

	@synchronized (self) {
		initialConnectTime = _monotonicTime();
		_debugLastConnectedEvent = [[NSString alloc] initWithFormat:@"thread=%@ stack=%@",[NSThread currentThread],[NSThread callStackSymbols]];
	}

	mysqlConnectionThreadId = mySQLConnection->thread_id;
	lastConnectionUsedTime = initialConnectTime;

	// the mysql_get_server_info() function
	//   * returns the version name that is part of the initial connection handshake.
	//   * Unless the connection failed, it will always return a non-null buffer containing at least a '\0'.
	//   * It will never affect the error variables (since it only returns a struct member)
	//
	// At that point (handshake) there is no charset and it's highly unlikely this will ever contain something other than ASCII,
	// but to be safe, we'll use the Latin1 encoding which won't bail on invalid chars.
	// Recorded under the same lock the version questions read it with: they can be asked on any
	// thread, while a reconnect sets up the next session.
	NSString *handshakeServerVersion = [[NSString alloc] initWithCString:mysql_get_server_info(mySQLConnection) encoding:NSISOLatin1StringEncoding];
	@synchronized (self) {
		serverVariableVersion = handshakeServerVersion;
	}
	// this one can actually change the error state, but only if the server version string is not set (ie. no connection)
	serverVersionNumber = mysql_get_server_version(mySQLConnection);

	// Update SSL state
	connectedWithSSL = (mysql_get_ssl_cipher(mySQLConnection))?YES:NO;
	if (useSSL && !connectedWithSSL) {
		if ([delegate respondsToSelector:@selector(connectionFellBackToNonSSL:)]) {
			[delegate connectionFellBackToNonSSL:self];
		}
	}

	// Reset keepalive variables
	lastKeepAliveTime = 0;
	keepAlivePingFailures = 0;

	// Clear the connection error record
	[self _updateLastErrorInfos];

	// Unlock the connection
	[self _unlockConnection];

	// Update connection variables to be in sync with the server state.  As this performs
	// a query, ensure the connection is still up afterwards (!)
	[self _updateConnectionVariables];
	if (state != SPMySQLConnected) return NO;

	// Now connection is established and verified, reset the counter
	reconnectionRetryAttempts = 0;

	// Update the maximum query size
	[self _updateMaxQuerySize];

	return YES;
}

/**
 * Make a connection using the class connection settings, returning a MySQL
 * connection object on success.
 */
- (MYSQL *)_makeRawMySQLConnectionWithEncoding:(NSString *)encodingName isMasterConnection:(BOOL)isMaster
{
	if ([[NSThread currentThread] isCancelled]) return NULL;

	// Set up the MySQL connection object
	MYSQL *theConnection = mysql_init(NULL);
	if (!theConnection) return NULL;

	// Calling mysql_init will have automatically installed per-thread variables if necessary,
	// so track their installation for removal and to avoid recreating again.
	[self _validateThreadSetup];

	// Disable automatic reconnection, as it's handled in-framework to preserve
	// options, encodings and connection state.
	bool falseMyBool = FALSE;
	mysql_options(theConnection, MYSQL_OPT_RECONNECT, &falseMyBool);
    
    // Set the connection protocol properly (needed so localhost can be used for TCP/IP)
    if (useSocket) {
        const uint proto = MYSQL_PROTOCOL_SOCKET;
        mysql_options(theConnection, MYSQL_OPT_PROTOCOL, &proto);
    } else {
        const uint proto = MYSQL_PROTOCOL_TCP;
        mysql_options(theConnection, MYSQL_OPT_PROTOCOL, &proto);
    }

	// Set the connection timeout; a check-triggered reconnect shortens it so the
	// user is asked quickly instead of waiting out a dead route.
	NSUInteger connectTimeout = connectTimeoutOverride > 0 ? connectTimeoutOverride : timeout;
	mysql_options(theConnection, MYSQL_OPT_CONNECT_TIMEOUT, (const void *)&connectTimeout);

	// A side connection only asks the server to kill a query, and does so while that query is
	// held still. It must not wait on a server that accepted it and then stopped answering; the
	// main connection keeps no such limit, as it would cut long queries short.
	if (!isMaster) {
		unsigned int answerTimeout = (unsigned int)[SAConnectionCheckBudget sideConnectionAnswerTimeout];
		mysql_options(theConnection, MYSQL_OPT_READ_TIMEOUT, (const void *)&answerTimeout);
		mysql_options(theConnection, MYSQL_OPT_WRITE_TIMEOUT, (const void *)&answerTimeout);
	}

	// Set the connection encoding
	NSStringEncoding connectEncodingNS = [SPMySQLConnection stringEncodingForMySQLCharset:[encodingName UTF8String]];
	mysql_options(theConnection, MYSQL_SET_CHARSET_NAME, [encodingName UTF8String]);
    
    // Some servers have issues when we try caching_sha2_password first; let's always try mysql_native_password first; ref: https://github.com/Sequel-Ace/Sequel-Ace/issues/141
    mysql_options(theConnection, MYSQL_DEFAULT_AUTH, [@"mysql_native_password" UTF8String]);

    // Point libmysqlclient at this framework's PlugIns directory for client-side auth plugins.
    // Without this the library falls back to the plugin path baked in at compile time - a
    // directory on the build machine that never exists on user systems - so any server auth
    // scheme requiring a client plugin (e.g. MariaDB ed25519) failed with a dlopen error
    // pointing at a meaningless path; ref: https://github.com/Sequel-Ace/Sequel-Ace/issues/1036
    NSString *pluginDirectory = [[NSBundle bundleForClass:[self class]] builtInPlugInsPath];
    if (pluginDirectory) {
        mysql_options(theConnection, MYSQL_PLUGIN_DIR, [pluginDirectory fileSystemRepresentation]);
    }

    // Allow using LOAD DATA LOCAL INFILE ...; ref: https://github.com/Sequel-Ace/Sequel-Ace/issues/245
    if(allowDataLocalInfile) {
        mysql_options(theConnection, MYSQL_OPT_LOCAL_INFILE, [@"On" UTF8String]);
    }
    
	// Allow using ENABLE CLEARTEXT PLUGIN; ref: https://github.com/Sequel-Ace/Sequel-Ace/issues/368
	if (enableClearTextPlugin) {
		mysql_options(theConnection, MYSQL_ENABLE_CLEARTEXT_PLUGIN, [@"On" UTF8String]);
	}

	if (requestServerPublicKey) {
		bool trueMyBool = TRUE;
		mysql_options(theConnection, MYSQL_OPT_GET_SERVER_PUBLIC_KEY, &trueMyBool);
	}
    
	// Set up the connection variables in the format MySQL needs, from the class-wide variables
	const char *theHost = NULL;
	const char *theUsername = "";
	const char *thePassword = NULL;
	const char *theSocket = NULL;

	if (host) theHost = [host UTF8String]; //mysql calls getaddrinfo on the hostname. Apples code uses -UTF8String in that situation.
    if (username) theUsername = [username cStringUsingEncoding:connectEncodingNS]; //during connect this is in MYSQL_SET_CHARSET_NAME encoding

	// If a password was supplied, use it; otherwise ask the delegate if appropriate.
	//
	// Note that password has no charset in mysql: If a user password is set to 'ü' on a latin1 connection
	// and you later try to connect on an UTF-8 terminal (or vice versa) it will fail. The MySQL (5.5) manual wrongly states that
	// MYSQL_SET_CHARSET_NAME has influence over that, but it does not and could not, since the password is hashed by the client
	// before transmitting it to the server and the (5.5) client has no charset support, effectively treating password as
	// a NUL-terminated byte array.
	// There is one exception, though: The "mysql_clear_password" auth plugin sends the password in plaintext and the server side
	// MAY choose to do a charset conversion as appropriate before handing it to whatever backend is used.
	// Since we don't know which auth plugin server and client will agree upon, we'll do as the manual says...
	if (password) {
		thePassword = [password cStringUsingEncoding:connectEncodingNS];
	} else if ([delegate respondsToSelector:@selector(keychainPasswordForConnection:)]) {
        thePassword = [[delegate keychainPasswordForConnection:self] cStringUsingEncoding:connectEncodingNS];
	}

	// If set to use a socket and a socket was supplied, use it; otherwise, search for a socket to use
	if (useSocket) {
		//default to user supplied path
		NSString *mySocketPath = socketPath;
		//if none was given, search in the default locations instead
		if (![mySocketPath length]) {
			mySocketPath = [SPMySQLConnection findSocketPath];
		}
		//get C string if we have a path (danger: method will throw on empty/nil string!)
		if([mySocketPath length]) {
			theSocket = [mySocketPath fileSystemRepresentation];
		}
	}

	// Apply SSL if appropriate
	if (useSSL) {
		const char *theSSLKeyFilePath = NULL;
		const char *theSSLCertificatePath = NULL;
		const char *theCACertificatePath = NULL;
		const char *theSSLCiphers = [[SPMySQLConnection _defaultSSLCipherListString] UTF8String];
		const char *theTLSCipherSuites = [[SPMySQLConnection _defaultTLSSuiteListString] UTF8String];

		if ([sslKeyFilePath length]) {
			theSSLKeyFilePath = [[sslKeyFilePath stringByExpandingTildeInPath] fileSystemRepresentation];
		}
		if ([sslCertificatePath length]) {
			theSSLCertificatePath = [[sslCertificatePath stringByExpandingTildeInPath] fileSystemRepresentation];
		}
		if ([sslCACertificatePath length]) {
			theCACertificatePath = [[sslCACertificatePath stringByExpandingTildeInPath] fileSystemRepresentation];
		}
		if ([sslCipherList length]) {
			theSSLCiphers = [sslCipherList UTF8String];
		}

		// Calling mysql_ssl_set() to libmysqlclient only means that connecting with SSL would be nice.
		// If the server doesn't support SSL though, it will *silently* fall back to plaintext and in the worst case even transmit
		// the password in cleartext.
		//
		// Setting MYSQL_OPT_SSL_MODE is required, to actually make it abort the connection if the server doesn't signal SSL support.
		//
		//   mysql 5.5.55+
		//   mysql 5.6.36+
		//   mysql 5.7.11+ (5.7.3 - 5.7.10 with a different name)
		//   mysql 8.0+
		mysql_ssl_set(theConnection, theSSLKeyFilePath, theSSLCertificatePath, theCACertificatePath, NULL, theSSLCiphers);
		if (mysql_options(theConnection, MYSQL_OPT_TLS_CIPHERSUITES, (const void *)theTLSCipherSuites)) {
			SPLog(@"Failed to set default TLS 1.3 cipher suites; continuing with libmysqlclient defaults.");
		}
		enum mysql_ssl_mode opt_ssl_mode = SSL_MODE_REQUIRED;
		if(mysql_options(theConnection, MYSQL_OPT_SSL_MODE, (void *)&opt_ssl_mode)) {
			if(isMaster) {
				[self _updateLastErrorMessage:@"libmysqlclient is missing support for MYSQL_OPT_SSL_MODE"];
				[self _updateLastSqlstate:@"HY000"];
				[self _updateLastErrorID:2026];
			}
			return NULL;
		}
    } else {
        enum mysql_ssl_mode opt_ssl_mode = SSL_MODE_PREFERRED;
        mysql_options(theConnection, MYSQL_OPT_SSL_MODE, (void *)&opt_ssl_mode);
    }

    // A failed attempt frees every option that was set on this handle unless the client asks
    // to keep them, and the retry below has to run on the same connection timeout as the
    // attempt before it rather than on the system default.
    unsigned long connectClientFlags = [self clientFlags] | CLIENT_REMEMBER_OPTIONS;

    MYSQL *connectionStatus = mysql_real_connect(theConnection, theHost, theUsername, thePassword, NULL, (unsigned int)port, theSocket, connectClientFlags);

    //If we attempted SSL and failed, try one more time non-ssl if the user isn't requiring SSL.
    // A host that never answered is not worth a second connection timeout: it fails the same
    // way without TLS, and the wait happens while the interface stands still.
    if(!useSSL && theConnection != connectionStatus && [SAConnectionRetryPolicy shouldRetryWithoutTLSAfterErrorID:mysql_errno(theConnection)]) {
        enum mysql_ssl_mode opt_ssl_mode = SSL_MODE_DISABLED;
        mysql_options(theConnection, MYSQL_OPT_SSL_MODE, (void *)&opt_ssl_mode);
        connectionStatus = mysql_real_connect(theConnection, theHost, theUsername, thePassword, NULL, (unsigned int)port, theSocket, connectClientFlags);
    }

	// If the connection failed, return NULL
	if (theConnection != connectionStatus) {
		// If the connection is the master connection, record the error state
		if (isMaster) {
			// <TODO>
			// this is tricky: mysql_error() is supposed to return data encoded in character_set_results (in mysql 5.5+),
			// yet the whole API treats it as if it were a plain C string.
			// So if the charset is e.g. utf16 the mysql server will itself fall over that and return an empty error message
			// (5.5, 5.7: the message is really missing at the network layer).
			//   (Side Note: There is a workaround for server generated error messages: "show warnings" will also include errors
			//               and because it uses a regular results table it can contain the actual error message)
			//
			// Before 5.5 things are much worse, because the charset of the message depends on the language of the error messages
			// (which can be changed at runtime per session (or at launch time in 4.1)) plus all arguments in the template string
			// will retain their original encoding.
			// So if you connect with utf8 to a server with russian locale the error message will be in koi8r and contain the name of
			// an erroneus value in utf8...
			//
			// On the other hand mysql_error() may also return errors generated by the client locally.
			// The client has no charset support and simply assumes the local charset is ASCII-compatible.
			// The english messages are compiled into the client (see libmysql/errmsg.c and include/errmsg.h).
			// We could use a little trick, though: client errors are in the exclusive range 2000 to 2999 (CR_MIN_ERROR/CR_MAX_ERROR)
			// and all their string arguments are either hostnames or file system paths, which on OS X use UTF-8.
			[self _updateLastErrorMessage:[self _stringForCString:mysql_error(theConnection)]];
			// </TODO>
			[self _updateLastErrorID:mysql_errno(theConnection)];
			// sqlstate is always an ASCII string, regardless of charset (but use latin1 anyway as that is less picky about invalid bytes)
			[self _updateLastSqlstate:_stringForCStringWithEncoding(mysql_sqlstate(theConnection),NSISOLatin1StringEncoding)];
		}

		// The handle keeps its options and its own allocations after a failed attempt, so it
		// is closed here rather than left behind.
		mysql_close(theConnection);

		return NULL;
	}

	// Ensure automatic reconnection is disabled for older versions
	theConnection->reconnect = 0;

	// Successful connection - return the handle
	return theConnection;
}

/**
 * If the current reconnect was cancelled by its thread or an explicit
 * disconnect while holding the connection lock, cancel any preserved proxy
 * work, restore notifications, and unlock.
 */
- (BOOL)_abortCancelledReconnectWhileLocked
{
	BOOL threadCancelled = [[NSThread currentThread] isCancelled];
	if (![_proxyReconnectCoordinator shouldAbortReconnectWithThreadCancelled:threadCancelled
	                                              userTriggeredDisconnect:userTriggeredDisconnect]) return NO;

	// The attempt ends here, and the short check budgets end with it.
	connectTimeoutOverride = 0;
	reconnectingAfterFailedCheck = NO;
	userEndedPendingWork = NO;

	[self _recoverFromCancelledReconnectMayDisconnect:NO];

	SPLog(@"reconnect cancelled by thread or explicit disconnect; cleaning up proxy attempt");
	[self _unlockConnection];
	if (proxy) {
		// Keep proxy callbacks suppressed until the pending attempt is cancelled,
		// then restore the state snapshot and normal notification handling.
		[_proxyReconnectCoordinator disconnectProxy:proxy preservingReconnect:NO];
		previousProxyState = [proxy state];
	}
	proxyStateChangeNotificationsIgnored = NO;
	reconnectingThread = NULL;
	return YES;
}

/**
 * Perform a reconnection task, either once-only or looping as requested.  If looping is
 * permitted and this method fails, it will ask how to proceed and loop depending on
 * the status, not returning control until either a connection has been established or
 * the connection and document have been closed.
 * Runs its own autorelease pool as sometimes called in a thread following proxy changes
 * (where the return code doesn't matter).
 *
 * WARNING: This method may exit early returning NO if the current thread is cancelled!
 *          You MUST check the isCancelled flag before using the result!
 */
- (BOOL)_reconnectAllowingRetries:(BOOL)canRetry
{

    SPLog(@"_reconnectAllowingRetries");
	if (userTriggeredDisconnect) return NO;
	BOOL reconnectSucceeded = NO;
    NSString *timeZoneIdentifierToRestore = nil;

	@autoreleasepool {
		// Check whether a reconnection attempt is already being made - if so, wait
		// and return the status of that reconnection attempt.  This improves threaded
		// use of the connection by preventing reconnect races.
		if (reconnectingThread && !pthread_equal(reconnectingThread, pthread_self())) {

			// Loop in a panel runloop mode until the reconnection has processed; if an iteration
			// takes less than the requested 0.1s, sleep instead.
			while (reconnectingThread) {
                SPLog(@"a reconnection attempt is already being made, waiting");

				uint64_t loopIterationStart_t = _monotonicTime();

				[[NSRunLoop currentRunLoop] runMode:NSModalPanelRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
				if (_timeIntervalSinceMonotonicTime(loopIterationStart_t) < 0.1) {
					usleep(100000 - (useconds_t)(1000000 * _timeIntervalSinceMonotonicTime(loopIterationStart_t)));
				}
			}

			// Continue only if the reconnection being waited on was a background attempt
			if (!(state == SPMySQLConnectionLostInBackground && canRetry)) {
				return (state == SPMySQLConnected);
			}
		}

		if ([[NSThread currentThread] isCancelled]) {
            SPLog(@"NSThread currentThread] isCancelled, returning");

			return NO;
		}

		reconnectingThread = pthread_self();

		// Store certain details about the connection, so that if the reconnection is successful
		// they can be restored.  This has to be treated separately from _restoreConnectionDetails
		// as a full connection reinitialises certain values from the server.
		if (!encodingToRestore) {
			encodingToRestore = [encoding copy];
			encodingUsesLatin1TransportToRestore = encodingUsesLatin1Transport;
			databaseToRestore = [database copy];
		}
        // Keep this per-attempt capture aligned with self.timeZoneIdentifier:
        // reconnect retries re-capture it from the surviving property value, so
        // revisit this if disconnect teardown ever clears timeZoneIdentifier.
        if (!timeZoneIdentifierToRestore && [self.timeZoneIdentifier length]) {
            timeZoneIdentifierToRestore = [self.timeZoneIdentifier copy];
        }

		// If there is a connection proxy, temporarily disassociate the state change action
		if (proxy) proxyStateChangeNotificationsIgnored = YES;

		// Close the connection if it's active
		[self _disconnectPreservingProxyReconnect:YES];

		// Lock the connection while waiting for network and proxy
		[self _lockConnection];

		// The short budget belongs to the attempt made right after the user stopped waiting. One
		// that comes later - once the network is back, say - is an ordinary attempt.
		if (userEndedPendingWork && ![SAConnectionCheckBudget attemptIsShortenedStartingSecondsAfterEndedWait:_timeIntervalSinceMonotonicTime(userEndedPendingWorkTime)]) {
			userEndedPendingWork = NO;
		}

		// What this attempt may spend, on every step - the proxy's included. The decision is
		// SAConnectionCheckBudget's.
		SAConnectionAttemptBudget *attemptBudget = [SAConnectionCheckBudget attemptBudgetForConfiguredTimeout:timeout
		                                                                                         userEndedWait:userEndedPendingWork
		                                                                                      afterFailedCheck:reconnectingAfterFailedCheck];
		NSUInteger attemptConnectTimeout = [attemptBudget connectTimeout];

		// If no network is present, wait for a short time for one to become available
		[self _waitForNetworkConnectionWithTimeout:[attemptBudget networkWait]];

		if ([self _abortCancelledReconnectWhileLocked]) return NO;

		// If there is a proxy, attempt to reconnect it in blocking fashion
		if (proxy) {

            SPLog(@"we have a proxy");

			uint64_t loopIterationStart_t, proxyWaitStart_t;

			// A tunnel left running when only the session was closed is used as it is.
			BOOL reuseProxy = [_proxyReconnectCoordinator reusesConnectedProxyAfterClosingSessionOnly:sessionWasClosedWithoutItsProxy
			                                                                          proxyConnected:([proxy state] == SPMySQLProxyConnected)];

			// If the proxy is not yet idle after requesting a disconnect, wait for a short time
			// to allow it to disconnect.
			if (!reuseProxy && [proxy state] != SPMySQLProxyIdle) {

                SPLog(@"proxy not idle, waiting");

				proxyWaitStart_t = _monotonicTime();
				while ([proxy state] != SPMySQLProxyIdle) {
					if ([self _abortCancelledReconnectWhileLocked]) return NO;
					loopIterationStart_t = _monotonicTime();

					// If the connection timeout has passed, break out of the loop
					if (_timeIntervalSinceMonotonicTime(proxyWaitStart_t) > [_proxyReconnectCoordinator idleWaitLimitForConnectTimeout:attemptConnectTimeout]) break;

					// Allow events to process for 0.25s, sleeping to completion on early return
					[[NSRunLoop currentRunLoop] runMode:NSModalPanelRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
					if (_timeIntervalSinceMonotonicTime(loopIterationStart_t) < 0.25) {
						usleep(250000 - (useconds_t)(1000000 * _timeIntervalSinceMonotonicTime(loopIterationStart_t)));
					}
				}
			}
			if ([self _abortCancelledReconnectWhileLocked]) return NO;

			// Request that the proxy re-establishes its connection
            SPLog(@"Request that the proxy re-establishes its connection, calling proxy connect");

			if (!reuseProxy) [proxy connect];

			// Wait while the proxy connects
			SAProxyConnectWait *connectWait = [[SAProxyConnectWait alloc] initWithConnectTimeout:attemptConnectTimeout];
			proxyWaitStart_t = _monotonicTime();
			while (1) {
				if ([self _abortCancelledReconnectWhileLocked]) return NO;
				loopIterationStart_t = _monotonicTime();
				BOOL connectionAttemptPending = [_proxyReconnectCoordinator connectionAttemptPendingForProxy:proxy];

                SPLog(@"Wait while the proxy connects");

				// If the proxy has connected, record the new local port and break out of the loop
				if ([proxy state] == SPMySQLProxyConnected) {
                    SPLog(@"SPMySQLProxyConnected. port: %lu",(unsigned long)[proxy localPort] );

					port = [proxy localPort];
					break;
				}

				// If the proxy connection attempt has run out of time, or ended without connecting, break out of the loop.
				if (![connectWait shouldKeepWaitingAfter:_timeIntervalSinceMonotonicTime(proxyWaitStart_t)
				                               proxyState:[proxy state]
				                           attemptPending:connectionAttemptPending]) {
                    SPLog(@"proxy connection attempt time has exceeded the timeout, break of of the loop, calling proxy disconnect");
					[_proxyReconnectCoordinator disconnectProxy:proxy preservingReconnect:YES];
					break;
				}

				// Process events for a short time, allowing dialogs to be shown but waiting for
				// the proxy. Capture how long this interface action took, standardising the
				// overall time.
				[[NSRunLoop currentRunLoop] runMode:NSModalPanelRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
				if (_timeIntervalSinceMonotonicTime(loopIterationStart_t) < 0.25) {
					usleep((useconds_t)(250000 - (1000000 * _timeIntervalSinceMonotonicTime(loopIterationStart_t))));
				}

				// Extend the connection timeout by interface time and by time that
				// the proxy intentionally spends waiting to start the requested attempt.
				if ([_proxyReconnectCoordinator
						shouldExcludeWaitTimeForAuthentication:([proxy state] == SPMySQLProxyWaitingForAuth)
						connectionAttemptPending:connectionAttemptPending]) {
					proxyWaitStart_t += _monotonicTime() - loopIterationStart_t;
				}
			}
			if ([self _abortCancelledReconnectWhileLocked]) return NO;

			// Having in theory performed the proxy connect, update state
			previousProxyState = [proxy state];
			proxyStateChangeNotificationsIgnored = NO;
		}

		// Unlock the connection
		[self _unlockConnection];

		// If not using a proxy, or if the proxy successfully connected, trigger a connection
		if (![[NSThread currentThread] isCancelled] && (!proxy || [proxy state] == SPMySQLProxyConnected)) {
			// A host that is no longer routed swallows the connection attempt, so
			// the attempt made before the user is asked runs on a short budget.
			// Anything the user then triggers uses the full connection timeout.
			if ([attemptBudget overridesConfiguredTimeout]) {
				connectTimeoutOverride = attemptConnectTimeout;
			}
			[self _connect];
			connectTimeoutOverride = 0;
			reconnectingAfterFailedCheck = NO;
			userEndedPendingWork = NO;
			[self _recoverFromCancelledReconnectMayDisconnect:YES];
		} else if ([[NSThread currentThread] isCancelled] && proxy) {
			[_proxyReconnectCoordinator disconnectProxy:proxy preservingReconnect:NO];
			connectTimeoutOverride = 0;
			reconnectingAfterFailedCheck = NO;
			userEndedPendingWork = NO;
			[self _recoverFromCancelledReconnectMayDisconnect:NO];
		} else {
			// The proxy never came up: no connection was attempted, and the short
			// budgets must not outlive this attempt either.
			connectTimeoutOverride = 0;
			reconnectingAfterFailedCheck = NO;
			userEndedPendingWork = NO;
		}

		// If the reconnection succeeded, restore the connection state as appropriate
		if (state == SPMySQLConnected && ![[NSThread currentThread] isCancelled]) {
            [self _restoreSessionStateAfterReconnectWithDatabase:databaseToRestore
                                                        encoding:encodingToRestore
                                    encodingUsesLatin1Transport:encodingUsesLatin1TransportToRestore
                                               timeZoneIdentifier:timeZoneIdentifierToRestore];

            // The user can stop waiting while the session is being restored, and the restoring
            // queries then do not run. A half-restored session is dropped like one that came up
            // too late, and the values to restore stay for the next attempt.
            if ([[NSThread currentThread] isCancelled]) {

                // Restoring clears the recorded time zone before setting it again, and that
                // second step did not run. The next attempt takes its snapshot from the record.
                if (![self.timeZoneIdentifier length] && [timeZoneIdentifierToRestore length]) {
                    self.timeZoneIdentifier = timeZoneIdentifierToRestore;
                }
                [self _recoverFromCancelledReconnectMayDisconnect:YES];
            } else {
                reconnectSucceeded = YES;

                // When the connection is restored successfully, reset the relevant variables to prepare for the next time
                databaseToRestore = nil;
                encodingToRestore = nil;
                encodingUsesLatin1TransportToRestore = NO;
            }
		}
			// If the connection failed and the connection is permitted to retry,
			// then retry the reconnection.
		else if (canRetry && ![[NSThread currentThread] isCancelled]) {

			// Default to attempting another reconnect
			SPMySQLConnectionLostDecision connectionLostDecision = SPMySQLConnectionLostReconnect;

			// If the delegate supports the decision process, ask it how to proceed
			if (delegateSupportsConnectionLost) {
				connectionLostDecision = [self _delegateDecisionForLostConnection];
			}
				// Otherwise default to reconnect, but only a set number of times to prevent a runaway loop
			else {
				if (reconnectionRetryAttempts < 5) {
					connectionLostDecision = SPMySQLConnectionLostReconnect;
				} else {
					connectionLostDecision = SPMySQLConnectionLostDisconnect;
				}
				reconnectionRetryAttempts++;
			}

			switch (connectionLostDecision) {
				case SPMySQLConnectionLostDisconnect:
					[self _updateLastErrorMessage:NSLocalizedString(@"User triggered disconnection", @"User triggered disconnection")];
					userTriggeredDisconnect = YES;
					break;

					// By default attempt a reconnect
				default:
					reconnectingThread = NULL;
                    SPLog(@"_reconnectAllowingRetries By default attempt a reconnect");
					reconnectSucceeded = [self _reconnectAllowingRetries:YES];
			}
		}
	}

	reconnectingThread = NULL;
	return reconnectSucceeded;
}

/**
 * Trigger a single reconnection attempt after losing network in the background,
 * setting the state appropriately for connection on next use if this fails.
 */
- (BOOL)_reconnectAfterBackgroundConnectionLoss
{
	if (![self _reconnectAllowingRetries:NO]) {
		state = SPMySQLConnectionLostInBackground;
	}

	return (state == SPMySQLConnected);
}


/**
 * Applies what becomes of a connection whose reconnect ended while its thread was cancelled.
 * The decision is SAConnectionCancellation's; this only carries it out.
 *
 * @param mayDisconnect Whether the caller is in a position to close a connection that came up.
 */
- (void)_recoverFromCancelledReconnectMayDisconnect:(BOOL)mayDisconnect
{
	SAConnectionRecoveryAction action = [SAConnectionCancellation recoveryAfterCancelledReconnectWithThreadCancelled:[[NSThread currentThread] isCancelled]
	                                                                                               userDisconnected:userTriggeredDisconnect
	                                                                                                    isConnected:(state == SPMySQLConnected)
	                                                                                                 isDisconnected:(state == SPMySQLDisconnected)
	                                                                                                  mayDisconnect:mayDisconnect];
	switch (action) {
		case SAConnectionRecoveryActionDiscardAndMarkLost:
			[self _disconnectPreservingProxyReconnect:YES];
			state = SPMySQLConnectionLostInBackground;
			break;
		case SAConnectionRecoveryActionMarkLost:
			state = SPMySQLConnectionLostInBackground;
			break;
		case SAConnectionRecoveryActionNone:
			break;
	}
}

/**
 * Whether connection work would actually move to another thread if it were handed over.
 *
 * Off the main thread there is nothing to protect, and without a delegate there is nothing that
 * could show the wait or end it; the work then runs where it was asked for. Callers that hand
 * their work over have to ask first, because work that runs where it was asked for would
 * otherwise hand itself over again, and again.
 *
 * @return Whether handing work over would move it off the main thread.
 */
- (BOOL)_workShouldRunOffMainThread
{
	return [NSThread isMainThread] && delegateSupportsConnectionCheckProgress;
}

/**
 * Runs connection work that may have to wait for a server, without freezing the interface.
 *
 * Away from the main thread the work runs where it was asked for. On the main thread it is
 * handed to the connection's work coordinator, which runs it on a thread of its own; the
 * delegate is asked to do the waiting from there, so the window keeps answering and the user
 * can stop waiting.
 *
 * @param work The work to run. It must not expect to be on the main thread.
 * @return What the work returned, or nil if the waiting ended before the work did.
 */
- (id)_runWorkKeepingInterfaceAlive:(id (^)(void))work
{
	if (![self _workShouldRunOffMainThread]) {
		return work();
	}

	if (!connectionWorkCoordinator) {
		connectionWorkCoordinator = [[SAConnectionWorkCoordinator alloc] init];
	}

	// Whatever was abandoned before, this is the work the caller will ask about next.
	lastWorkWasAbandoned = NO;

	SAConnectionWorkOutcome *outcome = [connectionWorkCoordinator runWork:work
	                                                       operationStamp:^NSUInteger{
		return self->queryGeneration;
	}
	                                                             whenSlow:^(BOOL (^workHasFinished)(void)) {
		self->connectionWorkWaitDepth++;
		[self->delegate connection:self waitForConnectionWorkUntilFinished:workHasFinished];
		self->connectionWorkWaitDepth--;
	} whenAbandonedWorkFinishes:^(NSUInteger abandonedAtGeneration) {
		[self->connectionCancellation settleAbandonedWorkFromGeneration:abandonedAtGeneration];
	}];

	// A streaming result keeps the connection until it has been read, and it is read here, on the
	// thread that asked for it - which therefore holds the connection now, not the worker. A result
	// store downloads on a thread of its own and gives the connection back there.
	if ([outcome finished] && [[outcome result] isKindOfClass:[SPMySQLStreamingResult class]]
	    && ![[outcome result] isKindOfClass:[SPMySQLStreamingResultStore class]]) {
		[inFlightQuery noteConnectionHeldByCurrentThread:YES];
	}

	// Work the user stopped waiting for keeps running until the server or a timeout answers it.
	// The caller is told the same thing a cancelled query tells it, because that is what this
	// is: callers that judge by the error state rather than by the result see it too.
	if (![outcome finished]) {
		[self _recordWorkAsCancelled];
		lastWorkWasAbandoned = YES;

		// The session that work runs in is on its way out: the work closes it once it finishes,
		// and may have changed it before. Nothing else uses it any more - a value escaped meanwhile
		// is escaped for the session that replaces it. A session with an open transaction is kept
		// instead, and only the stopped statement ends.
		if (![SAConnectionCancellation keepsSessionOfAbandonedWorkWithOpenTransaction:[valueEscaper sessionReportedOpenTransaction]
		                                                           markedForReplacement:NO]) {
			sessionMustBeReplacedBeforeUse = YES;
		}

		return nil;
	}

	return [outcome result];
}


/**
 * Records that work on this connection was cancelled, in the same way a cancelled query is
 * recorded, so that everything which asks the connection what happened gets the same answer.
 */
- (void)_recordWorkAsCancelled
{
	lastQueryWasCancelled = YES;
	[self _updateLastErrorMessage:NSLocalizedString(@"Query cancelled.", @"Query cancelled error")];
	[self _updateLastErrorID:1317];
	[self _updateLastSqlstate:@"70100"];
}

/**
 * Runs connection work whose answer is a plain yes or no. See -_runWorkKeepingInterfaceAlive:.
 *
 * @param work The work to run.
 * @return What the work returned, or NO if the user stopped waiting before it finished.
 */
- (BOOL)_runConnectionWorkKeepingInterfaceAlive:(BOOL (^)(void))work
{
	NSNumber *result = [self _runWorkKeepingInterfaceAlive:^id{
		return @(work());
	}];

	return [result boolValue];
}

/**
 * Asks a recently used connection's socket whether its peer is still there, without
 * sending anything over it. A query that goes out on a connection whose route has
 * disappeared blocks the thread that runs it, so a socket that already reports the
 * loss is worth the connection check the grace period would otherwise skip.
 *
 * @param idleTime Seconds since the connection last carried traffic.
 * @return Whether the connection should be verified despite its recent use.
 */
- (BOOL)_shouldVerifyRecentlyUsedConnectionIdleFor:(double)idleTime
{
	if (state != SPMySQLConnected || !mySQLConnection) return NO;

	// Only look while nothing else holds the connection: an active query is traffic
	// of its own, and the thread running it owns the connection structure.
	if (![self _tryLockConnection]) return NO;

	BOOL shouldVerify = NO;
	if (mySQLConnection && !mySQLConnection->net.reading_or_writing && mySQLConnection->net.vio) {
		shouldVerify = [SAConnectionLivenessProbe shouldVerifyConnectionIdleFor:idleTime socket:mySQLConnection->net.fd];
	}

	[self _unlockConnection];

	return shouldVerify;
}

/**
 * Loop while a connection isn't available; allows blocking while the network is disconnected
 * or still connecting (eg Airport still coming up after sleep).
 */
- (BOOL)_waitForNetworkConnectionWithTimeout:(double)timeoutSeconds
{
	NSString *probeHost = [SPMySQLConnection _reachabilityProbeHostForHost:host useSocket:useSocket hasProxy:(proxy != nil)];
	if (![probeHost length]) return YES;

    SPLog(@"_waitForNetworkConnectionWithTimeout: %f probeHost: %@", timeoutSeconds, probeHost);
	// This is only a lightweight route check for direct TCP reconnects; it must not block
	// socket or proxy reconnects on unrelated external hosts.
    SCNetworkReachabilityRef reachabilityTarget = SCNetworkReachabilityCreateWithName(NULL, [probeHost UTF8String]);
	if (!reachabilityTarget) return YES;

	BOOL hostReachable;
	// In a loop until success or the timeout, test reachability
	uint64_t loopStart_t = _monotonicTime();
	while (1) {
		SCNetworkReachabilityFlags reachabilityStatus;

		// Check reachability
		Boolean flagsValid = SCNetworkReachabilityGetFlags(reachabilityTarget, &reachabilityStatus);

		hostReachable = flagsValid ? YES : NO;

		// Ensure that the network is reachable
		if (hostReachable && !(reachabilityStatus & kSCNetworkReachabilityFlagsReachable)) hostReachable = NO;

		// Ensure that Airport is up/connected if present
		if (hostReachable && (reachabilityStatus & kSCNetworkReachabilityFlagsConnectionRequired)) hostReachable = NO;

		// If the host *is* reachable, return success
		if (hostReachable) break;

		// If the timeout has been exceeded, break out of the loop
		if (_timeIntervalSinceMonotonicTime(loopStart_t) >= timeoutSeconds) {
            SPLog(@"Network connection timeout exceeded");
            break;
        }

		// Sleep before the next loop iteration - increase sleep time to reduce CPU usage
		usleep(500000); // Sleep for 0.5 seconds instead of 0.25
	}

	CFRelease(reachabilityTarget);

    SPLog(@"return hostReachable: %d", hostReachable);

	return hostReachable;
}

/**
 * Perform a disconnect of any active connections, cleaning up state to match.
 */
- (void)_disconnect
{
	[self _disconnectPreservingProxyReconnect:NO];
}

- (void)_disconnectPreservingProxyReconnect:(BOOL)preserveProxyReconnect
{
    SPLog(@"_disconnect");

	// If state is connection lost, set state directly to disconnected.
	if (state == SPMySQLConnectionLostInBackground) {
		state = SPMySQLDisconnected;
	}

	// Only continue if a connection is active
	if (state != SPMySQLConnected && state != SPMySQLConnecting) {
		// An explicit disconnect must still reach the proxy so it can cancel an
		// SSH attempt queued behind cleanup. Internal reconnect teardown keeps
		// the existing inactive-state behavior and preserves that queued attempt.
		if (!preserveProxyReconnect && proxy) {
			[_proxyReconnectCoordinator disconnectProxy:proxy preservingReconnect:NO];
		}
		return;
	}

	// If a query is active, cancel it - without recording a request to stop it: a retry that is
	// reconnecting would otherwise find that request and stop, although nobody asked it to.
	[self _cancelCurrentQueryRecordingRequest:NO];

	state = SPMySQLDisconnecting;

	// Allow any pings or cancelled queries  to complete, inside a time limit of ten seconds
	uint64_t disconnectStartTime_t = _monotonicTime();
	while (![self _tryLockConnection]) {
		usleep(100000);
		if (_timeIntervalSinceMonotonicTime(disconnectStartTime_t) > 10) {
			NSLog(@"%s: Could not acquire connection lock within time limit (10s). Forcing unlock!",__PRETTY_FUNCTION__);
			break;
		}
	}

	[self _unlockConnection];
	[self _cancelKeepAlives];
	[self _lockConnection];
	// Close the underlying MySQL connection if it still appears to be active, and not reading
	// or writing.  While this may result in a leak of the MySQL object, it prevents crashes
	// due to attempts to close a blocked/stuck connection.
	if (mySQLConnection && !mySQLConnection->net.reading_or_writing && mySQLConnection->net.vio && mySQLConnection->net.buff) {
        SPLog(@"calling mysql_close(mySQLConnection)");

		mysql_close(mySQLConnection);
	}
	mySQLConnection = NULL;
	serverVersionNumber = 0;
	state = SPMySQLDisconnected;
	[self _unlockConnection];

	// If using a connection proxy, disconnect that too
	if (proxy) {
		[_proxyReconnectCoordinator disconnectProxy:proxy preservingReconnect:preserveProxyReconnect];
	}
}

/**
 * Update connection variables from the server, collecting state and ensuring
 * settings like encoding are in sync.
 */
- (void)_updateConnectionVariables
{
	if (state != SPMySQLConnected && state != SPMySQLConnecting) return;

	// Retrieve all variables from the server in a single query
	SPMySQLResult *theResult = [self queryString:@"SHOW VARIABLES"];
	if (![theResult numberOfRows]) return;

	// SHOW VARIABLES can return binary results on certain MySQL 4 versions; ensure string output
	[theResult setReturnDataAsStrings:YES];

	// Convert the result set into a variables dictionary
	[theResult setDefaultRowReturnType:SPMySQLResultRowAsArray];
	NSMutableDictionary *variables = [NSMutableDictionary new];
	for (NSArray *variableRow in theResult) {
		[variables SPsafeSetObject:[variableRow SPsafeObjectAtIndex:1] forKey:[variableRow firstObject]];
	}

	// Get the connection encoding.  Although a specific encoding may have been requested on
	// connection, it may be overridden by init_connect commands or connection state changes.
	// Default to latin1 for older server versions.
	NSString *retrievedEncoding = @"latin1";
	// character_set_results is the charset the strings received from the server will be in
	if ([variables objectForKey:@"character_set_results"]) {
		retrievedEncoding = [variables objectForKey:@"character_set_results"];
	}
	// not used in 4.1+ (?)
	else if ([variables objectForKey:@"character_set"]) {
		retrievedEncoding = [variables objectForKey:@"character_set"];
	}
	// character_set_client is the charset the server expects strings transmitted by us to be in
	else if ([variables objectForKey:@"character_set_client"]) {
		retrievedEncoding = [variables objectForKey:@"character_set_client"]; // fallback for sphinxql
	}
	// character_set_connection is used internally by the server for comparisons.
	// String literals (without a cast) will always be converted from character_set_client to character_set_connection first.
	// As an example:
	//   * Use a client with "SET NAMES utf8"
	//   * Do a "set @@session.character_set_connection = 'latin1';"
	//   * Finally try a "SELECT '犬';" (also try "select _utf8'犬';" for completeness)
	//   * The result will just show a "?"
	// So even though we told the server that the client uses utf8 and the results
	// should be encoded in utf8, too, the character got lost.
	// This happened because the server did a roundtrip of utf8 -> latin1 -> utf8.

	// Update instance variables
	encoding = [[NSString alloc] initWithString:retrievedEncoding];
	stringEncoding = [SPMySQLConnection stringEncodingForMySQLCharset:[encoding cStringUsingEncoding:stringEncoding]];
	encodingUsesLatin1Transport = NO;

	// Check the interactive timeout - if it's below five minutes, increase it to ten
	// to improve timeout/keepalive behaviour.  Note that wait_timeout also has be
	// increased; current versions effectively populate the wait timeout from the
	// interactive_timeout for interactive clients, but don't pick up changes.
	if ([variables objectForKey:@"interactive_timeout"]) {
		if ([[variables objectForKey:@"interactive_timeout"] integerValue] < 300) {
			[self queryString:@"SET interactive_timeout=600"];
			[self queryString:@"SET wait_timeout=600"];
		}
	}

    // Check the information_schema_stats_expiry timeout - if it's not zero, set it to 0
    // Otherwise, stats page will lag behind reality
    // https://github.com/Sequel-Ace/Sequel-Ace/issues/1206
    // ProxySQL doesn't track this variable, so the SET pins the connection to its current
    // hostgroup and a later SELECT that should route elsewhere fails with "locked to
    // hostgroup". Skip it on ProxySQL; the only cost there is a stats page that can lag.
    // https://github.com/Sequel-Ace/Sequel-Ace/issues/2006
    if ([variables objectForKey:@"information_schema_stats_expiry"]) {
        if ([[variables objectForKey:@"information_schema_stats_expiry"] integerValue] != 0 && ![self _serverIsProxySQL]) {
            [self queryString:@"SET information_schema_stats_expiry=0"];
        }
    }
}

/**
 * Returns whether the active connection is served by ProxySQL rather than MySQL or MariaDB directly.
 */
- (BOOL)_serverIsProxySQL
{
	if (state != SPMySQLConnected && state != SPMySQLConnecting) return NO;

	// ProxySQL answers this exact lowercase query itself with "(ProxySQL)", whatever version it
	// reports in the handshake. Uppercase keywords or SHOW VARIABLES are forwarded to a backend,
	// so the query has to match byte for byte to read ProxySQL's own version_comment.
	SPMySQLResult *theResult = [self queryString:@"select @@version_comment limit 1"];
	if (![theResult numberOfRows]) return NO;

	[theResult setReturnDataAsStrings:YES];
	NSString *versionComment = [[theResult getRowAsArray] firstObject];

	return [versionComment isKindOfClass:[NSString class]] && [versionComment rangeOfString:@"ProxySQL"].location != NSNotFound;
}

/**
 * Restore the connection encoding details as necessary based on previously set
 * details.
 */
- (void)_restoreConnectionVariables
{
	mysqlConnectionThreadId = mySQLConnection->thread_id;
	initialConnectTime = _monotonicTime();

	[self selectDatabase:database];

	[self setEncoding:encoding];
	[self setEncodingUsesLatin1Transport:encodingUsesLatin1Transport];
}

- (void)_restoreSessionStateAfterReconnectWithDatabase:(NSString *)databaseName
                                              encoding:(NSString *)encodingName
                      encodingUsesLatin1Transport:(BOOL)useLatin1Transport
                                 timeZoneIdentifier:(NSString *)timeZoneIdentifier
{
    if (databaseName) {
        [self selectDatabase:databaseName];
    }

    if (encodingName) {
        [self setEncoding:encodingName];
        [self setEncodingUsesLatin1Transport:useLatin1Transport];
    }

    if ([timeZoneIdentifier length]) {
        // Clear the cached timeZoneIdentifier so updateTimeZoneIdentifier:
        // bypasses its equality guard and re-runs SET time_zone after reconnect.
        self.timeZoneIdentifier = nil;
        [self updateTimeZoneIdentifier:timeZoneIdentifier];
    }
}

/**
 * Ensure that the thread this method is called on has been registered for
 * use with MySQL.  MySQL requires thread-specific variables for safe
 * execution.
 *
 * Calling this multiple times per thread is OK.
 */
- (void)_validateThreadSetup
{
	// Check to see whether the handler has already been installed
	if (pthread_getspecific(mySQLThreadInitFlagKey)) return;

	// If not, install it
	mysql_thread_init(); // multiple calls per thread OK.

	// Mark the thread to avoid multiple installs
	pthread_setspecific(mySQLThreadInitFlagKey, &mySQLThreadFlag);

	// Set up the notification handler to deregister it
	[[NSNotificationCenter defaultCenter] addObserver:[self class]
	                                         selector:@selector(_removeThreadVariables:)
	                                             name:NSThreadWillExitNotification
	                                           object:[NSThread currentThread]];
}

/**
 * Remove the MySQL variables and handlers from each closing thread which
 * has had them installed to avoid memory leaks.
 * This is a class method for easy global tracking; it will be called on the appropriate
 * thread automatically.
 */
+ (void)_removeThreadVariables:(NSNotification *)aNotification
{
	mysql_thread_end();
}
@end
