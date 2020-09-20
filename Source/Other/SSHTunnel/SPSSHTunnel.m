//
//  SPSSHTunnel.m
//  sequel-pro
//
//  Created by Rowan Beentje on April 26, 2009.
//  Copyright (c) 2009 Rowan Beentje. All rights reserved.
//  
//  Inspired by code by Yann Bizuel for SSH Tunnel Manager 2.
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

#import "SPSSHTunnel.h"
#import "RegexKitLite.h"
#import "SPKeychain.h"
#import "SPAlertSheets.h"
#import "SPThreadAdditions.h"
#import "SPOSInfo.h"

#import <netinet/in.h>
#import <CommonCrypto/CommonDigest.h>

static unsigned short getRandomPort();

@interface SPSSHTunnel ()

- (void)setLastError:(NSString *)msg;

@end

@implementation SPSSHTunnel

@synthesize passwordPromptCancelled;
@synthesize taskExitedUnexpectedly;

/*
 * Initialise with the supplied connection details.  Host, login and port should all be provided.
 * The password can either be set later via setPassword:, which stores the password locally and is
 * therefore not recommended, or via setPasswordKeychainName:, which will use the keychain on-demand
 * and is therefore preferred.
 */
- (id)initToHost:(NSString *)theHost port:(NSInteger)thePort login:(NSString *)theLogin tunnellingToPort:(NSInteger)targetPort onHost:(NSString *)targetHost
{
	if (!theHost || !targetPort || !targetHost) return nil;

	if ((self = [super init])) {
		
		// Store the connection settings as appropriate
		sshHost = [[NSString alloc] initWithString:theHost];
		sshLogin = [[NSString alloc] initWithString:(theLogin?theLogin:@"")];
		sshPort = thePort;
		useHostFallback = [theHost isEqualToString:targetHost];
		remoteHost = [[NSString alloc] initWithString:targetHost];
		remotePort = targetPort;
		delegate = nil;
		stateChangeSelector = nil;
		lastErrorLock = [NSObject new];
		lastError = nil;
		debugMessages = [[NSMutableArray alloc] init];
		debugMessagesLock = [[NSLock alloc] init];
		answerAvailableLock = [[NSLock alloc] init];

		// Enable connection muxing on 10.7+, but only if a preference is enabled; this is because
		// muxing causes connection instability for a large number of users (see Issue #1457)
		connectionMuxingEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:SPSSHEnableMuxingPreference];

		// Set up a connection for use by the tunnel process
		tunnelConnectionName = [[NSString alloc] initWithFormat:@"NKQ4HJ66PX.sequel-ace.SequelAce-%lu", (unsigned long)[[NSString stringWithFormat:@"%f", [[NSDate date] timeIntervalSince1970]] hash]];
		tunnelConnectionVerifyHash = [[NSString alloc] initWithFormat:@"%lu", (unsigned long)[[NSString stringWithFormat:@"%f-seeded", [[NSDate date] timeIntervalSince1970]] hash]];
		tunnelConnection = [NSConnection new];
		
		[tunnelConnection runInNewThread];
		[tunnelConnection removeRunLoop:[NSRunLoop currentRunLoop]];
		[tunnelConnection setRootObject:self];
		
		
		if (![tunnelConnection registerName:tunnelConnectionName]) {
			NSLog(@"Could not start ssh connection. %@", tunnelConnectionName);
			return nil;
		}
		
		parentWindow = nil;
		identityFilePath = nil;
		sshQuestionDialog = nil;
		sshPasswordDialog = nil;
		password = nil;
		keychainName = nil;
		keychainAccount = nil;
		requestedPassphrase = nil;
		task = nil;
		localPort = 0;
		connectionState = SPMySQLProxyIdle;
		
		requestedResponse = NO;
		passwordInKeychain = NO;
		passwordPromptCancelled = NO;
	}

	return self;
}

/*
 * Sets the connection callback selector; a function to be called whenever the tunnel state changes.
 * The callback function will be called and passed this SSH Tunnel object..
 */
- (BOOL)setConnectionStateChangeSelector:(SEL)theStateChangeSelector delegate:(id)theDelegate
{
	delegate = theDelegate;
	stateChangeSelector = theStateChangeSelector;

	return YES;
}

/*
 * Set the parent window of the connection for use with dialogs.
 */
