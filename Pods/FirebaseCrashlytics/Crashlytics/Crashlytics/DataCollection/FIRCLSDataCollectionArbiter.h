// Copyright 2019 Google
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import <Foundation/Foundation.h>

@class FIRApp;
@class FBLPromise<T>;

NS_ASSUME_NONNULL_BEGIN

@interface FIRCLSDataCollectionArbiter : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithApp:(FIRApp *)app withAppInfo:(NSDictionary *)dict;

- (BOOL)isLegacyDataCollectionKeyInPlist;

- (BOOL)isCrashlyticsCollectionEnabled;

- (void)setCrashlyticsCollectionEnabled:(BOOL)enabled;

// Returns a promise that is fulfilled once data collection is enabled.
- (FBLPromise<NSNumber *> *)waitForCrashlyticsCollectionEnabled;

@end

NS_ASSUME_NONNULL_END
