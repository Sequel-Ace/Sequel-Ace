//
//  SPNetworkPreferencePane.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on October 31, 2010.
//  Copyright (c) 2010 Stuart Connolly. All rights reserved.
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

#import "SPNetworkPreferencePane.h"
#import "SPPanelOptions.h"
#import "SPAppController.h"
#import "SPPreferenceController.h"

#import "sequel-ace-Swift.h"

static NSString *SPSSLCipherListMarkerItem = @"--";
static NSString *SPSSLCipherPboardTypeName = @"SSLCipherPboardType";

@interface SPNetworkPreferencePane ()
- (void)updateHiddenFiles;
- (void)loadSSLCiphers;
- (void)storeSSLCiphers;
+ (NSArray *)defaultSSLCipherList;
- (void)_refreshBookmarks;

@end

@implementation SPNetworkPreferencePane

@synthesize bookmarks;
@synthesize knownHostsChooser;
@synthesize errorFileNames;
@synthesize goodFileNames;
@synthesize userKnownHostsFiles;

- (instancetype)init
{
	self = [super init];
	if (self) {
		sslCiphers = [[NSMutableArray alloc] init];
        bookmarks = [NSMutableArray arrayWithArray:SecureBookmarkManager.sharedInstance.bookmarks];
        errorFileNames = [[NSMutableArray alloc] init];
        goodFileNames = [[NSMutableArray alloc] init];
        userKnownHostsFiles = [[NSMutableArray alloc] init];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_refreshBookmarks) name:SPBookmarksChangedNotification object:SecureBookmarkManager.sharedInstance];
	}
	
	return self;
}

- (void)dealloc
{
    SPLog(@"dealloc");
    [self removeObserver:self forKeyPath:SPBookmarksChangedNotification];
    [SecureBookmarkManager.sharedInstance stopAllSecurityScopedAccess];
}

- (void)_refreshBookmarks{
    SPLog(@"Got SPBookmarksChangedNotification, refreshing bookmarks");

    [bookmarks setArray:SecureBookmarkManager.sharedInstance.bookmarks];
}

#pragma mark -
#pragma mark Preference pane protocol methods

- (NSView *)preferencePaneView
{
	return [self view];
}

- (NSImage *)preferencePaneIcon
{
	if (@available(macOS 11.0, *)) {
		return [NSImage imageWithSystemSymbolName:@"network" accessibilityDescription:nil];
	} else {
		return [NSImage imageNamed:NSImageNameNetwork];
	}
}

- (NSString *)preferencePaneName
{
	return NSLocalizedString(@"Network", @"network preference pane name");
}

- (NSString *)preferencePaneIdentifier
{
	return SPPreferenceToolbarNetwork;
}

- (NSString *)preferencePaneToolTip
{
	return NSLocalizedString(@"Network Preferences", @"network preference pane tooltip");
}

- (void)preferencePaneWillBeShown
{
    [self updateSSHConfigPopUp:sshConfigChooser];
    [self updateSSHConfigPopUp:knownHostsChooser];

	[self loadSSLCiphers];
	if(![[sslCipherView registeredDraggedTypes] containsObject:SPSSLCipherPboardTypeName])
		[sslCipherView registerForDraggedTypes:@[SPSSLCipherPboardTypeName]];
}


#pragma mark -
#pragma mark Custom SSH client methods

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if([SPHiddenKeyFileVisibilityKey isEqualTo:keyPath]) {
		[self updateHiddenFiles];
	}
	else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

- (void)updateHiddenFiles
{
	[_currentFilePanel setShowsHiddenFiles:[prefs boolForKey:SPHiddenKeyFileVisibilityKey]];
}

