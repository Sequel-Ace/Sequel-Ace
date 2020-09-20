//
//  YRKSpinningProgressIndicator.m
//
//  Original drawing code by Kelan Champagne; forked by Rowan Beentje
//  for fixes, determinate mode, and threaded drawing.
//
//  Copyright (c) 2009, Kelan Champagne (http://yeahrightkeller.com)
//  All rights reserved.
// 
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of the <organization> nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
// 
//  THIS SOFTWARE IS PROVIDED BY Kelan Champagne ''AS IS'' AND ANY
//  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//  DISCLAIMED. IN NO EVENT SHALL Kelan Champagne BE LIABLE FOR ANY
//  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
//  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
//  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
//  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import "YRKSpinningProgressIndicator.h"

@interface YRKSpinningProgressIndicator ()

- (void)updateFrame:(NSTimer *)timer;
- (void) animateInBackgroundThread;
- (void)actuallyStartAnimation;
- (void)actuallyStopAnimation;

@end

@implementation YRKSpinningProgressIndicator

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _position = 0;
        _numFins = 12;
        _isAnimating = NO;
        _isFadingOut = NO;
		_isIndeterminate = YES;
		_currentValue = 0.0;
		_maxValue = 100.0;
		_usesThreadedAnimation = NO;
		_shadow = nil;
    }
    return self;
}

- (void) dealloc {
	if (_foreColor) [_foreColor release];
	if (_backColor) [_backColor release];
	if (_shadow) [_shadow release];
	if (_isAnimating) [self stopAnimation:self];
    
	[super dealloc];
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];

    if ([self window] == nil) {
        // No window?  View hierarchy may be going away.  Dispose timer to clear circular retain of timer to self to timer.
        [self actuallyStopAnimation];
    }
    else if (_isAnimating) {
        [self actuallyStartAnimation];
    }
}

- (void)drawRect:(NSRect)rect
{
	NSInteger i;
	CGFloat alpha = 1.0f;

	// Determine size based on current bounds
	NSSize size = [self bounds].size;
	CGFloat rectMaxSize;
	if(size.width >= size.height)
		rectMaxSize = size.height;
	else
		rectMaxSize = size.width;

	CGContextRef currentContext = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
	[NSGraphicsContext saveGraphicsState];

	if (_shadow) [_shadow set];

	// fill the background, if set
	if(_drawBackground) {
		[_backColor set];
		[NSBezierPath fillRect:[self bounds]];
	}

	// Move the CTM so 0,0 is at the center of our bounds
	CGContextTranslateCTM(currentContext,[self bounds].size.width/2,[self bounds].size.height/2);

	if (_isIndeterminate) {
		// do initial rotation to start place
		CGContextRotateCTM(currentContext, 3.14159f*2/_numFins * _position);

		NSBezierPath *path = [[NSBezierPath alloc] init];
		CGFloat lineWidth = 0.08f * rectMaxSize; // should be 2.75 for 32x32
		CGFloat lineStart = 0.234375f * rectMaxSize; // should be 7.5 for 32x32
		CGFloat lineEnd = 0.421875f * rectMaxSize;  // should be 13.5 for 32x32
		[path setLineWidth:lineWidth];
		[path setLineCapStyle:NSRoundLineCapStyle];
		[path moveToPoint:NSMakePoint(0,lineStart)];
		[path lineToPoint:NSMakePoint(0,lineEnd)];

		for (i=0; i<_numFins; i++) {
			if(_isAnimating) {
				[[_foreColor colorWithAlphaComponent:alpha] set];
			} else {
				[[_foreColor colorWithAlphaComponent:0.2f] set];
			}

			[path stroke];

			// we draw all the fins by rotating the CTM, then just redraw the same segment again
			CGContextRotateCTM(currentContext, 6.282185f/_numFins);
			alpha -= 1.0f/_numFins;
		}
		[path release];

	} else {

		CGFloat lineWidth = 1 + (0.01f * rectMaxSize);
		CGFloat circleRadius = (rectMaxSize - lineWidth) / 2.1f;
		NSPoint circleCenter = NSMakePoint(0, 0);
		[[_foreColor colorWithAlphaComponent:alpha] set];
		NSBezierPath *path = [[NSBezierPath alloc] init];
		[path setLineWidth:lineWidth];
		[path appendBezierPathWithOvalInRect:NSMakeRect(-circleRadius, -circleRadius, circleRadius*2, circleRadius*2)];
		[path stroke];
		[path release];
		path = [[NSBezierPath alloc] init];
		[path appendBezierPathWithArcWithCenter:circleCenter radius:circleRadius startAngle:90 endAngle:90-(360*(float)(_currentValue/_maxValue)) clockwise:YES];
		[path lineToPoint:circleCenter] ;
		[path fill];
		[path release];
	}

	[NSGraphicsContext restoreGraphicsState];
}

# pragma mark -
# pragma mark Subclass

- (void)updateFrame:(NSTimer *)timer;
{
    if(_position > 0) {
        _position--;
    }
    else {
        _position = _numFins - 1;
    }
    
    if (_usesThreadedAnimation) {
        // draw now instead of waiting for setNeedsDisplay (that's the whole reason
        // we're animating from background thread)
        [self display];
    }
    else {
        [self setNeedsDisplay:YES];
    }
}

