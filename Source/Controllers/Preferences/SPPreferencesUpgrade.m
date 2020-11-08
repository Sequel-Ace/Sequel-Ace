//
//  SPPreferencesUpgrade.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on October 29, 2010.
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

#import "SPPreferencesUpgrade.h"
#import "SPKeychain.h"
#import "SPFavoritesController.h"
#import "SPTreeNode.h"
#import "SPFavoriteNode.h"

@implementation SPPreferencesUpgrade

/**
 * Checks the revision number, applies any preference upgrades, and updates to latest revision.
 * Currently uses both lastUsedVersion and LastUsedVersion for <0.9.5 compatibility.
 */
void SPApplyRevisionChanges(void)
{
	NSUInteger currentVersionNumber, recordedVersionNumber = 0;
	NSMutableArray *importantUpdateNotes = [NSMutableArray new];
	
	NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];

	// Get the current bundle version number (the SVN build number) for per-version upgrades
	currentVersionNumber = [[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"] integerValue];
	
	// Get the current revision
	if ([prefs objectForKey:SPLastUsedVersion]) {
		recordedVersionNumber = [[prefs objectForKey:SPLastUsedVersion] integerValue];
	}

	// Check if version changed at all
	if (currentVersionNumber != recordedVersionNumber) {
		// Update the prefs revision
		[prefs setObject:[NSNumber numberWithInteger:currentVersionNumber] forKey:SPLastUsedVersion];

		// Inform SPAppController to check installed default Bundles for available updates
		[prefs setObject:@YES forKey:@"doBundleUpdate"];
	}

	// If no recorded version, or current version matches or is less than recorded version, don't show release notes or do version-specific processing
	if (!recordedVersionNumber) {
		return;
	}

	
	// This is how you add release notes and run specific migration steps
	if (recordedVersionNumber < 2061) {
		[importantUpdateNotes addObject:NSLocalizedString(@"There is a new option in Preferences->Alerts & Logs: \"Show warning before executing a query\". When enabled, you will be prompted to confirm that you want to execute an SQL query or edit a row.", @"Short important release note for new option in Preferences->Alerts & Logs")];
	}

	// Display any important release notes, if any.  Call this after a slight delay to prevent double help
	// menus - see http://www.cocoabuilder.com/archive/cocoa/6200-two-help-menus-why.html .
	[SPPreferencesUpgrade performSelector:@selector(showPostMigrationReleaseNotes:) withObject:importantUpdateNotes afterDelay:0.1];
}

/**
 * Displays important release notes for a new revision.
 */
+ (void)showPostMigrationReleaseNotes:(NSArray *)releaseNotes
{
	if (![releaseNotes count]) return;

	NSString *introText;
	
	if ([releaseNotes count] == 1) {
		introText = NSLocalizedString(@"We've made a few changes but we thought you should know about one particularly important one:", "Important release notes informational text, single change");	
	} 
	else {
		introText = NSLocalizedString(@"We've made a few changes but we thought you should know about some particularly important ones:", "Important release notes informational text, multiple changes");
	}

	// Create a *modal* alert to show the release notes
	NSAlert *noteAlert = [[NSAlert alloc] init];
	
	[noteAlert setAlertStyle:NSInformationalAlertStyle];
	[noteAlert setAccessoryView:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 450, 1)]];
	[noteAlert setMessageText:NSLocalizedString(@"Thanks for updating Sequel Ace!", @"Release notes dialog title thanking user for upgrade")];
	[noteAlert addButtonWithTitle:NSLocalizedString(@"Continue", @"Continue button title")];
	[noteAlert addButtonWithTitle:NSLocalizedString(@"View full release notes", @"Release notes button title")];
	[noteAlert setInformativeText:[NSString stringWithFormat:@"%@\n\n • %@", introText, [releaseNotes componentsJoinedByString:@"\n\n • "]]];

	// Show the dialog
	NSInteger returnCode = [noteAlert runModal];

	// Show releae notes if desired
	if (returnCode == NSAlertSecondButtonReturn || returnCode == NSAlertOtherReturn) {

		// Work out whether to link to the normal site or the nightly list
		NSString *releaseNotesLink = @"https://github.com/Sequel-Ace/Sequel-Ace/releases";

		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:releaseNotesLink]];
	}
}

@end