- (IBAction)pickSSHClientViaFileBrowser:(id)sender
{
	_currentFilePanel = [NSOpenPanel openPanel];
	[_currentFilePanel setCanChooseFiles:YES];
	[_currentFilePanel setCanChooseDirectories:NO];
	[_currentFilePanel setAllowsMultipleSelection:NO];
	[_currentFilePanel setAccessoryView:hiddenFileView];
	[_currentFilePanel setResolvesAliases:NO];
	[self updateHiddenFiles];
	
	[prefs addObserver:self
			forKeyPath:SPHiddenKeyFileVisibilityKey
			   options:NSKeyValueObservingOptionNew
			   context:NULL];

	[_currentFilePanel beginSheetModalForWindow:[[NSApplication sharedApplication] keyWindow] completionHandler:^(NSInteger result) {
		if(result == NSFileHandlingPanelOKButton) [self->sshClientPath setStringValue:[[self->_currentFilePanel URL] path]];
		
		[self->prefs removeObserver:self forKeyPath:SPHiddenKeyFileVisibilityKey];
		
		self->_currentFilePanel = nil;
	}];
}

- (IBAction)pickSSHClient:(id)sender {
	//take value from user defaults
	NSString *oldPath = [prefs stringForKey:SPSSHClientPath];
	if([oldPath length]) [sshClientPath setStringValue:oldPath];

	[NSAlert createAccessoryAlertWithTitle:NSLocalizedString(@"Unsupported configuration!",@"Preferences : Network : Custom SSH client : warning dialog title") message:NSLocalizedString(@"Sequel Ace only supports and is tested with the default OpenSSH client versions included with Mac OS X. Using different clients might cause connection issues, security risks or not work at all.\n\nPlease be aware, that we cannot provide support for such configurations.",@"Preferences : Network : Custom SSH client : warning dialog message") accessoryView:sshClientPickerView primaryButtonTitle:NSLocalizedString(@"OK",@"Preferences : Network : Custom SSH client : warning dialog : accept button") primaryButtonHandler:^{
		//store new value to user defaults
		NSString *newPath = [self->sshClientPath stringValue];
		if (![newPath length]) {
			[self->prefs removeObjectForKey:SPSSHClientPath];
		} else {
			[self->prefs setObject:newPath forKey:SPSSHClientPath];
		}
	} cancelButtonHandler:nil];

}

#pragma mark -
#pragma mark PopUp Button

- (IBAction)updateKnownHostsConfig:(NSPopUpButton *)sender {

    for (NSMenuItem *item in [knownHostsChooser itemArray]) {
        [item setState:NSOffState];
    }

    [sender setState:NSOnState];
    [knownHostsChooser setTitle:[sender title]];

    if ([[sender title] isEqualToString:@"Sequel Ace default"]) {
        // the user has not selected Use known hosts from ssh config (ADVANCED), set pref to NO.
        user_defaults_set_bool_ud(SPSSHConfigContainsUserKnownHostsFile, NO, prefs);
        return;
    }

    // FIXME: would rather use an enum or ints instead of strings
    if ([[sender title] isEqualToString:@"Use known hosts from ssh config (ADVANCED)"]) {
        [prefs setObject:@"Use known hosts from ssh config (ADVANCED)" forKey:SPSSHUsualKnownHostsFile];
        [self updateSSHConfigPopUp:knownHostsChooser];
        return;
    }

    // choose a config file not listed
    if ((NSUInteger) [knownHostsChooser indexOfSelectedItem] == ([[knownHostsChooser itemArray] count] - 1)) {
        // open the file chooser dialog
        PanelOptions *options = [[PanelOptions alloc] init];

        options.allowsMultipleSelection = NO;
        options.canChooseFiles = YES;
        options.canChooseDirectories = NO;
        options.title = NSLocalizedString(@"Please choose your known hosts file", "Please choose your known hosts file");
        options.prefsKey = SPSSHUsualKnownHostsFile;
        options.chooser = knownHostsChooser;
        options.bookmarkCreationOptions = (NSURLBookmarkCreationWithSecurityScope); // RW
        options.isForKnownHostsFile = YES;

        SPLog(@"calling chooseSSHConfigWithOptions: %@", [options jsonStringWithPrettyPrint:YES]);

        [self chooseSSHConfigWithOptions:options];

        return;
    }

    // the title contains the absolute path of the config file. Therefore save
    // it to the preferences as selected config file.
    [prefs setObject:[sender title] forKey:SPSSHUsualKnownHostsFile];

    [self updateSSHConfigPopUp:knownHostsChooser];

}

