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
#import "SPThreadAdditions.h"
#import "SPFileHandle.h"
#import "SPAppController.h"
#import "SPPreferenceController.h"
#import "SPGeneralPreferencePane.h"
#import "SPDatabaseDocument.h"
#import "SPFunctions.h"
#import "SPConnectionController.h"


#import "sequel-ace-Swift.h"

#import <netinet/in.h>

static unsigned short getRandomPort(void);

@interface SPSSHTunnel () <SASSHTunnelAuthSource>
{
	// Private: kept out of the public header so the NSConnection deprecation is
	// not re-emitted in every translation unit that reaches SPSSHTunnel.h via
	// the bridging header. Used only in this file.
	NSConnection *tunnelConnection;

	// The object actually vended over the connection: only the three
	// authentication methods the tunnel assistant needs are reachable through
	// it (SSH tunnel IPC plan, Step 1). It holds this tunnel weakly and reads
	// the state it needs through SASSHTunnelAuthSource.
	SASSHTunnelAuthService *authService;

	// Decides whether a prompt may be shown and fails an in-flight prompt
	// closed on teardown (SSH tunnel IPC plan, Step 1). The sheets, their
	// modal sessions and the answer ivars stay here; the state machine is Swift.
	SASSHTunnelPromptCoordinator *promptCoordinator;

	SASSHStderrDrainCoordinator *standardErrorDrainCoordinator;
}

- (void)setLastError:(NSString *)msg;
- (void)cancelPendingPrompt;
- (void)startConnectionAttempt;
- (void)completeStandardErrorDrain;
- (void)disconnectPreservingQueuedReconnect:(BOOL)preserveQueuedReconnect;

@end

@implementation SPSSHTunnel

@synthesize passwordPromptCancelled;
@synthesize taskExitedUnexpectedly;
@synthesize sshQuestionText, sshQuestionDialog, sshPasswordText, sshPasswordDialog, sshPasswordField;
/*
 * Initialise with the supplied connection details.  Host, login and port should all be provided.
 * The password can either be set later via setPassword:, which stores the password locally and is
 * therefore not recommended, or via setPasswordKeychainName:, which will use the keychain on-demand
 * and is therefore preferred.
 */
