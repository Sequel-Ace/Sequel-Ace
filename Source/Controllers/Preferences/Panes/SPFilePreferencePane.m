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

typedef struct {
    NSString *title;
    BOOL canChooseFiles;
    BOOL canChooseDirectories;
    BOOL allowsMultipleSelection;
    BOOL isForStaleBookmark;
    NSString *fileName;
} PanelOptions;

@interface SPFilePreferencePane ()
- (void)_refreshBookmarks;

@property (readwrite, strong) NSMutableArray<NSDictionary<NSString *, id> *> *bookmarks;
@property (readwrite, strong) NSMutableArray<NSString *> *staleBookmarks;

@end

@implementation SPFilePreferencePane

@synthesize bookmarks, staleBookmarks, staleLabel;

- (instancetype)init
{
	self = [super init];
	
	if (self) {
		fileNames = [[NSMutableArray alloc] init];
        bookmarks = [[NSMutableArray alloc] init];
        staleBookmarks = [[NSMutableArray alloc] init];

        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_refreshBookmarks) name:SPBookmarksChangedNotification object:SecureBookmarkManager.sharedInstance];

		[self loadBookmarks];
	}
	
	return self;
}

- (IBAction)doubleClick:(id)sender {

    SPLog(@"clickedColumn = %li", (long)fileView.clickedColumn);
    SPLog(@"clickedRow = %li", (long)fileView.clickedRow);

    if(fileView.clickedColumn >= 0 && fileView.clickedRow >= 0){
        NSString *fileName = [fileNames safeObjectAtIndex:fileView.clickedRow];
        SPLog(@"fileName: %@", fileName);
        if(fileName != nil){

            PanelOptions options = {
                .title = @"Choose stale file",
                .canChooseFiles = YES,
                .canChooseDirectories = YES,
                .allowsMultipleSelection = NO,
                .isForStaleBookmark = YES,
                .fileName = fileName
            };

            [self chooseFileWithOptions:options];
        }
        else{
            SPLog(@"ERROR: fileName is nil");
            CLS_LOG(@"ERROR: fileName is nil");
        }
    }
}

- (void)dealloc
{
    SPLog(@"dealloc");
    [SecureBookmarkManager.sharedInstance stopAllSecurityScopedAccess]; // FIXME: not sure about this... just because this pane is deallocated, we don't need to revoke access?
}

- (void)_refreshBookmarks{
    SPLog(@"Got SPBookmarksChangedNotification, refreshing bookmarks");
    CLS_LOG(@"Got SPBookmarksChangedNotification, refreshing bookmarks");

    [bookmarks setArray:SecureBookmarkManager.sharedInstance.bookmarks];
    [staleBookmarks setArray:SecureBookmarkManager.sharedInstance.staleBookmarks];
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
    SPLog(@"loadBookmarks");
    CLS_LOG(@"loadBookmarks");

    [bookmarks setArray:SecureBookmarkManager.sharedInstance.bookmarks];
    [staleBookmarks setArray:SecureBookmarkManager.sharedInstance.staleBookmarks];

    if(staleBookmarks.count > 0){
        staleLabel.hidden = NO;
    }
    else{
        staleLabel.hidden = YES;
    }

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
            NSString *fileName = [key dropPrefixWithPrefix:@"file://"];
            // save the filename without the file protocol
            [fileNames addObject:fileName];
            SPLog(@"fileNames adding: %@", fileName);
		}
	}];

    // add on any stale bookmarks
    for(NSString* staleFile in staleBookmarks){
        [fileNames addObject:[staleFile dropPrefixWithPrefix:@"file://"]];
        SPLog(@"fileNames adding stale file: %@", staleFile);
    }

    if(staleBookmarks.count > 0){
        staleLabel.hidden = NO;
    }

	
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
		NSString *fileName = [NSString stringWithFormat:@"file://%@", fileNames[idx]];
		
        if([SecureBookmarkManager.sharedInstance revokeBookmarkWithFilename:fileName] == YES){
            [bookmarks setArray:SecureBookmarkManager.sharedInstance.bookmarks];
            SPLog(@"revokeBookmarkWithFilename success. refreshing bookmarks: %@", bookmarks);
            CLS_LOG(@"revokeBookmarkWithFilename success. refreshing bookmarks");
        }
        else{
            SPLog(@"revokeBookmarkWithFilename failed: %@", fileName);
            CLS_LOG(@"revokeBookmarkWithFilename failed: %@", fileName);
        }
	}];
	
	// reload the bookmarks and reset the view
	[self loadBookmarks];
}

