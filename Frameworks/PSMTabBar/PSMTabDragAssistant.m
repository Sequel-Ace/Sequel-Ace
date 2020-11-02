//
//  PSMTabDragAssistant.m
//  PSMTabBarControl
//
//  Created by John Pannell on 4/10/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import "PSMTabDragAssistant.h"
#import "PSMTabBarCell.h"
#import "PSMTabStyle.h"
#import "PSMTabDragWindowController.h"

#define PI 3.1417

@interface PSMTabBarControl (Private)
- (void)update:(BOOL)animate;
@end

@interface PSMTabDragAssistant (Private)
- (NSImage *)_imageForViewOfCell:(PSMTabBarCell *)cell styleMask:(NSUInteger *)outMask;
- (NSImage *)_miniwindowImageOfWindow:(NSWindow *)window;
- (void)_expandWindow:(NSWindow *)window atPoint:(NSPoint)point;
- (void)_expandWindowTimerFired:(NSTimer *)timer;
@end

@implementation PSMTabDragAssistant

static PSMTabDragAssistant *sharedDragAssistant = nil;

#pragma mark -
#pragma mark Creation/Destruction

+ (PSMTabDragAssistant *)sharedDragAssistant
{
    if (!sharedDragAssistant) {
        sharedDragAssistant = [[PSMTabDragAssistant alloc] init];
    }
    
    return sharedDragAssistant;
}

- (id)init
{
    if ( (self = [super init]) ) {
        _sourceTabBar = nil;
        _destinationTabBar = nil;
        _participatingTabBars = [[NSMutableSet alloc] init];
        _draggedCell = nil;
        _animationTimer = nil;
        _sineCurveWidths = [[NSMutableArray alloc] initWithCapacity:kPSMTabDragAnimationSteps];
        _targetCell = nil;
        _isDragging = NO;
    }
    
    return self;
}

- (void)dealloc
{
    [_sourceTabBar release];
    [_destinationTabBar release];
    [_participatingTabBars release];
    [_draggedCell release];
    [_animationTimer release];
    [_sineCurveWidths release];
    [_targetCell release];
    [super dealloc];
}

#pragma mark -
#pragma mark Accessors

- (PSMTabBarControl *)sourceTabBar
{
    return _sourceTabBar;
}

- (void)setSourceTabBar:(PSMTabBarControl *)tabBar
{
    [tabBar retain];
    [_sourceTabBar release];
    _sourceTabBar = tabBar;
}

- (PSMTabBarControl *)destinationTabBar
{
    return _destinationTabBar;
}

- (void)setDestinationTabBar:(PSMTabBarControl *)tabBar
{
    [tabBar retain];
    [_destinationTabBar release];
    _destinationTabBar = tabBar;
}

- (PSMTabBarCell *)draggedCell
{
    return _draggedCell;
}

- (void)setDraggedCell:(PSMTabBarCell *)cell
{
    [cell retain];
    [_draggedCell release];
    _draggedCell = cell;
}

- (NSInteger)draggedCellIndex
{
    return _draggedCellIndex;
}

- (void)setDraggedCellIndex:(NSInteger)value
{
    _draggedCellIndex = value;
}

- (BOOL)isDragging
{
    return _isDragging;
}

- (void)setIsDragging:(BOOL)value
{
    _isDragging = value;
}

- (NSPoint)currentMouseLoc
{
    return _currentMouseLoc;
}

- (void)setCurrentMouseLoc:(NSPoint)point
{
    _currentMouseLoc = point;
}

- (PSMTabBarCell *)targetCell
{
    return _targetCell;
}

- (void)setTargetCell:(PSMTabBarCell *)cell
{
    [cell retain];
    [_targetCell release];
    _targetCell = cell;
}

#pragma mark -
#pragma mark Functionality

