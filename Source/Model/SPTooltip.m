//
//  SPTooltip.m
//  sequel-pro
//
//  Created by Hans-Jörg Bibiko on August 11, 2009.
//  Copyright (c) 2009 Hans-Jörg Bibiko. All rights reserved.
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

//	Usage:
//	#import "SPTooltip.h"
//	
//	[SPTooltip showWithObject:@"<h1>Hello</h1>I am a <b>tooltip</b>" ofType:@"html" 
//			displayOptions:[NSDictionary dictionaryWithObjectsAndKeys:
//			@"#EEEEEE", @"backgroundcolor",
//			@"transparent", @"transparent", nil]];
//	
//	[SPTooltip  showWithObject:(id)content 
//					atLocation:(NSPoint)point 
//						ofType:(NSString *)type 
//				displayOptions:(NSDictionary *)displayOptions]
//	
//			content: a NSString with the actual content; a NSImage object AND type:"image"
//			  point: n NSPoint where the tooltip should be shown
//			         if not given it will be shown under the current caret position or
//			         if no caret could be found in the upper left corner of the current window
//			   type: a NSString of: "text", "html", or "image"; no type - 'text' is default
//	 displayOptions: a NSDictionary with the following keys (all values must be of type NSString):
//	                        backgroundcolor (as #RRGGBB), transparent (any value)
//	                 if no displayOptions are passed or if a key doesn't exist the following default
//	                 are taken:
//	                       "Lucida Grande", "10", "#F9FBC5", NO
//	
//	See more possible syntaxa in SPTooltip to init a tooltip

#import "SPTooltip.h"
#import "SPOSInfo.h"

#include <tgmath.h>

static NSInteger spTooltipCounter = 0;

static CGFloat slow_in_out (CGFloat t)
{
	if(t < 1.0f)
		t = 1.0f / (1.0f + exp((-t*12.0f)+6.0f));
	if(t>1.0f) return 1.0f;
	return t;
}

@interface SPTooltip ()

- (void)setContent:(NSString *)content withOptions:(NSDictionary *)displayOptions;
- (void)runUntilUserActivity;
- (void)stopAnimation:(id)sender;
- (void)sizeToContent;
+ (NSPoint)caretPosition;
+ (void)setDisplayOptions:(NSDictionary *)aDict;
- (void)initMeWithOptions:(NSDictionary *)displayOptions;

@end

@implementation SPTooltip

// ==================
// = Setup/teardown =
// ==================

+ (void)showWithObject:(id)content atLocation:(NSPoint)point
{
	[self showWithObject:content atLocation:point ofType:@"text" displayOptions:@{}];
}

+ (void)showWithObject:(id)content atLocation:(NSPoint)point ofType:(NSString *)type
{
	[self showWithObject:content atLocation:point ofType:type displayOptions:nil];
}

+ (void)showWithObject:(id)content
{
	[self showWithObject:content atLocation:[self caretPosition] ofType:@"text" displayOptions:nil];
}

+ (void)showWithObject:(id)content ofType:(NSString *)type
{
	[self showWithObject:content atLocation:[self caretPosition] ofType:type displayOptions:nil];
}

+ (void)showWithObject:(id)content ofType:(NSString *)type displayOptions:(NSDictionary *)options
{
	[self showWithObject:content atLocation:[self caretPosition] ofType:type displayOptions:options];
}

+ (void)showWithObject:(id)content atLocation:(NSPoint)point ofType:(NSString *)type displayOptions:(NSDictionary *)displayOptions
{

	spTooltipCounter++;
	
	SPTooltip* tip = [SPTooltip new]; // Automatically released on close
	[tip initMeWithOptions:displayOptions];
	[tip setFrameTopLeftPoint:point];

	if([type isEqualToString:@"text"]) {
		NSString* html = nil;
		NSMutableString* text = [[(NSString*)content mutableCopy] autorelease];
		if(text)
		{
			[text replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, [text length])];
			[text replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, [text length])];
			html = text;
		}
		else
		{
			html = @"Error";
		}
		[tip setContent:html withOptions:displayOptions];
	}
	else if([type isEqualToString:@"html"]) {
		[tip setContent:(NSString*)content withOptions:displayOptions];
	}
	else if([type isEqualToString:@"image"]) {
		[tip setBackgroundColor:[NSColor clearColor]];
		[tip setOpaque:NO];
		[tip setLevel:NSNormalWindowLevel];
		[tip setExcludedFromWindowsMenu:YES];
		[tip setAlphaValue:1];

		NSSize s = [(NSImage *)content size];
		
		// Downsize a large image
		NSInteger w = s.width;
		NSInteger h = s.height;
		if(w>h) {
			if(s.width > 200) {
				w = 200;
				h = 200/s.width*s.height;
			}
		} else {
			if(s.height > 200) {
				h = 200;
				w = 200/s.height*s.width;
			}
		}
		
		// Show image in a NSImageView
		NSImageView *backgroundImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0,0,w, h)];
		[backgroundImageView setImage:(NSImage *)content];
		[backgroundImageView setFrameSize:NSMakeSize(w, h)];
		[tip setContentView:backgroundImageView];
		[tip setContentSize:NSMakeSize(w,h)];
		[tip setFrameTopLeftPoint:point];
		[tip sizeToContent];
		[tip orderFront:self];
		[tip performSelector:@selector(runUntilUserActivity) withObject:nil afterDelay:0];
		[backgroundImageView release];
	}
	else {
		[tip setContent:(NSString*)content withOptions:displayOptions];
		NSBeep();
		NSLog(@"SPTooltip: Type '%@' is not supported. Please use 'text' or 'html'. Tooltip is displayed as type 'html'", type);
	}

}

