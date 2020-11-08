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
#import "sequel-ace-Swift.h"

static NSString *SPSSLCipherListMarkerItem = @"--";
static NSString *SPSSLCipherPboardTypeName = @"SSLCipherPboardType";

@interface SPNetworkPreferencePane ()
- (void)updateHiddenFiles;
- (void)loadSSLCiphers;
- (void)storeSSLCiphers;
+ (NSArray *)defaultSSLCipherList;
@end

@implementation SPNetworkPreferencePane

@synthesize bookmarks;
@synthesize resolvedBookmarks;

- (instancetype)init
{
	self = [super init];
	if (self) {
		sslCiphers = [[NSMutableArray alloc] init];
		bookmarks = [[NSMutableArray alloc] init];
		resolvedBookmarks = [[NSMutableArray alloc] init];
		
		id o;
		if((o = [prefs objectForKey:SPSecureBookmarks])){
			[bookmarks setArray:o];
		}
		
		[self reRequestSecureAccess];
	}
	
	return self;
}

- (void)dealloc
{
	for(NSURL *url in resolvedBookmarks){
		[url stopAccessingSecurityScopedResource];
	}
}

#pragma mark -
#pragma mark Preference pane protocol methods

- (NSView *)preferencePaneView
{
	return [self view];
}

- (NSImage *)preferencePaneIcon
{
	return [NSImage imageNamed:@"toolbar-preferences-network"];
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

- (BOOL)preferencePaneAllowsResizing
{
	return NO;
}

- (void)preferencePaneWillBeShown
{
	[self updateSSHConfigPopUp];
	
	[self loadSSLCiphers];
	if(![[sslCipherView registeredDraggedTypes] containsObject:SPSSLCipherPboardTypeName])
		[sslCipherView registerForDraggedTypes:@[SPSSLCipherPboardTypeName]];
}

#pragma mark -
#pragma mark Bookmarks

-(void)reRequestSecureAccess{
	
	SPLog(@"reRequestSecureAccess to saved bookmarks");

	[self.bookmarks enumerateObjectsUsingBlock:^(NSDictionary *dict, NSUInteger idx, BOOL *stop) {
		
		[dict enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSData *obj, BOOL *stop2) {
			
			NSError *error = nil;
			
			NSURL *tmpURL = [NSURL URLByResolvingBookmarkData:obj
													  options:NSURLBookmarkResolutionWithSecurityScope
												relativeToURL:nil
										  bookmarkDataIsStale:nil
														error:&error];
			
			if(!error){
				[tmpURL startAccessingSecurityScopedResource];
				[resolvedBookmarks addObject:tmpURL];
			}
			else{
				SPLog(@"Problem resolving bookmark - %@ : %@",key, [error localizedDescription]);
			}
		}];
	}];
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
#pragma mark - PopUp Button

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
		[self chooseSSHConfig];
		
		return;
	}
	
	// the title contains the absolute path of the config file. Therefore save
	// it to the preferences as selected config file.
	[prefs setObject:[sender title] forKey:SPSSHConfigFile];
	
	[self updateSSHConfigPopUp];
}

- (void)updateSSHConfigPopUp
{
	// clear up all existing items
	[sshConfigChooser removeAllItems];
	
	// add the default item to give the user the ability to revert his/her changes
	[sshConfigChooser addItemWithTitle:@"Sequel Ace default"];
	[[sshConfigChooser menu] addItem:[NSMenuItem separatorItem]];
	
	NSUInteger __block count = 0;
	
	// iterate through all bookmarks in order to display them as menu items
	[bookmarks enumerateObjectsUsingBlock:^(NSDictionary *dict, NSUInteger idx, BOOL *stop) {
		NSEnumerator *keyEnumerator = [dict keyEnumerator];
		id key;
		
		// every bookmark is saved in relation to it's abslute path
		while (key = [keyEnumerator nextObject]) {
			NSString *itemTitle = [key substringFromIndex:[@"file://" length]];
			
			[sshConfigChooser addItemWithTitle:itemTitle];
			
			count++;
		}
	}];

	// default value if no bookmarks are available
	if (count == 0) {
		[sshConfigChooser selectItemWithTitle:@"Sequel Ace default"];
	}
	
	// add a separate add option under all granted files, that will open a
	// file chooser panel in order to select a new file and grant access to
	// it
	[[sshConfigChooser menu] addItem:[NSMenuItem separatorItem]];
	[sshConfigChooser addItemWithTitle:@"Other file..."];

	NSString *defaultConfig = [[NSBundle mainBundle] pathForResource:SPSSHConfigFile ofType:@""];
	
	if (count != 0) {
		// select the currently configured value
		NSString *currentConfig = [prefs stringForKey:SPSSHConfigFile];
		
		if ([currentConfig isEqualToString:defaultConfig]) {
			currentConfig = @"Sequel Ace default";
		}
		
		[sshConfigChooser selectItemWithTitle:currentConfig];
	}
}

- (void) chooseSSHConfig
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
	[_currentFilePanel setTitle:@"Choose ssh config"];
	[_currentFilePanel setCanChooseFiles:YES];
	[_currentFilePanel setCanChooseDirectories:NO];
	[_currentFilePanel setAllowsMultipleSelection:YES];
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
			return;
		}

		// since ssh configs are able to consist of multiple files, bookmarks
		// for every selected file should be created in order to access them
		// read-only.
		[self->_currentFilePanel.URLs enumerateObjectsUsingBlock:^(NSURL *url, NSUInteger idxURL, BOOL *stopURL){
			// check if the file is out of the sandbox
			if ([self->_currentFilePanel.URL startAccessingSecurityScopedResource] == YES) {
				NSLog(@"got access to: %@", url.absoluteString);
				
				BOOL __block beenHereBefore = NO;
				
				[self.bookmarks enumerateObjectsUsingBlock:^(NSDictionary *dict, NSUInteger idx, BOOL *stop) {
					// check, if a bookmark already exists
					if (dict[url.absoluteString] != nil) {
						beenHereBefore = YES;
						*stop = YES;
					}
				}];
				
				// if no bookmark exist, create on
				if (beenHereBefore == NO) {
					NSError *error = nil;
					
					NSData *tmpAppScopedBookmark = [url
													bookmarkDataWithOptions:(NSURLBookmarkCreationWithSecurityScope
																			 |
																			 NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess)
													includingResourceValuesForKeys:nil
													relativeToURL:nil
													error:&error];
					
					// save the bookmark to the preferences in order to access
					// them later in the SPConnectionController
					if (tmpAppScopedBookmark && !error) {
						[self->bookmarks addObject:@{url.absoluteString : tmpAppScopedBookmark}];
						[self->prefs setObject:self->bookmarks forKey:SPSecureBookmarks];
					}
				}
			}
			
			// set the config path to the first selected file
			if (idxURL == 0) {
				// save the preferences
				if (![[url path] length]) {
					[self->prefs removeObjectForKey:SPSSHConfigFile];
				} else {
					[self->prefs setObject:[url path] forKey:SPSSHConfigFile];
				}
			}
		}];
		
		// update the popup button with its items and the selected item
		// from the file picker
		[self updateSSHConfigPopUp];
		
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

- (IBAction)resetCipherList:(id)sender
{
	//remove the user pref and reset the GUI
	[prefs removeObjectForKey:SPSSLCipherListKey];
	[self loadSSLCiphers];
}

+ (NSArray *)defaultSSLCipherList
{
	//this is the default list as hardcoded in SPMySQLConnection.m
	//Sadly there is no way to make MySQL give us the list of runtime-supported ciphers.
	return @[
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
}

@end