- (void)startDraggingCell:(PSMTabBarCell *)cell fromTabBar:(PSMTabBarControl *)control withMouseDownEvent:(NSEvent *)event
{

	// Ensure the window is frontmost
	[[control window] makeKeyAndOrderFront:self];

    [self setIsDragging:YES];
    [self setSourceTabBar:control];
    [self setDestinationTabBar:control];
    [_participatingTabBars addObject:control];
    [self setDraggedCell:cell];
    [self setDraggedCellIndex:[[control cells] indexOfObject:cell]];
    
    NSRect cellFrame = [cell frame];

    // Generate a list of widths for animation
    NSInteger i;
    CGFloat cellStepSize = ([control orientation] == PSMTabBarHorizontalOrientation) ? (cellFrame.size.width + 6) : (cellFrame.size.height + 1);
    for (i = 0; i < kPSMTabDragAnimationSteps - 1; i++) {
        NSInteger thisWidth = (NSInteger)(cellStepSize - ((cellStepSize/2.0) + ((sin((PI/2.0) + ((CGFloat)i/(CGFloat)kPSMTabDragAnimationSteps)*PI) * cellStepSize) / 2.0)));
        [_sineCurveWidths addObject:[NSNumber numberWithInteger:thisWidth]];
    }
	[_sineCurveWidths addObject:[NSNumber numberWithInteger:([control orientation] == PSMTabBarHorizontalOrientation) ? cellFrame.size.width : cellFrame.size.height]];
    
    // hide UI buttons
    [[control overflowPopUpButton] setHidden:YES];
    [[control addTabButton] setHidden:YES];
    
    [[NSCursor closedHandCursor] set];
    
	NSPasteboard *pboard;
	if (@available(macOS 10.13, *)) {
		pboard = [NSPasteboard pasteboardWithName:NSPasteboardNameDrag];
	} else {
		pboard = [NSPasteboard pasteboardWithName:NSDragPboard];
	}
    NSImage *dragImage = [cell dragImage];
    [[cell indicator] removeFromSuperview];
    [self distributePlaceholdersInTabBar:control withDraggedCell:cell];

    if ([control isFlipped]) {
        cellFrame.origin.y += cellFrame.size.height;
    }
    [cell setHighlighted:NO];
    NSSize offset = NSZeroSize;
	[pboard declareTypes:@[@"PSMTabBarControlItemPBType"] owner:nil];
    [pboard setString:[[NSNumber numberWithInteger:[[control cells] indexOfObject:cell]] stringValue] forType:@"PSMTabBarControlItemPBType"];
    _animationTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0/30.0) target:self selector:@selector(animateDrag:) userInfo:nil repeats:YES];
    
	[[NSNotificationCenter defaultCenter] postNotificationName:PSMTabDragDidBeginNotification object:nil];
	
	//retain the control in case the drag operation causes the control to be released
	[control retain];

	//TODO: jcs - fixing deprecated dragImage needs a DraggingItems and DragginSource. Beyond me. 2020-10-22
	if ([control delegate] && [[control delegate] respondsToSelector:@selector(tabView:shouldDropTabViewItem:inTabBar:)] &&
			[[control delegate] tabView:[control tabView] shouldDropTabViewItem:[[self draggedCell] representedObject] inTabBar:nil]) {
		_currentTearOffStyle = [control tearOffStyle];
		_draggedTab = [[PSMTabDragWindowController alloc] initWithImage:dragImage styleMask:NSBorderlessWindowMask tearOffStyle:_currentTearOffStyle initialAlpha:[control usesSafariStyleDragging]?1:kPSMTabDragWindowAlpha];
		
		cellFrame.origin.y -= cellFrame.size.height;
		[control dragImage:[[[NSImage alloc] initWithSize:NSMakeSize(1, 1)] autorelease] at:cellFrame.origin offset:offset event:event pasteboard:pboard source:control slideBack:NO];
	} else {
		[control dragImage:dragImage at:cellFrame.origin offset:offset event:event pasteboard:pboard source:control slideBack:YES];
	}
	
	[control release];
}

- (void)draggingEnteredTabBar:(PSMTabBarControl *)control atPoint:(NSPoint)mouseLoc
{

	// Bring the new tab window to the front
	[[control window] makeKeyAndOrderFront:self];
	
	if (_currentTearOffStyle == PSMTabBarTearOffMiniwindow && ![self destinationTabBar]) {
		[_draggedTab switchImages];
	}

	// If this is not the starting drag bar...
	if ([self sourceTabBar] != [self destinationTabBar] && control != [self destinationTabBar]) {

		// Add a single placeholder to the tab bar and tell the new tab bar to update.
		// The placeholder is later removed by distributePlaceholdersInTabBar:.
		PSMTabBarCell *pc = [[[PSMTabBarCell alloc] initPlaceholderWithFrame:[[self draggedCell] frame] expanded:NO inControlView:control] autorelease];
		[[control cells] addObject:pc];
		[control update:NO];

		// Deselect any currently selected tabs after the update
		for (PSMTabBarCell *aCell in [control cells]) {
			if ([aCell tabState] & PSMTab_SelectedMask) {
				[aCell setState:NSOffState];
				[aCell setTabState:PSMTab_PositionMiddleMask];
				break;
			}
		}
	}
	
    [self setDestinationTabBar:control];
    [self setCurrentMouseLoc:mouseLoc];

    [_participatingTabBars addObject:control];

	// Add placeholders if necessary
    if ([[control cells] count] == 0 || ![[[control cells] objectAtIndex:0] isPlaceholder]) {
        [self distributePlaceholdersInTabBar:control];
    }
	
    // hide UI buttons
    [[control overflowPopUpButton] setHidden:YES];
    [[control addTabButton] setHidden:YES];

	//tell the drag window to display only the header if there is one
	if (_currentTearOffStyle == PSMTabBarTearOffAlphaWindow && _draggedView) {
		if (_fadeTimer) {
			[_fadeTimer invalidate];
		}
		
		[[_draggedTab window] orderFront:nil];
		_fadeTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0 target:self selector:@selector(fadeOutDragWindow:) userInfo:nil repeats:YES];
	}
}

- (void)draggingUpdatedInTabBar:(PSMTabBarControl *)control atPoint:(NSPoint)mouseLoc
{
    if ([self destinationTabBar] != control) {
        [self setDestinationTabBar:control];
    }
    [self setCurrentMouseLoc:mouseLoc];
}

