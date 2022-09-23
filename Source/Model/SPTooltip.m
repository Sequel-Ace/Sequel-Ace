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
//			SPDefaultMonospacedFontName, @"fontname",
//			@"#EEEEEE", @"backgroundcolor",
//			@"20", @"fontsize",
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
//	                       fontname, fontsize, backgroundcolor (as #RRGGBB), transparent (any value)
//	                 if no displayOptions are passed or if a key doesn't exist the following default
//	                 are taken:
//	                       "Lucida Grande", "10", "#F9FBC5", NO
//
//	See more possible syntaxa in SPTooltip to init a tooltip

#import "SPTooltip.h"
#import "SPFunctions.h"
#import "sequel-ace-Swift.h"
#include <tgmath.h>
@import AppCenterAnalytics;

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

@property (nonatomic, assign) BOOL gotHeight;
@property (nonatomic, assign) BOOL gotWidth;

@end

@implementation SPTooltip

@synthesize gotHeight, gotWidth;

+ (instancetype)sharedInstance {
	static SPTooltip *sharedInstance = nil;

	static dispatch_once_t SPTooltipOnceToken;

	dispatch_once(&SPTooltipOnceToken, ^{
		sharedInstance = [[[self class] alloc] init];
	});

	return sharedInstance;
}

- (instancetype)init {
	if((self = [super initWithContentRect:NSMakeRect(1,1,1,1)
					styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO]))
	{
		
		// some setup?
		
	}
	return self;
}

// ==================
// = Setup/teardown =
// ==================

+ (void)showWithObject:(id)content atLocation:(NSPoint)point
{
	[self.sharedInstance showWithObject:content atLocation:point ofType:@"text" displayOptions:@{}];
}

+ (void)showWithObject:(id)content atLocation:(NSPoint)point ofType:(NSString *)type
{
	[self.sharedInstance showWithObject:content atLocation:point ofType:type displayOptions:nil];
}

+ (void)showWithObject:(id)content
{
	[self.sharedInstance showWithObject:content atLocation:[self caretPosition] ofType:@"text" displayOptions:nil];
}

+ (void)showWithObject:(id)content ofType:(NSString *)type
{
	[self.sharedInstance showWithObject:content atLocation:[self caretPosition] ofType:type displayOptions:nil];
}

+ (void)showWithObject:(id)content ofType:(NSString *)type displayOptions:(NSDictionary *)options
{
	[self.sharedInstance showWithObject:content atLocation:[self caretPosition] ofType:type displayOptions:options];
}

+ (void)showWithObject:(id)content atLocation:(NSPoint)point ofType:(NSString *)type displayOptions:(NSDictionary *)displayOptions{
	
	[self.sharedInstance showWithObject:content atLocation:point ofType:type displayOptions:displayOptions];
}

- (void)showWithObject:(id)content atLocation:(NSPoint)point ofType:(NSString *)type displayOptions:(NSDictionary *)displayOptions
{

	spTooltipCounter++;
	
	self.gotWidth = NO;
	self.gotHeight = NO;
	
	[self initMeWithOptions:displayOptions];
	[self setFrameTopLeftPoint:point];

	if([type isEqualToString:@"text"]) {
		NSString *html = nil;
        NSMutableString *text = nil;
        NSString *textStr = nil;

        NSMutableDictionary *errorDict = [[NSMutableDictionary alloc] init];

        if ([content isKindOfClass:[NSString class]]) {
            textStr = (NSString*)content;
            text = [(NSString*)content mutableCopy];
        }
        else{
            [errorDict setObject:@"not an NSString" forKey:@"content"];
            [errorDict safeSetObject:[content class] forKey:@"content"];
        }

        if(!IsEmpty(textStr)){
            // check to see if the string is a unix timestamp, within +/- oneHundredYears
            // if it is create a date time string from the unix timestamp
            NSString *unixTimestampAsString = textStr.dateStringFromUnixTimestamp;
            if(!IsEmpty(unixTimestampAsString)){
                SPLog(@"unixTimestampAsString: %@", unixTimestampAsString);
                [text setString:unixTimestampAsString];
            }
        }
        else{
            [errorDict setObject:@"string is empty" forKey:@"textStr"];
            [errorDict safeSetObject:textStr forKey:@"textStr"];
            [errorDict safeSetObject:text forKey:@"textMut"];
        }
        
        if(errorDict.count > 0){
            NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
            if ([prefs boolForKey:SPSaveApplicationUsageAnalytics]) {
                executeOnBackgroundThread(^{
                    [MSACAnalytics trackEvent:@"error" withProperties:errorDict];
                });
            }
        }

		if(text)
		{
			int fontSize = ([displayOptions objectForKey:@"fontsize"]) ? [[displayOptions objectForKey:@"fontsize"] intValue] : 10;
			if(fontSize < 5) fontSize = 5;
			[text replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, [text length])];
			[text replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, [text length])];
			[text insertString:[NSString stringWithFormat:@"<pre style=\"font-family:'%@'; font-size: %dpx\">",
							([displayOptions objectForKey:@"fontname"]) ? [displayOptions objectForKey:@"fontname"] : @"Lucida Grande", fontSize]
							atIndex:0];
			[text appendString:@"</pre>"];
			html = text;
            SPLog(@"html: %@", html);
		}
		else
		{
			html = @"Error";
		}
		[self setContent:html withOptions:displayOptions];
	}
	else if([type isEqualToString:@"html"]) {
		[self setContent:(NSString*)content withOptions:displayOptions];
	}
	else if([type isEqualToString:@"image"]) {
		[self setBackgroundColor:[NSColor clearColor]];
		[self setOpaque:NO];
		[self setLevel:NSNormalWindowLevel];
		[self setExcludedFromWindowsMenu:YES];
		[self setAlphaValue:1];

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
		[self setContentView:backgroundImageView];
		[self setContentSize:NSMakeSize(w,h)];
		[self setFrameTopLeftPoint:point];
		[self sizeToContent];
		[self orderFront:self];
		[self performSelector:@selector(runUntilUserActivity) withObject:nil afterDelay:0];
	}
	else {
		[self setContent:(NSString*)content withOptions:displayOptions];
		NSBeep();
		NSLog(@"SPTooltip: Type '%@' is not supported. Please use 'text' or 'html'. Tooltip is displayed as type 'html'", type);
	}

}

