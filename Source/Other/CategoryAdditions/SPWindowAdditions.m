//
//  SPWindowAdditions.m
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

#import "SPWindowAdditions.h"
#import "SPDatabaseDocument.h"

#import "sequel-ace-Swift.h"

@implementation NSWindow (SPWindowAdditions)

/**
 * Resizes this window to the size of the supplied view.
 */
- (void)resizeForContentView:(NSView *)view
{
	//Zoomed in handling
	if([self frame].size.width == [self maxSize].width) {
		return;
	}

	NSSize viewSize = view.fittingSize;
	NSRect frame    = [self frame];

	if(viewSize.height < [self contentMinSize].height) {
		viewSize.height = [self contentMinSize].height;
	}
	if(viewSize.width < [self contentMinSize].width) {
		viewSize.width = [self contentMinSize].width;
	}

	CGFloat newHeight = viewSize.height + (self.frame.size.height - self.contentView.frame.size.height);
	frame.origin.y += frame.size.height - newHeight;

	frame.size.height = MAX(newHeight, [self minSize].height);
	//If width is bigger, keep it the same for consistency
	frame.size.width  = MAX(MAX(self.contentView.frame.size.width, viewSize.width + (self.frame.size.width - self.contentView.frame.size.width)), [self minSize].width);

	[self setFrame:frame display:YES animate:YES];
}

/**
 * Three finger multi-touch right/left swipe event to go back/forward in table history.
 */
- (void)swipeWithEvent:(NSEvent *)event
{
	if (![[self delegate] isKindOfClass:[SPWindowController class]]) return;

	id frontDoc = [(SPWindowController *)[self delegate] databaseDocument];

	if (frontDoc && [frontDoc isKindOfClass:[SPDatabaseDocument class]] && [frontDoc valueForKeyPath:@"spHistoryControllerInstance"] && ![frontDoc isWorking])
	{
#warning Private ivar accessed from outside (#2978)
		if ([event deltaX] == -1.0f) {
			[[frontDoc valueForKeyPath:@"spHistoryControllerInstance"] valueForKey:@"goForwardInHistory"];
		}
		else if ([event deltaX] == 1.0f) {
			[[frontDoc valueForKeyPath:@"spHistoryControllerInstance"] valueForKey:@"goBackInHistory"];
		}
	}
}

@end