- (void)draggingExitedTabBar:(PSMTabBarControl *)control
{
	if ([[control delegate] respondsToSelector:@selector(tabView:shouldAllowTabViewItem:toLeaveTabBar:)] &&
		![[control delegate] tabView:[control tabView] shouldAllowTabViewItem:[[self draggedCell] representedObject] toLeaveTabBar:control]) {
		return;
	}

    [self setDestinationTabBar:nil];
    [self setCurrentMouseLoc:NSMakePoint(-1.0f, -1.0f)];
	
	if (_fadeTimer) {
		[_fadeTimer invalidate];
		_fadeTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0 target:self selector:@selector(fadeInDragWindow:) userInfo:nil repeats:YES];
	} else if (_draggedTab) {
		if (_currentTearOffStyle == PSMTabBarTearOffAlphaWindow) {
			//create a new floating drag window
			if (!_draggedView) {
				NSUInteger styleMask;
				NSImage *viewImage = [self _imageForViewOfCell:[self draggedCell] styleMask:&styleMask];
				
				_draggedView = [[PSMTabDragWindowController alloc] initWithImage:viewImage styleMask:styleMask tearOffStyle:PSMTabBarTearOffAlphaWindow initialAlpha:[control usesSafariStyleDragging]?1:kPSMTabDragWindowAlpha];
				[[_draggedView window] setAlphaValue:0.0f];

				// Inform the delegate a new drag window was created to allow any changes
				if ([control delegate] && [[control delegate] respondsToSelector:@selector(tabViewDragWindowCreated:)]) {
					[[control delegate] tabViewDragWindowCreated:[_draggedView window]];
				}
			}
			
			NSPoint targetPoint = [[_draggedTab window] frame].origin;
			targetPoint.y += _dragWindowOffset.height;
			[[_draggedView window] setFrameTopLeftPoint:targetPoint];
			[[_draggedView window] orderWindow:NSWindowBelow relativeTo:[[_draggedTab window] windowNumber]];

		} else if (_currentTearOffStyle == PSMTabBarTearOffMiniwindow && ![_draggedTab alternateImage]) {
			NSImage *image;
			NSSize imageSize;
			NSUInteger mask; //we don't need this but we can't pass nil in for the style mask, as some delegate implementations will crash
			
			if ( !(image = [self _miniwindowImageOfWindow:[control window]]) ) {
				image = [[self _imageForViewOfCell:[self draggedCell] styleMask:&mask] copy];
			}
			
			imageSize = [image size];
			
			if (imageSize.width > imageSize.height) {
				[image setSize:NSMakeSize(125, 125 * (imageSize.height / imageSize.width))];
			} else {
				[image setSize:NSMakeSize(125 * (imageSize.width / imageSize.height), 125)];
			}
			
			[_draggedTab setAlternateImage:image];
		}
		
		//set the window's alpha mask to zero if the last tab is being dragged
		//don't fade out the old window if the delegate doesn't respond to the new tab bar method, just to be safe
		if ([[[self sourceTabBar] tabView] numberOfTabViewItems] == 1 && [self sourceTabBar] == control &&
				[[[self sourceTabBar] delegate] respondsToSelector:@selector(tabView:newTabBarForDraggedTabViewItem:atPoint:)]) {
			[[[self sourceTabBar] window] setAlphaValue:0.0f];
			[[[self sourceTabBar] window] setIgnoresMouseEvents:YES];
			
			if ([_sourceTabBar tearOffStyle] == PSMTabBarTearOffAlphaWindow) {
				[[_draggedView window] setAlphaValue:kPSMTabDragWindowAlpha];				
			} else {
				[_draggedTab switchImages];
				_centersDragWindows = YES;
			}
		} else {
			if ([_sourceTabBar tearOffStyle] == PSMTabBarTearOffAlphaWindow) {
				_fadeTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0 target:self selector:@selector(fadeInDragWindow:) userInfo:nil repeats:YES];
			} else {
				[_draggedTab switchImages];
				_centersDragWindows = YES;
			}
		}
	}
}

- (void)performDragOperation
{
    // move cell
	NSUInteger destinationIndex = [[[self destinationTabBar] cells] indexOfObject:[self targetCell]];
	
	//there is the slight possibility of the targetCell now being set properly, so avoid errors
	if (destinationIndex >= [[[self destinationTabBar] cells] count])  {
		destinationIndex = [[[self destinationTabBar] cells] count] - 1;
	}
	
    [[[self destinationTabBar] cells] replaceObjectAtIndex:destinationIndex withObject:[self draggedCell]];
    [[self draggedCell] setCustomControlView:[self destinationTabBar]];
	
    // move actual NSTabViewItem
    if ([self sourceTabBar] != [self destinationTabBar]) {

		//remove the tracking rects and bindings registered on the old tab
		[[self sourceTabBar] removeTrackingRect:[[self draggedCell] closeButtonTrackingTag]];
		[[self sourceTabBar] removeTrackingRect:[[self draggedCell] cellTrackingTag]];
		[[self sourceTabBar] removeTabForCell:[self draggedCell]];
		
		NSUInteger i;
		NSInteger insertIndex;
		NSArray *cells = [[self destinationTabBar] cells];
		
		//find the index of where the dragged cell was just dropped
		for (i = 0, insertIndex = 0; (i < [cells count]) && ([cells objectAtIndex:i] != [self draggedCell]); i++, insertIndex++) {
			if ([[cells objectAtIndex:i] isPlaceholder]) {
				insertIndex--;
			}
		}
		
        [[[self sourceTabBar] tabView] removeTabViewItem:[[self draggedCell] representedObject]];
        [[[self destinationTabBar] tabView] insertTabViewItem:[[self draggedCell] representedObject] atIndex:insertIndex];
		
		//calculate the position for the dragged cell
		if ([[self destinationTabBar] automaticallyAnimates]) {
			if (insertIndex > 0) {
				NSRect cellRect = [[cells objectAtIndex:insertIndex - 1] frame];
				cellRect.origin.x += cellRect.size.width;
				[[self draggedCell] setFrame:cellRect];
			}
		}
		
		//rebind the cell to the new control
		[[self destinationTabBar] bindPropertiesForCell:[self draggedCell] andTabViewItem:[[self draggedCell] representedObject]];
		
		//select the newly moved item in the destination tab view
		[[[self destinationTabBar] tabView] selectTabViewItem:[[self draggedCell] representedObject]];
    } else {
		//have to do this before checking the index of a cell otherwise placeholders will be counted
		[self removeAllPlaceholdersFromTabBar:[self sourceTabBar]];
		
		//rearrange the tab view items
		NSTabView *tabView = [[self sourceTabBar] tabView];
		NSTabViewItem *item = [[self draggedCell] representedObject];
		BOOL reselect = ([tabView selectedTabViewItem] == item);
		NSUInteger anIndex;
		NSArray *cells = [[self sourceTabBar] cells];
		
		//find the index of where the dragged cell was just dropped
		for (anIndex = 0; anIndex < [cells count] && [cells objectAtIndex:anIndex] != [self draggedCell]; anIndex++);
		
		//temporarily disable the delegate in order to move the tab to a different index
		id tempDelegate = [tabView delegate];
		[tabView setDelegate:nil];
		[item retain];
		[tabView removeTabViewItem:item];
		[tabView insertTabViewItem:item atIndex:anIndex];
		if (reselect) {
			[tabView selectTabViewItem:item];
		}
		[tabView setDelegate:tempDelegate];
	}
	
	if (([self sourceTabBar] != [self destinationTabBar] || (NSInteger)[[[self sourceTabBar] cells] indexOfObject:[self draggedCell]] != _draggedCellIndex) && [[[self sourceTabBar] delegate] respondsToSelector:@selector(tabView:didDropTabViewItem:inTabBar:)]) {
		[[[self sourceTabBar] delegate] tabView:[[self sourceTabBar] tabView] didDropTabViewItem:[[self draggedCell] representedObject] inTabBar:[self destinationTabBar]];
	}
	
    [self finishDrag];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:PSMTabDragDidEndNotification object:nil];
}