- (IBAction)updateSSHConfig:(NSPopUpButton *)sender
{
	for (NSMenuItem *item in [sshConfigChooser itemArray]) {
		[item setState:NSOffState];
	}
	
	[sender setState:NSOnState];
	[sshConfigChooser setTitle:[sender title]];
	
	if ([[sender title] isEqualToString:@"Sequel Ace default"]) {
		[prefs setObject:[[NSBundle mainBundle] pathForResource:SPSSHConfigFile ofType:@""] forKey:SPSSHConfigFile];
		
		return;
	}
	
	// choose a config file not listed
	if ((NSUInteger) [sshConfigChooser indexOfSelectedItem] == ([[sshConfigChooser itemArray] count] - 1)) {
		// open the file chooser dialog
        PanelOptions *options = [[PanelOptions alloc] init];

        options.allowsMultipleSelection = YES;
        options.canChooseFiles = YES;
        options.canChooseDirectories = NO;
        options.title = NSLocalizedString(@"Please choose your ssh config files(s)", "Please choose your ssh config files(s)");
        options.prefsKey = SPSSHConfigFile;
        options.chooser = sshConfigChooser;
        options.isForKnownHostsFile = NO;
        options.bookmarkCreationOptions = (NSURLBookmarkCreationWithSecurityScope|NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess);


        SPLog(@"calling chooseSSHConfigWithOptions: %@", [options jsonStringWithPrettyPrint:YES]);

        [self chooseSSHConfigWithOptions:options];
		
		return;
	}
	
	// the title contains the absolute path of the config file. Therefore save
	// it to the preferences as selected config file.
	[prefs setObject:[sender title] forKey:SPSSHConfigFile];
	
    [self updateSSHConfigPopUp:sshConfigChooser];
}

