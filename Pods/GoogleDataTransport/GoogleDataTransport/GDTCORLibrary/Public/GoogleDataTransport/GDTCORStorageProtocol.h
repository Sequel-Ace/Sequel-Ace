/*
 * Copyright 2020 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <Foundation/Foundation.h>

#import "GDTCORLifecycle.h"
#import "GDTCORStorageEventSelector.h"
#import "GDTCORTargets.h"

@class GDTCOREvent;
@class GDTCORClock;

NS_ASSUME_NONNULL_BEGIN

/** The data type to represent storage size. */
typedef uint64_t GDTCORStorageSizeBytes;

typedef void (^GDTCORStorageBatchBlock)(NSNumber *_Nullable newBatchID,
                                        NSSet<GDTCOREvent *> *_Nullable batchEvents);

/** Defines the interface a storage subsystem is expected to implement. */
@protocol GDTCORStorageProtocol <NSObject, GDTCORLifecycleProtocol>

@required

/** Stores an event and calls onComplete with a non-nil error if anything went wrong.
 *
 * @param event The event to store
 * @param completion The completion block to call after an attempt to store the event has been made.
 */
- (void)storeEvent:(GDTCOREvent *)event
        onComplete:(void (^_Nullable)(BOOL wasWritten, NSError *_Nullable error))completion;

/** Returns YES if some events have been stored for the given target, NO otherwise.
 *
 * @param onComplete The completion block to invoke when determining if there are events is done.
 */
- (void)hasEventsForTarget:(GDTCORTarget)target onComplete:(void (^)(BOOL hasEvents))onComplete;

/** Constructs an event batch with the given event selector. Events in this batch will not be
 * returned in any queries or other batches until the batch is removed.
 *
 * @param eventSelector The event selector used to find the events.
 * @param expiration The expiration time of the batch. If removeBatchWithID:deleteEvents:onComplete:
 * is not called within this time frame, the batch will be removed with its events deleted.
 * @param onComplete The completion handler to be called when the events have been fetched.
 */
- (void)batchWithEventSelector:(nonnull GDTCORStorageEventSelector *)eventSelector
               batchExpiration:(nonnull NSDate *)expiration
                    onComplete:(nonnull GDTCORStorageBatchBlock)onComplete;

/** Removes the event batch.
 *
 * @param batchID The batchID to remove.
 * @param deleteEvents If YES, the events in this batch are deleted.
 * @param onComplete The completion handler to call when the batch removal process has completed.
 */
- (void)removeBatchWithID:(NSNumber *)batchID
             deleteEvents:(BOOL)deleteEvents
               onComplete:(void (^_Nullable)(void))onComplete;

/** Finds the batchIDs for the given target and calls the callback block.
 *
 * @param target The target.
 * @param onComplete The block to invoke with the set of current batchIDs.
 */
- (void)batchIDsForTarget:(GDTCORTarget)target
               onComplete:(void (^)(NSSet<NSNumber *> *_Nullable batchIDs))onComplete;

/** Checks the storage for expired events and batches, deletes them if they're expired. */
- (void)checkForExpirations;

/** Persists the given data with the given key.
 *
 * @param data The data to store.
 * @param key The unique key to store it to.
 * @param onComplete An block to be run when storage of the data is complete.
 */
- (void)storeLibraryData:(NSData *)data
                  forKey:(NSString *)key
              onComplete:(nullable void (^)(NSError *_Nullable error))onComplete;

/** Retrieves the stored data for the given key and optionally sets a new value.
 *
 * @param key The key corresponding to the desired data.
 * @param onFetchComplete The callback to invoke with the data once it's retrieved.
 * @param setValueBlock This optional block can provide a new value to set.
 */
- (void)libraryDataForKey:(nonnull NSString *)key
          onFetchComplete:(nonnull void (^)(NSData *_Nullable data,
                                            NSError *_Nullable error))onFetchComplete
              setNewValue:(NSData *_Nullable (^_Nullable)(void))setValueBlock;

/** Removes data from storage and calls the callback when complete.
 *
 * @param key The key of the data to remove.
 * @param onComplete The callback that will be invoked when removing the data is complete.
 */
- (void)removeLibraryDataForKey:(NSString *)key
                     onComplete:(void (^)(NSError *_Nullable error))onComplete;

/** Calculates and returns the total disk size that this storage consumes.
 *
 * @param onComplete The callback that will be invoked once storage size calculation is complete.
 */
- (void)storageSizeWithCallback:(void (^)(GDTCORStorageSizeBytes storageSize))onComplete;

@end

/** Retrieves the storage instance for the given target.
 *
 * @param target The target.
 * * @return The storage instance registered for the target, or nil if there is none.
 */
FOUNDATION_EXPORT
id<GDTCORStorageProtocol> _Nullable GDTCORStorageInstanceForTarget(GDTCORTarget target);

NS_ASSUME_NONNULL_END
