//
//  SPPreferencePane.m
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

#import "SPPreferencePane.h"
#import "SPAppController.h"
#import "sequel-ace-Swift.h"

@implementation SPPreferencePane

#pragma mark -
#pragma mark Intialisation

/**
 * Initialisation. Establishes a reference to the user's defaults to be used by subclasses.
 */
- (instancetype)init
{
	if ((self = [super initWithNibName:nil bundle:nil])) {
		prefs = [NSUserDefaults standardUserDefaults];
	}
	
	return self;
}

- (void)preferencePaneWillBeShown
{
	// Default: do nothing. Override in subclass.
}

- (NSView *)modifyAndReturnBookmarkHelpView{

    SPAppController *appCon = SPAppDelegate;

    NSView *helpView = [appCon staleBookmarkHelpView];
    HyperlinkTextField *helpViewTF = [appCon staleBookmarkTextField];
    NSTextFieldCell *helpViewTFC = [appCon staleBookmarkTextFieldCell];

    helpViewTF.href = SPDocsAppSandbox;

    helpViewTFC.title = NSLocalizedString(@"App Sandbox Info", @"App Sandbox Info");

    [helpViewTF reapplyAttributes];

    return helpView;
}
@end
