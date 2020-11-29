//
//  SPPrintUtility.m
//  Sequel Ace
//
//  Created by Jakub Kaspar on 29.11.2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

#import "SPPrintUtility.h"
#import "SPPrintAccessory.h"

@implementation SPPrintUtility

+ (NSPrintOperation *)preparePrintOperationWithView:(NSView *)view printView:(WebView *)printView {
	// Because we need the webFrame loaded (for preview), we've moved the actual printing here
	NSPrintInfo *printInfo = [NSPrintInfo sharedPrintInfo];

	NSSize paperSize = [printInfo paperSize];
	NSRect printableRect = [printInfo imageablePageBounds];

	// Calculate page margins
	CGFloat marginL = printableRect.origin.x;
	CGFloat marginR = paperSize.width - (printableRect.origin.x + printableRect.size.width);
	CGFloat marginB = printableRect.origin.y;
	CGFloat marginT = paperSize.height - (printableRect.origin.y + printableRect.size.height);

	// Make sure margins are symetric and positive
	CGFloat marginLR = MAX(0, MAX(marginL, marginR));
	CGFloat marginTB = MAX(0, MAX(marginT, marginB));

	// Set the margins
	[printInfo setLeftMargin:marginLR];
	[printInfo setRightMargin:marginLR];
	[printInfo setTopMargin:marginTB];
	[printInfo setBottomMargin:marginTB];

	[printInfo setHorizontalPagination:NSFitPagination];
	[printInfo setVerticalPagination:NSAutoPagination];
	[printInfo setVerticallyCentered:NO];

	NSPrintOperation *op = [NSPrintOperation printOperationWithView:view printInfo:printInfo];

	// do not try to use webkit from a background thread!
	[op setCanSpawnSeparateThread:NO];

	// Add the ability to select the orientation to print panel
	NSPrintPanel *printPanel = [op printPanel];

	[printPanel setOptions:[printPanel options] + NSPrintPanelShowsOrientation + NSPrintPanelShowsScaling + NSPrintPanelShowsPaperSize];

	SPPrintAccessory *printAccessory = [[SPPrintAccessory alloc] initWithNibName:@"PrintAccessory" bundle:nil];

	[printAccessory setPrintView:printView];
	[printPanel addAccessoryController:printAccessory];

	[[NSPageLayout pageLayout] addAccessoryController:printAccessory];

	[op setPrintPanel:printPanel];

	return op;
}

@end