- (void)setParentWindow:(NSWindow *)theWindow
{

	// As this object is not a NSWindowController, use manual top-level nib item management
	if (sshQuestionDialog) SPClear(sshQuestionDialog);
	if (sshPasswordDialog) SPClear(sshPasswordDialog);

	parentWindow = theWindow;
	if (![NSBundle loadNibNamed:@"SSHQuestionDialog" owner:self]) {
		NSLog(@"SSH query dialog could not be loaded; SSH tunnels will not function correctly.");
		parentWindow = nil;
	}
}

/*
 * Sets the password to be stored (and returned to the tunnel authenticator) locally.
 * Providing a keychain name is much more secure.
 */
- (BOOL)setPassword:(NSString *)thePassword
{
	if (passwordInKeychain) return NO;
	password = [[NSString alloc] initWithString:thePassword];
	
	return YES;
}

/**
 * Sets the path of an identity file, or public key file, to use when connecting.
 */
- (BOOL)setKeyFilePath:(NSString *)thePath
{
	NSString *expandedPath = [thePath stringByExpandingTildeInPath];
	if (![[NSFileManager defaultManager] fileExistsAtPath:expandedPath]) return NO;

	if (identityFilePath) [identityFilePath release];
	identityFilePath = [[NSString alloc] initWithString:expandedPath];
	return YES;
}

/*
 * Sets the keychain name to use to retrieve the password.  This is the recommended and
 * secure way of supplying a password to the SSH tunnel.
 */
- (BOOL)setPasswordKeychainName:(NSString *)theName account:(NSString *)theAccount
{
	if (password) SPClear(password);

	passwordInKeychain = YES;
	keychainName = [[NSString alloc] initWithString:theName];
	keychainAccount = [[NSString alloc] initWithString:theAccount];

	return YES;
}

/*
 * Get the state of the connection.
 */
- (SPMySQLConnectionProxyState)state
{
	// See if an auth dialog is up
	if (![answerAvailableLock tryLock]) {
		return SPMySQLProxyWaitingForAuth;
	}
	
	[answerAvailableLock unlock];

	// Return the currently recorded state
	return connectionState;
}

/*
 * Returns the last error string, if any.
 */
- (NSString *)lastError
{
	@synchronized(lastErrorLock) {
		if (!lastError) return nil;
	
		return [NSString stringWithString:lastError];
	}
}

- (void)setLastError:(NSString *)msg
{
	@synchronized(lastErrorLock) {
		if (lastError) [lastError release];
		lastError = msg? [[NSString alloc] initWithString:msg] : nil;
	}
}

/*
 * Returns all the debug text for this tunnel as a string, separated
 * by line endings.
 */
- (NSString *)debugMessages {
	[debugMessagesLock lock];
	NSString *debugMessagesString = [debugMessages componentsJoinedByString:@"\n"];
	[debugMessagesLock unlock];
	return debugMessagesString;
}

/*
 * Initiate the SSH tunnel connection, launching the task in a background thread.
 */
- (void)connect
{
	localPort = 0;

	if (connectionState != SPMySQLProxyIdle) return;

	[debugMessagesLock lock];
	[debugMessages removeAllObjects];
	[debugMessagesLock unlock];
	taskExitedUnexpectedly = NO;

	[NSThread detachNewThreadWithName:@"SPSSHTunnel SSH binary communication task"
	                           target:self
	                         selector:@selector(launchTask:)
	                           object:nil];
}

/*
 * Launch the NSTask which wraps the SSH process, and use it to initiate the
 * tunnel to the remote server.
 * Sets up and tears down as appropriate for usage in a background thread.
 */
