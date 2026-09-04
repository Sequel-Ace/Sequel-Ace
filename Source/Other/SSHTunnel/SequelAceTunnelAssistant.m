//
//  SequelAceTunnelAssistant.m
//  sequel-pro
//
//  Created by Rowan Beentje on May 4, 2009.
//  Copyright (c) 2009 Rowan Beentje. All rights reserved.
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

#import <Cocoa/Cocoa.h>

#import "SPSSHTunnel.h"
#import "SPConstants.h"
#import "sequel-ace-Swift.h"


int main(int argc, const char *argv[])
{
	@autoreleasepool {
		// The socket transport (SSH tunnel IPC plan, Step 3) is handled entirely
		// in Swift; everything below is the Distributed Objects path, kept
		// verbatim until Step 5 deletes it.
		if ([SASSHTunnelAssistantSocketMain isSelectedInEnvironment]) {
			return [SASSHTunnelAssistantSocketMain run];
		}

		NSDictionary *environment = [[NSProcessInfo processInfo] environment];
		NSString *argument = nil;
		SPSSHTunnel *sequelProTunnel;
		NSString *connectionName = [environment objectForKey:@"SP_CONNECTION_NAME"];
		NSString *verificationHash = [environment objectForKey:@"SP_CONNECTION_VERIFY_HASH"];

		if (![environment objectForKey:@"SP_PASSWORD_METHOD"]) {
			return 1;
		}

		if (argc > 1) {
			argument = [[NSString alloc] initWithCString:argv[1] encoding:NSUTF8StringEncoding];
		}

		// Check if we're being asked a question and respond if so
		if (argument && [argument rangeOfString:@" (yes/no"].location != NSNotFound) {

			sequelProTunnel = (SPSSHTunnel *)[NSConnection rootProxyForConnectionWithRegisteredName:connectionName host:nil];

			if (!sequelProTunnel) {
				NSLog(@"SSH Tunnel: unable to connect to Sequel Ace to show SSH question");
				return 1;

			}

			BOOL response = [sequelProTunnel getResponseForQuestion:argument];

			if (response) {
				printf("yes\n");
			}
			else {
				printf("no\n");
			}

			return 0;
		}

		// Check whether we're being asked for a standard SSH password - if so, request it from the app.
		if (argument && [[argument lowercaseString] rangeOfString:@"password:"].location != NSNotFound ) {
			NSInteger passwordMethod = [[environment objectForKey:@"SP_PASSWORD_METHOD"] integerValue];

			// Both password methods ask the app over the connection: it
			// either holds the password in memory (AsksUI) or resolves it
			// from the keychain at ask time (UsesKeychain). This helper no
			// longer reads the keychain itself — see the keychain migration
			// plan, Step 3.
			if (passwordMethod == SPSSHPasswordUsesKeychain || passwordMethod == SPSSHPasswordAsksUI) {
				NSString *password;

				if (!connectionName || !verificationHash) {
					NSLog(@"SSH Tunnel: internal authentication specified but insufficient details supplied");
					return 1;
				}

				sequelProTunnel = (SPSSHTunnel *)[NSConnection rootProxyForConnectionWithRegisteredName:connectionName host:nil];

				if (!sequelProTunnel) {
					NSLog(@"SSH Tunnel: unable to connect to Sequel Ace for internal authentication");
					return 1;
				}

				password = [sequelProTunnel getPasswordWithVerificationHash:verificationHash];

				if (password) {
					printf("%s\n", [password UTF8String]);
					return 0;
				}

				// If retrieving the password failed, log an error and fall
				// back to requesting from the GUI, explaining per method.
				if (passwordMethod == SPSSHPasswordUsesKeychain) {
					NSLog(@"SSH Tunnel: specified keychain password not found");
					argument = [NSString stringWithFormat:NSLocalizedString(@"The SSH password could not be loaded from the keychain; please enter the SSH password for %@:", @"Prompt for SSH password when keychain fetch failed"), connectionName];
				}
				else {
					NSLog(@"SSH Tunnel: unable to successfully request password from Sequel Ace for internal authentication");
					argument = [NSString stringWithFormat:NSLocalizedString(@"The SSH password could not be loaded; please enter the SSH password for %@:", @"Prompt for SSH password when direct fetch failed"), connectionName];
				}
			}
		}

		// Key passphrases, and any other question SSH asks, go to the app's
		// GUI prompt via getPasswordForQuery: — the app checks the stored
		// "SSH"/<key name> passphrase item before showing its prompt, which
		// used to be this helper's keychain read. Also covers RSA SecurID.
		if (argument) {
			NSString *passphrase;

			if (!verificationHash) {
				NSLog(@"SSH Tunnel: key passphrase authentication required but insufficient details supplied to connect to GUI");
				return 1;
			}

			sequelProTunnel = (SPSSHTunnel *)[NSConnection rootProxyForConnectionWithRegisteredName:connectionName host:nil];

			if (!sequelProTunnel) {
				NSLog(@"SSH Tunnel: unable to connect to Sequel Ace to show SSH question");
				return 1;
			}

			passphrase = [sequelProTunnel getPasswordForQuery:argument verificationHash:verificationHash];

			if (!passphrase) {
				return 1;
			}

			printf("%s\n", [passphrase UTF8String]);
			return 0;
		}
	}
	
	return 1;
}
