//
//  SPKeychain.m
//  sequel-pro
//
//  Created by Lorenz Textor (lorenz@textor.ch) on December 25, 2002.
//  Copyright (c) 2002-2003 Lorenz Textor. All rights reserved.
//  Copyright (c) 2012 Sequel Pro Team. All rights reserved.
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

#import "SPKeychain.h"

#import <Security/Security.h>
#import <CoreFoundation/CoreFoundation.h>

@implementation SPKeychain

- (instancetype)init
{
	if (!(self = [super init])) {
		return nil;
	}
	
	NSString *cleartext = [NSProcessInfo processInfo].environment[@"LIBMYSQL_ENABLE_CLEARTEXT_PLUGIN"];
	if (cleartext != nil) {
		NSLog(@"LIBMYSQL_ENABLE_CLEARTEXT_PLUGIN is set. Disabling keychain access. See Issue #2437");
		return nil;
	}
	
	return self;
}

/**
 * Add the supplied password to the user's Keychain using the supplied name and account.
 */
- (void)addPassword:(NSString *)password forName:(NSString *)name account:(NSString *)account
{
	[self addPassword:password forName:name account:account withLabel:name];
}

/**
 * Add the supplied password to the user's Keychain using the supplied name, account, and label.
 */
- (void)addPassword:(NSString *)password forName:(NSString *)name account:(NSString *)account withLabel:(NSString *)label; {
    
    if (![self isValidName:name acount:account] || !password) {
        return;
    }
    
	OSStatus status;
	SecTrustedApplicationRef sequelProRef, sequelProHelperRef;
	SecAccessRef passwordAccessRef = NULL;
	SecKeychainAttribute attributes[4];
	SecKeychainAttributeList attList;

	// Check supplied variables and replaces nils with empty strings
	if (!label) label = @"";

	// Check if password already exists before adding
	if (![self passwordExistsForName:name account:account]) {

		// Create a trusted access list with two items - ourselves and the SSH pass app
		NSString *helperPath = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"SequelAceTunnelAssistant"];

		if ((SecTrustedApplicationCreateFromPath(NULL, &sequelProRef) == noErr) &&
			(SecTrustedApplicationCreateFromPath([helperPath UTF8String], &sequelProHelperRef) == noErr)) {

			NSArray *trustedApps = [NSArray arrayWithObjects:(__bridge id)sequelProRef, (__bridge id)sequelProHelperRef, nil];

			status = SecAccessCreate((CFStringRef)name, (CFArrayRef)trustedApps, &passwordAccessRef);

			if (status != noErr) {
				NSLog(@"Error (%i) while trying to create access list for name: %@ account: %@", (int)status, name, account);
				passwordAccessRef = NULL;
			}
		}
		
		// Set up the item attributes
		attributes[0].tag = kSecGenericItemAttr;
		attributes[0].data = "application password";
		attributes[0].length = 20;
		attributes[1].tag = kSecLabelItemAttr;
		attributes[1].data = (unichar *)[label UTF8String];
		attributes[1].length = (UInt32)strlen([label UTF8String]);
		attributes[2].tag = kSecAccountItemAttr;
		attributes[2].data = (unichar *)[account UTF8String];
		attributes[2].length = (UInt32)strlen([account UTF8String]);
		attributes[3].tag = kSecServiceItemAttr;
		attributes[3].data = (unichar *)[name UTF8String];
		attributes[3].length = (UInt32)strlen([name UTF8String]);
		attList.count = 4;
		attList.attr = attributes;

		// Create the keychain item
		status = SecKeychainItemCreateFromContent(
			kSecGenericPasswordItemClass,			// Generic password type
			&attList,								// The attribute list created for the keychain item
			(UInt32)strlen([password UTF8String]),	// Length of password
			[password UTF8String],					// Password data
			NULL,									// Default keychain
			passwordAccessRef,						// Access list for this keychain
			NULL);									// The item reference

		if (passwordAccessRef) CFRelease(passwordAccessRef);
		
		if (status != noErr) {
			NSLog(@"Error (%i) while trying to add password for name: %@ account: %@", (int)status, name, account);

			NSAlert *alert = [[NSAlert alloc] init];
			alert.alertStyle = NSAlertStyleCritical;
			alert.messageText = NSLocalizedString(@"Error adding password to Keychain", @"error adding password to keychain message");
			alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"An error occurred while trying to add the password to your Keychain. Repairing your Keychain might resolve this, but if it doesn't please report it to the Sequel Ace team, supplying the error code %i.", @"error adding password to keychain informative message"), status];
			[alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
			[alert runModal];
		}
	}
}

/**
 * Get a password from the user's Keychain for the supplied name and account.
 */