- (void)updateSSHConfigPopUp:(NSPopUpButton*)button
{
	// clear up all existing items
	[button removeAllItems];
	
	// add the default item to give the user the ability to revert his/her changes
	[button addItemWithTitle:@"Sequel Ace default"];
	[[button menu] addItem:[NSMenuItem separatorItem]];

    if(button.tag == 2){
        [button addItemWithTitle:NSLocalizedString(@"Use known hosts from ssh config (ADVANCED)", @"Use known hosts from ssh config (ADVANCED)")];
        [[button menu] addItem:[NSMenuItem separatorItem]];
    }

	NSUInteger __block count = 0;

    NSUInteger len = [@"file://" length];

	// iterate through all bookmarks in order to display them as menu items
	[bookmarks enumerateObjectsUsingBlock:^(NSDictionary *dict, NSUInteger idx, BOOL *stop) {
		NSEnumerator *keyEnumerator = [dict keyEnumerator];
		id key;
		
		// every bookmark is saved in relation to it's abslute path
        while (key = [keyEnumerator nextObject]) {
            if([key hasPrefixWithPrefix:@"file://" caseSensitive:YES] != YES){
                continue;
            }
            NSString *itemTitle = [key substringFromIndex:len];
            [button safeAddItemWithTitle:itemTitle];
            count++;
        }
	}];

	// default value if no bookmarks are available
	if (count == 0) {
		[button selectItemWithTitle:@"Sequel Ace default"];
	}
	
	// add a separate add option under all granted files, that will open a
	// file chooser panel in order to select a new file and grant access to
	// it
	[[button menu] addItem:[NSMenuItem separatorItem]];
	[button addItemWithTitle:@"Other file..."];

    // sshConfigChooser button tagged with @1 in IB
    if(button.tag == 1){
        NSString *defaultConfig = [[NSBundle mainBundle] pathForResource:SPSSHConfigFile ofType:@""];

        if (count != 0) {
            // select the currently configured value
            NSString *currentConfig = [prefs stringForKey:SPSSHConfigFile];

            // if currentConfig is @0, they didn't choose anything in the file chooser
            // so set to default and update prefs.
            if ([currentConfig isEqualToString:defaultConfig] || currentConfig.isNumeric == YES) {
                currentConfig = @"Sequel Ace default";
                [prefs setObject:[[NSBundle mainBundle] pathForResource:SPSSHConfigFile ofType:@""] forKey:SPSSHConfigFile];
            }

            [button selectItemWithTitle:currentConfig];
        }
    }
    // knownHostsChooser button tagged with @1 in IB
    else if(button.tag == 2){
        NSString *defaultConfig = [prefs stringForKey:SPSSHDefaultKnownHostsFile];

        if (count != 0) {
            // select the currently configured value
            NSString *currentConfig = [prefs stringForKey:SPSSHUsualKnownHostsFile];

            // if currentConfig is @0, they didn't choose anything in the file chooser
            // so set to default
            if ([currentConfig isEqualToString:defaultConfig] || currentConfig.isNumeric == YES) {
                currentConfig = @"Sequel Ace default";
            }

            [button selectItemWithTitle:currentConfig];

            if([currentConfig isEqualToString:NSLocalizedString(@"Use known hosts from ssh config (ADVANCED)", @"Use known hosts from ssh config (ADVANCED)")]){
                BOOL ret = [self checkSSHConfigFileForUserKnownHostsFile:[prefs stringForKey:SPSSHConfigFile]];
                SPLog(@"checkSSHConfigFileForUserKnownHostsFile ret: [%hhd]", ret);

                if(ret == NO){
                    NSString *title = NSLocalizedString(@"ERROR: known hosts (ADVANCED)", @"ERROR: known hosts (ADVANCED)");

                    NSString *message = NSLocalizedString(@"No ssh config file contained UserKnownHostsFile.\n\nPlease check your config files and try again.", @"No ssh config file contained UserKnownHostsFile.\n\nPlease check your config files and try again.");

                    [NSAlert createWarningAlertWithTitle:title message:message callback:nil];
                }
                else{
                    // are the UserKnownHostsFiles RW?
                    [self checkUserKnownHostsFilesAreWritable];
                    user_defaults_set_bool_ud(SPSSHConfigContainsUserKnownHostsFile, YES, prefs);
                }

                SecureBookmarkManager *secureBookmarkManager = SecureBookmarkManager.sharedInstance;
                NSUInteger staleCount = secureBookmarkManager.staleBookmarks.count;

                // error files should be sent to the files pref for the user to grant access
                for(NSString *file in errorFileNames){
                    NSString *fileName = [NSString stringWithFormat:@"file://%@", file];
                    SPLog(@"calling addStaleBookmarkWithFilename: %@", fileName);
                    [secureBookmarkManager addStaleBookmarkWithFilename:fileName];
                    [secureBookmarkManager addKnownHostsBookmarkWithFilename:fileName];
                }
                if(secureBookmarkManager.staleBookmarks.count > staleCount){
                    SPLog(@"staleBookmarks.count: %lu > staleCount: %lu", (unsigned long)secureBookmarkManager.staleBookmarks.count, (unsigned long)staleCount);

                    // prompt user to recreate secure bookmarks
                    if(secureBookmarkManager.staleBookmarks.count > 0){

                        NSMutableString *staleBookmarksString = [[NSMutableString alloc] initWithCapacity:secureBookmarkManager.staleBookmarks.count];

                        for(NSString* staleFile in secureBookmarkManager.staleBookmarks){
                            [staleBookmarksString appendFormat:@"%@\n", staleFile.lastPathComponent];
                            SPLog(@"fileNames adding stale file: %@", staleFile.lastPathComponent);
                        }

                        [staleBookmarksString setString:[staleBookmarksString dropSuffixWithSuffix:@"\n"]];

                        NSView *helpView = [self modifyAndReturnBookmarkHelpView];

                        [NSAlert createAccessoryAlertWithTitle:NSLocalizedString(@"App Sandbox Issue", @"App Sandbox Issue") message:[NSString stringWithFormat:NSLocalizedString(@"You have missing secure bookmarks:\n\n%@\n\nWould you like to request access now?", @"Would you like to request access now?"), staleBookmarksString] accessoryView:helpView primaryButtonTitle:NSLocalizedString(@"Yes", @"Yes")
                                          primaryButtonHandler:^{
                            SPLog(@"request access now");
                            [self->errorFileNames removeAllObjects];
                            SPPreferenceController *prefCon = [((SPAppController *)[NSApp delegate]) preferenceController];
                            [prefCon showWindow:nil];
                            [prefCon displayPreferencePane:prefCon->fileItem];

                        } cancelButtonHandler:^{
                            SPLog(@"No not now");
                        }];
                    }
                }
            } // end of advance config
            else{
                // the user has not selected Use known hosts from ssh config (ADVANCED), set pref to NO.
                user_defaults_set_bool_ud(SPSSHConfigContainsUserKnownHostsFile, NO, prefs);
            }
        }
    }
}

