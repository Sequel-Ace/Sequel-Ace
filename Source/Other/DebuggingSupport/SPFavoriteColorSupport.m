//
//  SPFavoriteColorSupport.m
//  sequel-pro
//
//  Created by Max Lohrmann on 2013-10-20
//  Copyright (c) 2013 Max Lohrmann. All rights reserved.
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

#import "SPFavoriteColorSupport.h"
#import "SPFunctions.h"


@implementation SPFavoriteColorSupport

@synthesize userColorList;

static SPFavoriteColorSupport *_colorSupport = nil;

- (instancetype)init
{
    if ((self = [super init])) {
        prefs = [NSUserDefaults standardUserDefaults];
        userColorList = [self populateUserColorList];

        // I doubt the colours will ever change in prefs, but just in case....
        [prefs addObserver:self
                forKeyPath:SPFavoriteColorList
                   options:NSKeyValueObservingOptionNew
                   context:NULL];
    }

    return self;
}

+ (SPFavoriteColorSupport *)sharedInstance
{
    static dispatch_once_t onceToken;

	if (!_colorSupport) {
        dispatch_once_on_main_thread(&onceToken, ^{
            _colorSupport = [[self allocWithZone:NULL] init];
        });
	}
	
	return _colorSupport;
}

- (NSColor *)colorForIndex:(NSInteger)colorIndex
{
	return [userColorList safeObjectAtIndex:colorIndex];
}

- (NSArray<NSColor *>*)populateUserColorList
{

	if (@available(macOS 10.13, *)) {
		return @[
			[NSColor colorNamed:@"favoriteRed"],
			[NSColor colorNamed:@"favoriteOrange"],
			[NSColor colorNamed:@"favoriteYellow"],
			[NSColor colorNamed:@"favoriteGreen"],
			[NSColor colorNamed:@"favoriteBlue"],
			[NSColor colorNamed:@"favoritePurple"],
			[NSColor colorNamed:@"favoriteGraphite"]
		];
	}
	
	NSArray *archivedColors = [prefs objectForKey:SPFavoriteColorList];
	NSMutableArray *colorList = [NSMutableArray arrayWithCapacity:[archivedColors count]];

	for (NSData *archivedColor in archivedColors)
	{
		NSColor *color = [NSUnarchiver unarchiveObjectWithData:archivedColor];

		[colorList addObject:color];
	}
	
	return [colorList copy];
}

#pragma mark -
#pragma mark Key Value Observing

/**
 * I doubt the colours will ever change in prefs, but just in case....
 */
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    // reload the colours, when the observer detected a change in them
    //
    if ([keyPath isEqualToString:SPFavoriteColorList]) {

        NSArray *archivedColors = [prefs objectForKey:SPFavoriteColorList];
        NSMutableArray *colorList = [NSMutableArray arrayWithCapacity:[archivedColors count]];

        for (NSData *archivedColor in archivedColors)
        {
            NSColor *color = [NSUnarchiver unarchiveObjectWithData:archivedColor];

            [colorList addObject:color];
        }

        userColorList = [colorList copy];
    }
}

@end
