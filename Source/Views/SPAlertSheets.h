//
//  SPAlertSheets.h
//  sequel-pro
//
//  Created by Rowan Beentje on January 20, 2010.
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

@interface SPAlertSheets : NSObject

+ (void)beginWaitingAlertSheetWithTitle:(NSString *)title
                          defaultButton:(NSString *)defaultButton
                        alternateButton:(NSString *)alternateButton
                            otherButton:(NSString *)otherButton
                             alertStyle:(NSAlertStyle)alertStyle
                              docWindow:(NSWindow *)docWindow
                          modalDelegate:(id)modalDelegate
                         didEndSelector:(SEL)didEndSelector
                            contextInfo:(void *)contextInfo
                               infoText:(NSString *)infoText
                             returnCode:(NSInteger *)returnCode;

@end

void SPBeginAlertSheet(
	NSString *title,
	NSString *defaultButton,
	NSString *alternateButton,
	NSString *otherButton,
	NSWindow *docWindow,
		  id modalDelegate,
		 SEL didEndSelector,
		void *contextInfo,
	NSString *msg
);

void SPOnewayAlertSheet(
	NSString *title,
	NSWindow *docWindow,
	NSString *msg
);

void SPOnewayAlertSheetWithStyle(
	NSString *title,
	NSString *defaultButton,
	NSWindow *docWindow,
	NSString *msg,
	NSAlertStyle alertStyle
);
