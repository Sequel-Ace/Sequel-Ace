//
//  SPPostgresStreamingResultStoreDelegate.h
//  SPPostgresFramework
//
//  Created by Mehmet Karabulut (mehmetik@gmail.com) on November 30, 2025.
//  Copyright (c) 2025 Mehmet Karabulut.
//  This software is released under the GPL License.
//  This is an open-source project forked from Sequel Ace.
//

@class SPPostgresStreamingResultStore;

@protocol SPPostgresStreamingResultStoreDelegate <NSObject>

@optional

- (void)resultStoreDidFinishLoadingData:(SPPostgresStreamingResultStore *)resultStore;

@end
