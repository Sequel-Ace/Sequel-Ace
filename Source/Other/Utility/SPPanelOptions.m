//
//  SPPanelOptions.m
//  Sequel Ace
//
//  Created by James on 4/1/2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SPPanelOptions.h"
#import "SPFunctions.h"

@implementation PanelOptions

@synthesize fileNames;

- (instancetype)init
{
    if ((self = [super init])) {
        fileNames = [[NSMutableArray alloc] init];
    }

    return self;
}

#pragma mark - Debug Description

-(NSDictionary *)dictionary {

    return @{
        @"title" : self.title,
        @"prefsKey" : safeString(self.prefsKey),
        @"chooser" : SPBoxNil(self.chooser.description),
        @"canChooseFiles" : @(self.canChooseFiles),
        @"canChooseDirectories" : @(self.canChooseDirectories),
        @"bookmarkCreationOptions" : @(self.bookmarkCreationOptions),
        @"allowsMultipleSelection" : @(self.allowsMultipleSelection),
        @"isForStaleBookmark" : @(self.isForStaleBookmark),
        @"fileNames" : self.fileNames.count > 0 ? self.fileNames : @[]
    };
}

- (NSString *)jsonStringWithPrettyPrint:(BOOL)prettyPrint {
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[self dictionary]
                                                       options:(NSJSONWritingOptions) (prettyPrint ? NSJSONWritingPrettyPrinted : 0)
                                                         error:&error];

    if (!jsonData) {
        SPLog(@"jsonStringWithPrettyPrint: error: %@", error.localizedDescription);
        return @"[]";
    }
    else {
        return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
}

@end