- (IBAction)addBookmark:(id)sender
{
    PanelOptions options = {
        .title = @"Choose ssh config",
        .canChooseFiles = YES,
        .canChooseDirectories = YES,
        .allowsMultipleSelection = YES,
        .isForStaleBookmark = NO,
        .fileName = nil
    };

	[self chooseFileWithOptions:options];
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


- (void)chooseFileWithOptions:(PanelOptions)options
{
    // retrieve the file manager in order to fetch the current user's home
    // directory
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *directory = nil;
    if(options.fileName == nil){
        if ([fileManager respondsToSelector:@selector(homeDirectoryForCurrentUser)]) {
            directory = [[fileManager homeDirectoryForCurrentUser] URLByAppendingPathComponent:@".ssh"];
        } else {
            directory = [[NSURL fileURLWithPath:NSHomeDirectory()] URLByAppendingPathComponent:@".ssh"];
        }
    }
    else{
        NSString *staleFileDir = [options.fileName stringByDeletingLastPathComponent];
        SPLog(@"staleFileDir: %@", staleFileDir);
        directory = [NSURL fileURLWithPath:staleFileDir];
    }

    _currentFilePanel = [NSOpenPanel openPanel];
    [_currentFilePanel setTitle:options.title];
    [_currentFilePanel setCanChooseFiles:options.canChooseFiles];
    [_currentFilePanel setCanChooseDirectories:options.canChooseDirectories];
    [_currentFilePanel setAllowsMultipleSelection:options.allowsMultipleSelection];
    [_currentFilePanel setAccessoryView:hiddenFileView];
    [_currentFilePanel setResolvesAliases:NO];
    [_currentFilePanel setDirectoryURL:directory];
    [self updateHiddenFiles];

    [prefs addObserver:self
            forKeyPath:SPHiddenKeyFileVisibilityKey
               options:NSKeyValueObservingOptionNew
               context:NULL];

    [_currentFilePanel beginWithCompletionHandler:^(NSInteger returnCode) {
        // only process data, when the user pressed ok
        if (returnCode != NSModalResponseOK) {
            return;
        }

        // since ssh configs are able to consist of multiple files, bookmarks
        // for every selected file should be created in order to access them
        // read-only.
        [self->_currentFilePanel.URLs enumerateObjectsUsingBlock:^(NSURL *url, NSUInteger idxURL, BOOL *stopURL){

            if([SecureBookmarkManager.sharedInstance addBookmarkForUrl:self->_currentFilePanel.URL options:(NSURLBookmarkCreationWithSecurityScope|NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess) isForStaleBookmark:options.isForStaleBookmark] == YES){
                SPLog(@"addBookmarkForUrl success");
                CLS_LOG(@"addBookmarkForUrl success");
            }
            else{
                CLS_LOG(@"addBookmarkForUrl failed: %@", self->_currentFilePanel.URL.absoluteString);
                SPLog(@"addBookmarkForUrl failed: %@", self->_currentFilePanel.URL.absoluteString);
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

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex{

    // this could be optimised I think

    if([cell isKindOfClass:[NSCell class]] == YES){
        // default to controlTextColor
        [cell setTextColor:[NSColor controlTextColor]];

        if(staleBookmarks.count > 0){
            NSString *title = ((NSCell*)cell).title;

            for(NSString* staleFile in staleBookmarks){
                if([[staleFile dropPrefixWithPrefix:@"file://"] isEqualToString:title] == YES){
                    [cell setTextColor:[NSColor redColor]];
                }
            }
        }
    }
}

@end
