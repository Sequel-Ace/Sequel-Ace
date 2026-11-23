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

#import "sequel-ace-Swift.h"


@implementation SPFavoriteColorSupport

@synthesize userColorList;

static SPFavoriteColorSupport *_colorSupport = nil;

- (instancetype)init
{
    return [self initWithDefaults:[NSUserDefaults standardUserDefaults]];
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
{
    if ((self = [super init])) {
        prefs = defaults;
        userColorList = [self populateUserColorList];

        // I doubt the colours will ever change in prefs, but just in case....
        [prefs addObserver:self
                forKeyPath:SPFavoriteColorList
                   options:NSKeyValueObservingOptionNew
                   context:NULL];
    }

    return self;
}

- (void)dealloc
{
    [prefs removeObserver:self forKeyPath:SPFavoriteColorList];
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
	// The vivid palette, one colour per stored index; it replaces the preference-archived list.
	return [SAFavoritePalette assetColours];
}

#pragma mark -
#pragma mark Key Value Observing

/**
 * A change to the old archived list (a defaults write, a preferences import) reloads the vivid palette:
 * the old 7-colour list never comes back, so Teal, Blue and Pink (indices 7-9) keep their colour.
 */
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:SPFavoriteColorList]) {
        userColorList = [self populateUserColorList];
    }
}

@end