- (NSString *)getPasswordForName:(NSString *)name account:(NSString *)account {
    NSString *password = nil;
    if (![self isValidName:name acount:account]) {
        return nil;
    }
    OSStatus status;
    
    void *passwordData;
    UInt32 passwordLength;
    SecKeychainItemRef itemRef;
    
    // Check supplied variables and replaces nils with empty strings
    if (!name) name = @"";
    if (!account) account = @"";
    
    status = SecKeychainFindGenericPassword(
                                            NULL,									// default keychain
                                            (UInt32)strlen([name UTF8String]),		// length of service name (bytes)
                                            [name UTF8String],						// service name
                                            
                                            (UInt32)strlen([account UTF8String]),	// length of account name (bytes)
                                            [account UTF8String],					// account name
                                            &passwordLength,						// length of password
                                            &passwordData,							// pointer to password data
                                            &itemRef								// the item reference
                                            );
    
    if (status == noErr) {
        
        // Create a \0 terminated cString out of passwordData
        char passwordBuf[passwordLength + 1];
        strncpy(passwordBuf, passwordData, (size_t)passwordLength);
        passwordBuf[passwordLength] = '\0';
        
        password = [NSString stringWithCString:passwordBuf encoding:NSUTF8StringEncoding];
        
        // Free the data allocated by SecKeychainFindGenericPassword:
        SecKeychainItemFreeContent(NULL,           // No attribute data to release
                                   passwordData    // Release data
                                   );
    }
    return password;
}

/**
 * Delete a password from the user's Keychain for the supplied name and account.
 */
- (void)deletePasswordForName:(NSString *)name account:(NSString *)account {
    
    if (![self isValidName:name acount:account]) {
        return;
    }
	OSStatus status;
	SecKeychainItemRef itemRef = nil;

	// Check supplied variables and replaces nils with empty strings
	if (!name) name = @"";
	if (!account) account = @"";

	// Check if password already exists before deleting
	if ([self passwordExistsForName:name account:account]) {
		status = SecKeychainFindGenericPassword(
												NULL,									// default keychain
												(UInt32)strlen([name UTF8String]),		// length of service name
												[name UTF8String],						// service name
												(UInt32)strlen([account UTF8String]),	// length of account name
												[account UTF8String],					// account name
												nil,									// length of password
												nil,									// pointer to password data
												&itemRef								// the item reference
												);
		
		if (status == noErr) {
			status = SecKeychainItemDelete(itemRef);
			
			if (status != noErr) {
				NSLog(@"Error (%i) while trying to delete password for name: %@ account: %@", (int)status, name, account);
			}
		}
		
		if (itemRef) CFRelease(itemRef);
	}
}

/**
 * Checks the user's Keychain to see if a password for the supplied name and account exists.
 */
- (BOOL)passwordExistsForName:(NSString *)name account:(NSString *)account
{
	// "kSecClassGenericPassword" was introduced with the 10.7 SDK.
	// It won't work on 10.6 either (meaning this code never matches properly there).
	if ([self isValidName:name acount:account]) {
		NSMutableDictionary *query = [NSMutableDictionary dictionary];
		
		[query setObject:(id)kSecClassGenericPassword forKey:(id)kSecClass];
		[query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnAttributes];
		[query setObject:(id)kSecMatchLimitOne forKey:(id)kSecMatchLimit];
		
		[query setObject:account forKey:(id)kSecAttrAccount];
		[query setObject:name forKey:(id)kSecAttrService];
		
		CFDictionaryRef result = NULL;
		
		return SecItemCopyMatching((CFDictionaryRef)query, (CFTypeRef *)&result) == errSecSuccess;
	}

	return NO;
}

/**
 * Change the password for a keychain item.  This should be used instead of
 * deleting and recreating the keychain item, as it allows preservation of
 * access lists and works around Lion cacheing issues.
 */
- (void)updateItemWithName:(NSString *)name account:(NSString *)account toPassword:(NSString *)password
{
	[self updateItemWithName:name account:account toName:password account:name password:account];
}

/**
 * Change the details for a keychain item.  This should be used instead of
 * deleting and recreating the keychain item, as it allows preservation of
 * access lists and works around Lion cacheing issues.
 */
