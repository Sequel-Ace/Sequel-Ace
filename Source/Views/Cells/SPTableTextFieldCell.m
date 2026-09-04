//
//  SPTableTextFieldCell.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on November 1, 2009.
//  Copyright (c) 2009 Stuart Connolly. All rights reserved.
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

#import "SPTableTextFieldCell.h"
#import "sequel-ace-Swift.h"

@implementation SPTableTextFieldCell

/**
 * Initialise
 */
- (id) initWithCoder:(NSCoder *)coder
{
	if (self = [super initWithCoder:coder]) {
		noteButton = [[NSTextFieldCell alloc] initTextCell:@""];
		[noteButton setTitle:@""];
		[noteButton setBordered:NO];
		[noteButton setAlignment:NSTextAlignmentRight];
		[noteButton setSelectable:FALSE];
		[noteButton setEditable:FALSE];
	}
	return self;
}

/**
 * Deallocate
 */
- (void) dealloc
{
	noteButton = nil;
}

- copyWithZone:(NSZone *)zone
{
	SPTableTextFieldCell *cell = (SPTableTextFieldCell *)[super copyWithZone:zone];
	cell->noteButton = nil;
	if (noteButton) cell->noteButton = [noteButton copyWithZone:zone];
	return cell;
}

/**
 * Draw the name and optional comment in separate, non-overlapping rectangles.
 */
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	[SATableListCellRenderer drawNameCell:self commentCell:noteButton frame:cellFrame inView:controlView drawName:^(NSRect nameFrame) {
		[super drawInteriorWithFrame:nameFrame inView:controlView];
	}];
}

- (void)setNote:(NSString *)lableText
{
	if (noteButton != nil)
	{
		[noteButton setTitle:lableText];
	}
}

- (NSSize)cellSize
{
	NSSize cellSize = [super cellSize];

	cellSize.width = [[self attributedStringValue] size].width + (([self image] != nil) ? [[self image] size].width : 0) + 25;
	cellSize.height = [[self attributedStringValue] size].height + 14.0f;

	return cellSize;
}

@end
