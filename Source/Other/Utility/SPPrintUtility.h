//
//  SPPrintUtility.h
//  Sequel Ace
//
//  Created by Jakub Kaspar on 29.11.2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

#import <Foundation/Foundation.h>

@class WebView;

NS_ASSUME_NONNULL_BEGIN

@interface SPPrintUtility : NSObject

+ (NSPrintOperation *)preparePrintOperationWithView:(NSView *)view printView:(WebView *)printView;

@end

NS_ASSUME_NONNULL_END
