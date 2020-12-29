//
//  SPAppController.h
//  sequel-pro
//
//  Created by Lorenz Textor (lorenz@textor.ch) on May 1, 2002.
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

@class SPPreferenceController;
@class SPAboutController;
@class SPDatabaseDocument;
@class SPBundleEditorController;
@class SPWindowController;

@import Firebase;

@interface SPAppController : NSObject <NSApplicationDelegate, NSOpenSavePanelDelegate, NSFileManagerDelegate, NSWindowDelegate>
{
	SPAboutController *aboutController;
	SPPreferenceController *prefsController;

	id encodingPopUp;

	NSURL *_sessionURL;
	NSMutableDictionary *_spfSessionDocData;

	NSMutableArray *runningActivitiesArray;

	NSString *lastBundleBlobFilesDirectory;
}

@property (readwrite, copy) NSString *lastBundleBlobFilesDirectory;


// IBAction methods
- (IBAction)openAboutPanel:(id)sender;
- (IBAction)openPreferences:(id)sender;
- (IBAction)openConnectionSheet:(id)sender;

// Services menu methods
- (void)doPerformQueryService:(NSPasteboard *)pboard userData:(NSString *)data error:(NSString **)error;
- (void)rebuildMenus;
- (IBAction)reloadBundles:(id)sender;
- (IBAction)openBundleEditor:(id)sender;
- (IBAction)bundleCommandDispatcher:(id)sender;


// Menu methods
- (IBAction)visitWebsite:(id)sender;
- (IBAction)visitHelpWebsite:(id)sender;
- (IBAction)visitFAQWebsite:(id)sender;
- (IBAction)viewKeyboardShortcuts:(id)sender;

// Getters
- (SPPreferenceController *)preferenceController;
- (NSArray *)orderedDatabaseConnectionWindows;
- (SPDatabaseDocument *)frontDocument;
- (NSURL *)sessionURL;
- (NSDictionary *)spfSessionDocData;

- (void)setSessionURL:(NSString *)urlString;
- (void)setSpfSessionDocData:(NSDictionary *)data;

// Others
- (NSString *)generateHTML:(NSString *)theTitle theHTML:(NSString *)someHTML;
- (void)displayStaleBookmarkReminderWindow:(NSString *)staleBookmarksString;
- (void)registerActivity:(NSDictionary *)commandDict;
- (void)removeRegisteredActivity:(NSInteger)pid;
- (NSArray *)runningActivities;
- (void)defaultsChanged:(NSNotification *)notification;
- (void)switchAppearance;

- (void)handleEventWithURL:(NSURL *)url;
- (NSString*)doSQLSyntaxHighlightForString:(NSString *)sqlText cssLike:(BOOL)cssLike;

- (NSDictionary *)shellEnvironmentForDocument:(NSString *)docUUID;


#pragma mark - SPAppleScriptSupport

- (NSArray *)orderedDocuments;
- (void)insertInOrderedDocuments:(SPDatabaseDocument *)doc;
- (NSArray *)orderedWindows;
- (id)handleQuitScriptCommand:(NSScriptCommand *)command;
- (id)handleOpenScriptCommand:(NSScriptCommand *)command;

#pragma mark - SPWindowManagement

- (IBAction)newWindow:(id)sender;
- (IBAction)newTab:(id)sender;
- (IBAction)duplicateTab:(id)sender;

- (SPWindowController *)newWindow;
- (SPDatabaseDocument *)makeNewConnectionTabOrWindow;
- (SPWindowController *)frontController;

- (NSWindow *)frontDocumentWindow;
- (void)tabDragStarted:(id)sender;

@end
