//
//  SPFilePreferencePane.m
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

#import "SPFilePreferencePane.h"
#import "sequel-ace-Swift.h"

@import Firebase;

@interface SPFilePreferencePane ()
- (void)_refreshBookmarks;

@end

@implementation SPFilePreferencePane

@synthesize bookmarks;

- (instancetype)init
{
	self = [super init];
	
	if (self) {
		fileNames = [[NSMutableArray alloc] init];
		bookmarks = [[NSMutableArray alloc] init];
        
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_refreshBookmarks) name:SPBookmarksChangedNotification object:SecureBookmarkManager.sharedInstance];

		[self loadBookmarks];
	}
	
	return self;
}

- (void)dealloc
{
    SPLog(@"dealloc");
    [SecureBookmarkManager.sharedInstance stopAllSecurityScopedAccess];

}

- (void)_refreshBookmarks{
    SPLog(@"Got SPBookmarksChangedNotification, refreshing bookmarks");
    CLS_LOG(@"Got SPBookmarksChangedNotification, refreshing bookmarks");

    [bookmarks setArray:SecureBookmarkManager.sharedInstance.bookmarks];
}

- (NSImage *)preferencePaneIcon {
	if (@available(macOS 11.0, *)) {
		return [NSImage imageWithSystemSymbolName:@"folder" accessibilityDescription:nil];
	} else {
		return [NSImage imageNamed:NSImageNameFolder];
	}
}

- (NSString *)preferencePaneIdentifier {
	return SPPreferenceToolbarFile;
}

- (NSString *)preferencePaneName {
	return NSLocalizedString(@"Files", @"file preference pane name");
}

- (NSString *)preferencePaneToolTip {
	return NSLocalizedString(@"File Preferences", @"file preference pane tooltip");
}

- (NSView *)preferencePaneView {
	return [self view];
}

- (void)preferencePaneWillBeShown
{
	[self loadBookmarks];
}

- (void)loadBookmarks
{
 
    [bookmarks setArray:SecureBookmarkManager.sharedInstance.bookmarks];

	// we need to re-request access to places we've been before..
    // not anymore, done at startup

	// remove all saved filenames for the list view
	[fileNames removeAllObjects];
	
	// iterate through all bookmarks
	[bookmarks enumerateObjectsUsingBlock:^(NSDictionary *dict, NSUInteger idx, BOOL *stop) {
		NSEnumerator *keyEnumerator = [dict keyEnumerator];
		id key;
		
		while (key = [keyEnumerator nextObject]) {
			if (dict[key] == nil) {
				continue;
			}
			
			// remove the file protocol
            if([key hasPrefixWithPrefix:@"file://" caseSensitive:YES] == YES){
                NSString *fileName = [key substringFromIndex:[@"file://" length]];
                // save the filename without the file protocol
                [fileNames addObject:fileName];
            }
		}
	}];
	
	// reset the table view for the files
	[fileView deselectAll:nil];
	[fileView reloadData];
}

#pragma mark -
#pragma mark File operations

- (IBAction)revokeBookmark:(id)sender
{
	NSIndexSet *indiceToRevoke = [fileView selectedRowIndexes];

	// iterate through all selected indice
	[indiceToRevoke enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
		// retrieve the filename
		NSString __block *fileName = [NSString stringWithFormat:@"file://%@", fileNames[idx]];
		
        if([SecureBookmarkManager.sharedInstance revokeBookmarkWithFilename:fileName] == YES){
            SPLog(@"refreshing bookmarks: %@", bookmarks);
            [bookmarks setArray:SecureBookmarkManager.sharedInstance.bookmarks];
        }
	}];
	
	// reload the bookmarks and reset the view
	[self loadBookmarks];
}

- (IBAction)addBookmark:(id)sender
{
	[self chooseFile];
}

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

- (void) chooseFile
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
	[_currentFilePanel setCanChooseDirectories:YES];
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

            if([SecureBookmarkManager.sharedInstance addBookmarkForUrl:self->_currentFilePanel.URL options:(NSURLBookmarkCreationWithSecurityScope|NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess)] == YES){
                SPLog(@"addBookmarkForUrl success");
            }
		}];
		
		[self loadBookmarks];
		
		self->_currentFilePanel = nil;
	}];
}

#pragma mark -
#pragma mark Granted Files View

/**
 * Provide the count of bookmarks for the TableView
 */
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [fileNames count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	return [fileNames objectAtIndex:rowIndex];
}

@end
