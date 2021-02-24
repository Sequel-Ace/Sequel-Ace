//
//  SPPanelOptions.h
//  Sequel Ace
//
//  Created by James on 4/1/2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PanelOptions : NSObject{

}

@property (readwrite, copy) NSString *title;
@property (readwrite, copy) NSString *prefsKey;
@property (readwrite, strong) NSPopUpButton *chooser;
@property (readwrite, assign) BOOL canChooseFiles;
@property (readwrite, assign) BOOL canChooseDirectories;
@property (readwrite, assign) BOOL allowsMultipleSelection;
@property (readwrite, assign) BOOL isForStaleBookmark;
@property (readwrite, assign) NSUInteger index;
@property (readwrite, copy, nullable) NSMutableArray<NSString *> *fileNames;

- (NSString *)jsonStringWithPrettyPrint:(BOOL)prettyPrint;

@end

NS_ASSUME_NONNULL_END