- (BOOL)checkSSHConfigFileForUserKnownHostsFile:(NSString*)configFile{

    SPLog(@"checkSSHConfigFileForUserKnownHostsFile");

    NSString *defaultConfig = [[NSBundle mainBundle] pathForResource:SPSSHConfigFile ofType:@""];

    if ([configFile isEqualToString:defaultConfig] || configFile.isNumeric == YES) {
        SPLog(@"ERROR: SPSSHConfigFile set to default. This has no UserKnownHostsFile");
        return NO;
    }

    NSError *error = nil;
    NSString *sshConfig = [NSString stringWithContentsOfFile:configFile encoding:NSUTF8StringEncoding error:&error];

    if(error != nil){
        SPLog(@"ERROR: configFile [%@] read error: %@", configFile, error.localizedDescription);
        [errorFileNames addObjectIfNotContains:configFile];
        return NO;
    }

    SPLog(@"sshConfig: %@", sshConfig);

    if([sshConfig contains:@"UserKnownHostsFile"] == NO){
        SPLog(@"ERROR: configFile [%@] has no UserKnownHostsFile", configFile);
    }
    else{
        SPLog(@"configFile [%@] CONTAINS UserKnownHostsFile", configFile);
        [goodFileNames addObjectIfNotContains:configFile];
    }

    NSArray *sshConfigAsArray = [sshConfig separatedIntoLinesObjc];
    SPLog(@"sshConfigAsArray: %@", sshConfigAsArray);

    NSMutableArray<NSString *> __block *includeFileNames = [[NSMutableArray alloc] init];

    for(NSString *str in sshConfigAsArray){
        if([str contains:@"Include"]){
            SPLog(@"found Include line: [%@]", [str trimWhitespaces]);
            [includeFileNames addObjectIfNotContains:[[str trimWhitespaces] dropPrefixWithPrefix:@"Include "]];
        }
        if([str contains:@"UserKnownHostsFile"]){
            SPLog(@"found UserKnownHostsFile line: [%@]", [str trimWhitespaces]);
            [userKnownHostsFiles addObjectIfNotContains:[[str trimWhitespaces] dropPrefixWithPrefix:@"UserKnownHostsFile "]];
        }
    }

    SPLog(@"includeFileNames: %@", includeFileNames);
    SPLog(@"SecureBookmarkManager.sharedInstance.resolved: %@", SecureBookmarkManager.sharedInstance.resolvedBookmarks);
    SPLog(@"SecureBookmarkManager.sharedInstance.stale: %@", SecureBookmarkManager.sharedInstance.staleBookmarks);

    NSMutableArray<NSString *> __block *includeFileNamesCopy = [includeFileNames mutableCopy];

    [includeFileNamesCopy enumerateObjectsUsingBlock:^(NSString *str, NSUInteger idx, BOOL *stop){
        NSURL *tmpURL = [NSURL URLWithString:[NSString stringWithFormat:@"file://%@",str]];
        if([SecureBookmarkManager.sharedInstance.resolvedBookmarks containsObject:tmpURL]){
            SPLog(@"found resolvedBookmark: [%@]", str);
        }
        else{
            [errorFileNames addObjectIfNotContains:str];
            [includeFileNames removeObject:str];
        }
    }];

    for(NSString *incFile in includeFileNames){
        [self checkSSHConfigFileForUserKnownHostsFile:incFile];
    }

    SPLog(@"errorFileNames: %@", errorFileNames);
    SPLog(@"goodFileNames: %@", goodFileNames);
    SPLog(@"userKnownHostsFiles: %@", userKnownHostsFiles);

    return goodFileNames.count > 0;

}