- (void)draggedImageEndedAt:(NSPoint)aPoint operation:(NSDragOperation)operation
{
    if ([self isDragging]) {  // means there was not a successful drop (performDragOperation)
		id sourceDelegate = [[self sourceTabBar] delegate];

		// Extract the menu bar rect
		NSScreen *menuBarScreen = [[NSScreen screens] objectAtIndex:0];
		NSRect menuBarRect = [menuBarScreen frame];
		menuBarRect.origin.y = menuBarRect.size.height;
		menuBarRect.size.height = 22;

		// Split off the dragged tab into a new window.
		// Do this if there's no destination tab bar, the delegate approves it, and the delegate supports it - and
		// not if the drag ended in the menu bar (which acts as a cancel)
		if ([self destinationTabBar] == nil
			&& sourceDelegate && [sourceDelegate respondsToSelector:@selector(tabView:shouldDropTabViewItem:inTabBar:)] &&
				[sourceDelegate tabView:[[self sourceTabBar] tabView] shouldDropTabViewItem:[[self draggedCell] representedObject] inTabBar:nil]
			&& [sourceDelegate respondsToSelector:@selector(tabView:newTabBarForDraggedTabViewItem:atPoint:)]
			&& !NSPointInRect(aPoint, menuBarRect))
		{
			PSMTabBarControl *control = [sourceDelegate tabView:[[self sourceTabBar] tabView] newTabBarForDraggedTabViewItem:[[self draggedCell] representedObject] atPoint:aPoint];
			
			if (control) {
				//add the dragged tab to the new window
				[[control cells] insertObject:[self draggedCell] atIndex:0];
				
				//remove the tracking rects and bindings registered on the old tab
				[[self sourceTabBar] removeTrackingRect:[[self draggedCell] closeButtonTrackingTag]];
				[[self sourceTabBar] removeTrackingRect:[[self draggedCell] cellTrackingTag]];
				[[self sourceTabBar] removeTabForCell:[self draggedCell]];
				
				//rebind the cell to the new control
				[control bindPropertiesForCell:[self draggedCell] andTabViewItem:[[self draggedCell] representedObject]];
				
				[[self draggedCell] setCustomControlView:control];
				
				[[[self sourceTabBar] tabView] removeTabViewItem:[[self draggedCell] representedObject]];
				
				[[control tabView] addTabViewItem:[[self draggedCell] representedObject]];
				[control update:NO]; //make sure the new tab is set in the correct position
				
				if (_currentTearOffStyle == PSMTabBarTearOffAlphaWindow) {
				
					// Grab the window frame, and show - which moves it fully onto screen - before restoring
					NSRect draggedWindowFrame = [[control window] frame];
					[[control window] makeKeyAndOrderFront:nil];
					[[control window] setFrame:draggedWindowFrame display:YES];
				} else {
					//center the window over where we ended dragging
					[self _expandWindow:[control window] atPoint:[NSEvent mouseLocation]];
				}
				
				if ([sourceDelegate respondsToSelector:@selector(tabView:didDropTabViewItem:inTabBar:)]) {
					[sourceDelegate tabView:[[self sourceTabBar] tabView] didDropTabViewItem:[[self draggedCell] representedObject] inTabBar:control];
				}
			} else {
				NSLog(@"Delegate returned no control to add to.");
				[[[self sourceTabBar] cells] insertObject:[self draggedCell] atIndex:[self draggedCellIndex]];
			}
			
		} else {

			// put cell back
			[[[self sourceTabBar] cells] insertObject:[self draggedCell] atIndex:[self draggedCellIndex]];
			[[[self sourceTabBar] window] makeKeyAndOrderFront:self];

			// Restore the window alpha if appropriate
			if ([[[self sourceTabBar] tabView] numberOfTabViewItems]) {
				[[[self sourceTabBar] window] setAlphaValue:1.0f];
			}
		}
		
		[self finishDrag];
		
		[[NSNotificationCenter defaultCenter] postNotificationName:PSMTabDragDidEndNotification object:nil];
    }
}

