//
//  SPNotificationsPreferencePane.m
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

#import "SPNotificationsPreferencePane.h"
#import "sequel-ace-Swift.h"

@interface SPNotificationsPreferencePane ()

@property (weak) IBOutlet NSButton *updateAvailableButton;

@end 

@implementation SPNotificationsPreferencePane

@synthesize updateAvailableButton;

#pragma mark -
#pragma mark Preference pane protocol methods

- (NSView *)preferencePaneView
{

    if(NSBundle.mainBundle.isMASVersion == YES){
        SPLog(@"isMASVersion == YES, set enabled = no, state = off");
        updateAvailableButton.enabled = NO;
        updateAvailableButton.state = NSOffState;
    }
    else {
        SPLog(@"isMASVersion == NO, set enabled = yes, state = on");
        updateAvailableButton.enabled = YES;
        updateAvailableButton.state = (NSControlStateValue)[prefs boolForKey:SPShowUpdateAvailable];
    }

    updateAvailableButton.toolTip = NSLocalizedString(@"Only available for GitHub downloads", @"Only available for GitHub downloads");

	return [self view];
}

- (NSImage *)preferencePaneIcon
{
	if (@available(macOS 11.0, *)) {
		return [NSImage imageWithSystemSymbolName:@"exclamationmark.triangle" accessibilityDescription:nil];
	} else {
		return [NSImage imageNamed:NSImageNameCaution];
	}
}

- (NSString *)preferencePaneName
{
	return NSLocalizedString(@"Alerts & Logs", @"notifications preference pane name");
}

- (NSString *)preferencePaneIdentifier
{
	return SPPreferenceToolbarNotifications;
}

- (NSString *)preferencePaneToolTip
{
	return NSLocalizedString(@"Alerts & Logs Preferences", @"notifications preference pane tooltip");
}

@end
