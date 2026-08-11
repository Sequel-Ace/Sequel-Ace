//
//  SPHelpViewerClient.h
//  sequel-pro
//
//  Created by Max Lohrmann on 25.05.18.
//  Copyright (c) 2018 Max Lohrmann. All rights reserved.
//  Parts relocated from existing files. Previous copyright applies.
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

@class SAHelpViewerWindowController;
@class SPMySQLConnection;
@class MGTemplateEngine;

/**
 * Magic search string the help viewer uses to request the table of contents.
 */
extern NSString * const SPHelpViewerSearchTOC;

/**
 * This notification is posted by the SAHelpViewerWindowController when the user
 * triggered closing the help viewer window (or by -performClose:).
 * The window is not guaranteed to be off screen already, when the notification is sent.
 *
 * It will NOT be sent when the window was closed or hidden by code (including app termination).
 */
extern NSString * const SPUserClosedHelpViewerNotification;

@protocol SPHelpViewerDataSource <NSObject>

@required
/**
 * When called with a search string this method should open the user's default browser
 * with an URL to the MySQL online manual for the page that explains the search string.
 */
- (void)openOnlineHelpForTopic:(NSString *)searchString;

/**
 * This method is called by the help viewer's window controller when it wants to
 * receive the HTML page to display in response to a search string.
 *
 * The implementation has to handle the magic search string SPHelpViewerSearchTOC to
 * return a table of contents document.
 */
- (NSString *)HTMLHelpContentsForSearchString:(NSString *)searchString autoHelp:(BOOL)autoHelp;

@end

/**
 * This is the client side of the Help Viewer window, i.e. this class
 * can be instantiated from within an xib file as a custom object.
 *
 * It also contains the logic to look up the help in the mysql database
 * using the mySQLConnection (which does not belong into the Help Viewer's
 * window controller).
 *
 * Notifications posted:
 *  * SPUserClosedHelpViewerNotification
 *      When the user triggered closing the help viewer window
 */
@interface SPHelpViewerClient : NSObject
{
	SAHelpViewerWindowController *controller;

	NSString *helpHTMLTemplate;
	SPMySQLConnection *mySQLConnection;

	MGTemplateEngine *engine;
}

- (void)setConnection:(SPMySQLConnection *)theConnection;

- (NSWindow *)helpWebViewWindow;

- (void)showHelpFor:(NSString *)aString addToHistory:(BOOL)addToHistory calledByAutoHelp:(BOOL)autoHelp;

// this is not bound in Interface Builder, but used by the SPTextView context menu
- (IBAction)showHelpForCurrentWord:(id)sender;
@end
