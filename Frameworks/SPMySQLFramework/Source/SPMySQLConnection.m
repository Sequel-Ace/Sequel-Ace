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
#import "SPMySQLUtilities.h"
#import "SPMySQLArrayAdditions.h"
#import "SPMySQLMutableDictionaryAdditions.h"
#import <SPMySQL/SPMySQL-Swift.h>

@interface SPMySQLConnection ()

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
@synthesize clientFlags = clientFlags;

#pragma mark -
#pragma mark Getters and Setters

- (BOOL)lastQueryWasCancelled
{
	@synchronized (self) {
		return lastQueryWasCancelled;
	}
}

- (void)setLastQueryWasCancelled:(BOOL)cancelled
{
	// Some callers issue KILL through another connection and mark cancellation here.
	@synchronized (self) {
		if (cancelled) [self.sessionAccess recordQueryCancellation];
		lastQueryWasCancelled = cancelled;
	}
}

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
		_sessionAccess = [[SAConnectionSessionAccess alloc] init];

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
		valueEscaper = [[SAConnectionEscaper alloc] init];

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
	// If the connection has been allowed to drop in the background, restore it if posslbe
	if (state == SPMySQLConnectionLostInBackground) {
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
		// The check just failed, so this attempt runs on the check's limits rather than the
		// configured timeout - the interface is waiting on it.
		connectionVerified = [self _reconnectAllowingRetries:YES afterFailedCheck:YES];
	}

	// Update the connection tracking use variable if the connection was confirmed,
	// as at least a mysql_ping will have been used.
	if (connectionVerified) {
        lastConnectionUsedTime = _monotonicTime();
	}

	return connectionVerified;
}

/**
 * Whether a connection used this recently is worth verifying before it is used again.
 * A check costs a round trip, so one is only made when the connection has been idle long
 * enough that the route may have gone while nothing was looking, and only while nothing else
 * holds the connection - an active query is traffic of its own, and the thread running it owns
 * the connection structure.
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
		return [self _reconnectAllowingRetries:YES];
	}
	
	// If the connection was recently used, return success - unless its socket
	// already knows the peer is gone, which a dropped route does not announce.
	double idleTime = _timeIntervalSinceMonotonicTime(lastConnectionUsedTime);
	if (idleTime < 30) {
		if (![self _shouldVerifyRecentlyUsedConnectionIdleFor:idleTime]) return YES;
		SPLog(@"connection socket reports the peer is gone; checking despite recent use");
	}
	
	// Otherwise check the connection
	return [self checkConnection];
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
    serverVariableVersion = [[NSString alloc] initWithCString:mysql_get_server_info(mySQLConnection) encoding:NSISOLatin1StringEncoding];
    NSLog(@"%@", [serverVariableVersion lowercaseString]);
    NSString *someRegexp = @"(.*)10(\\.[3-9]+[0-9]*(\\.[0-9]*))*-(mariadb)(.*)";
    NSPredicate *myTest = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", someRegexp];
    
    if ([myTest evaluateWithObject: [serverVariableVersion lowercaseString]]){
        return false;
    }
    return true;
}

- (BOOL) isMariaDB
{
  serverVariableVersion = [[NSString alloc] initWithCString:mysql_get_server_info(mySQLConnection) encoding:NSISOLatin1StringEncoding];
  // See more: https://regex101.com/r/0QRlsG/1
  NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", @"(^.*)-[mariadb].*"];
  if ([predicate evaluateWithObject: [serverVariableVersion lowercaseString]]){
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
	// An attempt entitled to the connection's configured timeout.
	return [self _connectUsingConnectTimeout:0];
}

/**
 * Establish the connection, with a connect timeout the caller may limit.
 * A reconnect that follows a failed connection check passes the limit its budget allows;
 * zero means the connection's configured timeout applies, as it does everywhere else.
 */
