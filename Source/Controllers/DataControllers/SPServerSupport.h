//
//  SPServerSupport.h
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

/**
 * @class SPServerSupport SPServerSupport.h
 *
 * @author Stuart Connolly http://stuconnolly.com/
 *
 * This class is provided as a convenient method of determining what features/functionality the MySQL server
 * with the supplied version numbers supports. Note that this class has no direct connection to the server,
 * all of it's information is simply determined by way of version comparisons using hard coded values of known
 * versions and the functionality they support.
 *
 * Every new MySQL connection that is established should create an instance of this class and make it globally
 * accessible to the rest of the application to remove the need of manual version comparisons. Calling it's 
 * designated initializer (initWithMajorVersion:major:minor:release:) causes the determination of what 
 * functionality is supported, and so other initializtion is required.
 *
 * See the method evaluate for information regarding adding additional functionality checks.
 */
@interface SPServerSupport : NSObject 
{
	// Convenience vars
	BOOL isMySQL5;
    BOOL isMySQL8;
	
	// Indexes
	BOOL supportsFulltextOnInnoDB;
	
	// Data types
	BOOL supportsFractionalSeconds;
	
	// Server versions
	NSInteger serverMajorVersion;
	NSInteger serverMinorVersion;
	NSInteger serverReleaseVersion;
}

/**
 * @property serverMajorVersion
 */
@property (readwrite, assign) NSInteger serverMajorVersion;

/**
 * @property serverMinorVersion
 */
@property (readwrite, assign) NSInteger serverMinorVersion;

/**
 * @property serverReleaseVersion
 */
@property (readwrite, assign) NSInteger serverReleaseVersion;

/**
 * @property isMySQL5 Indicates if the server is MySQL version 5
 */
@property (readonly) BOOL isMySQL5;

/**
 * @property isMySQL8 Indicates if the server is MySQL version 8
 */
@property (readonly) BOOL isMySQL8;

/**
 * @property supportsFractionalSeconds Indicates whether the server supports fractional seconds in date/time data types.
 */
@property (readonly) BOOL supportsFractionalSeconds;

/**
 * @property supportsFulltextOnInnoDB Indicates whether the server supports FULLTEXT indexes with the InnoDb engine.
 */
@property (readonly) BOOL supportsFulltextOnInnoDB;

- (instancetype)initWithMajorVersion:(NSInteger)majorVersion minor:(NSInteger)minorVersion release:(NSInteger)releaseVersion;

- (void)evaluate;
- (BOOL)isEqualToOrGreaterThanMajorVersion:(NSInteger)majorVersion minor:(NSInteger)minorVersion release:(NSInteger)releaseVersion;

@end