- (instancetype)initToHost:(NSString *)theHost port:(NSInteger)thePort login:(NSString *)theLogin tunnellingToPort:(NSInteger)targetPort onHost:(NSString *)targetHost
{
	if (!theHost) return nil;

	if ((self = [super init])) {
		NSString *safeTargetHost = targetHost ?: @"127.0.0.1";
		
		// Store the connection settings as appropriate
		sshHost = [[NSString alloc] initWithString:theHost];
		sshLogin = [[NSString alloc] initWithString:(theLogin?theLogin:@"")];
		sshPort = thePort;
		useHostFallback = [theHost isEqualToString:safeTargetHost];
		remoteHost = [safeTargetHost copy];
		remotePort = targetPort;
		delegate = nil;
		stateChangeSelector = nil;
		lastErrorLock = [NSObject new];
		lastError = nil;
		debugMessages = [[NSMutableArray alloc] init];
		debugMessagesLock = [[NSLock alloc] init];
		answerAvailableLock = [[NSLock alloc] init];
		promptCoordinator = [[SASSHTunnelPromptCoordinator alloc] initWithAnswerLock:answerAvailableLock];
		standardErrorDrainCoordinator = [[SASSHStderrDrainCoordinator alloc] init];

		// Enable connection muxing on 10.7+, but only if a preference is enabled; this is because
		// muxing causes connection instability for a large number of users (see Issue #1457)
		connectionMuxingEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:SPSSHEnableMuxingPreference];

		// Set up a connection for use by the tunnel process
		tunnelConnectionName = [[NSString alloc] initWithFormat:@"NKQ4HJ66PX.sequel-ace.SequelAce-%lu", (unsigned long)[[NSString stringWithFormat:@"%f", [[NSDate date] timeIntervalSince1970]] hash]];
		tunnelConnectionVerifyHash = [[NSString alloc] initWithFormat:@"%lu", (unsigned long)[[NSString stringWithFormat:@"%f-seeded", [[NSDate date] timeIntervalSince1970]] hash]];
		tunnelConnection = [NSConnection new];
		
		[tunnelConnection runInNewThread];
		[tunnelConnection removeRunLoop:[NSRunLoop currentRunLoop]];
		authService = [[SASSHTunnelAuthService alloc] initWithSource:self keychain:[SAKeychainAccess make]];
		[tunnelConnection setRootObject:authService];
		
		
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

- (BOOL)failureDiagnosticsReady
{
	return standardErrorDrainCoordinator.failureDiagnosticsReady;
}

- (BOOL)connectionAttemptPending
{
	return standardErrorDrainCoordinator.connectionAttemptPending;
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
	
	

	parentWindow = theWindow;
	if (![NSBundle.mainBundle loadNibNamed:@"SSHQuestionDialog" owner:self topLevelObjects:nil]) {
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
	identityFilePath = [[NSString alloc] initWithString:expandedPath];
	return YES;
}

- (void)setRemoteSocketPath:(NSString *)thePath
{
	remoteSocketPath = [thePath copy];
}

/*
 * Sets the keychain name to use to retrieve the password.  This is the recommended and
 * secure way of supplying a password to the SSH tunnel.
 */
- (BOOL)setPasswordKeychainName:(NSString *)theName account:(NSString *)theAccount
{
    BOOL error = NO;
    passwordInKeychain = YES;

    if(theName != nil){
        keychainName = [[NSString alloc] initWithString:theName];
    }
    else{
        error = YES;
    }
    if(theAccount != nil){
        keychainAccount = [[NSString alloc] initWithString:theAccount];
    }
    else{
        error = YES;
    }

    if(error == YES){
        SPLog(@"keychainName or keychainAccount is nil");
    }

	return !error;
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
    SPLog(@"connect in ssh tunnel connection state = %i", connectionState);

	if (connectionState != SPMySQLProxyIdle) {
		SPLog(@"connect ssh connection is active, returning");
		return;
	}

	SASSHAttemptRequestDisposition requestDisposition = [standardErrorDrainCoordinator requestAttempt];
	if (requestDisposition == SASSHAttemptRequestDispositionQueued) {
		SPLog(@"connect queued until SSH failure diagnostics finish draining");
		return;
	}
	if (requestDisposition == SASSHAttemptRequestDispositionIgnored) {
		SPLog(@"connect ssh connection attempt is already starting, returning");
		return;
	}

	[self startConnectionAttempt];
}

- (void)startConnectionAttempt
{
	localPort = 0;

	[debugMessagesLock lock];
	[debugMessages removeAllObjects];
	[debugMessagesLock unlock];
	taskExitedUnexpectedly = NO;
	[promptCoordinator reset];

	[NSThread detachNewThreadWithName:@"SPSSHTunnel SSH binary communication task"
	                           target:self
	                         selector:@selector(launchTask:)
	                           object:nil];
}

- (void)completeStandardErrorDrain
{
	// Keep the final failure snapshot ahead of any queued attempt, which clears
	// the diagnostic buffer when it starts.
	if (delegate) [delegate performSelectorOnMainThread:stateChangeSelector withObject:self waitUntilDone:YES];

	if ([standardErrorDrainCoordinator completeDrainNotificationAndReservePendingAttempt]) {
		SPLog(@"starting SSH connection request queued during diagnostics drain");
		[self startConnectionAttempt];
	}
}

/*
 * Launch the NSTask which wraps the SSH process, and use it to initiate the
 * tunnel to the remote server.
 * Sets up and tears down as appropriate for usage in a background thread.
 */
- (void)launchTask:(id) dummy {
    
    SPLog(@"connection state = %i", connectionState);

	if (standardErrorDrainCoordinator.attemptCancellationRequested) {
		SPLog(@"launch task cancelled before SSH process setup");
		connectionState = SPMySQLProxyIdle;
		[standardErrorDrainCoordinator finishWithoutStandardErrorPipe];
		return;
	}

    if (connectionState != SPMySQLProxyIdle){
        SPLog(@"launch task ssh connection state != SPMySQLProxyIdle, returning");
		[standardErrorDrainCoordinator finishWithoutStandardErrorPipe];
        return;
    }

    if (task){
        SPLog(@"launch task already has task, aborting previous");
        [self abortTask];
    }

	@autoreleasepool {
		NSMutableArray *taskArguments;
		NSMutableDictionary *taskEnvironment;
		NSString *authenticationAppPath;

		connectionState = SPMySQLProxyConnecting;
		if (delegate) [delegate performSelectorOnMainThread:stateChangeSelector withObject:self waitUntilDone:NO];

		// Enforce a parent window being present for dialogs
		if (!parentWindow) {
			[self setLastError:@"SSH Tunnel started without a parent window.  A parent window must be present."];
			[standardErrorDrainCoordinator finishWithoutStandardErrorPipe];
			connectionState = SPMySQLProxyIdle;
			if (delegate) [delegate performSelectorOnMainThread:stateChangeSelector withObject:self waitUntilDone:NO];
            SPLog(@"launchTask SSH Tunnel started without a parent window, returning");
			return;
		}

		NSInteger connectionTimeout = [[[NSUserDefaults standardUserDefaults] objectForKey:SPConnectionTimeoutValue] integerValue];
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
				[self setLastError:NSLocalizedString(@"No local port could be allocated for the SSH Tunnel.", @"SSH tunnel could not be created because no local port could be allocated")];
				[standardErrorDrainCoordinator finishWithoutStandardErrorPipe];
				connectionState = SPMySQLProxyIdle;
				if (delegate) [delegate performSelectorOnMainThread:stateChangeSelector withObject:self waitUntilDone:NO];
                SPLog(@"launchTask No local port could be allocated for the SSH Tunnel, returning");

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
            // name is always set
            if (!IsEmpty(_value)){
                [taskArguments addObjectsFromArray:@[_name,_value]];
            }
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
			NSString *pathString = [NSString stringWithFormat:@"%@@%@:%ld", sshLogin?sshLogin:@"", sshHost, (long)(sshPort?sshPort:0)];
			NSString *hashedString = [pathString.sha256Hash substringToIndex:8];
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
        if(connectionTimeout > 0) {
            TA(@"-o",([NSString stringWithFormat:@"ConnectTimeout=%ld", (long)connectionTimeout]));
        }

		// Allow three password prompts
		TA(@"-o",@"NumberOfPasswordPrompts=3");

        if(user_defaults_get_bool(SPSSHConfigContainsUserKnownHostsFile) == NO){
            NSString *customKnownHostsFilePath = [[NSUserDefaults standardUserDefaults] stringForKey:SPSSHUsualKnownHostsFile];

            NSString *alertMessage = nil;

            // if not set, could be empty or @0
            if(IsEmpty(customKnownHostsFilePath) == NO && customKnownHostsFilePath.isNumeric == NO){
                SPLog(@"customKnownHostsFilePath set to: %@", customKnownHostsFilePath);
                if (![[NSFileManager defaultManager] isWritableFileAtPath:customKnownHostsFilePath]){

                    SPLog(@"ERROR: customKnownHostsFilePath NOT writable");

                    BOOL validFile = IsLocalFilePath(customKnownHostsFilePath);

                    if(validFile == YES){
                        alertMessage = [NSString stringWithFormat:NSLocalizedString(@"The selected known hosts file is not writable.\n\n%@\n\nPlease re-select the file in Sequel Ace's Preferences and try again.", @"known hosts not writable message"), customKnownHostsFilePath];
                    }
                    else{
                        alertMessage = [NSString stringWithFormat:NSLocalizedString(@"The selected known hosts file is invalid.\n\nPlease re-select the file in Sequel Ace's Preferences and try again.", @"known hosts is invalid message")];
                    }

                } else if ([customKnownHostsFilePath containsString:@"\""]) {
                    alertMessage = [NSString stringWithFormat:NSLocalizedString(@"The selected known hosts file contains a quote (\") in its file path which is not supported.\n\n%@\n\nPlease select a different file in Sequel Ace's Preferences or rename the file/path to remove the quote.", @"known hosts contains quote message"), customKnownHostsFilePath];
                }
            }
            else{
                // Use a KnownHostsFile in the sandbox folder
                customKnownHostsFilePath = [NSHomeDirectory() stringByAppendingPathComponent:SPSSHDefaultKnownHostsFile];
                if (![[NSFileManager defaultManager] isWritableFileAtPath:customKnownHostsFilePath]){
                    //Handle deleting an old known hosts file if it exists and we don't have permission to write
                    [[NSFileManager defaultManager] removeItemAtPath:customKnownHostsFilePath error:nil];
                    //Create new known hosts file
                    [[NSFileManager defaultManager] createFileAtPath:customKnownHostsFilePath contents:[@"" dataUsingEncoding:NSUTF8StringEncoding] attributes:nil];
                }
            }

            if(alertMessage != nil) {
                taskExitedUnexpectedly = YES;
                [self setLastError:alertMessage];
				[standardErrorDrainCoordinator finishWithoutStandardErrorPipe];
				connectionState = SPMySQLProxyIdle;

                if (delegate) [delegate performSelectorOnMainThread:stateChangeSelector withObject:self waitUntilDone:NO];
                // Run the run loop for a short time to ensure all task/pipe callbacks are dealt with
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];

                return;
            }

            TA(@"-o", [NSString stringWithFormat:@"UserKnownHostsFile=\"%@\"", [self prepareFilePathForSshCommand:customKnownHostsFilePath]]);
        }
        else{
            SPLog(@"the ssh config files should point to a known hosts file");
        }


		
		// Use a custom ssh config file
		NSString *sshConfigFile = [[NSUserDefaults standardUserDefaults] stringForKey:SPSSHConfigFile];
		
		// If the config is not set, use the default one
		if (sshConfigFile == nil) {
			sshConfigFile = [[NSBundle mainBundle] pathForResource:SPSSHConfigFile ofType:@""];
		}
		
		TA(@"-F", [self prepareFilePathForSshCommand:sshConfigFile]);

		if(![SPFileHandle fileHandleForReadingAtPath:sshConfigFile]) {
			SPLog(@"Cannot read sshConfigFile: %@",sshConfigFile);
		}

		// Specify an identity file if available
		if (identityFilePath) {
			TA(@"-i", [self prepareFilePathForSshCommand:identityFilePath]);
		}

		// If keepalive is set in the preferences, use the same value for the SSH tunnel
		if (useKeepAlive && keepAliveInterval) {
			TA(@"-o", @"TCPKeepAlive=yes");  // Enable TCP keepalive
			TA(@"-o", ([NSString stringWithFormat:@"ServerAliveInterval=%ld", (long)ceil(keepAliveInterval)]));
			TA(@"-o", @"ServerAliveCountMax=3");  // Increase max retries before disconnecting
			TA(@"-o", @"ConnectTimeout=10");  // Add a shorter connect timeout
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
		if ([remoteSocketPath length]) {
			TA(@"-L", ([NSString stringWithFormat:@"%ld:%@", (long)localPort, remoteSocketPath]));
		}
		else if (useHostFallback) {
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

		// use default shell so ProxyJump commands run by ssh stay inside the sandbox
		[taskEnvironment removeObjectForKey:@"SHELL"];

		[taskEnvironment safeSetObject:authenticationAppPath forKey:@"SSH_ASKPASS"];
		[taskEnvironment safeSetObject:@":0" forKey:@"DISPLAY"];
		[taskEnvironment safeSetObject:tunnelConnectionName forKey:@"SP_CONNECTION_NAME"];
		[taskEnvironment safeSetObject:tunnelConnectionVerifyHash forKey:@"SP_CONNECTION_VERIFY_HASH"];
		if (passwordInKeychain) {
			// The keychain item's name and account deliberately stay out of
			// the environment: the assistant no longer reads the keychain —
			// it asks getPasswordWithVerificationHash: over the connection,
			// and the app resolves the item at ask time.
            [taskEnvironment safeSetObject:[[NSNumber numberWithInteger:SPSSHPasswordUsesKeychain] stringValue] forKey:@"SP_PASSWORD_METHOD"];
		} else if (password) {
			[taskEnvironment safeSetObject:[[NSNumber numberWithInteger:SPSSHPasswordAsksUI] stringValue] forKey:@"SP_PASSWORD_METHOD"];
		} else {
			[taskEnvironment safeSetObject:[[NSNumber numberWithInteger:SPSSHPasswordNone] stringValue] forKey:@"SP_PASSWORD_METHOD"];
		}
		[task setEnvironment:taskEnvironment];

        SPLog(@"taskEnvironment: %@",taskEnvironment);

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
		[[standardError fileHandleForReading] waitForDataInBackgroundAndNotify]; // TODO: leaks

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
			[task SPlaunch]; //throws for invalid paths, missing +x permission
			if (standardErrorDrainCoordinator.attemptCancellationRequested) {
				[self abortTask];
			}

			// Listen for output
			[task waitUntilExit]; // TODO: this leaks
		}
		@catch (NSException *e) {
			connectionState = SPMySQLProxyLaunchFailed;
            SPLog(@"launchTask SSH Tunnel NSException, connectionState = SPMySQLProxyLaunchFailed");
			// No child owns the pipe after a launch failure, so close the local
			// writer to let the pending data-available read observe EOF.
			[[standardError fileHandleForWriting] closeFile];

			// Log the exception. Could be improved by showing a dedicated alert instead
			[debugMessagesLock lock];
			[debugMessages addObject:[NSString stringWithFormat:@"%@: %@\n", [e name], [e reason]]];
			[debugMessagesLock unlock];
            SPLog(@"launchTask SSH Tunnel NSException debugMessages = %@", [self debugMessages]);

		}

		// On tunnel close, clean up, ready for re-use if the delegate reconnects.
		
		[standardErrorDrainCoordinator beginStandardErrorDrain];
		
		// ssh is gone, so nobody is waiting for a prompt that may still be up;
		// dismiss it before the diagnostics drain below, not after it
		[self cancelPendingPrompt];

		// If the task closed unexpectedly, alert appropriately
		if (connectionState != SPMySQLProxyIdle) {
			connectionState = SPMySQLProxyIdle;
			taskExitedUnexpectedly = YES;
			[self setLastError:NSLocalizedString(@"The SSH Tunnel has unexpectedly closed.", @"SSH tunnel unexpectedly closed")];
            SPLog(@"SSH Tunnel has unexpectedly closed");
		}

		if (![standardErrorDrainCoordinator finishAfterStandardErrorDrain]) {
			SPLog(@"Timed out waiting for SSH stderr EOF; using the diagnostics collected so far");
		}

		[[NSNotificationCenter defaultCenter] removeObserver:self
		                                                name:NSFileHandleDataAvailableNotification
		                                              object:nil];

		// A stderr callback may have observed an intermediate state while draining,
		// but an exited task is always idle. Notify once more only after the immutable
		// diagnostics snapshot is safe to take.
		connectionState = SPMySQLProxyIdle;
		[self performSelectorOnMainThread:@selector(completeStandardErrorDrain)
		                       withObject:nil
		                    waitUntilDone:NO];

		
		
	}
}

/*
 * Disconnects the tunnel
 */
- (void)disconnect
{
    SPLog(@"ssh tunnel disconnect");
	[self disconnectPreservingQueuedReconnect:NO];
}

- (void)disconnectForReconnect
{
	SPLog(@"ssh tunnel disconnect for reconnect");
	[self disconnectPreservingQueuedReconnect:YES];
}

- (void)disconnectPreservingQueuedReconnect:(BOOL)preserveQueuedReconnect
{
	BOOL cancelledQueuedOrRunningAttempt = preserveQueuedReconnect
		? NO
		: [standardErrorDrainCoordinator cancelPendingOrRunningAttempt];

	// Fail any prompt the assistant is blocked on closed, whatever the state
	[self cancelPendingPrompt];

    if (connectionState == SPMySQLProxyIdle){
		if (preserveQueuedReconnect) {
			SPLog(@"internal reconnect preserved the queued SSH attempt");
		} else if (cancelledQueuedOrRunningAttempt) {
			SPLog(@"disconnect cancelled a queued or not-yet-launched SSH attempt");
		} else {
			SPLog(@"disconnect connectionState == SPMySQLProxyIdle, returning without disconnecting");
		}
        return;
    }

	// If there's a delegate set, clear it to prevent unexpected state change messaging
//	if (delegate) {
//		delegate = nil;
//		stateChangeSelector = NULL;
//	}

	// Before terminating the tunnel, check that it's actually running. This is to accommodate tunnels which
	// suddenly disappear as a result of network disconnections. 
    if (task) {
        SPLog(@"disconnect found task, aborting");
        [self abortTask];
    }
}

/*
 * Abort the currently running task and null it out
 */
-(void)abortTask
{
    SPLog(@"Aborting task");
    [self cancelPendingPrompt];
    if (task){
        if ([task isRunning]){
            SPLog(@"Task is running - calling terminate");
            [task SPterminate];
        }
        SPLog(@"Nilling out task");
//        task = nil;
    }
}

/*
 * Processes messages recieved from the SSH task.  These may be received singly
 * or several stuck together.
 */
- (void)standardErrorHandler:(NSNotification*)aNotification
{
	NSData *availableData;
	NSString *notificationText;
	NSEnumerator *enumerator;
	NSArray *messages;
	NSString *message;

	availableData = [[aNotification object] availableData];
	notificationText = [[NSString alloc] initWithData:availableData encoding:NSASCIIStringEncoding];

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

			// Terminal states are published once by launchTask: after stderr has
			// drained, so automatic reconnects cannot start during cleanup.
			if ([message rangeOfString:@"bind: Address already in use"].location != NSNotFound) {
				[standardErrorDrainCoordinator beginStandardErrorDrain];
				connectionState = SPMySQLProxyIdle;
                [self abortTask];
				[self setLastError:NSLocalizedString(@"The SSH Tunnel was unable to bind to the local port. This error may occur if you already have an SSH connection to the same server and are using a 'LocalForward' setting in your SSH configuration.\n\nWould you like to fall back to a standard connection to localhost in order to use the existing tunnel?", @"SSH tunnel unable to bind to local port message")];
			}

			if ([message rangeOfString:@"closed by remote host." ].location != NSNotFound) {
				[standardErrorDrainCoordinator beginStandardErrorDrain];
				connectionState = SPMySQLProxyIdle;
                [self abortTask];
				[self setLastError:NSLocalizedString(@"The SSH Tunnel was closed 'by the remote host'. This may indicate a networking issue or a network timeout.", @"SSH tunnel was closed by remote host message")];
			}
			if ([message rangeOfString:@"Permission denied (" ].location != NSNotFound || [message rangeOfString:@"No more authentication methods to try" ].location != NSNotFound) {
				[standardErrorDrainCoordinator beginStandardErrorDrain];
				connectionState = SPMySQLProxyIdle;
                [self abortTask];
				[self setLastError:NSLocalizedString(@"The SSH Tunnel could not authenticate with the remote host. Please check your password and ensure you still have access.", @"SSH tunnel authentication failed message")];
			}
			if ([message rangeOfString:@"connect failed: Connection refused" ].location != NSNotFound) {
				connectionState = SPMySQLProxyForwardingFailed;
				[self setLastError:NSLocalizedString(@"The SSH Tunnel was established successfully, but could not forward data to the remote port as the remote port refused the connection.", @"SSH tunnel forwarding port connection refused message")];
			}
			if ([message rangeOfString:@"Operation timed out" ].location != NSNotFound) {
				[standardErrorDrainCoordinator beginStandardErrorDrain];
				connectionState = SPMySQLProxyIdle;
                [self abortTask];
				[self setLastError:[NSString stringWithFormat:NSLocalizedString(@"The SSH Tunnel was unable to connect to host %@, or the request timed out.\n\nBe sure that the address is correct and that you have the necessary privileges, or try increasing the connection timeout (currently %ld seconds).", @"SSH tunnel failed or timed out message"), sshHost, (long)[[[NSUserDefaults standardUserDefaults] objectForKey:SPConnectionTimeoutValue] integerValue]]];
			}
		}
	}

	// NSFileHandle data-available notifications are one-shot. Keep re-arming
	// after terminal-state detection so trailing stderr is consumed; an empty
	// read is the pipe's EOF signal and ends the chain.
	if ([standardErrorDrainCoordinator recordStandardErrorReadWithByteCount:[availableData length]]) {
		[[standardError fileHandleForReading] waitForDataInBackgroundAndNotify]; // TODO: leaks
	}
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

#pragma mark - Connection surface

/*
 * The three methods the tunnel assistant may call over the connection. They
 * stay declared in the public header so the assistant can type its proxy, but
 * the object actually vended is authService (SSH tunnel IPC plan, Step 1): it
 * owns the verification-hash check, the keychain lookups and the cancelled-
 * prompt refusal, and calls back into the SASSHTunnelAuthSource methods below
 * for tunnel state and the blocking sheets.
 */
- (NSString *)getPasswordWithVerificationHash:(NSString *)theHash
{
	return [authService getPasswordWithVerificationHash:theHash];
}

- (BOOL)getResponseForQuestion:(NSString *)theQuestion
{
	return [authService getResponseForQuestion:theQuestion];
}

- (NSString *)getPasswordForQuery:(NSString *)theQuery verificationHash:(NSString *)theHash
{
	return [authService getPasswordForQuery:theQuery verificationHash:theHash];
}

#pragma mark - SASSHTunnelAuthSource

- (NSString *)verificationHash
{
	return tunnelConnectionVerifyHash;
}

- (NSString *)heldPassword
{
	return password;
}

- (BOOL)usesKeychainPassword
{
	return passwordInKeychain;
}

- (NSString *)keychainItemName
{
	return keychainName;
}

- (NSString *)keychainItemAccount
{
	return keychainAccount;
}

/*
 * Runs the yes/no question sheet and blocks the calling (connection) thread
 * until it is answered, or until teardown dismisses it with "no". Used by the
 * SSH_ASKPASS flow to deal with situations like host key mismatches.
 */
- (BOOL)promptForResponseToQuestion:(NSString *)theQuestion
{
	// Lock the answer available lock
	[[answerAvailableLock onMainThread] lock];

	// Request an answer on the main thread (UI stuff must be done on main thread)
	[self performSelectorOnMainThread:@selector(workerGetResponseForQuestion:) withObject:theQuestion waitUntilDone:YES];

	// Wait for closeSSHQuestionSheet: to unlock the lock, indicating an answer is available
	[answerAvailableLock lock];

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

	// Teardown got here first, or ssh is already gone: answer "no" unseen
	if (![promptCoordinator shouldPresentPromptWhileSSHRunning:(task != nil && [task isRunning])]) {
		requestedResponse = NO;
		[answerAvailableLock unlock];
		return;
	}

	// set up the question window
	[sshQuestionText setStringValue:theQuestion];
	questionTextSize = [[sshQuestionText cell] cellSizeForBounds:NSMakeRect(0, 0, [sshQuestionText bounds].size.width, 500)];
	windowFrameRect = [sshQuestionDialog frame];
	windowFrameRect.size.height = ((questionTextSize.height < 100)?100:questionTextSize.height) + 70 + ([sshPasswordDialog isSheet]?0:22);
	[sshQuestionDialog setFrame:windowFrameRect display:NO];

	//show the question window
	[promptCoordinator promptDidPresentWithDismisser:^{
		// Teardown: answer "no" without the user
		self->requestedResponse = NO;
		[NSApp endSheet:self->sshQuestionDialog];
		[self->sshQuestionDialog orderOut:nil];
		[[NSApplication sharedApplication] abortModal];
		[[self->answerAvailableLock onMainThread] unlock];
	}];
	[parentWindow beginSheet:sshQuestionDialog completionHandler:nil];
	[[NSApplication sharedApplication] runModalForWindow:sshQuestionDialog];
}

/*
 * Ends an existing modal session
 */
- (IBAction)closeSSHQuestionSheet:(id)sender
{
	requestedResponse = [sender tag] == 1 ? YES : NO;
	[promptCoordinator promptDidClose];
	[NSApp endSheet:sshQuestionDialog];
	[sshQuestionDialog orderOut:nil];
	[[NSApplication sharedApplication] abortModal];
	[[answerAvailableLock onMainThread] unlock];
}

/*
 * Runs the password sheet and blocks the calling (connection) thread until it
 * is answered, cancelled, or dismissed by teardown. Used by the SSH_ASKPASS
 * flow for key passphrases and any other prompt ssh raises.
 */
- (NSString *)promptForPasswordForQuery:(NSString *)theQuery
{
	// Lock the answer available lock
	[[answerAvailableLock onMainThread] lock];

	// Request password on the main thread (UI stuff must be done on main thread)
	[self performSelectorOnMainThread:@selector(workerGetPasswordForQuery:) withObject:theQuery waitUntilDone:YES];

	// Wait for closeSSHPasswordSheet: to unlock the lock, indicating an answer is available
	[answerAvailableLock lock];

	// Save the answer
	NSString *thePassword = nil;
	if (requestedPassphrase) {
		thePassword = [NSString stringWithString:requestedPassphrase];
		
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

	// Teardown got here first, or ssh is already gone: refuse unseen
	if (![promptCoordinator shouldPresentPromptWhileSSHRunning:(task != nil && [task isRunning])]) {
		requestedPassphrase = nil;
		[answerAvailableLock unlock];
		return;
	}

	// Work out whether a passphrase is being requested, extracting the key name
    NSString *keyName = [theQuery captureGroupForRegex:@"^\\s*Enter passphrase for key \\'(.*)\\':\\s*$"];

	if (keyName.length > 0) {
        SPLog(@"keyName: %@", keyName);
		[sshPasswordText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Enter your password for the SSH key\n\"%@\"", @"SSH key password prompt"), keyName]];
		[sshPasswordKeychainCheckbox setHidden:NO];
		currentKeyName = keyName;
	} 
	else {
        SPLog(@"key not found in [%@]", theQuery);
		[sshPasswordText setStringValue:theQuery];
		[sshPasswordKeychainCheckbox setHidden:YES];
		currentKeyName = nil;
	}

	// Request the password, sizing the window appropriately to fit the query
	queryTextSize = [[sshPasswordText cell] cellSizeForBounds:NSMakeRect(0, 0, [sshPasswordText bounds].size.width, 500)];
	windowFrameRect = [sshPasswordDialog frame];
	windowFrameRect.size.height = ((queryTextSize.height < 40)?40:queryTextSize.height) + 140 + ([sshPasswordDialog isSheet]?0:22);
	
	[sshPasswordDialog setFrame:windowFrameRect display:NO];
	[promptCoordinator promptDidPresentWithDismisser:^{
		// Teardown: refuse without the user, and without marking a user cancel
		self->requestedPassphrase = nil;
		[self->sshPasswordField setStringValue:@""];
		[NSApp endSheet:self->sshPasswordDialog];
		[self->sshPasswordDialog orderOut:nil];
		[[NSApplication sharedApplication] abortModal];
		[[self->answerAvailableLock onMainThread] unlock];
	}];
	[parentWindow beginSheet:sshPasswordDialog completionHandler:nil];
	[[NSApplication sharedApplication] runModalForWindow: sshPasswordDialog];
}
 