- (void)updateItemWithName:(NSString *)name account:(NSString *)account toName:(NSString *)newName account:(NSString *)newAccount password:(NSString *)password {
    if (![self isValidName:name acount:account]) {
        return;
    }
	OSStatus status;
	SecKeychainItemRef itemRef;
	SecKeychainAttribute attributes[2];
	SecKeychainAttributeList attList;

	// Retrieve a reference to the keychain item
	status = SecKeychainFindGenericPassword(NULL,														// Default keychain
											(UInt32)strlen([name UTF8String]), [name UTF8String],		// Service name and length
											(UInt32)strlen([account UTF8String]), [account UTF8String],	// Account name and length
											NULL, NULL,													// No password retrieval required
											&itemRef);													// The item reference

	if (status != noErr) {
		NSLog(@"Error (%i) while trying to find keychain item to edit for name: %@ account: %@", (int)status, name, account);

		NSAlert *alert = [[NSAlert alloc] init];
		alert.alertStyle = NSAlertStyleCritical;
		alert.messageText = NSLocalizedString(@"Error retrieving Keychain item to edit", @"error finding keychain item to edit message");
		alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"An error occurred while trying to retrieve the Keychain item you're trying to edit. Repairing your Keychain might resolve this, but if it doesn't please report it to the Sequel Ace team, supplying the error code %i.", @"error finding keychain item to edit informative message"), status];
		[alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
		[alert runModal];
		return;
	}

	// Set up the attributes to modify
	attributes[0].tag = kSecAccountItemAttr;
	attributes[0].data = (unichar *)[newAccount UTF8String];
    attributes[0].length = (newAccount != nil) ? (UInt32)strlen([newAccount UTF8String]) : 0;
	attributes[1].tag = kSecServiceItemAttr;
	attributes[1].data = (unichar *)[newName UTF8String];
    attributes[1].length = (newName != nil) ? (UInt32)strlen([newName UTF8String]) : 0;
	attList.count = 2;
	attList.attr = attributes;

	// Amend the keychain item
	status = SecKeychainItemModifyAttributesAndData(itemRef, &attList, (UInt32)strlen([password UTF8String]), [password UTF8String]);

	if (status != noErr) {

		// An error of -25299 indicates that the keychain item is a duplicate.  As connection names include a unique ID,
		// this indicates an issue when previously altering keychain items; delete the old item and try again.
		if ((int)status == -25299) {
			[self deletePasswordForName:newName account:newAccount];
			
			return [self updateItemWithName:name account:account toName:newName account:newAccount password:password];
		}

		NSLog(@"Error (%i) while updating keychain item for name: %@ account: %@", (int)status, name, account);

		NSAlert *alert = [[NSAlert alloc] init];
		alert.alertStyle = NSAlertStyleCritical;
		alert.messageText = NSLocalizedString(@"Error updating Keychain item", @"error updating keychain item message");
		alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"An error occurred while trying to update the Keychain item. Repairing your Keychain might resolve this, but if it doesn't please report it to the Sequel Ace team, supplying the error code %i.", @"error updating keychain item informative message"), status];
		[alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
		[alert runModal];
	}
}

/**
 * Retrieve the keychain item name for a supplied name and id.
 */
- (NSString *)nameForFavoriteName:(NSString *)favoriteName id:(id)favoriteId {
	if (!favoriteName || favoriteName.length == 0 || !favoriteId) {
		return nil;
	}
	// Look up the keychain name using long longs to support 64-bit > 32-bit keychain usage
	return [NSString stringWithFormat:@"Sequel Ace : %@ (%lld)", favoriteName, [favoriteId longLongValue]];
}

/**
 * Retrieve the keychain item account for a supplied user, host, and database - which can be nil.
 */
- (NSString *)accountForUser:(NSString *)user host:(NSString *)host database:(NSString *)database {
    if (!user || user.length == 0 || !host || host.length == 0) {
		return nil;
	}
	return [NSString stringWithFormat:@"%@@%@/%@", user, host, database ? database : @""];
}

/**
 * Retrieve the keychain SSH item name for a supplied name and id.
 */
- (NSString *)nameForSSHForFavoriteName:(NSString *)favoriteName id:(id)favoriteId {
    if (!favoriteName || favoriteName.length == 0 || !favoriteId) {
		return nil;
	}
	// Look up the keychain name using long longs to support 64-bit > 32-bit keychain usage
	return [NSString stringWithFormat:@"Sequel Ace SSHTunnel : %@ (%lld)", favoriteName, [favoriteId longLongValue]];
}

/**
 * Retrieve the keychain SSH item account for a supplied SSH user and host - which can be nil.
 */
- (NSString *)accountForSSHUser:(NSString *)theSSHUser sshHost:(NSString *)theSSHHost {
    if (!theSSHUser || theSSHUser.length == 0 || !theSSHHost || theSSHHost.length == 0) {
        return nil;
    }
	return [NSString stringWithFormat:@"%@@%@", theSSHUser, theSSHHost];
}

- (BOOL)isValidName:(NSString *)name acount:(NSString *)account {
    if (name && name.length > 0 && account && account.length > 0) {
        return YES;
    }
    return NO;
}

@end
