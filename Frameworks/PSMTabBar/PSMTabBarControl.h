//
//  PSMTabBarControl.h
//  PSMTabBarControl
//
//  Created by John Pannell on 10/13/05.
//  Copyright 2005 Positive Spin Media. All rights reserved.
//

/*
 This view provides a control interface to manage a regular NSTabView.  It looks and works like the tabbed browsing interface of many popular browsers.
 */

#import <Cocoa/Cocoa.h>

#define PSMTabDragDidEndNotification @"PSMTabDragDidEndNotification"
#define PSMTabDragDidBeginNotification @"PSMTabDragDidBeginNotification"

#define kPSMTabBarControlHeight 25
#define kPSMTabBarControlDefaultHeightCollapsed 0 // can be changed with a property

// internal cell border
#define MARGIN_X        6
#define MARGIN_Y        6

// padding between objects
#define kPSMTabBarCellPadding 4

// fixed size objects
#define kPSMMinimumTitleWidth 30
#define kPSMTabBarIndicatorWidth 16.0f
#define kPSMTabBarIconWidth 16.0f
#define kPSMHideAnimationSteps 3.0f

// Value used in _currentStep to indicate that resizing operation is not in progress
#define kPSMIsNotBeingResized -1

// Value used in _currentStep when a resizing operation has just been started
#define kPSMStartResizeAnimation 0

@class PSMOverflowPopUpButton, PSMRolloverButton, PSMTabBarCell, PSMTabBarController;
@protocol PSMTabStyle;

typedef enum {
	PSMTabBarHorizontalOrientation,
	PSMTabBarVerticalOrientation
} PSMTabBarOrientation;

typedef enum {
	PSMTabBarTearOffAlphaWindow,
	PSMTabBarTearOffMiniwindow
} PSMTabBarTearOffStyle;

enum {
    PSMTab_SelectedMask         = 1 << 1,
    PSMTab_LeftIsSelectedMask   = 1 << 2,
    PSMTab_RightIsSelectedMask  = 1 << 3,
    PSMTab_PositionLeftMask     = 1 << 4,
    PSMTab_PositionMiddleMask   = 1 << 5,
    PSMTab_PositionRightMask    = 1 << 6,
    PSMTab_PositionSingleMask   = 1 << 7
};

@interface PSMTabBarControl : NSControl {
	// control basics
	NSMutableArray			*_cells;					// the cells that draw the tabs
	IBOutlet NSTabView		*tabView;					// the tab view being navigated
	PSMOverflowPopUpButton	*_overflowPopUpButton;		// for too many tabs
	PSMRolloverButton			*_addTabButton;
	PSMTabBarController		*_controller;
	
	// Spring-loading.
	NSTabViewItem			*_tabViewItemWithSpring;
	
	// drawing style
	id<PSMTabStyle>			style;
	BOOL					_canCloseOnlyTab;
	BOOL					_disableTabClose;
	BOOL					_hideForSingleTab;
	BOOL					_showAddTabButton;
	BOOL					_sizeCellsToFit;
	BOOL					_useOverflowMenu;
	BOOL					_alwaysShowActiveTab;
	BOOL					_allowsScrubbing;
	BOOL					_useSafariStyleDragging;
	NSInteger				_resizeAreaCompensation;
	PSMTabBarOrientation	_orientation;
	BOOL					_automaticallyAnimates;
	NSTimer					*_animationTimer;
	PSMTabBarTearOffStyle	_tearOffStyle;
	
	// behavior
	BOOL					_allowsBackgroundTabClosing;
	BOOL					_selectsTabsOnMouseDown;
	BOOL					_createsTabOnDoubleClick;
	id						_createNewTabTarget;
	SEL						_createNewTabAction;
	id						_doubleClickTarget;
	SEL						_doubleClickAction;
	
	// vertical tab resizing
	BOOL					_allowsResizing;
	BOOL					_resizing;
	
	// cell width
	NSInteger				_cellMinWidth;
	NSInteger				_cellMaxWidth;
	NSInteger				_cellOptimumWidth;
	