/*
 * Ends an existing modal session
 */
- (IBAction)closeSSHPasswordSheet:(id)sender
{
	requestedResponse = [sender tag]==1 ? YES : NO;
	[promptCoordinator promptDidClose];
	
	[NSApp endSheet:sshPasswordDialog];
	[sshPasswordDialog orderOut:nil];
	[[NSApplication sharedApplication] abortModal];

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
		if (currentKeyName && [sshPasswordKeychainCheckbox state] == NSControlStateValueOn) {
			id<SAKeychainProviding> keychain = [SAKeychainAccess make];
			[keychain addPassword:thePassword forName:@"SSH" account:currentKeyName withLabel:[NSString stringWithFormat:@"SSH: %@", currentKeyName]];
			
		}
	}
	
	if (!requestedPassphrase) passwordPromptCancelled = YES;

	[[answerAvailableLock onMainThread] unlock];
}

/*
 * Fails any prompt the assistant is blocked on closed, without marking it as
 * cancelled by the user (so the real failure reason still reaches the
 * connection controller). Called on every teardown path so a tunnel that goes
 * away mid-prompt does not leave a sheet up and the assistant blocked until ssh
 * gives up (SSH tunnel IPC plan, Step 1). The decision — dismiss a presented
 * sheet, or latch a prompt still on its way to the main thread — is
 * SASSHTunnelPromptCoordinator's; the dismissal itself is the block handed over
 * when the sheet was presented.
 */
- (void)cancelPendingPrompt
{
	[promptCoordinator cancelPendingPrompt];
}

/*
 * Escape spaces and special characters in path
 */
- (NSString *)prepareFilePathForSshCommand:(NSString *)thePath
{
    return [thePath stringByRemovingPercentEncoding];
}


#pragma mark -

- (void)dealloc
{
	[promptCoordinator invalidate];
	delegate = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self disconnect];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	
	[tunnelConnection invalidate];
	
	[self setLastError:nil];
	
	[answerAvailableLock tryLock];
	[answerAvailableLock unlock];
    
    NSLog(@"Dealloc called %s", __FILE_NAME__);
}

@end

#pragma mark -

unsigned short getRandomPort(void) {
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