- (void)launchTask:(id) dummy
{
	if (connectionState != SPMySQLProxyIdle || task) return;

	@autoreleasepool {
		NSMutableArray *taskArguments;
		NSMutableDictionary *taskEnvironment;
		NSString *authenticationAppPath;

		connectionState = SPMySQLProxyConnecting;
		if (delegate) [delegate performSelectorOnMainThread:stateChangeSelector withObject:self waitUntilDone:NO];

		// Enforce a parent window being present for dialogs
		if (!parentWindow) {
			connectionState = SPMySQLProxyIdle;
			if (delegate) [delegate performSelectorOnMainThread:stateChangeSelector withObject:self waitUntilDone:NO];
			[self setLastError:@"SSH Tunnel started without a parent window.  A parent window must be present."];
			return;
		}

		NSInteger connectionTimeout = [[[NSUserDefaults standardUserDefaults] objectForKey:SPConnectionTimeoutValue] integerValue];
		if (!connectionTimeout) connectionTimeout = 10;
		BOOL useKeepAlive = [[[NSUserDefaults standardUserDefaults] objectForKey:SPUseKeepAlive] doubleValue];
		double keepAliveInterval = [[[NSUserDefaults standardUserDefaults] objectForKey:SPKeepAliveInterval] doubleValue];
		if (!keepAliveInterval) keepAliveInterval = 0;

		// If no local port has yet been chosen, choose one
		if (!localPort) {
			localPort = getRandomPort();

			if (useHostFallback) {
				localPortFallback = getRandomPort();
			}

			// Abort if no local free port could be allocated
			if (!localPort || (useHostFallback && !localPortFallback)) {
				connectionState = SPMySQLProxyIdle;
				if (delegate) [delegate performSelectorOnMainThread:stateChangeSelector withObject:self waitUntilDone:NO];
				[self setLastError:NSLocalizedString(@"No local port could be allocated for the SSH Tunnel.", @"SSH tunnel could not be created because no local port could be allocated")];
				return;
			}
		}

		// Set up the NSTask
		task = [[NSTask alloc] init];
		NSString *launchPath = @"/usr/bin/ssh";
		NSString *userSSHPath = [[NSUserDefaults standardUserDefaults] stringForKey:SPSSHClientPath];

		if([userSSHPath length]) {
			launchPath = userSSHPath;
			// And I'm sure we will get issue reports about it anyway!
			[debugMessagesLock lock];
			[debugMessages addObject:@"################################################################"];
			[debugMessages addObject:[NSString stringWithFormat:@"# %@",NSLocalizedString(@"Custom SSH binary enabled. Disable in Preferences to rule out incompatibilities!", @"SSH connection : debug header with user-defined ssh binary")]];
			[debugMessages addObject:@"################################################################"];
			[debugMessagesLock unlock];
		}

		[task setLaunchPath:launchPath];

		// Prepare to set up the arguments for the task
		taskArguments = [[NSMutableArray alloc] init];
		void (^TA)(NSString *, NSString *) = ^(NSString *_name, NSString *_value) {
			[taskArguments addObjectsFromArray:@[_name,_value]];
		};

		// Enable verbose mode for message parsing
		[taskArguments addObject:@"-v"];

		// Ensure that the connection can be used for only tunnels, not interactive
		[taskArguments addObject:@"-N"];

		// If explicitly enabled, activate connection multiplexing - note that this can cause connection
		// instability on some setups, so is currently disabled by default.
		if (connectionMuxingEnabled) {
			// Enable automatic connection muxing/sharing, for faster connections
			TA(@"-o",@"ControlMaster=auto");

			// Set a custom control path to isolate connection sharing to Sequel Ace, to prevent picking up
			// existing masters without forwarding enabled and to isolate from interactive sessions.  Use a short
			// hashed path to aid length limit issues.
			unsigned char hashedPathResult[16];
			NSString *pathString = [NSString stringWithFormat:@"%@@%@:%ld", sshLogin?sshLogin:@"", sshHost, (long)(sshPort?sshPort:0)];
			CC_MD5([pathString UTF8String], (unsigned int)strlen([pathString UTF8String]), hashedPathResult);
			NSString *hashedString = [[[NSData dataWithBytes:hashedPathResult length:16] dataToHexString] substringToIndex:8];
			TA(@"-o",([NSString stringWithFormat:@"ControlPath=%@/SPSSH-%@", [NSFileManager temporaryDirectory], hashedString]));
		}
		else {
			// Disable muxing if requested
			TA(@"-S", @"none");
			TA(@"-o", @"ControlMaster=no");
		}

		// If the port forwarding fails, exit - as this is the primary use case for the instance
		TA(@"-o",@"ExitOnForwardFailure=yes");

		// Specify a connection timeout based on the preferences value
		TA(@"-o",([NSString stringWithFormat:@"ConnectTimeout=%ld", (long)connectionTimeout]));

		// Allow three password prompts
		TA(@"-o",@"NumberOfPasswordPrompts=3");
		
		// Use a KnownHostsFile in the sandbox folder
		NSString *customKnownHostsFilePath = [NSHomeDirectory() stringByAppendingPathComponent:@".keys/ssh_known_hosts_strict"];
		if (![[NSFileManager defaultManager] isWritableFileAtPath:customKnownHostsFilePath]){
			//Handle deleting an old known hosts file if it exists and we don't have permission to write
			[[NSFileManager defaultManager] removeItemAtPath:customKnownHostsFilePath error:nil];
			//Create new known hosts file
			[[NSFileManager defaultManager] createFileAtPath:customKnownHostsFilePath contents:[@"" dataUsingEncoding:NSUTF8StringEncoding] attributes:nil];
		}
		TA(@"-o", [NSString stringWithFormat:@"UserKnownHostsFile=%@", customKnownHostsFilePath]);
		
		// Use a custom ssh config file
		NSString *sshConfigFile = [[NSUserDefaults standardUserDefaults] stringForKey:SPSSHConfigFile];
		
		// If the config is not set, use the default one
		if (sshConfigFile == nil) {
			sshConfigFile = [[NSBundle mainBundle] pathForResource:SPSSHConfigFile ofType:@""];
		}
		
		TA(@"-F", sshConfigFile);

		// Specify an identity file if available
		if (identityFilePath) {
			TA(@"-i", identityFilePath);
		}

		// If keepalive is set in the preferences, use the same value for the SSH tunnel
		if (useKeepAlive && keepAliveInterval) {
			TA(@"-o", @"TCPKeepAlive=no");
			TA(@"-o", ([NSString stringWithFormat:@"ServerAliveInterval=%ld", (long)ceil(keepAliveInterval)]));
			TA(@"-o", @"ServerAliveCountMax=1");
		}

		// Specify the port, host, and authentication details
		if (sshPort) {
			TA(@"-p", ([NSString stringWithFormat:@"%ld", (long)sshPort]));
		}
		if ([sshLogin length]) {
			[taskArguments addObject:[NSString stringWithFormat:@"%@@%@", sshLogin, sshHost]];
		}
		else {
			[taskArguments addObject:sshHost];
		}
		if (useHostFallback) {
			TA(@"-L",([NSString stringWithFormat:@"%ld:127.0.0.1:%ld", (long)localPort, (long)remotePort]));
			TA(@"-L",([NSString stringWithFormat:@"%ld:%@:%ld", (long)localPortFallback, remoteHost, (long)remotePort]));
		}
		else {
			TA(@"-L", ([NSString stringWithFormat:@"%ld:%@:%ld", (long)localPort, remoteHost, (long)remotePort]));
		}

		[task setArguments:taskArguments];

		// Set up the environment for the task
		authenticationAppPath = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"SequelAceTunnelAssistant"];
		taskEnvironment = [[NSMutableDictionary alloc] initWithDictionary:[[NSProcessInfo processInfo] environment]];
		[taskEnvironment setObject:authenticationAppPath forKey:@"SSH_ASKPASS"];
		[taskEnvironment setObject:@":0" forKey:@"DISPLAY"];
		[taskEnvironment setObject:tunnelConnectionName forKey:@"SP_CONNECTION_NAME"];
		[taskEnvironment setObject:tunnelConnectionVerifyHash forKey:@"SP_CONNECTION_VERIFY_HASH"];
		if (passwordInKeychain) {
			[taskEnvironment setObject:[[NSNumber numberWithInteger:SPSSHPasswordUsesKeychain] stringValue] forKey:@"SP_PASSWORD_METHOD"];
			[taskEnvironment setObject:[keychainName stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] forKey:@"SP_KEYCHAIN_ITEM_NAME"];
			[taskEnvironment setObject:[keychainAccount stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] forKey:@"SP_KEYCHAIN_ITEM_ACCOUNT"];
		} else if (password) {
			[taskEnvironment setObject:[[NSNumber numberWithInteger:SPSSHPasswordAsksUI] stringValue] forKey:@"SP_PASSWORD_METHOD"];
		} else {
			[taskEnvironment setObject:[[NSNumber numberWithInteger:SPSSHPasswordNone] stringValue] forKey:@"SP_PASSWORD_METHOD"];
		}
		[task setEnvironment:taskEnvironment];

		// Add the connection details to the debug messages
		[debugMessagesLock lock];
		[debugMessages addObject:[NSString stringWithFormat:@"Used command:  %@ %@\n", [task launchPath], [[task arguments] componentsJoinedByString:@" "]]];
		[debugMessagesLock unlock];

		// Set up the standard error pipe
		standardError = [[NSPipe alloc] init];
		[task setStandardError:standardError];
		[[NSNotificationCenter defaultCenter] addObserver:self
		                                         selector:@selector(standardErrorHandler:)
		                                             name:NSFileHandleDataAvailableNotification
		                                           object:[standardError fileHandleForReading]];
		[[standardError fileHandleForReading] waitForDataInBackgroundAndNotify];

		{
			static BOOL hasCheckedTTY = NO;
			if(!hasCheckedTTY) {
				int fd = open("/dev/tty", O_RDWR);
				if(fd >= 0) {
					close(fd);
					fprintf(stderr, (
						"!!!\n"
						"!!! You are running Sequel Ace from a TTY.\n"
						"!!! Any SSH connections that require user input (e.g. a password/passphrase) will fail\n"
						"!!!  and appear stalled indefinitely.\n"
						"!!! Sorry!\n"
						"!!!\n"
					));
					fflush(stderr);
					// Explanation:
					// OpenSSH by default requests passwords AND yes/no questions directly from the TTY,
					// if it is part of a session group that has a controlling terminal (which is the case for
					// processes created by Terminal.app).
					//
					// But this won't work, because only the foreground process group can read from /dev/tty and
					// NSTask will create a new (background) process group for OpenSSH on launch.
					//   Side note: The internal method called from -[NSTask launch]
					//   -[NSConcreteTask launchWithDictionary:] accepts key @"_NSTaskNoNewProcessGroup" to skip that.
					//
					// Now, there are two preconditions for OpenSSH to use our SSH_ASKPASS utility instead:
					//   1) The "DISPLAY" envvar has to be set
					//   2) There must be no controlling terminal (ie. open("/dev/tty") fails)
					// (See readpass.c#read_passphrase() in OpenSSH for the relevant code)
					//
					// -[NSTask launch] internally uses posix_spawn() and according to its documentation
					//   "The new process also inherits the following attributes from the calling
					//    process: [...] control terminal [...]"
					// So if we wanted to avoid that, we would have to reimplement the whole NSTask class
					// and use fork()+exec*()+setsid() instead (or use GNUStep's NSTask which already does this).
					//
					// We could also do ioctl(fd, TIOCNOTTY, 0); before launching the child process, but
					// changing our own controlling terminal does not seem like a good idea in the middle
					// of the application lifecycle, when we don't know what other Cocoa code may use it...
				}
				hasCheckedTTY = YES;
			}
		}

		@try {
			// Launch and run the tunnel
			[task launch]; //throws for invalid paths, missing +x permission

			// Listen for output
			[task waitUntilExit];
		}
		@catch (NSException *e) {
			connectionState = SPMySQLProxyLaunchFailed;
			// Log the exception. Could be improved by showing a dedicated alert instead
			[debugMessagesLock lock];
			[debugMessages addObject:[NSString stringWithFormat:@"%@: %@\n", [e name], [e reason]]];
			[debugMessagesLock unlock];
		}

		// On tunnel close, clean up, ready for re-use if the delegate reconnects.
		SPClear(task);
		SPClear(standardError);
		[[NSNotificationCenter defaultCenter] removeObserver:self
		                                                name:NSFileHandleDataAvailableNotification
		                                              object:nil];

		// If the task closed unexpectedly, alert appropriately
		if (connectionState != SPMySQLProxyIdle) {
			connectionState = SPMySQLProxyIdle;
			taskExitedUnexpectedly = YES;
			[self setLastError:NSLocalizedString(@"The SSH Tunnel has unexpectedly closed.", @"SSH tunnel unexpectedly closed")];
			if (delegate) [delegate performSelectorOnMainThread:stateChangeSelector withObject:self waitUntilDone:NO];
		}

		// Run the run loop for a short time to ensure all task/pipe callbacks are dealt with
		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];

		SPClear(taskEnvironment);
		SPClear(taskArguments);
	}
}