- (void)initMeWithOptions:(NSDictionary *)displayOptions
{
	[self setReleasedWhenClosed:YES];
	[self setAlphaValue:0.97f];
	[self setOpaque:NO];
	[self setBackgroundColor:[NSColor clearColor]];
	[self setHasShadow:YES];
	[self setLevel:NSStatusWindowLevel];
	[self setHidesOnDeactivate:YES];
	[self setIgnoresMouseEvents:YES];

	webPreferences = [[WebPreferences alloc] initWithIdentifier:@"SequelPro Tooltip"];
	[webPreferences setJavaScriptEnabled:YES];

	webView = [[WebView alloc] initWithFrame:NSZeroRect];
	[webView setPreferencesIdentifier:@"SequelPro Tooltip"];
	[webView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[webView setFrameLoadDelegate:self];
	if ([webView respondsToSelector:@selector(setDrawsBackground:)])
	    [webView setDrawsBackground:NO];

	[self setContentView:webView];
	
}

- (id)init;
{
	if((self = [self initWithContentRect:NSMakeRect(1,1,1,1) 
					styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO]))
	{
	}
	return self;
}

- (void)dealloc
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	SPClear(didOpenAtDate);
	SPClear(webView);
	SPClear(webPreferences);
	[super dealloc];
}

+ (void)setDisplayOptions:(NSDictionary *)aDict
{
	// displayOptions = [NSDictionary dictionaryWithDictionary:aDict];
}

+ (NSPoint)caretPosition
{
	NSPoint pos;
	id fr = [[NSApp keyWindow] firstResponder];

	//If first responder is a textview return the caret position
	if(([fr isMemberOfClass:[NSTextView class]] && [fr alignment] == NSLeftTextAlignment) || [[[fr class] description] isEqualToString:@"SPTextView"]) {
		NSRange range = NSMakeRange([fr selectedRange].location,1);
		NSRange glyphRange = [[fr layoutManager] glyphRangeForCharacterRange:range actualCharacterRange:NULL];
		NSRect boundingRect = [[fr layoutManager] boundingRectForGlyphRange:glyphRange inTextContainer:[fr textContainer]];
		boundingRect = [fr convertRect: boundingRect toView:NULL];

		NSPoint oppositeOrigin = NSMakePoint(NSMaxX(boundingRect), NSMaxY(boundingRect));

		if (@available(macOS 10.12, *)) {
			pos = [[fr window] convertPointToScreen:oppositeOrigin];
		} else {
			pos = [[fr window] convertRectToScreen:(CGRect){.origin=oppositeOrigin}].origin;
		}
		return pos;
	// Otherwise return mouse location
	} else {
		pos = [NSEvent mouseLocation];
		pos.y -= 16;
		return pos;
	}
}

// ===========
// = Webview =
// ===========
- (void)setContent:(NSString *)content withOptions:(NSDictionary *)displayOptions
{

	NSString *fullContent =	@"<html>"
				@"<head>"
				@"  <style type='text/css' media='screen'>"
				@"      body {"
				@"          background: %@;"
				@"          margin: 0;"
				@"          padding: 2px;"
				@"          overflow: hidden;"
				@"          display: table-cell;"
				@"          max-width: 800px;"
				@"      }"
				@"      pre { white-space: pre-wrap; }"
				@"  </style>"
				@"</head>"
				@"<body>%@</body>"
				@"</html>";

	NSString *tooltipColor = ([SPOSInfo isOSVersionAtLeastMajor:10 minor:10 patch:0])? @"#F0F0F0" : @"#F9FBC5";
	NSString *bgColor = ([displayOptions objectForKey:@"backgroundcolor"]) ? [displayOptions objectForKey:@"backgroundcolor"] : tooltipColor;
	BOOL isTransparent = ([displayOptions objectForKey:@"transparent"]) ? YES : NO;


	fullContent = [NSString stringWithFormat:fullContent, isTransparent ? @"transparent" : bgColor, content];
	[[webView mainFrame] loadHTMLString:fullContent baseURL:nil];

}

