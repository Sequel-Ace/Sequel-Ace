//
//  SPFileManagerAdditions.m
//  sequel-pro
//
//  Created by Hans-Jörg Bibiko on August 19, 2010.
//  Copyright (c) 2010 Hans-Jörg Bibiko. All rights reserved.
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

#import "SPFileManagerAdditions.h"
#import "SPFileHandle.h"
#import "sequel-ace-Swift.h"

enum
{
	DirectoryLocationErrorNoPathFound,
	DirectoryLocationErrorFileExistsAtLocation
};
	
static NSString *DirectoryLocationDomain = @"DirectoryLocationDomain";

@implementation NSFileManager (SPFileManagerAdditions)

/**
 * Return the application support folder of the current application for 'subDirectory'.
 * If this folder doesn't exist it will be created. If 'subDirectory' == nil it only returns
 * the application support folder of the current application.
 */
- (NSString*)applicationSupportDirectoryForSubDirectory:(NSString*)subDirectory error:(NSError **)errorOut
{
	return [self applicationSupportDirectoryForSubDirectory:subDirectory createIfNotExists:YES error:errorOut];
}

- (NSString *)applicationSupportDirectoryForSubDirectory:(NSString*)subDirectory createIfNotExists:(BOOL)create error:(NSError **)errorOut;
{
	//  Based on Matt Gallagher on 06 May 2010
	//
	//  Permission is given to use this source code file, free of charge, in any
	//  project, commercial or otherwise, entirely at your risk, with the condition
	//  that any redistribution (in part or whole) of source code must retain
	//  this copyright and permission notice. Attribution in compiled projects is
	//  appreciated but not required.
	//

	NSError *error;

	NSArray* paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);

	if (![paths count]) {
		if (errorOut) {
			NSDictionary *userInfo =
				[NSDictionary dictionaryWithObjectsAndKeys:
					NSLocalizedStringFromTable(
						@"No path found for directory in domain.",
						@"Errors",
					nil),
					NSLocalizedDescriptionKey,
					[NSNumber numberWithInteger:NSApplicationSupportDirectory],
					@"NSSearchPathDirectory",
					[NSNumber numberWithInteger:NSUserDomainMask],
					@"NSSearchPathDomainMask",
				nil];
			*errorOut = [NSError 
					errorWithDomain:DirectoryLocationDomain
					code:DirectoryLocationErrorNoPathFound
					userInfo:userInfo];
		}
		SPLog(@"NSApplicationSupportDirectory not found : %@",[*errorOut localizedDescription]);

		return nil;
	}

	// Use only the first path returned
	NSString *resolvedPath = [paths objectAtIndex:0];

	// Append the application name
	resolvedPath = [resolvedPath stringByAppendingPathComponent:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleExecutable"]];

	// Append the subdirectory if passed
	if (subDirectory)
		resolvedPath = [resolvedPath stringByAppendingPathComponent:subDirectory];

	// Check if the path exists already
	BOOL exists;
	BOOL isDirectory;
	exists = [self fileExistsAtPath:resolvedPath isDirectory:&isDirectory];
	if (!exists || !isDirectory) {
		if (exists) {
			if (errorOut) {
				NSDictionary *userInfo =
					[NSDictionary dictionaryWithObjectsAndKeys:
						NSLocalizedStringFromTable(
							@"File exists at requested directory location.",
							@"Errors",
						nil),
						NSLocalizedDescriptionKey,
						[NSNumber numberWithInteger:NSApplicationSupportDirectory],
						@"NSSearchPathDirectory",
						[NSNumber numberWithInteger:NSUserDomainMask],
						@"NSSearchPathDomainMask",
					nil];
				*errorOut = [NSError 
						errorWithDomain:DirectoryLocationDomain
						code:DirectoryLocationErrorFileExistsAtLocation
						userInfo:userInfo];
			}
			SPLog(@"DirectoryLocationErrorFileExistsAtLocation: %@",[*errorOut localizedDescription]);

			return nil;
		}

		if(create) {
			// Create the path if it doesn't exist
			error = nil;
			BOOL success = [self createDirectoryAtPath:resolvedPath withIntermediateDirectories:YES attributes:nil error:&error];
			if (!success)  {
				if (errorOut) {
					*errorOut = error;
				}
				SPLog(@"Problem creating directory - %@ : %@",resolvedPath, [error localizedDescription]);
				return nil;
			}
		} else {
			return nil;
		}
	}
	
	if (errorOut)
		*errorOut = nil;
	
	if (!resolvedPath) {
		NSBeep();
		SPLog(@"Unable to find or create application support directory: %@",[error localizedDescription]);
	}
	
	
	return resolvedPath;
}

/**
 * Attempt to detect the encoding at the file at
 * the supplied URL.  Only the first five kb are read if the file is larger.
 * As with all encoding detection, this will return only best-guess result except
 * for where encoding markers exist.
 * Uses a SPFileHandle internally so it can detect the encoding within gzipped and
 * bzipped files.
 * https://stackoverflow.com/questions/5268661/how-to-detect-text-file-encoding-in-objective-c
 * Returns NSUTF8StringEncoding if the encoding cannot be detected.
 */
- (NSStringEncoding)detectEncodingforFileAtPath:(NSString *)aPath
{
	NSStringEncoding detectedEncoding;
	SPFileHandle *detectorFileHandle = [SPFileHandle fileHandleForReadingAtPath:aPath];
	if (!detectorFileHandle) {
		return NSUTF8StringEncoding;
	}
	
	NSData *startData = [detectorFileHandle readDataOfLength:500];
	Byte *bytes = (Byte *)[startData bytes];
	
	if (bytes[0] == 0xff && bytes[1] == 0xfe && (startData.length < 4 || bytes[2] != 0 || bytes[3] != 0))
	{
		detectedEncoding = NSUTF16LittleEndianStringEncoding;
	}
	else if (bytes[0] == 0xfe && bytes[1] == 0xff) {
		detectedEncoding = NSUTF16BigEndianStringEncoding;
	}
	else if (bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf) {
		detectedEncoding = NSUTF8StringEncoding;
	}
	else if (bytes[0] == 0xFF && bytes[1] == 0xFE && bytes[2] == 0 && bytes[3] == 0) {
		detectedEncoding = NSUTF32LittleEndianStringEncoding;
	}
	else if (bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0xFE && bytes[3] == 0xFF) {
		detectedEncoding = NSUTF32BigEndianStringEncoding;
	}
	else if (startData.length < 3) {
		detectedEncoding = NSASCIIStringEncoding;
	}
	else {
		detectedEncoding = NSUTF8StringEncoding;
	}
	

	return detectedEncoding;
}

+ (NSString *)temporaryDirectory
{
	NSString *tempDir = NSTemporaryDirectory();
	
	if (!tempDir) {
		tempDir = @"/tmp";
	} else if ([tempDir characterAtIndex:([tempDir length] - 1)] == '/') {
		tempDir = [tempDir substringToIndex:([tempDir length] - 1)];
	}

	return tempDir;
}

@end