/*
 * Disconnects the tunnel
 */
- (void)disconnect
{
	if (connectionState == SPMySQLProxyIdle) return;

	// If there's a delegate set, clear it to prevent unexpected state change messaging
	if (delegate) {
		delegate = nil;
		stateChangeSelector = NULL;
	}

	// Before terminating the tunnel, check that it's actually running. This is to accommodate tunnels which
	// suddenly disappear as a result of network disconnections. 
	if ([task isRunning]) [task terminate];
}

/*
 * Processes messages recieved from the SSH task.  These may be received singly
 * or several stuck together.
 */
- (void)standardErrorHandler:(NSNotification*)aNotification
{
	NSString *notificationText;
	NSEnumerator *enumerator;
	NSArray *messages;
	NSString *message;

	notificationText = [[NSString alloc] initWithData:[[aNotification object] availableData] encoding:NSASCIIStringEncoding];

	if ([notificationText length]) {
		messages = [notificationText componentsSeparatedByString:@"\n"];
		enumerator = [messages objectEnumerator];
		while ((message = [[enumerator nextObject] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]])) {
			if (![message length]) continue;
			[debugMessagesLock lock];
			[debugMessages addObject:[NSString stringWithString:message]];
			[debugMessagesLock unlock];

			if (connectionState != SPMySQLProxyConnected &&
				([message rangeOfString:@"Local forwarding listening on"].location != NSNotFound
				|| [message rangeOfString:@"mux_client_request_session: master session id: "].location != NSNotFound))
			{
				connectionState = SPMySQLProxyConnected;
				if (delegate) [delegate performSelectorOnMainThread:stateChangeSelector withObject:self waitUntilDone:NO];
			}

			if ([message rangeOfString:@"Connection established"].location != NSNotFound) {
				connectionState = SPMySQLProxyWaitingForAuth;
				if (delegate) [delegate performSelectorOnMainThread:stateChangeSelector withObject:self waitUntilDone:NO];
			}
			
			if ([message rangeOfString:@"bind: Address already in use"].location != NSNotFound) {
				connectionState = SPMySQLProxyIdle;
				[task terminate];
				[self setLastError:NSLocalizedString(@"The SSH Tunnel was unable to bind to the local port. This error may occur if you already have an SSH connection to the same server and are using a 'LocalForward' setting in your SSH configuration.\n\nWould you like to fall back to a standard connection to localhost in order to use the existing tunnel?", @"SSH tunnel unable to bind to local port message")];
				if (delegate) [delegate performSelectorOnMainThread:stateChangeSelector withObject:self waitUntilDone:NO];
			}

			if ([message rangeOfString:@"closed by remote host." ].location != NSNotFound) {
				connectionState = SPMySQLProxyIdle;
				[task terminate];
				[self setLastError:NSLocalizedString(@"The SSH Tunnel was closed 'by the remote host'. This may indicate a networking issue or a network timeout.", @"SSH tunnel was closed by remote host message")];
				if (delegate) [delegate performSelectorOnMainThread:stateChangeSelector withObject:self waitUntilDone:NO];
			}
			if ([message rangeOfString:@"Permission denied (" ].location != NSNotFound || [message rangeOfString:@"No more authentication methods to try" ].location != NSNotFound) {
				connectionState = SPMySQLProxyIdle;
				[task terminate];
				[self setLastError:NSLocalizedString(@"The SSH Tunnel could not authenticate with the remote host. Please check your password and ensure you still have access.", @"SSH tunnel authentication failed message")];
				if (delegate) [delegate performSelectorOnMainThread:stateChangeSelector withObject:self waitUntilDone:NO];
			}
			if ([message rangeOfString:@"connect failed: Connection refused" ].location != NSNotFound) {
				connectionState = SPMySQLProxyForwardingFailed;
				[self setLastError:NSLocalizedString(@"The SSH Tunnel was established successfully, but could not forward data to the remote port as the remote port refused the connection.", @"SSH tunnel forwarding port connection refused message")];
			}
			if ([message rangeOfString:@"Operation timed out" ].location != NSNotFound) {
				connectionState = SPMySQLProxyIdle;
				[task terminate];
				[self setLastError:[NSString stringWithFormat:NSLocalizedString(@"The SSH Tunnel was unable to connect to host %@, or the request timed out.\n\nBe sure that the address is correct and that you have the necessary privileges, or try increasing the connection timeout (currently %ld seconds).", @"SSH tunnel failed or timed out message"), sshHost, (long)[[[NSUserDefaults standardUserDefaults] objectForKey:SPConnectionTimeoutValue] integerValue]]];
				if (delegate) [delegate performSelectorOnMainThread:stateChangeSelector withObject:self waitUntilDone:NO];
			}
		}
	}

	if (connectionState != SPMySQLProxyIdle) {
		[[standardError fileHandleForReading] waitForDataInBackgroundAndNotify];
	}

	[notificationText release];
}

