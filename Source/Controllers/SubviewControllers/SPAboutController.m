//
//  SPAboutController.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on November 18, 2009.
//  Copyright (c) 2009 Stuart Connolly. All rights reserved.
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

#import "SPAboutController.h"
#import "sequel-ace-Swift.h"


static NSString *SPCreditsFilename = @"Credits";
static NSString *SPLicenseFilename = @"License";

static NSString *SPAboutPanelNibName = @"AboutPanel";

@interface SPAboutController ()

- (void)_setVersionLabel:(BOOL)isNightly;
- (NSMutableAttributedString *)_loadRtfResource:(NSString *)filename;

@end

@implementation SPAboutController

#pragma mark -

- (instancetype)init
{
	return [super initWithWindowNibName:SPAboutPanelNibName];
}

- (void)awakeFromNib
{
    [super awakeFromNib];

    NSBundle *mainBundle = [NSBundle mainBundle];

	BOOL isSnapshotBuild = mainBundle.isSnapshotBuild;
	
	// Set the application name, but only include the major version if this is not a nightly build.
	[appNameVersionTextField setStringValue:[NSString stringWithFormat:@"Sequel Ace%@", (isSnapshotBuild ? @" Beta" : @"")]];

	[self _setVersionLabel:isSnapshotBuild];
	
	// Set the credits
	[[appCreditsTextView textStorage] appendAttributedString:[self _loadRtfResource:SPCreditsFilename]];
	
	// Set the license
	[[appLicenseTextView textStorage] appendAttributedString:[self _loadRtfResource:SPLicenseFilename]];
}

#pragma mark -
#pragma mark IB action methods

/**
 * Display the license sheet.
 */
- (IBAction)openApplicationLicenseSheet:(id)sender {
	[self.window beginSheet:appLicensePanel completionHandler:nil];
}

/**
 * Close the license sheet.
 */
- (IBAction)closeApplicationLicenseSheet:(id)sender;
{
	[NSApp endSheet:appLicensePanel returnCode:0];
	[appLicensePanel orderOut:self];
}

#pragma mark -
#pragma mark Private API

/**
 * Set the UI version labels.
 *
 * @param isSnapshot Indicates whether or not this is a snapshot build.
 */
- (void)_setVersionLabel:(BOOL)isSnapshotBuild
{
    NSBundle *mainBundle = [NSBundle mainBundle];

    NSString *textFieldString = [NSString stringWithFormat:@"Version %@\n%@ %@",
                                 mainBundle.version,
                                 isSnapshotBuild ? NSLocalizedString(@"Beta Build", @"beta build label") : NSLocalizedString(@"Build", @"build label"),
                                 mainBundle.build];

	[appBuildVersionTextField setStringValue:textFieldString];
}

/**
 * Loads the resource with the supplied name and sets any necessary string attributes.
 */
- (NSAttributedString *)_loadRtfResource:(NSString *)filename
{
		
	NSURL *url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:filename ofType:@"rtf"] isDirectory:NO];
	
	NSMutableAttributedString *resource = [[NSMutableAttributedString alloc] initWithURL:url options:@{NSDocumentTypeDocumentOption : NSRTFTextDocumentType} documentAttributes:nil error:nil];
	
	[resource addAttribute:NSForegroundColorAttributeName value:[NSColor textColor] range:NSMakeRange(0, [resource length])];

	return resource;
}

@end