- (void)finishDrag
{
	if ([[[self sourceTabBar] tabView] numberOfTabViewItems] == 0 && [[[self sourceTabBar] delegate] respondsToSelector:@selector(tabView:closeWindowForLastTabViewItem:)]) {
		[[[self sourceTabBar] delegate] tabView:[[self sourceTabBar] tabView] closeWindowForLastTabViewItem:[[self draggedCell] representedObject]];
	}
	
	if (_draggedTab) {
		[[_draggedTab window] orderOut:nil];
		[_draggedTab release];
		_draggedTab = nil;
	}
	
	if (_draggedView) {
		[[_draggedView window] orderOut:nil];
		[_draggedView release];
		_draggedView = nil;
	}
	
	_centersDragWindows = NO;
	
    [_animationTimer invalidate];
    _animationTimer = nil;

    [self removeAllPlaceholdersFromTabBar:[self sourceTabBar]];
    [self setSourceTabBar:nil];
    [self setDestinationTabBar:nil];

    NSEnumerator *e = [_participatingTabBars objectEnumerator];
    PSMTabBarControl *tabBar;
    while ( (tabBar = [e nextObject]) ) {
        [self removeAllPlaceholdersFromTabBar:tabBar];
    }
    [_participatingTabBars removeAllObjects];

	[self setDraggedCell:nil];
    [_sineCurveWidths removeAllObjects];
    [self setTargetCell:nil];
    [self setIsDragging:NO];
}

- (void)draggingBeganAt:(NSPoint)aPoint
{
	if (_draggedTab) {
		[[_draggedTab window] setFrameTopLeftPoint:aPoint];
		[[_draggedTab window] orderFront:nil];
		
		if ([[[self sourceTabBar] tabView] numberOfTabViewItems] == 1) {
			[self draggingExitedTabBar:[self sourceTabBar]];
			if ([_sourceTabBar tearOffStyle] == PSMTabBarTearOffAlphaWindow) {
				[[_draggedTab window] setAlphaValue:0.0f];
			}
		}
	}
}

- (void)draggingMovedTo:(NSPoint)aPoint
{
	if (_draggedTab) {
		if (_centersDragWindows) {
			if ([_draggedTab isAnimating]) {
				return;
			}
			
			//Ignore aPoint, as it seems to give wacky values
			NSRect frame = [[_draggedTab window] frame];
			frame.origin = [NSEvent mouseLocation];
			frame.origin.x -= frame.size.width / 2;
			frame.origin.y -= frame.size.height / 2;
			[[_draggedTab window] setFrame:frame display:NO];
		} else {
			
			// If there is a destination tab bar set to snapping, snap the tab to it.
			if ([self destinationTabBar]
				&& [[self destinationTabBar] usesSafariStyleDragging]
				&& [[self destinationTabBar] orientation] == PSMTabBarHorizontalOrientation)
			{
				NSRect windowFrame = [[[self destinationTabBar] window] frame];
				NSPoint dragPointInWindow = [[self destinationTabBar] convertPoint:aPoint fromView:nil];

				// Vertical snapping
				aPoint.y += windowFrame.origin.y + dragPointInWindow.y;

				// Horizontal constraining/snapping
				if (dragPointInWindow.x - windowFrame.origin.x < 0) aPoint.x = windowFrame.origin.x;
				if (dragPointInWindow.x - windowFrame.origin.x + [[_draggedTab window] frame].size.width > windowFrame.size.width) aPoint.x = windowFrame.origin.x + windowFrame.size.width - [[_draggedTab window] frame].size.width;
			}
			[[_draggedTab window] setFrameTopLeftPoint:aPoint];
		}
		
		if (_draggedView) {
			//move the view representation with the tab
			//the relative position of the dragged view window will be different
			//depending on the position of the tab bar relative to the controlled tab view
			
			aPoint.y -= [[_draggedTab window] frame].size.height;
			aPoint.x -= _dragWindowOffset.width;
			aPoint.y += _dragWindowOffset.height;
			[[_draggedView window] setFrameTopLeftPoint:aPoint];
		}
	}
}

- (void)fadeInDragWindow:(NSTimer *)timer
{
	CGFloat value = [[_draggedView window] alphaValue];
	if (value >= kPSMTabDragWindowAlpha || _draggedTab == nil) {
		[timer invalidate];
		_fadeTimer = nil;
	} else {
		[[_draggedTab window] setAlphaValue:[[_draggedTab window] alphaValue] - kPSMTabDragAlphaInterval];
		[[_draggedView window] setAlphaValue:value + kPSMTabDragAlphaInterval];
	}
}

- (void)fadeOutDragWindow:(NSTimer *)timer
{
	CGFloat value = [[_draggedView window] alphaValue];
	NSWindow *tabWindow = [_draggedTab window], *viewWindow = [_draggedView window];
	float tabWindowAlphaValue = [[self destinationTabBar] usesSafariStyleDragging]?1:kPSMTabDragWindowAlpha;
	
	if (value <= 0.0) {
		[viewWindow setAlphaValue:0.0f];
		[tabWindow setAlphaValue:tabWindowAlphaValue];
		
		[timer invalidate];
		_fadeTimer = nil;
	} else {
		if ([tabWindow alphaValue] < tabWindowAlphaValue) {
			[tabWindow setAlphaValue:[tabWindow alphaValue] + kPSMTabDragAlphaInterval];
		}
		[viewWindow setAlphaValue:value - kPSMTabDragAlphaInterval];
	}
}