/*
 * Returns the local port assigned for use by the tunnel
 */
- (NSUInteger)localPort
{
	return localPort;
}

/*
 * Returns the local port assigned for fallback use by the tunnel, if any
 */
- (NSUInteger)localPortFallback
{
	if (!useHostFallback) return 0;
	
	return localPortFallback;
}

/*
 * Method to request the password for the current connection, as used by SequelAceTunnelAssistant;
 * called with a verification hash to check against the stored hash, to provide basic security.  Note
 * that this is easily bypassed, but if bypassed the password can already easily be retrieved in the same way.
 */
- (NSString *)getPasswordWithVerificationHash:(NSString *)theHash
{
	if (passwordInKeychain) return nil;
	if (![theHash isEqualToString:tunnelConnectionVerifyHash]) return nil;
	return password;
}

/*
 * Method to allow an SSH tunnel to request the response to a question, returning the response as
 * a boolean.  This is used by the SSH_ASKPASS environment setting to deal with situations like
 * host key mismatches.
 */
- (BOOL)getResponseForQuestion:(NSString *)theQuestion
{
	// Lock the answer available lock
	[[answerAvailableLock onMainThread] lock];

	// Request an answer on the main thread (UI stuff must be done on main thread)
	[self performSelectorOnMainThread:@selector(workerGetResponseForQuestion:) withObject:theQuestion waitUntilDone:YES];

	// Wait for closeSSHQuestionSheet: to unlock the lock, indicating an answer is available
	while (![answerAvailableLock tryLock]) usleep(25000);

	// Save the answer
	BOOL response = requestedResponse;

	// Unlock the lock again
	[answerAvailableLock unlock];

	// Return the answer
	return response;
}

