//
//  MGTemplateStandardMarkers.h
//
//  Created by Matt Gemmell on 13/05/2008.
//  Copyright 2008 Instinctive Code. All rights reserved.

#import "MGTemplateEngine.h"
#import "MGTemplateMarker.h"

@interface MGTemplateStandardMarkers : NSObject <MGTemplateMarker>

- (BOOL)currentBlock:(NSDictionary *)blockInfo matchesTopOfStack:(NSMutableArray *)stack;
- (BOOL)argIsNumeric:(NSString *)arg integerValue:(NSInteger *)val checkVariables:(BOOL)checkVars;
- (BOOL)argIsTrue:(NSString *)arg;

@end
