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

#import "SPKeychain.h"
#import "SPSSHTunnel.h"
#import "SPConstants.h"
#import "sequel-ace-Swift.h"


int main(int argc, const char *argv[])
{
	@autoreleasepool {
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

		// Check whether we're being asked for a standard SSH password - if so, use the app-entered value.
		if (argument && [[argument lowercaseString] rangeOfString:@"password:"].location != NSNotFound ) {

			// If the password method is set to use the keychain, use the supplied keychain name to
			// request the password
			if ([[environment objectForKey:@"SP_PASSWORD_METHOD"] integerValue] == SPSSHPasswordUsesKeychain) {
				SPKeychain *keychain;
				// think we can risk these stringByRemovingPercentEncoding rather than linking swift
				NSString *keychainName = [[environment objectForKey:@"SP_KEYCHAIN_ITEM_NAME"] stringByRemovingPercentEncoding];
				NSString *keychainAccount = [[environment objectForKey:@"SP_KEYCHAIN_ITEM_ACCOUNT"] stringByRemovingPercentEncoding];

				if (!keychainName || !keychainAccount) {
					NSLog(@"SSH Tunnel: keychain authentication specified but insufficient internal details supplied");
					return 1;
				}

				keychain = [[SPKeychain alloc] init];

				if ([keychain passwordExistsForName:keychainName account:keychainAccount]) {
					printf("%s\n", [[keychain getPasswordForName:keychainName account:keychainAccount] UTF8String]);
					return 0;
				}

				// If retrieving the password failed, log an error and fall back to requesting from the GUI
				NSLog(@"SSH Tunnel: specified keychain password not found");

				argument = [NSString stringWithFormat:NSLocalizedString(@"The SSH password could not be loaded from the keychain; please enter the SSH password for %@:", @"Prompt for SSH password when keychain fetch failed"), connectionName];
			}

			// If the password method is set to request the password from the tunnel instance, do so.
			if ([[environment objectForKey:@"SP_PASSWORD_METHOD"] integerValue] == SPSSHPasswordAsksUI) {
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

				// If retrieving the password failed, log an error and fall back to requesting from the GUI
				NSLog(@"SSH Tunnel: unable to successfully request password from Sequel Ace for internal authentication");

				argument = [NSString stringWithFormat:NSLocalizedString(@"The SSH password could not be loaded; please enter the SSH password for %@:", @"Prompt for SSH password when direct fetch failed"), connectionName];
			}
		}


		// Check whether we're being asked for a SSH key passphrase
		if (argument && [[argument lowercaseString] rangeOfString:@"enter passphrase for"].location != NSNotFound ) {
			NSString *passphrase;

            NSString *keyName = [argument captureGroupForRegex:@"^\\s*Enter passphrase for key \\'(.*)\\':\\s*$"];

			if (keyName.length > 0) {

                SPLog(@"keyName: %@", keyName);

				// Check whether the passphrase is in the keychain, using standard OS X sshagent name and account
				SPKeychain *keychain = [[SPKeychain alloc] init];

				if ([keychain passwordExistsForName:@"SSH" account:keyName]) {
					printf("%s\n", [[keychain getPasswordForName:@"SSH" account:keyName] UTF8String]);
					return 0;
				}
			}
            else{
                SPLog(@"key not found in [%@]", argument);
            }

			// Not found in the keychain - we need to ask the GUI.

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

		// SSH has some other question. Show that directly to the user. This is an attempt to support RSA SecurID
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