- (void)workerGetResponseForQuestion:(NSString *)theQuestion
{
	NSSize questionTextSize;
	NSRect windowFrameRect;

	// set up the question window
	[sshQuestionText setStringValue:theQuestion];
	questionTextSize = [[sshQuestionText cell] cellSizeForBounds:NSMakeRect(0, 0, [sshQuestionText bounds].size.width, 500)];
	windowFrameRect = [sshQuestionDialog frame];
	windowFrameRect.size.height = ((questionTextSize.height < 100)?100:questionTextSize.height) + 70 + ([sshPasswordDialog isSheet]?0:22);
	[sshQuestionDialog setFrame:windowFrameRect display:NO];

	//show the question window
	[NSApp beginSheet:sshQuestionDialog
	   modalForWindow:parentWindow
	    modalDelegate:nil
	   didEndSelector:NULL
	      contextInfo:NULL];
	[parentWindow makeKeyAndOrderFront:self];
}

/*
 * Ends an existing modal session
 */
- (IBAction)closeSSHQuestionSheet:(id)sender
{
	requestedResponse = [sender tag] == 1 ? YES : NO;
	[NSApp endSheet:sshQuestionDialog];
	[sshQuestionDialog orderOut:nil];
	[[answerAvailableLock onMainThread] unlock];
}