- (void) animateInBackgroundThread
{
	NSAutoreleasePool *animationPool = [[NSAutoreleasePool alloc] init];
	
	// Set up the animation speed to subtly change with size > 32.
	useconds_t animationDelay = 38000 + (2000 * ([self bounds].size.height / 32));
	NSInteger poolFlushCounter = 0;

	do {
		[self updateFrame:nil];
		usleep(animationDelay);
		poolFlushCounter++;
		if (poolFlushCounter > 256) {
			[animationPool drain];
			animationPool = [[NSAutoreleasePool alloc] init];
			poolFlushCounter = 0;
		}
	} while (![[NSThread currentThread] isCancelled]); 

	[animationPool release];
}

- (void)startAnimation:(id)sender
{
	if (!_isIndeterminate) return;
	if (_isAnimating) return;
    
    [self actuallyStartAnimation];
    _isAnimating = YES;
}

- (void)stopAnimation:(id)sender
{
    [self actuallyStopAnimation];
    _isAnimating = NO;
}

- (void)actuallyStartAnimation
{
    // Just to be safe kill any existing timer.
    [self actuallyStopAnimation];

    if ([self window]) {
        // Why animate if not visible?  viewDidMoveToWindow will re-call this method when needed.
        if (_usesThreadedAnimation) {
            _animationThread = [[NSThread alloc] initWithTarget:self selector:@selector(animateInBackgroundThread) object:nil];
            [_animationThread setName:@"YRKSpinningProgressIndicator animator"];
            [_animationThread start];
        }
        else {
            _animationTimer = [[NSTimer timerWithTimeInterval:(NSTimeInterval)0.05
                                                       target:self
                                                     selector:@selector(updateFrame:)
                                                     userInfo:nil
                                                      repeats:YES] retain];

            [[NSRunLoop currentRunLoop] addTimer:_animationTimer forMode:NSRunLoopCommonModes];
            [[NSRunLoop currentRunLoop] addTimer:_animationTimer forMode:NSDefaultRunLoopMode];
            [[NSRunLoop currentRunLoop] addTimer:_animationTimer forMode:NSEventTrackingRunLoopMode];
        }
    }
}

- (void)actuallyStopAnimation
{
	if (_animationThread) {
        // we were using threaded animation
		[_animationThread cancel];
		if (![_animationThread isFinished]) {
			[[NSRunLoop currentRunLoop] runMode:NSModalPanelRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
		}
		[_animationThread release];
        _animationThread = nil;
	}
    else if (_animationTimer) {
        // we were using timer-based animation
        [_animationTimer invalidate];
        [_animationTimer release];
        _animationTimer = nil;
    }
    [self setNeedsDisplay:YES];
}

# pragma mark Not Implemented

- (void)setStyle:(NSProgressIndicatorStyle)style
{
    if (NSProgressIndicatorSpinningStyle != style) {
        NSAssert(NO, @"Non-spinning styles not available.");
    }
}


# pragma mark -
# pragma mark Accessors

- (NSColor *)foreColor
{
    return [[_foreColor retain] autorelease];
}

- (void)setForeColor:(NSColor *)value
{
    if (_foreColor != value) {
        [_foreColor release];
        _foreColor = [value copy];
        [self setNeedsDisplay:YES];
    }
}

- (NSColor *)backColor
{
    return [[_backColor retain] autorelease];
}

- (void)setBackColor:(NSColor *)value
{
    if (_backColor != value) {
        [_backColor release];
        _backColor = [value copy];
        [self setNeedsDisplay:YES];
    }
}

- (BOOL)drawBackground
{
    return _drawBackground;
}

- (void)setDrawBackground:(BOOL)value
{
    if (_drawBackground != value) {
        _drawBackground = value;
    }
    [self setNeedsDisplay:YES];
}

- (NSShadow *)shadow
{
	return [[_shadow retain] autorelease];
}

- (void)setShadow:(NSShadow *)value
{
	if (_shadow != value) {
		[_shadow release];
		_shadow = [value copy];
		[self setNeedsDisplay:YES];
	}
}

- (BOOL)isIndeterminate
{
	return _isIndeterminate;
}

- (void)setIndeterminate:(BOOL)isIndeterminate
{
	_isIndeterminate = isIndeterminate;
	if (!_isIndeterminate && _isAnimating) [self stopAnimation:self];
    [self setNeedsDisplay:YES];
}

- (double)doubleValue
{
	return _currentValue;
}

- (void)setDoubleValue:(double)doubleValue
{
    // Automatically put it into determinate mode if it's not already.
    if (_isIndeterminate) {
        [self setIndeterminate:NO];
    }
	_currentValue = doubleValue;
	[self setNeedsDisplay:YES];
}

- (void)setNumberValue:(NSNumber *)numberValue
{
	[self setDoubleValue:[numberValue doubleValue]];
}
- (double)maxValue
{
	return _maxValue;
}

- (void)setMaxValue:(double)maxValue
{
	_maxValue = maxValue;
    [self setNeedsDisplay:YES];
}

- (void)setUsesThreadedAnimation:(BOOL)useThreaded
{
    if (_usesThreadedAnimation != useThreaded) {
        _usesThreadedAnimation = useThreaded;
        
        if (_isAnimating) {
            // restart the timer to use the new mode
            [self stopAnimation:self];
            [self startAnimation:self];
        }
    }
}

- (BOOL)usesThreadedAnimation
{
    return _usesThreadedAnimation;
}

@end