#pragma mark -
#pragma mark Private

- (NSImage *)_imageForViewOfCell:(PSMTabBarCell *)cell styleMask:(NSUInteger *)outMask
{
	PSMTabBarControl *control = (PSMTabBarControl *)[cell controlView];
	NSImage *viewImage = nil;
	
	if (outMask) {
		*outMask = NSBorderlessWindowMask;
	}
	
	if ([control delegate] && [[control delegate] respondsToSelector:@selector(tabView:imageForTabViewItem:offset:styleMask:)]) {
		//get a custom image representation of the view to drag from the delegate
		NSImage *tabImage = [_draggedTab image];
		NSPoint drawPoint;
		NSRect drawRect;
		_dragWindowOffset = NSZeroSize;
		viewImage = [[control delegate] tabView:[control tabView] imageForTabViewItem:[cell representedObject] offset:&_dragWindowOffset styleMask:outMask];
		[viewImage lockFocus];
		
		//draw the tab into the returned window, that way we don't have two windows being dragged (this assumes the tab will be on the window)
		drawPoint = NSMakePoint(_dragWindowOffset.width, [viewImage size].height - _dragWindowOffset.height);
		
		if ([control orientation] == PSMTabBarHorizontalOrientation) {
			drawPoint.y += [[control style] tabCellHeight] - [tabImage size].height;
			_dragWindowOffset.height -= [[control style] tabCellHeight] - [tabImage size].height;
		} else {
			drawPoint.x += [control frame].size.width - [tabImage size].width;
		}
		drawRect = NSMakeRect(drawPoint.x, drawPoint.y, [tabImage size].width, [tabImage size].height);
		
		[tabImage drawInRect:drawRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0f respectFlipped:YES hints:nil];

		[viewImage unlockFocus];
	} else {
		//the delegate doesn't give a custom image, so use an image of the view
		NSView *tabView = [[cell representedObject] view];
		viewImage = [[[NSImage alloc] initWithSize:[tabView frame].size] autorelease];
		[viewImage lockFocus];
		[tabView drawRect:[tabView bounds]];
		[viewImage unlockFocus];
	}
	
	if (outMask && (*outMask | NSBorderlessWindowMask)) {
		_dragWindowOffset.height += 22;
	}
	
	return viewImage;
}

- (NSImage *)_miniwindowImageOfWindow:(NSWindow *)window
{
	NSRect rect = [window frame];
	NSImage *image = [[[NSImage alloc] initWithSize:rect.size] autorelease];
	[image lockFocus];
	rect.origin = NSZeroPoint;
	CGContextCopyWindowCaptureContentsToRect([[NSGraphicsContext currentContext] graphicsPort], *(CGRect *)&rect, [NSApp contextID], [window windowNumber], 0);
	[image unlockFocus];
	
	return image;
}

- (void)_expandWindow:(NSWindow *)window atPoint:(NSPoint)point
{
	NSRect frame = [window frame];
	[window setFrameTopLeftPoint:NSMakePoint(point.x - frame.size.width / 2, point.y + frame.size.height / 2)];
	[window setAlphaValue:0.0f];
	[window makeKeyAndOrderFront:nil];
	
	NSAnimation *animation = [[NSAnimation alloc] initWithDuration:0.25 animationCurve:NSAnimationEaseInOut];
	[animation setAnimationBlockingMode:NSAnimationNonblocking];
	[animation setCurrentProgress:0.1f];
	[animation startAnimation];
	NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0 target:self selector:@selector(_expandWindowTimerFired:) userInfo:[NSDictionary dictionaryWithObjectsAndKeys:window, @"Window", animation, @"Animation", nil] repeats:YES];
	[[NSRunLoop currentRunLoop] addTimer:timer forMode:NSEventTrackingRunLoopMode];
}

- (void)_expandWindowTimerFired:(NSTimer *)timer
{
	NSWindow *window = [[timer userInfo] objectForKey:@"Window"];
	NSAnimation *animation = [[timer userInfo] objectForKey:@"Animation"];
	CGAffineTransform transform;
	NSPoint translation;
	NSRect winFrame = [window frame];
	
	translation.x = (winFrame.size.width / 2.0f);
	translation.y = (winFrame.size.height / 2.0f);
	transform = CGAffineTransformMakeTranslation(translation.x, translation.y);
	transform = CGAffineTransformScale(transform, 1.0f / [animation currentValue], 1.0f / [animation currentValue]);
	transform = CGAffineTransformTranslate(transform, -translation.x, -translation.y);
	
	translation.x = -winFrame.origin.x;
	translation.y = winFrame.origin.y + winFrame.size.height - [[NSScreen mainScreen] frame].size.height;
	
	transform = CGAffineTransformTranslate(transform, translation.x, translation.y);
	
	CGSSetWindowTransform([NSApp contextID], [window windowNumber], transform);
	
	[window setAlphaValue:[animation currentValue]];
	
	if (![animation isAnimating]) {
		[timer invalidate];
		[animation release];
	}
}

#pragma mark -
#pragma mark Animation

