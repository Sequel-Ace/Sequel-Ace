//
//  SPPreferenceController.h
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on December 10, 2008.
//  Copyright (c) 2008 Stuart Connolly. All rights reserved.
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

#import "SPPreferencePaneProtocol.h"

@class SPGeneralPreferencePane;
@class SPTablesPreferencePane;
@class SPNotificationsPreferencePane;
@class SPEditorPreferencePane;
@class SPNetworkPreferencePane;
@class SPFilePreferencePane;
@class SPMCPPreferencePane;
@class SPPreferencePane;

/**
 * @class SPPreferenceController SPPreferenceController.h
 *
 * @author Stuart Connolly http://stuconnolly.com/
 *
 * Main preferences window controller.
 */
@interface SPPreferenceController : NSWindowController <NSToolbarDelegate>
{	
	// Preference pane controllers
	IBOutlet SPGeneralPreferencePane <SPPreferencePaneProtocol>       *generalPreferencePane;
	IBOutlet SPTablesPreferencePane  <SPPreferencePaneProtocol>       *tablesPreferencePane;
	IBOutlet SPNotificationsPreferencePane <SPPreferencePaneProtocol> *notificationsPreferencePane;
	IBOutlet SPEditorPreferencePane <SPPreferencePaneProtocol>        *editorPreferencePane;
	IBOutlet SPNetworkPreferencePane <SPPreferencePaneProtocol>       *networkPreferencePane;
	IBOutlet SPFilePreferencePane <SPPreferencePaneProtocol>          *filePreferencePane;
	SPMCPPreferencePane <SPPreferencePaneProtocol>                    *mcpPreferencePane;
	IBOutlet NSPopUpButton                                            *appearancePopUp;
	IBOutlet NSTextField                                              *appearanceMacOSVersionLabel;

	NSToolbar *toolbar;
	NSArray *preferencePanes;
	
	// Toolbar items
	NSToolbarItem *generalItem;
	NSToolbarItem *notificationsItem;
	NSToolbarItem *tablesItem;
	NSToolbarItem *editorItem;
	NSToolbarItem *shortcutItem;
	NSToolbarItem *mcpItem;
    SPPreferenceFontChangeTarget fontChangeTarget;

    @package
    NSToolbarItem *networkItem;
	NSToolbarItem *fileItem;
	
}

@property (readonly) SPGeneralPreferencePane       *generalPreferencePane;
@property (readonly) SPTablesPreferencePane        *tablesPreferencePane;
@property (readonly) SPNotificationsPreferencePane *notificationsPreferencePane;
@property (readonly) SPEditorPreferencePane        *editorPreferencePane;
@property (readonly) SPNetworkPreferencePane       *networkPreferencePane;
@property (readonly) SPFilePreferencePane          *filePreferencePane;
@property (readonly) SPMCPPreferencePane           *mcpPreferencePane;

/**
 * @property fontChangeTarget Indicates which font was changed. See SPPreferenceFontChangeTarget for values.
 */
@property (readwrite, assign) SPPreferenceFontChangeTarget fontChangeTarget;

/**
 * The old pane controllers (General, Tables, Notifications, Editor, Network, File, MCP). They stay loaded behind the
 * Claude Settings content (SAClaudeSettingsWindow.swift), which calls their code; nil until the window has loaded.
 */
@property (readonly) NSArray<SPPreferencePane<SPPreferencePaneProtocol> *> *legacyPreferencePanes;

/**
 * Old toolbar items' action, kept for outside callers that pass `fileItem` / `networkItem`: opens the Settings pane
 * that now holds that pane's settings (nil: the first pane). Doesn't show the window.
 */
- (IBAction)displayPreferencePane:(id)sender;

/**
 * Shows the Settings window on a pane (an SAClaudeSettingsPaneID raw value, e.g. @"sshSecurity") and scrolls to a row
 * (a catalog row id, e.g. @"accessibleFiles"; it decides the pane when known; nil for the top). `regrantStaleFiles` is
 * passed to the accessible-files row (a file prompt asked for stale files to be re-granted).
 */
- (void)showSettingsPane:(NSString *)paneID revealRow:(NSString *)rowID regrantStaleFiles:(BOOL)flag;
- (void)showSettingsPane:(NSString *)paneID revealRow:(NSString *)rowID;

- (void)changeDefaultFont:(id)sender;

@end