- (void)initMeWithOptions:(NSDictionary *)displayOptions
{
	[self setReleasedWhenClosed:NO]; // important that this is NO, otherwise self is released
	[self setAlphaValue:0.97f];
	[self setOpaque:NO];
	[self setBackgroundColor:[NSColor clearColor]];
	[self setHasShadow:YES];
	[self setLevel:NSStatusWindowLevel];
	[self setHidesOnDeactivate:YES];
	[self setIgnoresMouseEvents:YES];

	WKPreferences *prefs = [WKPreferences new];
	prefs.javaScriptEnabled = YES;
	
	/* Create a configuration for our preferences */
	WKWebViewConfiguration *conf = [WKWebViewConfiguration new];
	conf.preferences = prefs;
	conf.applicationNameForUserAgent = @"SequelPro Tooltip";
	
	wkWebView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:conf];
	
	[wkWebView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	wkWebView.navigationDelegate = self;
	
	[self setContentView:wkWebView];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(null_unspecified WKNavigation *)navigation {
	SPLog(@"didFinishNavigation FINISHING LOAD");
	
	[self sizeToContent];
	[self orderFront:self];
	[self performSelector:@selector(runUntilUserActivity) withObject:nil afterDelay:0];
	
}
- (void)webView:(WKWebView *)webView didFailNavigation:(null_unspecified WKNavigation *)navigation withError:(NSError *)error {
	SPLog(@"didFailNavigation. error is: %@", error);
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(null_unspecified WKNavigation *)navigation withError:(NSError *)error {
	SPLog(@"didFailProvisionalNavigation. error is: %@", error);
}

- (void)dealloc
{
	SPLog(@"dealloc called");
	[NSObject cancelPreviousPerformRequestsWithTarget:self];

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
	if(([fr isMemberOfClass:[NSTextView class]] && [fr alignment] == NSTextAlignmentLeft) || [[[fr class] description] isEqualToString:@"SPTextView"]) {
		NSRange range = NSMakeRange([fr selectedRange].location,1);
		NSRange glyphRange = [[fr layoutManager] glyphRangeForCharacterRange:range actualCharacterRange:NULL];
		NSRect boundingRect = [[fr layoutManager] boundingRectForGlyphRange:glyphRange inTextContainer:[fr textContainer]];
		boundingRect = [fr convertRect: boundingRect toView:NULL];

		NSPoint oppositeOrigin = NSMakePoint(NSMaxX(boundingRect), NSMaxY(boundingRect));
        pos = [[fr window] convertPointToScreen:oppositeOrigin];
		NSFont* font = [fr font];
		if(font) pos.y -= [font pointSize]*1.3f;
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

	NSString *tooltipColor = @"#F0F0F0";
	NSString *bgColor = ([displayOptions objectForKey:@"backgroundcolor"]) ? [displayOptions objectForKey:@"backgroundcolor"] : tooltipColor;
	BOOL isTransparent = ([displayOptions objectForKey:@"transparent"]) ? YES : NO;

	fullContent = [NSString stringWithFormat:fullContent, isTransparent ? @"transparent" : bgColor, content];
	[wkWebView loadHTMLString:fullContent baseURL:nil];

}

- (void)sizeToContent
{

	NSRect frame;

	// Current tooltip position
	NSPoint pos = NSMakePoint([self frame].origin.x, [self frame].origin.y + [self frame].size.height);

	// Find the screen which we are displaying on
	NSRect screenFrame = [NSScreen rectOfScreenAtPoint:pos];

	// is contentView a webView calculate actual rendered size via JavaScript
	if([[[[self contentView] class] description] isEqualToString:@"WKWebView"]) {
		// The webview is set to a large initial size and then sized down to fit the content
		[self setContentSize:NSMakeSize(screenFrame.size.width - screenFrame.size.width / 3.0f , screenFrame.size.height)];

		NSInteger __block height = 21;
		NSInteger __block width = 400;
		
		[self->wkWebView evaluateJavaScript:@"document.body.offsetHeight + document.body.offsetTop;" completionHandler:^(id _Nullable height2, NSError * _Nullable error) {
			SPLog(@"height2: %@", height2);
			if (error) SPLog(@"error: %@", error.localizedDescription);
			
			height = [height2 integerValue];
			self->gotHeight = YES;
			
		}];
		[self->wkWebView evaluateJavaScript:@"document.body.offsetWidth + document.body.offsetLeft;" completionHandler:^(id _Nullable width2, NSError * _Nullable error) {
			SPLog(@"width2: %@", width2);
			if (error) SPLog(@"error: %@", error.localizedDescription);

            // Add 1 because sometimes document.body.offsetWidth value is not sufficient or the frame of WKWebView does not match the body. I don't know exactly where the truth is.
            // 1 seems to be enougth in my case.
			width = [width2 integerValue] + 1;
			self->gotWidth = YES;
		}];
		
		// wait until we have both height and width
		if (gotHeight == NO || gotWidth == NO) {

			[NSThread detachNewThreadSelector:@selector(runInBackground:) toTarget:self withObject:nil];

			while (gotHeight == NO || gotWidth == NO) {
				SPLog(@"waiting");
				[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
			}
		}
			
		[wkWebView setFrameSize:NSMakeSize(width, height)];

		frame = [self frameRectForContentRect:[wkWebView frame]];
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

- (void)runInBackground:(id)arg {
	@autoreleasepool {
		[self performSelectorOnMainThread:@selector(wakeUpMainThreadRunloop:) withObject:nil waitUntilDone:NO];
	}
}

- (void)wakeUpMainThreadRunloop:(id)arg {
	// This method is executed on main thread!
	// It doesn't need to do anything actually, just having it run will
	// make sure the main thread stops running the runloop
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

	NSWindow* appKeyWindow = [NSApp keyWindow];
	BOOL didAcceptMouseMovedEvents = [appKeyWindow acceptsMouseMovedEvents];
	[appKeyWindow setAcceptsMouseMovedEvents:YES];
	NSEvent* event = nil;
	NSInteger eventType;
	while((event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate distantFuture] inMode:NSDefaultRunLoopMode dequeue:YES]))
	{
		eventType = [event type];
		if(eventType == NSEventTypeKeyDown || eventType == NSEventTypeLeftMouseDown || eventType == NSEventTypeRightMouseDown || eventType == NSEventTypeOtherMouseDown || eventType == NSEventTypeScrollWheel)
			break;

		if(eventType == NSEventTypeMouseMoved && [self shouldCloseForMousePosition:[NSEvent mouseLocation]])
			break;

		if(appKeyWindow != [NSApp keyWindow] || ![NSApp isActive])
			break;
		
		if(spTooltipCounter > 1)
			break;
		[NSApp sendEvent:event];

	}

	[appKeyWindow setAcceptsMouseMovedEvents:didAcceptMouseMovedEvents];

	[self orderOut:self];

	// If we still have an event, pass it on to the app to ensure all actions are performed
	if (event) [NSApp sendEvent:event];
}

// =============
// = Animation =
// =============
- (void)orderOut:(id)sender
{
	// must set this to nil here
	// otherwise subsequent tootips do not display
	self.contentView = nil;
	
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
		[animationTimer invalidate];
		[self setValue:nil forKey:@"animationTimer"];
		[self setValue:nil forKey:@"animationStart"];
		[self setAlphaValue:0.97f];
	}
}

@end

