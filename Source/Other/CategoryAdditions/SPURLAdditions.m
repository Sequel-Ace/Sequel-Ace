//
//  SPURLAdditions.m
//  Sequel Ace
//
//  Created by James on 12/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

#import "SPURLAdditions.h"
#import "SPFunctions.h"
#import <FirebaseCrashlytics/FirebaseCrashlytics.h>

@implementation NSURL (SPURLAdditions)

+ (void)load
{
	SP_swizzleInstanceMethod(self, @selector(initFileURLWithPath: isDirectory:), @selector(SA_initFileURLWithPath: isDirectory:));
}

- (NSURL *)SA_initFileURLWithPath:(NSString *)path isDirectory:(BOOL)isDir{

	if(path == nil){
		CLS_LOG(@"initFileURLWithPath: path is nil");
		@throw NSInternalInconsistencyException;
	}

	return [self SA_initFileURLWithPath:path isDirectory:isDir];
}

@end

