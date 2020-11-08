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

@interface SPFilePreferencePane ()
@end

@implementation SPFilePreferencePane

@synthesize bookmarks;
@synthesize resolvedBookmarks;

- (instancetype)init
{
	self = [super init];
	
	if (self) {
		fileNames = [[NSMutableArray alloc] init];
		bookmarks = [[NSMutableArray alloc] init];
		resolvedBookmarks = [[NSMutableArray alloc] init];
		
		[self loadBookmarks];
	}
	
	return self;
}

- (void)dealloc
{
	for(NSURL *url in resolvedBookmarks){
		[url stopAccessingSecurityScopedResource];
	}

}

- (BOOL)preferencePaneAllowsResizing {
	return NO;
}

- (NSImage *)preferencePaneIcon {
	return [NSImage imageNamed:NSImageNameFolder];
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
	id o;
	
	if((o = [prefs objectForKey:SPSecureBookmarks])){
		[bookmarks setArray:o];
	}
	
	// we need to re-request access to places we've been before..
	[self reRequestSecureAccess];
	
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
			NSString *fileName = [key substringFromIndex:[@"file://" length]];
			
			// save the filename without the file protocol
			[fileNames addObject:fileName];
		}
	}];
	
	// reset the table view for the files
	[fileView deselectAll:nil];
	[fileView reloadData];
}

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
#pragma mark File operations

- (IBAction)revokeBookmark:(id)sender
{
	NSIndexSet *indiceToRevoke = [fileView selectedRowIndexes];

	// iterate through all selected indice
	[indiceToRevoke enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
		// retrieve the filename
		NSString __block *fileName = [NSString  stringWithFormat:@"file://%@", fileNames[idx]];
		
		[bookmarks enumerateObjectsUsingBlock:^(NSDictionary *dict, NSUInteger idxBookmarks, BOOL *stopBookmarks) {
			NSEnumerator *keyEnumerator = [dict keyEnumerator];
			id key;
			
			while (key = [keyEnumerator nextObject]) {
				if (![key isEqualToString:fileName]) {
					continue;
				}
				
				[bookmarks removeObjectAtIndex:idxBookmarks];
				[prefs setObject:bookmarks forKey:SPSecureBookmarks];
			}
		}];
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
