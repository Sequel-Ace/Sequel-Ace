//
//  SPWindowController.m
//  sequel-pro
//
//  Created by Rowan Beentje on May 16, 2010.
//  Copyright (c) 2010 Rowan Beentje. All rights reserved.
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

#import "SPWindowController.h"
#import "SPDatabaseDocument.h"
#import "SPAppController.h"
#import "PSMTabDragAssistant.h"
#import "SPConnectionController.h"
#import "SPFavoritesOutlineView.h"
#import "SPWindow.h"

#import "PSMTabBarControl.h"
#import "PSMTabStyle.h"

#import "sequel-ace-Swift.h"

@interface SPWindowController ()

- (void)_switchOutSelectedTableDocument:(SPDatabaseDocument *)newDoc;
- (void)_selectedTableDocumentDeallocd:(NSNotification *)notification;

@property (readwrite, strong) SPDatabaseDocument *selectedTableDocument;

@end

@implementation SPWindowController

#pragma mark -
#pragma mark Initialisation

- (instancetype)init {
    SPWindow *newWindow = [[SPWindow alloc] init];
    if (self = [self initWithWindow:newWindow]) {

    }
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];

    [self setupAppearance];
    [self setupConstraints];

    [self _switchOutSelectedTableDocument:nil];

    NSWindow *window = [self window];

    [window setCollectionBehavior:[window collectionBehavior] | NSWindowCollectionBehaviorFullScreenPrimary];

    // Disable automatic cascading - this occurs before the size is set, so let the app
    // controller apply cascading after frame autosaving.
    [self setShouldCascadeWindows:NO];

    // Retrieve references to the 'Close Window' and 'Close Tab' menus.  These are updated as window focus changes.
    NSMenu *mainMenu = [NSApp mainMenu];
    _closeWindowMenuItem = [[[mainMenu itemWithTag:SPMainMenuFile] submenu] itemWithTag:SPMainMenuFileClose];
    _closeTabMenuItem = [[[mainMenu itemWithTag:SPMainMenuFile] submenu] itemWithTag:SPMainMenuFileCloseTab];

    // Because we are a document-based app we automatically adopt window restoration on 10.7+.
    // However that causes a race condition with our own window setup code.
    // Remove this when we actually support restoration.
    if ([window respondsToSelector:@selector(setRestorable:)]) {
        [window setRestorable:NO];
    }
}

#pragma mark -
#pragma mark Database connection management

- (SPDatabaseDocument *)addNewConnection
{
	// Create a new database connection view
	SPDatabaseDocument *databaseDocument = [[SPDatabaseDocument alloc] initWithWindowController:self];
    self.contentViewController = databaseDocument;

    // Tell the new database connection view to set up the window and update titles
    [databaseDocument didBecomeActiveTabInWindow];
    [databaseDocument updateWindowTitle:self];

    return databaseDocument;
}

/**
 * Close the current tab, or if it's the last in the window, the window.
 */
- (IBAction)closeTab:(id)sender
{

		//trying to close the window will itself call parentTabShouldClose for all tabs in windowShouldClose:
		[[self window] performClose:self];
        [self.delegate windowControllerDidClose:self];
}

/**
 * Menu item validation.
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	
	// See if the front document blocks validation of this item
	if (![self.selectedTableDocument validateMenuItem:menuItem]) return NO;

	return YES;
}

/**
 * Opens the current connection in a new tab, but only if it's already connected.
 */
- (void)openDatabaseInNewTab
{
	if ([self.selectedTableDocument database]) {
		[self.selectedTableDocument openDatabaseInNewTab:self];
	}
}

#pragma mark -
#pragma mark First responder forwarding to active tab

/**
 * Delegate unrecognised methods to the selected table document, thanks to the magic
 * of NSInvocation (see forwardInvocation: docs for background). Must be paired
 * with methodSignationForSelector:.
 */
- (void)forwardInvocation:(NSInvocation *)theInvocation
{
	SEL theSelector = [theInvocation selector];
	
	if (![self.selectedTableDocument respondsToSelector:theSelector]) {
		[self doesNotRecognizeSelector:theSelector];
	}
	
	[theInvocation invokeWithTarget:self.selectedTableDocument];
}

/**
 * Return the correct method signatures for the selected table document if
 * NSObject doesn't implement the requested methods.
 */
- (NSMethodSignature *)methodSignatureForSelector:(SEL)theSelector
{
	NSMethodSignature *defaultSignature = [super methodSignatureForSelector:theSelector];
	
	return defaultSignature ? defaultSignature : [self.selectedTableDocument methodSignatureForSelector:theSelector];
}

/**
 * Override the default repondsToSelector:, returning true if either NSObject
 * or the selected table document supports the selector.
 */
- (BOOL)respondsToSelector:(SEL)theSelector
{
	return ([super respondsToSelector:theSelector] || [self.selectedTableDocument respondsToSelector:theSelector]);
}

#pragma mark -
#pragma mark Private API

- (void)_switchOutSelectedTableDocument:(SPDatabaseDocument *)newDoc
{
	NSAssert([NSThread isMainThread], @"Switching the selectedTableDocument via a background thread is not supported!");
	
	// shortcut if there is nothing to do
    if (self.selectedTableDocument == newDoc) {
        return;
    }
	
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	if (self.selectedTableDocument) {
		[nc removeObserver:self name:SPDocumentWillCloseNotification object:self.selectedTableDocument];
		self.selectedTableDocument = nil;
	}
	if (newDoc) {
		[nc addObserver:self selector:@selector(_selectedTableDocumentDeallocd:) name:SPDocumentWillCloseNotification object:newDoc];
		self.selectedTableDocument = newDoc;
	}
}

- (void)_selectedTableDocumentDeallocd:(NSNotification *)notification
{
	[self _switchOutSelectedTableDocument:nil];
}

#pragma mark -

- (void)dealloc {
	[self _switchOutSelectedTableDocument:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

@end