/*
 * Method to allow an SSH tunnel to request a password.  This is used by the program set by the
 * SSH_ASKPASS environment setting to request passphrases for SSH keys.
 */
- (NSString *)getPasswordForQuery:(NSString *)theQuery verificationHash:(NSString *)theHash
{
	if (![theHash isEqualToString:tunnelConnectionVerifyHash]) return nil;
	
	if (passwordPromptCancelled) return nil;

	// Lock the answer available lock
	[[answerAvailableLock onMainThread] lock];

	// Request password on the main thread (UI stuff must be done on main thread)
	[self performSelectorOnMainThread:@selector(workerGetPasswordForQuery:) withObject:theQuery waitUntilDone:YES];

	// Wait for closeSSHPasswordSheet: to unlock the lock, indicating an answer is available
	while (![answerAvailableLock tryLock]) usleep(25000);

	// Save the answer
	NSString *thePassword = nil;
	if (requestedPassphrase) {
		thePassword = [NSString stringWithString:requestedPassphrase];
		SPClear(requestedPassphrase);
	}

	// Unlock the lock again
	[answerAvailableLock unlock];

	// Return the answer
	return thePassword;
}

- (void)workerGetPasswordForQuery:(NSString *)theQuery
{
	NSSize queryTextSize;
	NSRect windowFrameRect;

	// Work out whether a passphrase is being requested, extracting the key name
	NSString *keyName = [theQuery stringByMatching:@"^\\s*Enter passphrase for key \\'(.*)\\':\\s*$" capture:1L];
	
	if (keyName) {
		[sshPasswordText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Enter your password for the SSH key\n\"%@\"", @"SSH key password prompt"), keyName]];
		[sshPasswordKeychainCheckbox setHidden:NO];
		currentKeyName = [keyName retain];
	} 
	else {
		[sshPasswordText setStringValue:theQuery];
		[sshPasswordKeychainCheckbox setHidden:YES];
		currentKeyName = nil;
	}

	// Request the password, sizing the window appropriately to fit the query
	queryTextSize = [[sshPasswordText cell] cellSizeForBounds:NSMakeRect(0, 0, [sshPasswordText bounds].size.width, 500)];
	windowFrameRect = [sshPasswordDialog frame];
	windowFrameRect.size.height = ((queryTextSize.height < 40)?40:queryTextSize.height) + 140 + ([sshPasswordDialog isSheet]?0:22);
	
	[sshPasswordDialog setFrame:windowFrameRect display:NO];
	[NSApp beginSheet:sshPasswordDialog
	   modalForWindow:parentWindow
	    modalDelegate:nil
	   didEndSelector:NULL
	      contextInfo:NULL];
	[parentWindow makeKeyAndOrderFront:self];
}
 
