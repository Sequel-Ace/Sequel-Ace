//
//  SPFavoriteColorSupport.h
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

#import <Foundation/Foundation.h>

@interface SPFavoriteColorSupport : NSObject
{
	NSUserDefaults *prefs;

    
}

@property (strong) NSArray<NSColor *> *userColorList;

/** 
 * Get the single instance of this class
 */
+ (SPFavoriteColorSupport *)sharedInstance;

/** 
 * Get the current color for a specific index.
 * 
 * @return The color or nil if colorIndex was < 0 or the index was not defined.
 */
- (NSColor *)colorForIndex:(NSInteger)colorIndex;

/** 
 * The current list of colors from user prefs.
 * 
 * @return An array with NSColor * items.
 */
- (NSArray<NSColor *>*)populateUserColorList;

@end
