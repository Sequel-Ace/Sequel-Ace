//
//  SPWindowController.h
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

@import AppKit;

@class PSMTabBarControl;
@class SPDatabaseDocument;
@protocol SPWindowControllerDelegate;

@interface SPWindowController : NSWindowController <NSWindowDelegate>
{
	IBOutlet NSTabView *tabView;

	NSClipView *titleBarLineHidingView;

	NSMenuItem *closeWindowMenuItem;
	NSMenuItem *closeTabMenuItem;

	NSMutableArray *managedDatabaseConnections;
}

@property (nonatomic, weak) id<SPWindowControllerDelegate> delegate;
@property (readonly, strong) IBOutlet PSMTabBarControl *tabBar;
@property (readonly, strong) SPDatabaseDocument *selectedTableDocument;

// Database connection management
- (IBAction)addNewConnection:(id)sender;
- (IBAction)moveSelectedTabInNewWindow:(id)sender;

- (SPDatabaseDocument *)addNewConnection;

- (void)updateSelectedTableDocument;
- (void)updateAllTabTitles:(id)sender;
- (IBAction)closeTab:(id)sender;
- (IBAction)selectNextDocumentTab:(id)sender;
- (IBAction)selectPreviousDocumentTab:(id)sender;
- (NSArray <SPDatabaseDocument *> *)documents;
- (void)selectTabAtIndex:(NSInteger)index;
- (void)updateTabBar;

@end

@protocol SPWindowControllerDelegate <NSObject>

- (void)windowControllerDidCreateNewWindowController:(SPWindowController *)newWindowController;
- (void)windowControllerDidClose:(SPWindowController *)windowController;

@end