/*
 * Ends an existing modal session
 */
- (IBAction)closeSSHPasswordSheet:(id)sender
{
	requestedResponse = [sender tag]==1 ? YES : NO;
	
	[NSApp endSheet:sshPasswordDialog];
	[sshPasswordDialog orderOut:nil];

	if (requestedResponse) {
		NSString *thePassword = [NSString stringWithString:[sshPasswordField stringValue]];
		[sshPasswordField setStringValue:@""];
		if ([delegate respondsToSelector:@selector(undoManager)] && [delegate undoManager]) {
			[[delegate undoManager] removeAllActionsWithTarget:sshPasswordField];
		} else if ([[parentWindow windowController] document] && [[[parentWindow windowController] document] undoManager]) {
			[[[[parentWindow windowController] document] undoManager] removeAllActionsWithTarget:sshPasswordField];
		}
		requestedPassphrase = [[NSString alloc] initWithString:thePassword];

		// Add to keychain if appropriate
		if (currentKeyName && [sshPasswordKeychainCheckbox state] == NSOnState) {
			SPKeychain *keychain = [[SPKeychain alloc] init];
			[keychain addPassword:thePassword forName:@"SSH" account:currentKeyName withLabel:[NSString stringWithFormat:@"SSH: %@", currentKeyName]];
			[keychain release];
			SPClear(currentKeyName);
		}
	}
	
	if (!requestedPassphrase) passwordPromptCancelled = YES;

	[[answerAvailableLock onMainThread] unlock];
}

#pragma mark -

- (void)dealloc
{
	delegate = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self disconnect];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	SPClear(sshHost);
	SPClear(sshLogin);
	SPClear(remoteHost);
	SPClear(tunnelConnectionName);
	SPClear(tunnelConnectionVerifyHash);
	[tunnelConnection invalidate];
	SPClear(tunnelConnection);
	[self setLastError:nil];
	SPClear(lastErrorLock);
	SPClear(debugMessages);
	SPClear(debugMessagesLock);
	[answerAvailableLock tryLock];
	[answerAvailableLock unlock];
	SPClear(answerAvailableLock);
	SPClear(password);
	SPClear(keychainName);
	SPClear(keychainAccount);
	SPClear(identityFilePath);

	// As this object is not a NSWindowController, use manual top-level nib item management
	SPClear(sshQuestionDialog);
	SPClear(sshPasswordDialog);
	
	[super dealloc];
}

@end

#pragma mark -

unsigned short getRandomPort() {
	int port = 0;
	int tempSocket;
	struct sockaddr_in tempSocketAddress;
	size_t addressLength = sizeof(tempSocketAddress);
	if((tempSocket = socket(AF_INET, SOCK_STREAM, 0)) > 0) {
		memset(&tempSocketAddress, 0, sizeof(tempSocketAddress));
		tempSocketAddress.sin_family = AF_INET;
		tempSocketAddress.sin_addr.s_addr = htonl(INADDR_ANY);
		tempSocketAddress.sin_port = 0;
		if (bind(tempSocket, (struct sockaddr *)&tempSocketAddress, (socklen_t)addressLength) >= 0) {
			if (getsockname(tempSocket, (struct sockaddr *)&tempSocketAddress, (uint32_t *)&addressLength) >= 0) {
				port = ntohs(tempSocketAddress.sin_port);
			}
		}
		close(tempSocket);
	}
	return port;
}
