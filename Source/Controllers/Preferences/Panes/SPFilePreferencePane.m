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

@property (readwrite, strong) NSMutableArray<NSDictionary<NSString *, id> *> *bookmarks;
@property (readwrite, strong) NSMutableArray<NSString *> *staleBookmarks;
@property (readwrite, strong) NSMutableIndexSet *selectedRows;
@property (readwrite, assign) BOOL weHaveStaleBookmarks;

@end

@implementation SPFilePreferencePane

@synthesize bookmarks, staleBookmarks, staleLabel, weHaveStaleBookmarks, selectedRows;

- (instancetype)init
{
    self = [super init];

    if (self) {
        fileNames = [[NSMutableArray alloc] init];
        bookmarks = [[NSMutableArray alloc] init];
        staleBookmarks = [[NSMutableArray alloc] init];
        selectedRows = [NSMutableIndexSet indexSet];
        weHaveStaleBookmarks = NO;

        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_refreshBookmarks) name:SPBookmarksChangedNotification object:SecureBookmarkManager.sharedInstance];
    }

    return self;
}

- (IBAction)doubleClick:(id)sender {

    SPLog(@"clickedColumn = %li", (long)fileView.clickedColumn);
    SPLog(@"clickedRow = %li", (long)fileView.clickedRow);

    SPLog(@"selectedRows = %@", selectedRows);
    SPLog(@"selectedRows count = %lu", (unsigned long)selectedRows.count);
    CLS_LOG(@"selectedRows = %@", selectedRows);
    CLS_LOG(@"selectedRows count = %lu", (unsigned long)selectedRows.count);
    SPLog(@"selectedRows firstIndex = %lu", (unsigned long)[selectedRows firstIndex]);
    SPLog(@"selectedRows lastIndex = %lu", (unsigned long)[selectedRows lastIndex]);

    if(weHaveStaleBookmarks == YES){

        PanelOptions *options = [[PanelOptions alloc] init];

        options.allowsMultipleSelection = YES;
        options.canChooseFiles = YES;
        options.canChooseDirectories = YES;
        options.isForStaleBookmark = YES;
        options.title = NSLocalizedString(@"Please re-select the file '%@' in order to restore Sequel Ace's access.", "Title for Stale Bookmark file selection dialog");

        BOOL __block match = NO;

        /*
            remember we added the stale files to the end of the fileNames array, so we need to go backwards
            so we get the starting index in selectedRows that matches a file in fileNames.
            This is options.index.

            See the example in loadBookmarks. With that fileNames array and selectedRows indexset, the code below would go:

            First iteration

            idx = 5
            fileName = StaleFile6.txt
            options.index = 5

            Second iteration

            idx = 4
            fileName = StaleFile5.txt
            options.index = 4

            Third and last iteration

            idx = 3
            fileName = StaleFile3.txt
            options.index = 3

            Thus we know the first index in selectedRows is 3

            Er, just seen [selectedRows firstIndex] does the same!

         */

        [selectedRows enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger idx, BOOL *stop) {
            // retrieve the filename
            NSString *fileName = [NSString stringWithFormat:@"file://%@", [fileNames safeObjectAtIndex:idx]];

            SPLog(@"idx = %lu", (unsigned long)idx);

            // check they really clicked on a stale file
            for(NSString* staleFile in staleBookmarks){
                if([staleFile isEqualToString:fileName] == YES){
                    match = YES;
                    SPLog(@"breaking. stale file MATCH = %@", fileName);
                    break;
                }
            }

            if(match == YES){
                SPLog(@"fileName = %@", fileName);
                if(fileName != nil){
                    [options.fileNames addObject:fileName];
                    options.index = idx;
                }
                else{
                    SPLog(@"ERROR: fileName is nil");
                    CLS_LOG(@"ERROR: fileName is nil");
                    // break?
                }
            }
            else{
                SPLog(@"Not a stale file");
                [fileView deselectRow:idx];
            }
        }];


        // only display panel if they clicked on a stale file.
        if(match == YES){
            SPLog(@"calling chooseFileWithOptions: %@", [options jsonStringWithPrettyPrint:YES]);
            CLS_LOG(@"calling chooseFileWithOptions: %@", [options jsonStringWithPrettyPrint:YES]);
            [self chooseFileWithOptions:options];
        }
        else{
            SPLog(@"No stale files selected");
            CLS_LOG(@"No stale files selected");
        }
    }
}