- (BOOL)_connectUsingConnectTimeout:(NSUInteger)connectTimeoutOrZero
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
	mySQLConnection = [self _makeRawMySQLConnectionWithEncoding:encoding isMasterConnection:YES connectTimeout:connectTimeoutOrZero];

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
		[valueEscaper forgetSession];
		[self _unlockConnection];
		return NO;
	}

	// Reserve the cancellation handle while the native connection is locked.
	NSError *socketError = nil;
	if (![self.sessionAccess trackSocket:mySQLConnection->net.fd serverThreadID:mySQLConnection->thread_id error:&socketError]) {
		[self _updateLastErrorMessage:socketError.localizedDescription];
		mysql_close(mySQLConnection);
		mySQLConnection = NULL;
		state = SPMySQLDisconnected;
		[self _unlockConnection];
		return NO;
	}

	// Successfully connected - record connected state and reset tracking variables
	state = SPMySQLConnected;
	// What the new session reports is recorded for the escaper, which escapes from this rather
	// than from the connection's own handle.
	[valueEscaper recordSessionCharacterSet:[NSString stringWithUTF8String:mysql_character_set_name(mySQLConnection)]
	                     noBackslashEscapes:(mySQLConnection->server_status & SERVER_STATUS_NO_BACKSLASH_ESCAPES) != 0
	                        openTransaction:(mySQLConnection->server_status & SERVER_STATUS_IN_TRANS) != 0
	                            isHandshake:YES
	                // A handshake carries no tracking item of its own; what the session reports
	                // becomes known once its first statement has run.
	                characterSetWasReported:NO];

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
	serverVariableVersion = [[NSString alloc] initWithCString:mysql_get_server_info(mySQLConnection) encoding:NSISOLatin1StringEncoding];
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

	// What a session starts with is only known once it has run a statement: a server's
	// init_connect runs after the handshake has been answered, and can turn
	// NO_BACKSLASH_ESCAPES on for every session without the global mode saying so. The escaping
	// mode is taken from here, so that a session forgotten at teardown falls back to the mode the
	// session after it will start under rather than to what the handshake alone showed.
	[self _lockConnection];
	if (mySQLConnection) {
		[valueEscaper recordStartingModeWithNoBackslashEscapes:(mySQLConnection->server_status & SERVER_STATUS_NO_BACKSLASH_ESCAPES) != 0];
	}
	[self _unlockConnection];

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
	// A connection on the configured timeout.
	return [self _makeRawMySQLConnectionWithEncoding:encodingName isMasterConnection:isMaster connectTimeout:0];
}

/**
 * Make a client-library connection, with a connect timeout the caller may limit.
 * Zero means the connection's configured timeout applies. A reconnect that follows a failed
 * check passes what its budget allows, so a route that has gone cannot hold the interface for
 * the configured timeout - or, with none configured, indefinitely.
 */
