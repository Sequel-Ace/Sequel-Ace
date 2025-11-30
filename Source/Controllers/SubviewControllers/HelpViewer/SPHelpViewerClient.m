//
//  SPHelpViewerClient.m
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

#import "SPHelpViewerClient.h"
#import "SPHelpViewerController.h"
#import "SPPostgresConnection.h"
#import "RegexKitLite.h"
#import "MGTemplateEngine.h"
#import "ICUTemplateMatcher.h"

typedef NS_ENUM(NSInteger, HelpVersionNumber) {
	MySQLVer56 = 11,
	MySQLVer57 = 12,
	MySQLVer80 = 201,
};

@interface SPHelpViewerClient () <SPHelpViewerDataSource>

+ (NSString *)linkToHelpTopic:(NSString *)aTopic;

- (void)helpViewerClosed:(NSNotification *)notification;

@end

@implementation SPHelpViewerClient

+ (void)initialize
{	
}

- (instancetype)init
{
	if (self = [super init]) {
		controller = [[SPHelpViewerController alloc] init];
		[controller setDataSource:self];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(helpViewerClosed:) name:SPUserClosedHelpViewerNotification object:controller];

		// init helpHTMLTemplate
		NSError *error;

		helpHTMLTemplate = [[NSString alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:SPHTMLHelpTemplate ofType:@"html"]
		                                                   encoding:NSUTF8StringEncoding
		                                                      error:&error];

		// Set up template engine with your chosen matcher
		engine = [[MGTemplateEngine alloc] init];
		[engine setMatcher:[ICUTemplateMatcher matcherWithTemplateEngine:engine]];

		// an error occurred while reading
		if (helpHTMLTemplate == nil) {
			helpHTMLTemplate = [@"<html><body>{{body}}</body></html>" copy]; //fallback
			NSLog(@"%@", [NSString stringWithFormat:@"Error reading “%@.html”!<br>%@", SPHTMLHelpTemplate, [error localizedFailureReason]]);
			NSBeep();
		}
	}
	
	return self;
}

#pragma mark -

- (void)helpViewerClosed:(NSNotification *)notification
{
	//we'll just proxy that notification because outsiders can't/shouldn't access the controller
	[[NSNotificationCenter defaultCenter] postNotificationName:SPUserClosedHelpViewerNotification object:self];
}

- (void)openOnlineHelpForTopic:(NSString *)searchString
{
	// PostgreSQL documentation search URL
	// https://www.postgresql.org/search/?q=SELECT
	
	NSString *url = [[NSString stringWithFormat:@"https://www.postgresql.org/search/?q=%@", searchString] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];

	SPLog("search URL: %@",url);
	
	if ([url length]) {
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
	}
}

- (NSString *)HTMLHelpContentsForSearchString:(NSString *)searchString autoHelp:(BOOL)autoHelp
{
    // PostgreSQL does not support HELP command via SQL.
    // Return a message indicating this or link to online help.
    NSMutableString *theTitle = [NSMutableString stringWithFormat:NSLocalizedString(@"Version %@", @"Mysql Help Viewer : window title : mysql server version"),[postgresConnection serverVersionString]];
    NSMutableString *theHelp = [NSMutableString string];
    
    [theHelp appendString:@"<p>PostgreSQL does not support the HELP command via SQL.</p>"];
    [theHelp appendFormat:@"<p><a href='https://www.postgresql.org/search/?q=%@'>Search PostgreSQL Documentation for '%@'</a></p>", searchString, searchString];
    
    return [self generateHelp:theTitle theHelp:theHelp];
}

- (NSString *)generateHelp:(NSString *)theTitle theHelp:(NSString *)theHelp {
	NSString *addBodyClass = @"";
	// Add CSS class if running in dark UI mode (10.14+)
	if (@available(macOS 10.14, *)) {
		NSString *match = [[[controller window] effectiveAppearance] bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
		// aqua is already the default theme
		if ([NSAppearanceNameDarkAqua isEqualToString:match]) {
			addBodyClass = @"dark";
		}
	}

	return [engine processTemplate:helpHTMLTemplate withVariables:@{
		@"bodyClass": addBodyClass,
		@"title": theTitle,
		@"body": theHelp,
	}];
}

+ (NSString *)linkToHelpTopic:(NSString *)aTopic
{
	NSString *linkTitle = [NSString stringWithFormat:NSLocalizedString(@"Show MySQL help for “%@”", @"MySQL Help Viewer : Results list : Link tooltip"),aTopic];
	return [NSString stringWithFormat:@"<a title='%2$@' href='%1$@' class='internallink'>%1$@</a>", aTopic, linkTitle];
}

- (void)setConnection:(SPPostgresConnection *)theConnection
{
	postgresConnection = theConnection;
}

/**
 * Return the Help window.
 */
- (NSWindow *)helpWebViewWindow
{
	return [controller window];
}

- (void)showHelpFor:(NSString *)aString addToHistory:(BOOL)addToHistory calledByAutoHelp:(BOOL)autoHelp
{
	[controller showHelpFor:aString addToHistory:addToHistory calledByAutoHelp:autoHelp];
}

/**
 * Show the data for "HELP 'currentWord'"
 */
- (IBAction)showHelpForCurrentWord:(id)sender
{
	NSString *searchString = [[sender string] substringWithRange:[sender getRangeForCurrentWord]];
	[controller showHelpFor:searchString addToHistory:YES calledByAutoHelp:NO];
}

#pragma mark -

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[controller setDataSource:nil]; // we are the (unretained) datasource, but the controller may outlive us (if retained by other objects)
	[controller close]; // hide the window if it is still visible (can't update anymore without delegate anyway)

	postgresConnection = nil;

}

@end