- (void)checkUserKnownHostsFilesAreWritable {

    for(NSString *file in userKnownHostsFiles){
        NSURL *tmpURL = [NSURL URLWithString:[NSString stringWithFormat:@"file://%@",file]];
        if([SecureBookmarkManager.sharedInstance.resolvedBookmarks containsObject:tmpURL]){
            SPLog(@"found resolvedBookmark: [%@]", file);
            SPLog(@"removing from errorFileNames. count: %lu", (unsigned long)errorFileNames.count);
            [errorFileNames removeObject:file];
            SPLog(@"errorFileNames. count: %lu", (unsigned long)errorFileNames.count);
        }
        else{
            SPLog(@"ERROR: adding to errorFileNames - not in resolvedBookmarks: [%@]", file);
            [errorFileNames addObjectIfNotContains:file];
        }
    }
}

#pragma mark -
#pragma mark chooseSSHConfig

- (void)chooseSSHConfigWithOptions:(PanelOptions*)options
{
    // retrieve the file manager in order to fetch the current user's home
    // directory
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *homeDirectory = nil;
    if ([fileManager respondsToSelector:@selector(homeDirectoryForCurrentUser)]) {
        homeDirectory = [fileManager homeDirectoryForCurrentUser];
    } else {
        homeDirectory = [NSURL fileURLWithPath:NSHomeDirectory()];
    }

    _currentFilePanel = [NSOpenPanel openPanel];
    [_currentFilePanel setMessage:options.title];
    [_currentFilePanel setCanChooseFiles:options.canChooseFiles];
    [_currentFilePanel setCanChooseDirectories:options.canChooseDirectories];
    [_currentFilePanel setAllowsMultipleSelection:options.allowsMultipleSelection];
    [_currentFilePanel setAccessoryView:hiddenFileView];
    [_currentFilePanel setResolvesAliases:NO];
    [_currentFilePanel setDirectoryURL:[homeDirectory URLByAppendingPathComponent:@".ssh"]];
    [self updateHiddenFiles];

    [prefs addObserver:self
            forKeyPath:SPHiddenKeyFileVisibilityKey
               options:NSKeyValueObservingOptionNew
               context:NULL];

    [_currentFilePanel beginWithCompletionHandler:^(NSInteger returnCode)
     {
        // only process data, when the user pressed ok
        if (returnCode != NSModalResponseOK) {
            // if they don't choose anything ... pref forKey:SPSSHConfigFile will be @0
            [self updateSSHConfigPopUp:options.chooser];
            return;
        }

        // since ssh configs are able to consist of multiple files, bookmarks
        // for every selected file should be created in order to access them
        // read-only.
        [self->_currentFilePanel.URLs enumerateObjectsUsingBlock:^(NSURL *url, NSUInteger idxURL, BOOL *stopURL){
            // check if the file is out of the sandbox

            NSMutableString *classStr = [NSMutableString string];
            [classStr appendStringOrNil:NSStringFromClass(url.class)];

            SPLog(@"Block URL class: %@", classStr);
            SPLog(@"Block URL str: %@", url.absoluteString);
            SPLog(@"Block URL add: %p", &url);
            SPLog(@"_currentFilePanel.URL add: %p", self->_currentFilePanel.URL);

            // check it's really a URL
            if(![url isKindOfClass:[NSURL class]]){
                SPLog(@"selected file is not a valid URL: %@", classStr);

                NSView *helpView = [self modifyAndReturnBookmarkHelpView];

                NSString *alertMessage = [NSString stringWithFormat:NSLocalizedString(@"The selected file is not a valid file.\n\nPlease try again.\n\nClass: %@", @"error while selecting file message"),
                                          classStr];

                [NSAlert createAccessoryWarningAlertWithTitle:NSLocalizedString(@"File Selection Error", @"error while selecting file message") message:alertMessage accessoryView:helpView callback:^{

                    NSDictionary *userInfo = @{
                        NSLocalizedDescriptionKey: @"selected file is not a valid URL",
                        @"class": classStr,
                        @"func": [NSString stringWithFormat:@"%s", __PRETTY_FUNCTION__],
                        @"URLs" : (self->_currentFilePanel.URLs) ?: @""
                    };

                    SPLog(@"userInfo: %@", userInfo);
                }];
            }
            else{
                // use url from the block, not self->_currentFilePanel.URL
                // From Apple docs: The NSOpenPanel subclass sets this property to nil
                // when the selection contains multiple items.
                if([SecureBookmarkManager.sharedInstance addBookmarkForUrl:url options:options.bookmarkCreationOptions isForStaleBookmark:NO isForKnownHostsFile:options.isForKnownHostsFile] == YES){
                    SPLog(@"addBookmarkForUrl success");
                }
                else{
                    SPLog(@"addBookmarkForUrl failed: %@", url.absoluteString);
                }
            }

            // set the config path to the first selected file
            if (idxURL == 0) {
                // save the preferences
                if (![[url path] length]) {
                    [self->prefs removeObjectForKey:options.prefsKey];
                } else {
                    [self->prefs setObject:[url path] forKey:options.prefsKey];
                }
            }
        }];

        // update the popup button with its items and the selected item
        // from the file picker
        [self updateSSHConfigPopUp:options.chooser];

        self->_currentFilePanel = nil;
    }];
}