	// animation for hide/show
	NSInteger				_currentStep;
	BOOL					_isHidden;
	IBOutlet id				partnerView;				// gets resized when hide/show
	BOOL					_awakenedFromNib;
	NSInteger				_tabBarWidth;
	NSTimer					*_showHideAnimationTimer;

	// Tracking last window state for update draws
	BOOL					_lastWindowIsMainCheck;
	BOOL					_lastAttachedWindowIsMainCheck;
	BOOL					_lastAppIsActiveCheck;

	// drag and drop
	NSEvent					*_lastMouseDownEvent;	    // keep this for dragging reference
	BOOL					_didDrag;
	BOOL					_closeClicked;
	
	// MVC help
	IBOutlet id				delegate;
}

// control characteristics
+ (NSBundle *)bundle;
- (CGFloat)availableCellWidth;
- (NSRect)genericCellRect;

// control configuration
- (PSMTabBarOrientation)orientation;
- (void)setOrientation:(PSMTabBarOrientation)value;
- (BOOL)canCloseOnlyTab;
- (void)setCanCloseOnlyTab:(BOOL)value;
- (BOOL)disableTabClose;
- (void)setDisableTabClose:(BOOL)value;
- (id<PSMTabStyle>)style;
- (void)setStyle:(id <PSMTabStyle>)newStyle;
- (NSString *)styleName;
- (void)setStyleNamed:(NSString *)name;
- (BOOL)hideForSingleTab;
- (void)setHideForSingleTab:(BOOL)value;
- (BOOL)showAddTabButton;
- (void)setShowAddTabButton:(BOOL)value;

- (id)createNewTabTarget;
- (void)setCreateNewTabTarget:(id)object;
- (SEL)createNewTabAction;
- (void)setCreateNewTabAction:(SEL)selector;

- (id)doubleClickTarget;
- (void)setDoubleClickTarget:(id)object;
- (SEL)doubleClickAction;
- (void)setDoubleClickAction:(SEL)selector;

- (NSInteger)cellMinWidth;
- (void)setCellMinWidth:(NSInteger)value;
- (NSInteger)cellMaxWidth;
- (void)setCellMaxWidth:(NSInteger)value;
- (NSInteger)cellOptimumWidth;
- (void)setCellOptimumWidth:(NSInteger)value;
- (BOOL)sizeCellsToFit;
- (void)setSizeCellsToFit:(BOOL)value;
- (BOOL)useOverflowMenu;
- (void)setUseOverflowMenu:(BOOL)value;
- (BOOL)allowsBackgroundTabClosing;
- (void)setAllowsBackgroundTabClosing:(BOOL)value;
- (BOOL)allowsResizing;
- (void)setAllowsResizing:(BOOL)value;
- (BOOL)selectsTabsOnMouseDown;
- (void)setSelectsTabsOnMouseDown:(BOOL)value;
- (BOOL)createsTabOnDoubleClick;
- (void)setCreatesTabOnDoubleClick:(BOOL)value;
- (BOOL)automaticallyAnimates;
- (void)setAutomaticallyAnimates:(BOOL)value;
- (BOOL)alwaysShowActiveTab;
- (void)setAlwaysShowActiveTab:(BOOL)value;
- (BOOL)allowsScrubbing;
- (void)setAllowsScrubbing:(BOOL)value;
- (BOOL)usesSafariStyleDragging;
- (void)setUsesSafariStyleDragging:(BOOL)value;
- (PSMTabBarTearOffStyle)tearOffStyle;
- (void)setTearOffStyle:(PSMTabBarTearOffStyle)tearOffStyle;
@property CGFloat heightCollapsed;

// accessors
- (NSTabView *)tabView;
- (void)setTabView:(NSTabView *)view;
- (id)delegate;
- (void)setDelegate:(id)object;
- (id)partnerView;
- (void)setPartnerView:(id)view;

// the buttons
- (PSMRolloverButton *)addTabButton;
- (PSMOverflowPopUpButton *)overflowPopUpButton;

// actions
- (void)tabClick:(id)sender;
- (void)overflowMenuAction:(id)sender;

// tab information
- (NSMutableArray *)representedTabViewItems;
- (NSUInteger)numberOfVisibleTabs;
- (PSMTabBarCell *)lastVisibleTab;