- (MYSQL *)_makeRawMySQLConnectionWithEncoding:(NSString *)encodingName isMasterConnection:(BOOL)isMaster connectTimeout:(NSUInteger)connectTimeoutOrZero
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

	// Set the connection timeout. A side connection, which only asks the server to kill a query,
	// keeps a short limit of its own instead of waiting out the configured one.
	// An attempt that may not take the configured timeout - a reconnect after a failed check -
	// is given its own by the caller.
	NSUInteger masterConnectTimeout = connectTimeoutOrZero > 0 ? connectTimeoutOrZero : timeout;
	NSUInteger connectTimeout = isMaster
		? masterConnectTimeout
		: [SAConnectionCheckBudget sideConnectionConnectTimeoutForConfiguredTimeout:timeout];
	mysql_options(theConnection, MYSQL_OPT_CONNECT_TIMEOUT, (const void *)&connectTimeout);

	// A side connection asks the server to kill a query while that query is held still. It must
	// not wait on a server that accepted it and then stopped answering; the main connection keeps
	// no such limit, as it would cut long queries short.
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
		bool trueMyBool = TRUE;
		mysql_options(theConnection, MYSQL_ENABLE_CLEARTEXT_PLUGIN, &trueMyBool);
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
		NSString *delegatePassword = [delegate keychainPasswordForConnection:self];

		// A non-empty delegate message abandons the attempt without contacting the server.
		if (!delegatePassword && [delegate respondsToSelector:@selector(credentialErrorMessageForConnection:)]) {
			NSString *credentialError = [delegate credentialErrorMessageForConnection:self];

			if ([credentialError length]) {
				if (isMaster) {
					[self _updateLastErrorMessage:credentialError];
					[self _updateLastErrorID:CR_UNKNOWN_ERROR];
					[self _updateLastSqlstate:@"HY000"];
				}

				mysql_close(theConnection);

				return NULL;
			}
		}

		thePassword = [delegatePassword cStringUsingEncoding:connectEncodingNS];
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
    }

	// An attempt that requires TLS is abandoned when the mode cannot be applied, as
	// libmysqlclient otherwise falls back to SSL_MODE_PREFERRED and its plaintext fallback.
	BOOL requiresTLS = [SACleartextAuthPolicy requiresTLSWithCleartextPluginEnabled:enableClearTextPlugin sslRequested:useSSL];
	enum mysql_ssl_mode opt_ssl_mode = requiresTLS ? SSL_MODE_REQUIRED : SSL_MODE_PREFERRED;

	if (mysql_options(theConnection, MYSQL_OPT_SSL_MODE, (void *)&opt_ssl_mode) && requiresTLS) {
		if (isMaster) {
			[self _updateLastErrorMessage:@"libmysqlclient is missing support for MYSQL_OPT_SSL_MODE"];
			[self _updateLastSqlstate:@"HY000"];
			[self _updateLastErrorID:CR_SSL_CONNECTION_ERROR];
		}

		mysql_close(theConnection);

		return NULL;
	}

    // A failed attempt frees every option set on this handle unless the client asks to keep them,
    // so the retry below would run without the timeouts set above - on the system default, which
    // is what the side connection's limits are there to avoid.
    unsigned long connectClientFlags = [self clientFlags] | CLIENT_REMEMBER_OPTIONS;

    uint64_t connectStart_t = _monotonicTime();
    MYSQL *connectionStatus = mysql_real_connect(theConnection, theHost, theUsername, thePassword, NULL, (unsigned int)port, theSocket, connectClientFlags);

    //If we attempted SSL and failed, try one more time non-ssl if the user isn't requiring SSL.
    // Only a failed TLS negotiation is retried that way: a host that never answered fails the
    // same way again, and credentials the server refused, or that may already have gone out over
    // TLS before the connection was lost, must not be sent a second time unencrypted.
    if([SACleartextAuthPolicy allowsRetryWithoutTLSWithCleartextPluginEnabled:enableClearTextPlugin sslRequested:useSSL] && theConnection != connectionStatus && [SAConnectionRetryPolicy shouldRetryWithoutTLSAfterErrorID:mysql_errno(theConnection)]) {
        // On what is left of the attempt's budget, not on a second helping of it: the flag above
        // keeps the timeout's value rather than a deadline, so a TLS negotiation that used the
        // whole budget would otherwise be followed by an attempt entitled to all of it again.
        NSNumber *retryConnectTimeout = [SAConnectionRetryPolicy retryConnectTimeoutForConnectTimeout:connectTimeout
                                                                                        secondsSpent:_timeIntervalSinceMonotonicTime(connectStart_t)];
        if (retryConnectTimeout) {
            NSUInteger retryTimeout = [retryConnectTimeout unsignedIntegerValue];
            if (retryTimeout > 0) {
                mysql_options(theConnection, MYSQL_OPT_CONNECT_TIMEOUT, (const void *)&retryTimeout);
            }
            opt_ssl_mode = SSL_MODE_DISABLED;
            mysql_options(theConnection, MYSQL_OPT_SSL_MODE, (void *)&opt_ssl_mode);
            connectionStatus = mysql_real_connect(theConnection, theHost, theUsername, thePassword, NULL, (unsigned int)port, theSocket, connectClientFlags);
        }
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

			// Replaces the reported TLS failure with the reason the attempt required TLS.
			if (enableClearTextPlugin && !useSSL && mysql_errno(theConnection) == CR_SSL_CONNECTION_ERROR) {
				[self _updateLastErrorMessage:NSLocalizedString(@"This connection has the cleartext authentication plugin enabled, which sends the password in plain text, so it is only made over TLS. TLS could not be established with the server and no password was sent.", @"cleartext authentication plugin requires TLS error")];
			}
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
	// An attempt nobody asked for keeps the connection's configured timeout.
	return [self _reconnectAllowingRetries:canRetry afterFailedCheck:NO];
}