#pragma mark -
#pragma mark SSL cipher list methods

- (void)loadSSLCiphers
{
	NSArray *supportedCiphers = [SPNetworkPreferencePane defaultSSLCipherList];
	[sslCiphers removeAllObjects];
	
	NSString *userCipherString = [prefs stringForKey:SPSSLCipherListKey];
	if(userCipherString) {
		//expand user list
		NSArray *userCipherList = [userCipherString componentsSeparatedByString:@":"];
		
		//compare the users list to the valid list and only copy over valid items
		for (NSString *userCipher in userCipherList) {
			if (![supportedCiphers containsObject:userCipher] || [sslCiphers containsObject:userCipher]) {
				SPLog(@"Unknown ssl cipher in users' list: %@",userCipher);
				continue;
			}
			[sslCiphers addObject:userCipher];
		}
		
		//now we do the reverse and add valid ciphers that are not yet in the users list.
		//We'll just assume the ones not in the users' list are newer and therefore better and add
		//them at the top
		NSUInteger shift = 0;
		for (NSString *validCipher in supportedCiphers) {
			if(![sslCiphers containsObject:validCipher]) {
				[sslCiphers insertObject:validCipher atIndex:shift++];
			}
		}
	}
	else {
		//no user prefs configured, so we'll just go with the defaults
		[sslCiphers addObjectsFromArray:supportedCiphers];
	}
	
	//reload UI
	[sslCipherView deselectAll:nil];
	[sslCipherView reloadData];
}

- (void)storeSSLCiphers
{
	NSString *flattedList = [sslCiphers componentsJoinedByString:@":"];
	[prefs setObject:flattedList forKey:SPSSLCipherListKey];
}

- (IBAction)resetCipherList:(id)sender
{
    //remove the user pref and reset the GUI
    [prefs removeObjectForKey:SPSSLCipherListKey];
    [self loadSSLCiphers];
}