// special effects
- (void)hideTabBar:(BOOL)hide animate:(BOOL)animate;
- (BOOL)isTabBarHidden;
- (BOOL)isAnimating;
- (void)destroyAnimations;

// internal bindings methods also used by the tab drag assistant
- (void)bindPropertiesForCell:(PSMTabBarCell *)cell andTabViewItem:(NSTabViewItem *)item;
- (void)removeTabForCell:(PSMTabBarCell *)cell;

// External drawing accessors
- (void)update;
- (void)update:(BOOL)animate;

@end


@interface NSObject (TabBarControlDelegateMethods)

//Standard NSTabView methods
- (BOOL)tabView:(NSTabView *)aTabView shouldCloseTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)aTabView didCloseTabViewItem:(NSTabViewItem *)tabViewItem;

//"Spring-loaded" tabs methods
- (NSArray *)allowedDraggedTypesForTabView:(NSTabView *)aTabView;
- (void)tabView:(NSTabView *)aTabView acceptedDraggingInfo:(id <NSDraggingInfo>)draggingInfo onTabViewItem:(NSTabViewItem *)tabViewItem;

//Contextual menu method
- (NSMenu *)tabView:(NSTabView *)aTabView menuForTabViewItem:(NSTabViewItem *)tabViewItem;

//Drag and drop methods
- (BOOL)tabView:(NSTabView *)aTabView shouldDragTabViewItem:(NSTabViewItem *)tabViewItem fromTabBar:(PSMTabBarControl *)tabBarControl;
- (BOOL)tabView:(NSTabView *)aTabView shouldDropTabViewItem:(NSTabViewItem *)tabViewItem inTabBar:(PSMTabBarControl *)tabBarControl;
- (BOOL)tabView:(NSTabView *)aTabView shouldAllowTabViewItem:(NSTabViewItem *)tabViewItem toLeaveTabBar:(PSMTabBarControl *)tabBarControl;
- (void)tabView:(NSTabView*)aTabView didDropTabViewItem:(NSTabViewItem *)tabViewItem inTabBar:(PSMTabBarControl *)tabBarControl;
- (void)draggingEvent:(id <NSDraggingInfo>)dragEvent enteredTabBar:(PSMTabBarControl *)tabBarControl tabView:(NSTabViewItem *)tabViewItem;
- (void)tabViewDragWindowCreated:(NSWindow *)dragWindow;

//Tear-off tabs methods
- (NSImage *)tabView:(NSTabView *)aTabView imageForTabViewItem:(NSTabViewItem *)tabViewItem offset:(NSSize *)offset styleMask:(NSUInteger *)styleMask;
- (PSMTabBarControl *)tabView:(NSTabView *)aTabView newTabBarForDraggedTabViewItem:(NSTabViewItem *)tabViewItem atPoint:(NSPoint)point;
- (void)tabView:(NSTabView *)aTabView closeWindowForLastTabViewItem:(NSTabViewItem *)tabViewItem;

//Overflow menu validation
- (BOOL)tabView:(NSTabView *)aTabView validateOverflowMenuItem:(NSMenuItem *)menuItem forTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)aTabView tabViewItem:(NSTabViewItem *)tabViewItem isInOverflowMenu:(BOOL)inOverflowMenu;

//tab bar hiding methods
- (void)tabView:(NSTabView *)aTabView tabBarDidHide:(PSMTabBarControl *)tabBarControl;
- (void)tabView:(NSTabView *)aTabView tabBarDidUnhide:(PSMTabBarControl *)tabBarControl;
- (CGFloat)desiredWidthForVerticalTabBar:(PSMTabBarControl *)tabBarControl;

//closing
- (BOOL)tabView:(NSTabView *)aTabView disableTabCloseForTabViewItem:(NSTabViewItem *)tabViewItem;

//tooltips
- (NSString *)tabView:(NSTabView *)aTabView toolTipForTabViewItem:(NSTabViewItem *)tabViewItem;

//accessibility
- (NSString *)accessibilityStringForTabView:(NSTabView *)aTabView objectCount:(NSInteger)objectCount;

@end