- (void)dealloc
{
    SPLog(@"dealloc");
    CLS_LOG(@"dealloc");
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

/**
 * Called shortly before the preference pane will be made visible
 *  so this is where we decide to show the stale file panel or not
 */
- (void)preferencePaneWillBeShown
{
    SPLog(@"calling loadBookmarks");
    CLS_LOG(@"calling loadBookmarks");
    [self loadBookmarks];

    if(weHaveStaleBookmarks == YES){
        SPLog(@"weHaveStaleBookmarks == YES, calling doubleClick");
        CLS_LOG(@"weHaveStaleBookmarks == YES, calling doubleClick");
        [self doubleClick:nil];
    }
}

- (void)loadBookmarks
{
    SPLog(@"loadBookmarks");
    CLS_LOG(@"loadBookmarks");

    [bookmarks setArray:SecureBookmarkManager.sharedInstance.bookmarks];
    [staleBookmarks setArray:SecureBookmarkManager.sharedInstance.staleBookmarks];

    if(staleBookmarks.count > 0){
        staleLabel.hidden = NO;
        weHaveStaleBookmarks = YES;
    }
    else{
        staleLabel.hidden = YES;
        weHaveStaleBookmarks = NO;
        SPLog(@"weHaveStaleBookmarks == NO");
        CLS_LOG(@"weHaveStaleBookmarks == NO");
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

/*
 How to generate an indexset of stale file positions

Example Good Bookmark list

 File1.txt
 File2.txt
 File3.txt

Add on stale files

 StaleFile4.txt
 StaleFile5.txt
 StaleFile6.txt

 This gives us a fileNames array of

 "fileNames" : [
    "file:File1.txt",
    "file:File2.txt",
    "file:File3.txt",
    "file:StaleFile4.txt",
    "file:StaleFile5.txt"
    "file:StaleFile6.txt"
 ]

Thus, if the user selected the three stale files and double clicked,
which is what we are trying to simulate, the selected rows in the table
 would be 4, 5 and 6

 In the fileNames array, these are at index 3, 4 and 5

 Remember we took the bookmarks, and added on the stale files

 So to create the indexset (selectedRows) we take the count of bookmarks
 and for each additional stale file we increment the index.

 StaleFile4.txt - add index bookmark.count     = 3
 StaleFile5.txt - add index bookmark.count + 1 = 4
 StaleFile6.txt - add index bookmark.count + 2 = 5

thus we get an index set with number of indexes: 3 (in 1 ranges), indexes: (3-5)

 Which is what is used in doubleClick:

 */

    NSUInteger index = bookmarks.count-1;

    // add on any stale bookmarks
    for(NSString* staleFile in staleBookmarks){
        [fileNames addObject:[staleFile dropPrefixWithPrefix:@"file://"]];
        SPLog(@"fileNames adding stale file: %@", staleFile);
        [selectedRows addIndex:++index];
    }

    SPLog(@"bookmarks.count: %lu", (unsigned long)bookmarks.count);
    SPLog(@"staleBookmarks.count: %lu", (unsigned long)staleBookmarks.count);
    SPLog(@"fileNames.count: %lu", (unsigned long)fileNames.count);
    CLS_LOG(@"bookmarks.count: %lu", (unsigned long)bookmarks.count);
    CLS_LOG(@"staleBookmarks.count: %lu", (unsigned long)staleBookmarks.count);
    CLS_LOG(@"fileNames.count: %lu", (unsigned long)fileNames.count);

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

    PanelOptions *options = [[PanelOptions alloc] init];

    options.allowsMultipleSelection = YES;
    options.canChooseFiles = YES;
    options.canChooseDirectories = YES;
    options.isForStaleBookmark = YES;
    options.isForStaleBookmark = NO;
    options.title = NSLocalizedString(@"Please choose a file or folder to grant Sequel Ace access to.", "Please choose a file or folder to grant Sequel Ace access to.");
    options.fileNames = nil;

    SPLog(@"calling chooseFileWithOptions: %@", [options jsonStringWithPrettyPrint:YES]);
    CLS_LOG(@"calling chooseFileWithOptions: %@", [options jsonStringWithPrettyPrint:YES]);
    
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


- (void)chooseFileWithOptions:(PanelOptions*)options
{
    // retrieve the file manager in order to fetch the current user's home
    // directory
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *directory = nil;

    NSString *message = options.title;

    if(options.fileNames.count == 0){
        SPLog(@"standard adding new file");
        CLS_LOG(@"standard adding new file");
        if ([fileManager respondsToSelector:@selector(homeDirectoryForCurrentUser)]) {
            directory = [[fileManager homeDirectoryForCurrentUser] URLByAppendingPathComponent:@".ssh"];
        } else {
            directory = [[NSURL fileURLWithPath:NSHomeDirectory()] URLByAppendingPathComponent:@".ssh"];
        }
    }
    else{
        SPLog(@"refreshing stale bookmarks. count: %lu", (unsigned long)options.fileNames.count);
        CLS_LOG(@"refreshing stale bookmarks. count: %lu", (unsigned long)options.fileNames.count);
        // add on a trailing / to set the panel directory to the file
        // this has the side effect of pre-selecting the file for the user
        // see: https://stackoverflow.com/a/18931821/150772
        NSString *fileName =  [options.fileNames safeObjectAtIndex:0];
        NSString *staleFileDir = [NSString stringWithFormat:@"%@/", fileName];
        SPLog(@"staleFileDir: %@", staleFileDir);
        directory = [NSURL fileURLWithPath:staleFileDir];
        message = [NSString stringWithFormat:options.title, [fileName lastPathComponent]];
    }

    _currentFilePanel = [NSOpenPanel openPanel];
    [_currentFilePanel setMessage:message];
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


    // really want to move the file panel to the front here
    // not sure how.
    // update - now it seems to be frontmost .... ???

    [_currentFilePanel beginWithCompletionHandler:^(NSInteger returnCode) {
        // only process data, when the user pressed ok
        if (returnCode != NSModalResponseOK) {
            SPLog(@"user pressed cancel");
            CLS_LOG(@"user pressed cancel");
            return;
        }

        [self->_currentFilePanel orderOut:nil];
        // since ssh configs are able to consist of multiple files, bookmarks
        // for every selected file should be created in order to access them
        // read-only.
        [self->_currentFilePanel.URLs enumerateObjectsUsingBlock:^(NSURL *url, NSUInteger idxURL, BOOL *stopURL){

            if([SecureBookmarkManager.sharedInstance addBookmarkForUrl:self->_currentFilePanel.URL options:(NSURLBookmarkCreationWithSecurityScope|NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess) isForStaleBookmark:options.isForStaleBookmark] == YES){
                SPLog(@"addBookmarkForUrl success");
                CLS_LOG(@"addBookmarkForUrl success");

                if(options.isForStaleBookmark == YES){

                    // Here we need to maintain the options filnames array
                    // and the selectedRows index
                    SPLog(@"options.fileNames: %@", options.fileNames);
                    SPLog(@"self->selectedRows: %@", self->selectedRows);
                    SPLog(@"removing stale file from options.fileNames at index 0");
                    SPLog(@"removing stale file from self->selectedRows at index: %lu", (unsigned long)options.index);
                    CLS_LOG(@"removing stale file from options.fileNames");

                    SPLog(@"selectedRows count = %lu", (unsigned long)self->selectedRows.count);

                    // we need to keep track of how many files there are to prompt for
                    // so we remove from the filenames array. Index 0 is safe.
                    [options.fileNames removeObjectAtIndex:0];
                    // to keep things nice and tidy, remove the index?
                    [self->selectedRows removeIndex:options.index];
                    SPLog(@"options.fileNames: %@", options.fileNames);
                    SPLog(@"self->selectedRows: %@", self->selectedRows);

                    // increment for the next file
                    options.index++;
                }
            }
            else{
                CLS_LOG(@"addBookmarkForUrl failed: %@", self->_currentFilePanel.URL.absoluteString);
                SPLog(@"addBookmarkForUrl failed: %@", self->_currentFilePanel.URL.absoluteString);
            }
        }];

        if(options.fileNames.count> 0){
            SPLog(@"User selected more than one file, call ourselves again");
            CLS_LOG(@"User selected more than one file, call ourselves again");
            [self chooseFileWithOptions:options];
        }
        else{
            SPLog(@"End, reload bookmarks");
            CLS_LOG(@"End, reload bookmarks");
            [self loadBookmarks];
            self->_currentFilePanel = nil;

            // this shouldn't be needed, but just in case
            [self->selectedRows removeAllIndexes];
            SPLog(@"self->selectedRows: %@", self->selectedRows);
            CLS_LOG(@"self->selectedRows: %@", self->selectedRows);
        }
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

        if(weHaveStaleBookmarks == YES){
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