+ (NSArray *)defaultSSLCipherList
{
    static dispatch_once_t token;
    static NSArray *defaultSSLCipherList;

    dispatch_once(&token, ^{
        //this is the default list as hardcoded in SPMySQLConnection.m
        //Sadly there is no way to make MySQL give us the list of runtime-supported ciphers.
        defaultSSLCipherList = @[
            @"ECDHE-ECDSA-AES256-GCM-SHA384",
            @"ECDHE-ECDSA-AES128-GCM-SHA256",
            @"ECDHE-RSA-AES256-GCM-SHA384",
            @"ECDHE-RSA-AES128-GCM-SHA256",
            @"DHE-DSS-AES256-GCM-SHA384",
            @"DHE-DSS-AES128-GCM-SHA256",
            @"DHE-RSA-AES256-GCM-SHA384",
            @"DHE-RSA-AES128-GCM-SHA256",
            @"ECDHE-ECDSA-AES256-SHA384",
            @"ECDHE-ECDSA-AES128-SHA256",
            @"ECDHE-RSA-AES256-SHA384",
            @"ECDHE-RSA-AES128-SHA256",
            @"DHE-RSA-AES128-SHA256",
            @"DHE-DSS-AES128-SHA256",
            @"DHE-RSA-AES256-SHA256",
            @"DHE-DSS-AES256-SHA256",
            SPSSLCipherListMarkerItem, //marker. disabled items below here
            @"AES128-GCM-SHA256",
            @"AES128-SHA",
            @"AES128-SHA256",
            @"AES256-GCM-SHA384",
            @"AES256-SHA",
            @"AES256-SHA256",
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
            @"DHE-DSS-AES128-SHA",
            @"DHE-DSS-AES256-SHA",
            @"DHE-RSA-AES128-SHA",
            @"DHE-RSA-AES256-SHA",
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
        ];

    });

    return defaultSSLCipherList;
}

#pragma mark -
#pragma mark tableView Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [sslCiphers count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	NSString *value = [sslCiphers objectAtIndex:rowIndex];
	if ([value isEqualTo:SPSSLCipherListMarkerItem]) {
		return NSLocalizedString(@"Disabled Cipher Suites", @"Preferences : Network : SSL Chiper suites : List seperator");
	}
	return value;
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row
{
	return ([[sslCiphers objectAtIndex:row] isEqualTo:SPSSLCipherListMarkerItem]);
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
	return ![self tableView:tableView isGroupRow:row];
}

- (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id <NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
	if(row < 0) return NO; //why is that even a signed int when all "indexes" are unsigned!?
	
	NSPasteboard *pboard = [info draggingPasteboard];
	NSArray *draggedItems = [NSKeyedUnarchiver unarchiveObjectWithData:[pboard dataForType:SPSSLCipherPboardTypeName]];
	
	NSUInteger nextInsert = row;
	for (NSString *item in draggedItems) {
		NSUInteger oldPos = [sslCiphers indexOfObject:item];
		[sslCiphers removeObjectAtIndex:oldPos];
		
		if(oldPos < (NSUInteger)row) {
			// readjust position because we removed an object further up in the list, shifting all following indexes down by 1
			nextInsert--;
		}
		
		[sslCiphers insertObject:item atIndex:nextInsert++];
	}
	
	NSMutableIndexSet *newSelection = [NSMutableIndexSet indexSet];
	for (NSString *item in draggedItems) {
		[newSelection addIndex:[sslCiphers indexOfObject:item]];
	}
	
	[self storeSSLCiphers];
	[sslCipherView selectRowIndexes:newSelection byExtendingSelection:NO];
	
	return YES;
}

- (NSDragOperation)tableView:(NSTableView *)aTableView validateDrop:(id <NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation
{
	//cannot drop something on another item in the list, only between them
	return (operation == NSTableViewDropOn)? NSDragOperationNone : NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)aTableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
{
	//the marker cannot be actively reordered
	if ([rowIndexes containsIndex:[sslCiphers indexOfObject:SPSSLCipherListMarkerItem]])
		return NO;
	
	//put the names of the items on the pasteboard. easier to work with than indexes...
	NSMutableArray *items = [NSMutableArray arrayWithCapacity:[rowIndexes count]];
	[rowIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
		[items addObject:[sslCiphers objectAtIndex:idx]];
	}];
	
	NSData *arch = [NSKeyedArchiver archivedDataWithRootObject:items];
	[pboard declareTypes:@[SPSSLCipherPboardTypeName] owner:self];
	[pboard setData:arch forType:SPSSLCipherPboardTypeName];
	return YES;
}

@end
