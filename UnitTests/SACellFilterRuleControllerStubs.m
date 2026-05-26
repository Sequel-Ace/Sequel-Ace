//
//  SACellFilterRuleControllerStubs.m
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "SPQueryController.h"
#import "SPContentFilterManager.h"
#import "SPTableContent.h"

@implementation SPQueryController

+ (SPQueryController *)sharedQueryController
{
	return nil;
}

- (NSMutableDictionary *)contentFilterForFileURL:(NSURL *)fileURL
{
	return nil;
}

@end

@implementation SPContentFilterManager

- (instancetype)initWithDatabaseDocument:(SPDatabaseDocument *)document forFilterType:(NSString *)compareType
{
	return [super init];
}

@end

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wprotocol"

@implementation SPTableContent

- (void)toggleRuleEditorVisible:(id)sender
{
}

@end

#pragma clang diagnostic pop
