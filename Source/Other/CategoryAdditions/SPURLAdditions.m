//
//  SPURLAdditions.m
//  Sequel Ace
//
//  Created by James on 12/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

#import "SPURLAdditions.h"
#import "SPFunctions.h"

@implementation NSURL (SPURLAdditions)

+ (void)load
{
	SP_swizzleInstanceMethod(self, @selector(initFileURLWithPath: isDirectory:), @selector(SA_initFileURLWithPath: isDirectory:));
}

- (NSURL *)SA_initFileURLWithPath:(NSString *)path isDirectory:(BOOL)isDir{

	if(path == nil){
        SPLog(@"initFileURLWithPath: path is nil");
		@throw NSInternalInconsistencyException;
	}

	return [self SA_initFileURLWithPath:path isDirectory:isDir];
}

@end