- (void)animateDrag:(NSTimer *)timer
{
    NSEnumerator *e = [[[_participatingTabBars copy] autorelease] objectEnumerator];
    PSMTabBarControl *tabBar;
    while ( (tabBar = [e nextObject]) ) {
        [self calculateDragAnimationForTabBar:tabBar];
		[[NSRunLoop currentRunLoop] performSelector:@selector(display) target:tabBar argument:nil order:1 modes:@[@"NSEventTrackingRunLoopMode", @"NSDefaultRunLoopMode"]];
    }
}

- (void)calculateDragAnimationForTabBar:(PSMTabBarControl *)control
{
    BOOL removeFlag = YES;
    NSMutableArray *cells = [control cells];
    NSInteger i, cellCount = [cells count];
    CGFloat position = [control orientation] == PSMTabBarHorizontalOrientation ? [[control style] leftMarginForTabBarControl] : [[control style] topMarginForTabBarControl];

    if ([self destinationTabBar] == control) {
        removeFlag = NO;

		// Determine the location of the point to use.
		NSPoint targetPoint;
		if ([control usesSafariStyleDragging]) {
			NSRect draggedTabWindowFrame = [[_draggedTab window] contentRectForFrameRect:[[_draggedTab window] frame]];
			NSRect controlWindowFrame = [[control window] contentRectForFrameRect:[[control window] frame]];
			NSPoint tabTopLeftInWindowCoords = NSMakePoint(draggedTabWindowFrame.origin.x - controlWindowFrame.origin.x, controlWindowFrame.origin.y + (2*controlWindowFrame.size.height) - draggedTabWindowFrame.origin.y);
			targetPoint = [control convertPoint:tabTopLeftInWindowCoords fromView:nil];
			targetPoint.x += (draggedTabWindowFrame.size.width / 2.0f);
			targetPoint.y = 0 - (draggedTabWindowFrame.size.height / 2.0f) - targetPoint.y;
		} else {
			targetPoint = [self currentMouseLoc];
		}

        if (targetPoint.x < [[control style] leftMarginForTabBarControl]) {
            [self setTargetCell:[cells objectAtIndex:0]];
        } else {

			// Identify which cell the mouse is over
			NSRect overCellRect;
			PSMTabBarCell *overCell = [control cellForPoint:targetPoint cellFrame:&overCellRect];
			if (overCell) {

				// Mouse is among cells - placeholder
				if ([overCell isPlaceholder]) {
					[self setTargetCell:overCell];
					
				// Non-placeholder cells - horizontal orientation
				} else if ([control orientation] == PSMTabBarHorizontalOrientation) {
					
					// Handle Safari-style dragging
					if ([control usesSafariStyleDragging]) {
					
						// Determine the index of the tab the dragged tab is over
						NSUInteger overCellIndex = [cells indexOfObject:overCell];
						
						// Determine the index of the current target
						NSUInteger currentTargetCellIndex = _targetCell?[cells indexOfObject:_targetCell]:NSUIntegerMax;

						// Ensure that drag changes aren't as a result of an animation
						NSInteger currentCellStep = [[cells objectAtIndex:(overCellIndex - 1)] currentStep];
						if (!currentCellStep || currentCellStep == kPSMTabDragAnimationSteps - 1) {

							// Center of the tab is past the edge of the tab to the left
							if (targetPoint.x < (overCellRect.origin.x + overCellRect.size.width)
								&& currentTargetCellIndex > overCellIndex)
							{
								[self setTargetCell:[cells objectAtIndex:(overCellIndex - 1)]];

							// Center of the tab is past the edge of the tab to the right
							} else if (targetPoint.x > overCellRect.origin.x) {
								[self setTargetCell:[cells objectAtIndex:(overCellIndex + 1)]];
							}
						}
					
					// Handle old-style dragging based on mouse position
					} else {
						
						// Mouse is over the left side of the cell
						if (targetPoint.x < (overCellRect.origin.x + (overCellRect.size.width / 2.0))) {
							[self setTargetCell:[cells objectAtIndex:([cells indexOfObject:overCell] - 1)]];
						
						// Otherwise the mouse is over the right side of the cell
						} else {
							[self setTargetCell:[cells objectAtIndex:([cells indexOfObject:overCell] + 1)]];
						}
					}
				} else {
					// non-placeholders - vertical orientation
					if (targetPoint.y < (overCellRect.origin.y + (overCellRect.size.height / 2.0))) {
						// mouse on top of cell
						[self setTargetCell:[cells objectAtIndex:([cells indexOfObject:overCell] - 1)]];
					} else {
						// mouse on bottom of cell
						[self setTargetCell:[cells objectAtIndex:([cells indexOfObject:overCell] + 1)]];
					}
				}
			} else {
				// out at end - must find proper cell (could be more in overflow menu)
				[self setTargetCell:[control lastVisibleTab]];
			}
		}
    } else {
        [self setTargetCell:nil];
    }
	
    for (i = 0; i < cellCount; i++) {
        PSMTabBarCell *cell = [cells objectAtIndex:i];
        NSRect newRect = [cell frame];
        if (![cell isInOverflowMenu]) {
            if ([cell isPlaceholder]) {
                if (cell == [self targetCell]) {
                    [cell setCurrentStep:([cell currentStep] + 1)];
                } else {
                    [cell setCurrentStep:([cell currentStep] - 1)];
                    if ([cell currentStep] > 0) {
                        removeFlag = NO;
                    }
                }
				
				if ([control orientation] == PSMTabBarHorizontalOrientation) {
					newRect.size.width = [[_sineCurveWidths objectAtIndex:[cell currentStep]] integerValue];
				} else {
					newRect.size.height = [[_sineCurveWidths objectAtIndex:[cell currentStep]] integerValue];
				}
            }
        } else {
            break;
        }
        
		if ([control orientation] == PSMTabBarHorizontalOrientation) {
			newRect.origin.x = position;
			position += newRect.size.width;
		} else {
			newRect.origin.y = position;
			position += newRect.size.height;
		}
        [cell setFrame:newRect];
        if ([cell indicator]) {
            [[cell indicator] setFrame:[[control style] indicatorRectForTabCell:cell]];
        }
    }
    if (removeFlag) {
        [_participatingTabBars removeObject:control];
        [self removeAllPlaceholdersFromTabBar:control];
    }
}

