//
//  SPTaskAdditions.h
//  Sequel Ace
//
//  Created by James on 28/2/2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSTask (SPTaskAdditions)

- (void)SPlaunch;
- (void)SPterminate;

@end

NS_ASSUME_NONNULL_END

