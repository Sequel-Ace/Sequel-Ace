//
//  SPAWSMFATokenDialog.m
//  Sequel Ace
//
//  Created for AWS IAM authentication support with MFA.
//  Copyright (c) 2024 Sequel-Ace. All rights reserved.
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

#import "SPAWSMFATokenDialog.h"

@implementation SPAWSMFATokenDialog

+ (nullable NSString *)promptForMFATokenWithProfile:(NSString *)profileName
                                          mfaSerial:(NSString *)mfaSerial
                                       parentWindow:(nullable NSWindow *)parentWindow {
    // Must run UI on main thread
    __block NSString *result = nil;

    void (^showDialog)(void) = ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(@"AWS MFA Authentication Required", @"MFA dialog title");
        alert.informativeText = [NSString stringWithFormat:
            NSLocalizedString(@"Profile: %@\nMFA Device: %@\n\nEnter your 6-digit MFA code from your authenticator app:", @"MFA dialog message"),
            profileName ?: @"default",
            mfaSerial ?: @"unknown"];
        alert.alertStyle = NSAlertStyleInformational;

        // Create the accessory view with the text field
        NSTextField *tokenField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
        tokenField.placeholderString = @"123456";
        tokenField.alignment = NSTextAlignmentCenter;
        tokenField.font = [NSFont monospacedSystemFontOfSize:18 weight:NSFontWeightMedium];

        alert.accessoryView = tokenField;

        // Add buttons
        [alert addButtonWithTitle:NSLocalizedString(@"Authenticate", @"MFA authenticate button")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"cancel button")];

        // Make the text field the first responder
        [alert.window setInitialFirstResponder:tokenField];

        // Run the modal
        NSModalResponse response = [alert runModal];

        if (response == NSAlertFirstButtonReturn) {
            NSString *token = [tokenField stringValue];

            // Validate the token (should be 6 digits)
            token = [token stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

            if (token.length == 6) {
                // Check if it's all digits
                NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
                if ([token rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
                    result = token;
                    return;
                }
            }

            // Invalid token - show error
            NSAlert *errorAlert = [[NSAlert alloc] init];
            errorAlert.messageText = NSLocalizedString(@"Invalid MFA Code", @"Invalid MFA code title");
            errorAlert.informativeText = NSLocalizedString(@"Please enter a valid 6-digit MFA code.", @"Invalid MFA code message");
            errorAlert.alertStyle = NSAlertStyleWarning;
            [errorAlert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
            [errorAlert runModal];

            // Retry - recursive call will also run on main thread
            result = [self promptForMFATokenWithProfile:profileName mfaSerial:mfaSerial parentWindow:parentWindow];
        }
    };

    if ([NSThread isMainThread]) {
        showDialog();
    } else {
        dispatch_sync(dispatch_get_main_queue(), showDialog);
    }

    return result;
}

@end
