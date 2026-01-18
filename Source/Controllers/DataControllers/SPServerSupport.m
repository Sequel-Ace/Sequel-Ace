//
//  SPServerSupport.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on September 23, 2010.
//  Copyright (c) 2010 Stuart Connolly. All rights reserved.
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

#import "SPServerSupport.h"

#import <objc/runtime.h>

@interface SPServerSupport ()

- (void)_invalidate;
- (NSComparisonResult)_compareServerMajorVersion:(NSInteger)majorVersionA 
										   minor:(NSInteger)minorVersionA 
										 release:(NSInteger)releaseVersionA
						  withServerMajorVersion:(NSInteger)majorVersionB
										   minor:(NSInteger)minorVersionB
										 release:(NSInteger)releaseVersionB;

@end

@implementation SPServerSupport

@synthesize supportsFractionalSeconds;
@synthesize serverMajorVersion;
@synthesize serverMinorVersion;
@synthesize serverReleaseVersion;
@synthesize supportsFulltextOnInnoDB;

#pragma mark -
#pragma mark Initialisation

/**
 * Creates and returns an instance of SPServerSupport with the supplied version numbers. The caller is
 * responsible it's memory.
 *
 * @param majorVersion   The major version number of the server
 * @param minorVersion   The minor version number of the server
 * @param releaseVersiod The release version number of the server
 *
 * @return The initializes SPServerSupport instance
 */
- (instancetype)initWithMajorVersion:(NSInteger)majorVersion minor:(NSInteger)minorVersion release:(NSInteger)releaseVersion
{
	if ((self = [super init])) {
		serverMajorVersion   = majorVersion;
		serverMinorVersion   = minorVersion;
		serverReleaseVersion = releaseVersion;
		
		// Determine what the server supports
		[self evaluate];
	}
	
	return self;
}

#pragma mark -
#pragma mark Public API

/**
 * Performs the actual version based comparisons to determine what functionaity the server supports. This
 * method is called automatically as part of the designated initializer (initWithMajorVersion:major:minor:release:)
 * and shouldn't really need to be called again throughout a connection's lifetime.
 *
 * Note that for the sake of simplicity this method does not try to be smart in that it does not assume
 * the presence of functionality based on a previous version check. This allows adding new ivars in the 
 * future a matter of simply performing a new version comparison.
 *
 * To add a new metod for determining a server's support for specific functionality, simply add a new 
 * (read only) ivar with the prefix 'supports' and peform the version checking within this method.
 */
- (void)evaluate
{
	// For PostgreSQL, most features are always supported
	[self _invalidate];

	// PostgreSQL has always supported fractional seconds and full-text search
	supportsFractionalSeconds = YES;
    supportsFulltextOnInnoDB  = YES; // PostgreSQL uses GIN/GiST indexes for full-text, always supported
}

/**
 * Convenience method provided as an easy way to determine whether the currently connected server version
 * is equal to or greater than the supplied version numbers. 
 *
 * This method should only be used in the case that the build in support ivars don't cover the version/functionality
 * checking that is required.
 *
 * @param majorVersion   The major version number of the server
 * @param minorVersion   The minor version number of the server
 * @param releaseVersiod The release version number of the server
 *
 * @return A BOOL indicating the result of the comparison.
 */
- (BOOL)isEqualToOrGreaterThanMajorVersion:(NSInteger)majorVersion minor:(NSInteger)minorVersion release:(NSInteger)releaseVersion;
{
	return ([self _compareServerMajorVersion:serverMajorVersion 
									   minor:serverMinorVersion 
									 release:serverReleaseVersion 
					  withServerMajorVersion:majorVersion 
									   minor:minorVersion 
									 release:releaseVersion] > NSOrderedAscending);
}

/**
 * Provides a general description of this object instance. Note that this should only be used for debugging purposes.
 *
 * @return The string describing the object instance
 */
- (NSString *)description
{
	unsigned int i;
	NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: Server is PostgreSQL version %ld.%ld.%ld. Supports:\n", [self className], (long)serverMajorVersion, (long)serverMinorVersion, (long)serverReleaseVersion];
	
	Ivar *vars = class_copyIvarList([self class], &i);
	
	for (NSUInteger j = 0; j < i; j++) 
	{	
		NSString *varName = [NSString stringWithUTF8String:ivar_getName(vars[j])];
		
		if ([varName hasPrefix:@"supports"]) {
			[description appendFormat:@"\t%@ = %@\n", varName, (object_getIvar(self, vars[j])) ? @"YES" : @"NO"];
		}
	}
	
	[description appendString:@">"];
	
	free(vars);
	
	return description;
}

#pragma mark -
#pragma mark Private API

/**
 * Invalidates all knowledge of what we know the server supports by simply reseting all ivars to their
 * original state, that is, it doesn't support anything.
 */
- (void)_invalidate
{
	supportsFractionalSeconds = NO;
	supportsFulltextOnInnoDB  = NO;
}

/**
 * Compares the supplied version numbers to determine their order.
 *
 * Note that this method assumes that release versions in the form XX are larger than X.
 * For example, version 14.0.18 is greater than version 14.0.8
 *
 * @param majorVersionA   The major version number of server A
 * @param minorVersionA   The minor version number of server A
 * @param releaseVersionA The release version number of server A
 * @param majorVersionB   The major version number of server B
 * @param minorVersionB   The minor version number of server B
 * @param releaseVersionB The release version number of server B
 *
 * @return One of NSComparisonResult constants indicating the order of the comparison
 */
- (NSComparisonResult)_compareServerMajorVersion:(NSInteger)majorVersionA 
										   minor:(NSInteger)minorVersionA 
										 release:(NSInteger)releaseVersionA
						  withServerMajorVersion:(NSInteger)majorVersionB
										   minor:(NSInteger)minorVersionB
										 release:(NSInteger)releaseVersionB
{	
	if (majorVersionA > majorVersionB) return NSOrderedDescending;

	if (majorVersionA < majorVersionB) return NSOrderedAscending;
	
	// The major versions are the same so move to checking the minor versions
	if (minorVersionA > minorVersionB) return NSOrderedDescending;
	
	if (minorVersionA < minorVersionB) return NSOrderedAscending;
	
	// The minor versions are the same so move to checking the release versions
	if (releaseVersionA > releaseVersionB) return NSOrderedDescending;
	
	if (releaseVersionA < releaseVersionB) return NSOrderedAscending;
	
	// Both version numbers are the same
	return NSOrderedSame;
}

#pragma mark -
#pragma mark Other

- (void)dealloc
{
	// Reset version integers
	serverMajorVersion   = 0;
	serverMinorVersion   = 0;
	serverReleaseVersion = 0;
	
	// Invalidate all ivars
	[self _invalidate];
	
}

@end