- (void)sizeToContent
{

	NSRect frame;

	// Current tooltip position
	NSPoint pos = NSMakePoint([self frame].origin.x, [self frame].origin.y + [self frame].size.height);

	// Find the screen which we are displaying on
	NSRect screenFrame = [NSScreen rectOfScreenAtPoint:pos];

	// is contentView a webView calculate actual rendered size via JavaScript
	if([[[[self contentView] class] description] isEqualToString:@"WebView"]) {
		// The webview is set to a large initial size and then sized down to fit the content
		[self setContentSize:NSMakeSize(screenFrame.size.width - screenFrame.size.width / 3.0f , screenFrame.size.height)];

		NSInteger height  = [[[webView windowScriptObject] evaluateWebScript:@"document.body.offsetHeight + document.body.offsetTop;"] integerValue];
		NSInteger width   = [[[webView windowScriptObject] evaluateWebScript:@"document.body.offsetWidth + document.body.offsetLeft;"] integerValue];
	
		[webView setFrameSize:NSMakeSize(width, height)];

		frame = [self frameRectForContentRect:[webView frame]];
	} else {
		frame = [self frame];
	}
	
	//Adjust frame to fit into the screenFrame
	frame.size.width  = MIN(NSWidth(frame), NSWidth(screenFrame));
	frame.size.height = MIN(NSHeight(frame), NSHeight(screenFrame));

	[self setFrame:frame display:NO];

	//Adjust tooltip origin to fit into the screenFrame
	pos.x = MAX(NSMinX(screenFrame), MIN(pos.x, NSMaxX(screenFrame)-NSWidth(frame)));
	pos.y = MIN(MAX(NSMinY(screenFrame)+NSHeight(frame), pos.y), NSMaxY(screenFrame));

	[self setFrameTopLeftPoint:pos];
	
}

- (void)webView:(WebView*)sender didFinishLoadForFrame:(WebFrame*)frame;
{
	[self sizeToContent];
	[self orderFront:self];
	[self performSelector:@selector(runUntilUserActivity) withObject:nil afterDelay:0];
}

// ==================
// = Event handling =
// ==================
- (BOOL)shouldCloseForMousePosition:(NSPoint)aPoint
{
	CGFloat ignorePeriod = 0.05f;
	if(-[didOpenAtDate timeIntervalSinceNow] < ignorePeriod)
		return NO;

	if(NSEqualPoints(mousePositionWhenOpened, NSZeroPoint))
	{
		mousePositionWhenOpened = aPoint;
		return NO;
	}

	NSPoint p = mousePositionWhenOpened;
	CGFloat deltaX = p.x - aPoint.x;
	CGFloat deltaY = p.y - aPoint.y;
	CGFloat dist = sqrt(deltaX * deltaX + deltaY * deltaY);

	CGFloat moveThreshold = 10;
	return dist > moveThreshold;
}

- (void)runUntilUserActivity
{
	[self setValue:[NSDate date] forKey:@"didOpenAtDate"];
	mousePositionWhenOpened = NSZeroPoint;

	NSWindow* appKeyWindow = [[NSApp keyWindow] retain];
	BOOL didAcceptMouseMovedEvents = [appKeyWindow acceptsMouseMovedEvents];
	[appKeyWindow setAcceptsMouseMovedEvents:YES];
	NSEvent* event = nil;
	NSInteger eventType;
	while((event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate distantFuture] inMode:NSDefaultRunLoopMode dequeue:YES]))
	{
		eventType = [event type];
		if(eventType == NSKeyDown || eventType == NSLeftMouseDown || eventType == NSRightMouseDown || eventType == NSOtherMouseDown || eventType == NSScrollWheel)
			break;

		if(eventType == NSMouseMoved && [self shouldCloseForMousePosition:[NSEvent mouseLocation]])
			break;

		if(appKeyWindow != [NSApp keyWindow] || ![NSApp isActive])
			break;
		
		if(spTooltipCounter > 1)
			break;
		[NSApp sendEvent:event];

	}

	[appKeyWindow setAcceptsMouseMovedEvents:didAcceptMouseMovedEvents];
	[appKeyWindow release];

	[self orderOut:self];

	// If we still have an event, pass it on to the app to ensure all actions are performed
	if (event) [NSApp sendEvent:event];
}

// =============
// = Animation =
// =============
- (void)orderOut:(id)sender
{
	if(![self isVisible] || animationTimer)
		return;

	[self stopAnimation:self];
	[self setValue:[NSDate date] forKey:@"animationStart"];
	[self setValue:[NSTimer scheduledTimerWithTimeInterval:0.01f target:self selector:@selector(animationTick:) userInfo:nil repeats:YES] forKey:@"animationTimer"];
}

- (void)animationTick:(id)sender
{
	CGFloat alpha = 0.97f * (1.0f - 40*slow_in_out(-2.2f * (float)[animationStart timeIntervalSinceNow]));

	if(alpha > 0.0f && spTooltipCounter==1)
	{
		[self setAlphaValue:alpha];
	}
	else
	{
		[super orderOut:self];
		[self stopAnimation:self];
		[self close];
		spTooltipCounter--;
		if(spTooltipCounter < 0) spTooltipCounter = 0;
	}
}

- (void)stopAnimation:(id)sender;
{
	if(animationTimer)
	{
		[[self retain] autorelease];
		[animationTimer invalidate];
		[self setValue:nil forKey:@"animationTimer"];
		[self setValue:nil forKey:@"animationStart"];
		[self setAlphaValue:0.97f];
	}
}

@end
