//
//  SPAutosizingTextView.m
//  Sequel Ace
//
//  Created by Jason Morcos on 7/8/20.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

#import "SPAutosizingTextView.h"

@implementation SPAutosizingTextView

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
	[self.layoutManager ensureLayoutForTextContainer:self.textContainer];
	self.frame = [self.layoutManager usedRectForTextContainer:self.textContainer];
}

@end