/**
 * Re-establish the connection, on the time budget the attempt is entitled to, under the
 * session's reconnect lease.
 * An attempt that follows a failed connection check runs on the check's limits instead of the
 * configured timeout: the interface is already waiting, and a route that has gone would
 * otherwise hold it for the whole timeout - or, with none configured, indefinitely.
 */
- (BOOL)_reconnectAllowingRetries:(BOOL)canRetry afterFailedCheck:(BOOL)afterFailedCheck
{
    BOOL restored = [self.sessionAccess reconnectAllowingRetries:canRetry operation:^BOOL {
        return [self _performReconnectAllowingRetries:canRetry afterFailedCheck:afterFailedCheck];
    }];
    // Explicit disconnect can retire a completed session while this caller waits.
    return restored && state == SPMySQLConnected && !userTriggeredDisconnect;
}

/**
 * Re-establish the connection on the budget the attempt was given, inside the lease above.
 * @param canRetry Whether the attempt may try again after a failure.
 * @param afterFailedCheck Whether this follows a failed connection check, whose limits it then runs on.
 * @return Whether the connection was re-established.
 */
- (BOOL)_performReconnectAllowingRetries:(BOOL)canRetry afterFailedCheck:(BOOL)afterFailedCheck
{

    SPLog(@"_reconnectAllowingRetries");
	if (userTriggeredDisconnect) return NO;
	// The budget travels with the attempt rather than in shared state: a second thread
	// entering this method would otherwise overwrite the limit of an attempt already running.
	SAConnectionAttemptBudget *attemptBudget = [SAConnectionCheckBudget
		attemptBudgetForConfiguredTimeout:timeout userEndedWait:NO afterFailedCheck:afterFailedCheck];
	// One clock for the whole attempt: the stages below share the budget instead of each
	// starting it afresh, so a proxy that takes its time does not add to what connecting may
	// then spend. __block because the proxy loop moves it forward to skip time the user spent
	// answering, and the block that reads it has to see that - a block captures a local by
	// value, so without this it would keep measuring from where the attempt began.
	__block uint64_t attemptStart_t = _monotonicTime();
	BOOL reconnectSucceeded = NO;
    NSString *timeZoneIdentifierToRestore = nil;

	@autoreleasepool {
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

		// If no network is present, wait for a short time for one to become available
		[self _waitForNetworkConnectionWithTimeout:[attemptBudget networkWait]];

		if ([self _abortCancelledReconnectWhileLocked]) return NO;

		// If there is a proxy, attempt to reconnect it in blocking fashion
		if (proxy) {

            SPLog(@"we have a proxy");

			uint64_t loopIterationStart_t, proxyWaitStart_t;
			// The proxy's own connection is part of the attempt, so it shares its budget. A
			// Whether this stage has waited long enough. Under a budget that is a question
			// about the attempt as a whole, which the proxy shares with the connect after it -
			// so it is asked of the attempt's own clock, not of this stage's, or the elapsed
			// time would count twice and the budget run out in half of it. Without a budget it
			// is the configured timeout per stage, as before. `extra` is the grace the second
			// loop allowed itself.
			double configuredTimeout = (double)timeout;
			BOOL (^proxyWaitedLongEnough)(uint64_t, double) = ^BOOL(uint64_t stageStart, double extra) {
				if ([attemptBudget overridesConfiguredTimeout]) {
					return [attemptBudget remainingSecondsAfterSeconds:_timeIntervalSinceMonotonicTime(attemptStart_t)] <= 0;
				}
				return _timeIntervalSinceMonotonicTime(stageStart) > (configuredTimeout + extra);
			};

			// If the proxy is not yet idle after requesting a disconnect, wait for a short time
			// to allow it to disconnect.
			if ([proxy state] != SPMySQLProxyIdle) {

                SPLog(@"proxy not idle, waiting");

				proxyWaitStart_t = _monotonicTime();
				while ([proxy state] != SPMySQLProxyIdle) {
					if ([self _abortCancelledReconnectWhileLocked]) return NO;
					loopIterationStart_t = _monotonicTime();

					// If the connection timeout has passed, break out of the loop
					if (proxyWaitedLongEnough(proxyWaitStart_t, 0)) break;

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

			[proxy connect];

			// Wait while the proxy connects
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

				// If the proxy connection attempt time has exceeded the timeout, break of of the loop.
				if (proxyWaitedLongEnough(proxyWaitStart_t, 1)) {
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
					uint64_t excluded = _monotonicTime() - loopIterationStart_t;
					proxyWaitStart_t += excluded;
					// The attempt's own clock skips it as well: a passphrase the user takes a
					// while over is their time, not the connection's, and charging it to the
					// budget would leave a healthy connection a second to be made in.
					attemptStart_t += excluded;
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
			[self _connectUsingConnectTimeout:[attemptBudget remainingConnectTimeoutAfterSeconds:_timeIntervalSinceMonotonicTime(attemptStart_t)]];
		} else if ([[NSThread currentThread] isCancelled] && proxy) {
			[_proxyReconnectCoordinator disconnectProxy:proxy preservingReconnect:NO];
		}

		// If the reconnection succeeded, restore the connection state as appropriate
		if (state == SPMySQLConnected && ![[NSThread currentThread] isCancelled]) {
            reconnectSucceeded = [self _restoreSessionStateAfterReconnectWithDatabase:databaseToRestore
                                                        encoding:encodingToRestore
                                    encodingUsesLatin1Transport:encodingUsesLatin1TransportToRestore
                                               timeZoneIdentifier:timeZoneIdentifierToRestore];
            if (!reconnectSucceeded) {
                // Never hand a session with the server's default time zone to a query.
                // Preserve all saved state so the next use can retry restoration.
                [self _disconnectPreservingProxyReconnect:YES];
                state = SPMySQLConnectionLostInBackground;
                reconnectingThread = NULL;
                return NO;
            }
            // When the connection is restored successfully, reset the relevant variables to prepare for the next time
            databaseToRestore = nil;
            encodingToRestore = nil;
            encodingUsesLatin1TransportToRestore = NO;
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
					// A question about this connection is already open on this thread, so nothing
					// was decided here. The thread that opened it decides; this attempt only
					// reports that it did not reconnect, and must not set the disconnect flag -
					// that would answer the open question behind the user's back.
				case SPMySQLConnectionLostDecisionPending:
					break;

				case SPMySQLConnectionLostDisconnect:
					[self _updateLastErrorMessage:NSLocalizedString(@"User triggered disconnection", @"User triggered disconnection")];
					userTriggeredDisconnect = YES;
					break;

					// By default attempt a reconnect
				default:
					reconnectingThread = NULL;
                    SPLog(@"_reconnectAllowingRetries By default attempt a reconnect");
					// The user asked for this one, so it is theirs to wait for: it runs on the
					// configured timeout rather than on the check's limits, which exist to keep
					// the interface from hanging while nobody has been asked anything. A
					// connection that legitimately needs longer - a slow proxy, or an
					// authentication handshake with a thirty-second timeout - could otherwise
					// never come back through this dialog. Where there was nobody to ask, the
					// decision above was the connection's own, and the attempt is still the
					// failed check's: it keeps the check's limits.
					reconnectSucceeded = [self _reconnectAllowingRetries:YES
					                                   afterFailedCheck:[SAConnectionCheckBudget retryKeepsFailedCheckLimitsAfterFailedCheck:afterFailedCheck
					                                                                                              decisionCameFromDelegate:delegateSupportsConnectionLost]];
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
		[self.sessionAccess clearSocket];
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

    [self.sessionAccess cancelActiveQuery:^{ [self cancelCurrentQuery]; }];

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
	[self.sessionAccess clearSocket];
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
	// The session is gone, so what it reported goes with it: until the next one shakes hands,
	// values follow the character set on record, which that session will be set up with.
	[valueEscaper forgetSession];
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

	// What a session still needs once it has reported its variables - that the server will
	// report later character set changes, and that the one it is in can be converted for - is
	// worked out by SASessionStartupPlan. Only the statements it returns are run here.
	SASessionStartupPlan *startupPlan = [SASessionStartupPlan
		planForReportedCharacterSet:retrievedEncoding
		               trackingList:[variables objectForKey:@"session_track_system_variables"]
		                      quote:^NSString *(NSString *value) { return [value mySQLTickQuotedString]; }
		           serverIsProxySQL:^BOOL{ return [self _serverIsProxySQL]; }];
	// Asking the server to report later changes to the character set. Whether it took is not
	// recorded anywhere: what the escaper needs is a change the server actually reported, which
	// it is told about when one arrives, and this statement only decides whether any ever will.
	if ([startupPlan trackingStatement]) {
		[self queryString:[startupPlan trackingStatement]];
		if ([self queryErrored]) {
			SPLog(@"[_updateConnectionVariables]: could not turn on session state tracking: %@", [self lastErrorMessage]);
		}
	}
	if ([startupPlan movesToAnotherCharacterSet]) {
		SPLog(@"[_updateConnectionVariables]: no string encoding carries the session's character set '%@'; moving the session.",
		      retrievedEncoding);
		// More than one candidate, best first: a server too old for utf8mb4 is offered utf8
		// rather than left in a character set nothing can convert for.
		retrievedEncoding = [startupPlan characterSetWithoutStatements];
		for (SASessionCharacterSetMove *move in [startupPlan characterSetMoves]) {
			NSUInteger reportsBeforeTheMove = [valueEscaper reportsSoFar];
			[self queryString:[move statement]];
			if (![self queryErrored]) {
				retrievedEncoding = [move characterSet];
				// The move settles what the variable list only suggested: whether this session's
				// changes are reported to the client at all. Judged by the report this statement
				// brought back, not by whatever the escaper holds once it has let go.
				[valueEscaper recordCharacterSetSetByConnection:retrievedEncoding reportsBefore:reportsBeforeTheMove];
				break;
			}
			SPLog(@"[_updateConnectionVariables]: '%@' failed: %@", [move statement], [self lastErrorMessage]);
		}
	} else {
		retrievedEncoding = [startupPlan characterSet];
	}

	// Update instance variables
	encoding = [[NSString alloc] initWithString:retrievedEncoding];
	stringEncoding = [SPMySQLConnection stringEncodingForMySQLCharset:[encoding cStringUsingEncoding:stringEncoding]];
	encodingUsesLatin1Transport = NO;

	// What the server reads statements in, which the record above does not have to agree with: the
	// record follows character_set_results, because results are decoded with it, and an
	// init_connect can set the two differently. Escaping follows this one instead - a value
	// escaped for the results character set and read in another one is how a quote escapes out of
	// its literal.
	BOOL aMoveTookEffect = [startupPlan movesToAnotherCharacterSet]
		&& ![retrievedEncoding isEqualToString:[startupPlan characterSetWithoutStatements]];
	// A move ran SET NAMES, which sets all of them alike, so there is nothing left to disagree.
	sqlInputEncoding = aMoveTookEffect
		? [[NSString alloc] initWithString:retrievedEncoding]
		: [SAConnectionCharacterSets sqlInputCharacterSetFromVariables:variables];

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

- (BOOL)_restoreSessionStateAfterReconnectWithDatabase:(NSString *)databaseName
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

    return [SASessionTimeZoneRestorer restoreTimeZoneIdentifier:timeZoneIdentifier onConnection:self];
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