#pragma mark -
#pragma mark Placeholders

- (void)distributePlaceholdersInTabBar:(PSMTabBarControl *)control withDraggedCell:(PSMTabBarCell *)cell
{
    // called upon first drag - must distribute placeholders
    [self distributePlaceholdersInTabBar:control];
	
	NSMutableArray *cells = [control cells];
	
    // replace dragged cell with a placeholder, and clean up surrounding cells
    NSInteger cellIndex = [cells indexOfObject:cell];
    PSMTabBarCell *pc = [[[PSMTabBarCell alloc] initPlaceholderWithFrame:[[self draggedCell] frame] expanded:YES inControlView:control] autorelease];
    [cells replaceObjectAtIndex:cellIndex withObject:pc];
    [cells removeObjectAtIndex:(cellIndex + 1)];
    [cells removeObjectAtIndex:(cellIndex - 1)];
	
	if (cellIndex - 2 >= 0) {
		pc = [cells objectAtIndex:cellIndex - 2];
		[pc setTabState:~[pc tabState] & PSMTab_RightIsSelectedMask];
	}
}

- (void)distributePlaceholdersInTabBar:(PSMTabBarControl *)control
{
    NSUInteger i, numVisibleTabs = [control numberOfVisibleTabs];
    for (i = 0; i < numVisibleTabs; i++) {
        PSMTabBarCell *pc = [[[PSMTabBarCell alloc] initPlaceholderWithFrame:[[self draggedCell] frame] expanded:NO inControlView:control] autorelease];
        [[control cells] insertObject:pc atIndex:(2 * i)];
    }
	
	PSMTabBarCell *pc = [[[PSMTabBarCell alloc] initPlaceholderWithFrame:[[self draggedCell] frame] expanded:NO inControlView:control] autorelease];
	if ([[control cells] count] > (2 * numVisibleTabs)) {
		[[control cells] insertObject:pc atIndex:(2 * numVisibleTabs)];
	} else {
		[[control cells] addObject:pc];
	}
}

- (void)removeAllPlaceholdersFromTabBar:(PSMTabBarControl *)control
{
    NSInteger i, cellCount = [[control cells] count];
    for (i = (cellCount - 1); i >= 0; i--) {
        PSMTabBarCell *cell = [[control cells] objectAtIndex:i];
        if ([cell isPlaceholder]) {
			[NSObject cancelPreviousPerformRequestsWithTarget:cell];
			[control removeTabForCell:cell];
        }
    }
    // redraw
    [control update:NO];
}

#pragma mark -
#pragma mark Archiving

- (void)encodeWithCoder:(NSCoder *)aCoder {
    //[super encodeWithCoder:aCoder];
    if ([aCoder allowsKeyedCoding]) {
        [aCoder encodeObject:_sourceTabBar forKey:@"sourceTabBar"];
        [aCoder encodeObject:_destinationTabBar forKey:@"destinationTabBar"];
        [aCoder encodeObject:_participatingTabBars forKey:@"participatingTabBars"];
        [aCoder encodeObject:_draggedCell forKey:@"draggedCell"];
        [aCoder encodeInteger:_draggedCellIndex forKey:@"draggedCellIndex"];
        [aCoder encodeBool:_isDragging forKey:@"isDragging"];
        [aCoder encodeObject:_animationTimer forKey:@"animationTimer"];
        [aCoder encodeObject:_sineCurveWidths forKey:@"sineCurveWidths"];
        [aCoder encodePoint:_currentMouseLoc forKey:@"currentMouseLoc"];
        [aCoder encodeObject:_targetCell forKey:@"targetCell"];
    }
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    //self = [super initWithCoder:aDecoder];
    //if (self) {
        if ([aDecoder allowsKeyedCoding]) {
            _sourceTabBar = [[aDecoder decodeObjectForKey:@"sourceTabBar"] retain];
            _destinationTabBar = [[aDecoder decodeObjectForKey:@"destinationTabBar"] retain];
            _participatingTabBars = [[aDecoder decodeObjectForKey:@"participatingTabBars"] retain];
            _draggedCell = [[aDecoder decodeObjectForKey:@"draggedCell"] retain];
            _draggedCellIndex = [aDecoder decodeIntegerForKey:@"draggedCellIndex"];
            _isDragging = [aDecoder decodeBoolForKey:@"isDragging"];
            _animationTimer = [[aDecoder decodeObjectForKey:@"animationTimer"] retain];
            _sineCurveWidths = [[aDecoder decodeObjectForKey:@"sineCurveWidths"] retain];
            _currentMouseLoc = [aDecoder decodePointForKey:@"currentMouseLoc"];
            _targetCell = [[aDecoder decodeObjectForKey:@"targetCell"] retain];
        }
    //}
    return self;
}


@end
