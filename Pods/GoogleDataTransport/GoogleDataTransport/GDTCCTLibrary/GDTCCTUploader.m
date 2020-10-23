/*
 * Copyright 2019 Google
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

#import "GoogleDataTransport/GDTCCTLibrary/Private/GDTCCTUploader.h"

#import "GoogleDataTransport/GDTCORLibrary/Public/GoogleDataTransport/GDTCORConsoleLogger.h"
#import "GoogleDataTransport/GDTCORLibrary/Public/GoogleDataTransport/GDTCOREvent.h"
#import "GoogleDataTransport/GDTCORLibrary/Public/GoogleDataTransport/GDTCORPlatform.h"
#import "GoogleDataTransport/GDTCORLibrary/Public/GoogleDataTransport/GDTCORRegistrar.h"
#import "GoogleDataTransport/GDTCORLibrary/Public/GoogleDataTransport/GDTCORStorageProtocol.h"

#import <nanopb/pb.h>
#import <nanopb/pb_decode.h>
#import <nanopb/pb_encode.h>

#import "GoogleDataTransport/GDTCCTLibrary/Private/GDTCCTCompressionHelper.h"
#import "GoogleDataTransport/GDTCCTLibrary/Private/GDTCCTNanopbHelpers.h"

#import "GoogleDataTransport/GDTCCTLibrary/Protogen/nanopb/cct.nanopb.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef GDTCOR_VERSION
#define STR(x) STR_EXPAND(x)
#define STR_EXPAND(x) #x
static NSString *const kGDTCCTSupportSDKVersion = @STR(GDTCOR_VERSION);
#else
static NSString *const kGDTCCTSupportSDKVersion = @"UNKNOWN";
#endif  // GDTCOR_VERSION

/** */
static NSInteger kWeekday;

/** */
static NSString *const kLibraryDataCCTNextUploadTimeKey = @"GDTCCTUploaderFLLNextUploadTimeKey";

/** */
static NSString *const kLibraryDataFLLNextUploadTimeKey = @"GDTCCTUploaderFLLNextUploadTimeKey";

static NSString *const kINTServerURL =
    @"https://dummyapiverylong-dummy.dummy.com/dummy/api/very/long";

#if !NDEBUG
NSNotificationName const GDTCCTUploadCompleteNotification = @"com.GDTCCTUploader.UploadComplete";
#endif  // #if !NDEBUG

typedef void (^GDTCCTUploaderURLTaskCompletion)(NSNumber *batchID,
                                                NSSet<GDTCOREvent *> *_Nullable events,
                                                NSData *_Nullable data,
                                                NSURLResponse *_Nullable response,
                                                NSError *_Nullable error);

typedef void (^GDTCCTUploaderEventBatchBlock)(NSNumber *_Nullable batchID,
                                              NSSet<GDTCOREvent *> *_Nullable events);

@interface GDTCCTUploader () <NSURLSessionDelegate>

/// Redeclared as readwrite.
@property(nullable, nonatomic, readwrite) NSURLSessionUploadTask *currentTask;

/// A flag indicating if there is an ongoing upload. The current implementation supports only a
/// single upload operation. If `uploadTarget` method is called when  `isCurrentlyUploading == YES`
/// then no new uploads will be started.
@property(atomic) BOOL isCurrentlyUploading;

@end

@implementation GDTCCTUploader

+ (void)load {
  GDTCCTUploader *uploader = [GDTCCTUploader sharedInstance];
  [[GDTCORRegistrar sharedInstance] registerUploader:uploader target:kGDTCORTargetCCT];
  [[GDTCORRegistrar sharedInstance] registerUploader:uploader target:kGDTCORTargetFLL];
  [[GDTCORRegistrar sharedInstance] registerUploader:uploader target:kGDTCORTargetCSH];
  [[GDTCORRegistrar sharedInstance] registerUploader:uploader target:kGDTCORTargetINT];
}

+ (instancetype)sharedInstance {
  static GDTCCTUploader *sharedInstance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[GDTCCTUploader alloc] init];
  });
  return sharedInstance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _uploaderQueue = dispatch_queue_create("com.google.GDTCCTUploader", DISPATCH_QUEUE_SERIAL);
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    _uploaderSession = [NSURLSession sessionWithConfiguration:config
                                                     delegate:self
                                                delegateQueue:nil];
  }
  return self;
}

/**
 *
 */
- (nullable NSURL *)serverURLForTarget:(GDTCORTarget)target {
  // These strings should be interleaved to construct the real URL. This is just to (hopefully)
  // fool github URL scanning bots.
  static NSURL *CCTServerURL;
  static dispatch_once_t CCTOnceToken;
  dispatch_once(&CCTOnceToken, ^{
    const char *p1 = "hts/frbslgiggolai.o/0clgbth";
    const char *p2 = "tp:/ieaeogn.ogepscmvc/o/ac";
    const char URL[54] = {p1[0],  p2[0],  p1[1],  p2[1],  p1[2],  p2[2],  p1[3],  p2[3],  p1[4],
                          p2[4],  p1[5],  p2[5],  p1[6],  p2[6],  p1[7],  p2[7],  p1[8],  p2[8],
                          p1[9],  p2[9],  p1[10], p2[10], p1[11], p2[11], p1[12], p2[12], p1[13],
                          p2[13], p1[14], p2[14], p1[15], p2[15], p1[16], p2[16], p1[17], p2[17],
                          p1[18], p2[18], p1[19], p2[19], p1[20], p2[20], p1[21], p2[21], p1[22],
                          p2[22], p1[23], p2[23], p1[24], p2[24], p1[25], p2[25], p1[26], '\0'};
    CCTServerURL = [NSURL URLWithString:[NSString stringWithUTF8String:URL]];
  });

  static NSURL *FLLServerURL;
  static dispatch_once_t FLLOnceToken;
  dispatch_once(&FLLOnceToken, ^{
    const char *p1 = "hts/frbslgigp.ogepscmv/ieo/eaybtho";
    const char *p2 = "tp:/ieaeogn-agolai.o/1frlglgc/aclg";
    const char URL[69] = {p1[0],  p2[0],  p1[1],  p2[1],  p1[2],  p2[2],  p1[3],  p2[3],  p1[4],
                          p2[4],  p1[5],  p2[5],  p1[6],  p2[6],  p1[7],  p2[7],  p1[8],  p2[8],
                          p1[9],  p2[9],  p1[10], p2[10], p1[11], p2[11], p1[12], p2[12], p1[13],
                          p2[13], p1[14], p2[14], p1[15], p2[15], p1[16], p2[16], p1[17], p2[17],
                          p1[18], p2[18], p1[19], p2[19], p1[20], p2[20], p1[21], p2[21], p1[22],
                          p2[22], p1[23], p2[23], p1[24], p2[24], p1[25], p2[25], p1[26], p2[26],
                          p1[27], p2[27], p1[28], p2[28], p1[29], p2[29], p1[30], p2[30], p1[31],
                          p2[31], p1[32], p2[32], p1[33], p2[33], '\0'};
    FLLServerURL = [NSURL URLWithString:[NSString stringWithUTF8String:URL]];
  });

  static NSURL *CSHServerURL;
  static dispatch_once_t CSHOnceToken;
  dispatch_once(&CSHOnceToken, ^{
    // These strings should be interleaved to construct the real URL. This is just to (hopefully)
    // fool github URL scanning bots.
    const char *p1 = "hts/cahyiseot-agolai.o/1frlglgc/aclg";
    const char *p2 = "tp:/rsltcrprsp.ogepscmv/ieo/eaybtho";
    const char URL[72] = {p1[0],  p2[0],  p1[1],  p2[1],  p1[2],  p2[2],  p1[3],  p2[3],  p1[4],
                          p2[4],  p1[5],  p2[5],  p1[6],  p2[6],  p1[7],  p2[7],  p1[8],  p2[8],
                          p1[9],  p2[9],  p1[10], p2[10], p1[11], p2[11], p1[12], p2[12], p1[13],
                          p2[13], p1[14], p2[14], p1[15], p2[15], p1[16], p2[16], p1[17], p2[17],
                          p1[18], p2[18], p1[19], p2[19], p1[20], p2[20], p1[21], p2[21], p1[22],
                          p2[22], p1[23], p2[23], p1[24], p2[24], p1[25], p2[25], p1[26], p2[26],
                          p1[27], p2[27], p1[28], p2[28], p1[29], p2[29], p1[30], p2[30], p1[31],
                          p2[31], p1[32], p2[32], p1[33], p2[33], p1[34], p2[34], p1[35], '\0'};
    CSHServerURL = [NSURL URLWithString:[NSString stringWithUTF8String:URL]];
  });

#if !NDEBUG
  if (_testServerURL) {
    return _testServerURL;
  }
#endif  // !NDEBUG

  switch (target) {
    case kGDTCORTargetCCT:
      return CCTServerURL;

    case kGDTCORTargetFLL:
      return FLLServerURL;

    case kGDTCORTargetCSH:
      return CSHServerURL;

    case kGDTCORTargetINT:
      return [NSURL URLWithString:kINTServerURL];

    default:
      GDTCORLogDebug(@"GDTCCTUploader doesn't support target %ld", (long)target);
      return nil;
      break;
  }
}

- (NSString *)FLLAndCSHandINTAPIKey {
  static NSString *defaultServerKey;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    // These strings should be interleaved to construct the real key.
    const char *p1 = "AzSBG0honD6A-PxV5nBc";
    const char *p2 = "Iay44Iwtu2vV0AOrz1C";
    const char defaultKey[40] = {p1[0],  p2[0],  p1[1],  p2[1],  p1[2],  p2[2],  p1[3],  p2[3],
                                 p1[4],  p2[4],  p1[5],  p2[5],  p1[6],  p2[6],  p1[7],  p2[7],
                                 p1[8],  p2[8],  p1[9],  p2[9],  p1[10], p2[10], p1[11], p2[11],
                                 p1[12], p2[12], p1[13], p2[13], p1[14], p2[14], p1[15], p2[15],
                                 p1[16], p2[16], p1[17], p2[17], p1[18], p2[18], p1[19], '\0'};
    defaultServerKey = [NSString stringWithUTF8String:defaultKey];
  });
  return defaultServerKey;
}

#

- (void)uploadTarget:(GDTCORTarget)target withConditions:(GDTCORUploadConditions)conditions {
  __block GDTCORBackgroundIdentifier backgroundTaskID = GDTCORBackgroundIdentifierInvalid;

  dispatch_block_t backgroundTaskCompletion = ^{
    // End the background task if there was one.
    if (backgroundTaskID != GDTCORBackgroundIdentifierInvalid) {
      [[GDTCORApplication sharedApplication] endBackgroundTask:backgroundTaskID];
      backgroundTaskID = GDTCORBackgroundIdentifierInvalid;
    }
  };

  backgroundTaskID = [[GDTCORApplication sharedApplication]
      beginBackgroundTaskWithName:@"GDTCCTUploader-upload"
                expirationHandler:^{
                  if (backgroundTaskID != GDTCORBackgroundIdentifierInvalid) {
                    // Cancel the upload and complete delivery.
                    [self.currentTask cancel];

                    // End the background task.
                    backgroundTaskCompletion();
                  }
                }];

  dispatch_async(_uploaderQueue, ^{
    id<GDTCORStorageProtocol> storage = GDTCORStorageInstanceForTarget(target);

    // 1. Fetch events to upload.
    [self batchToUploadForTarget:target
                         storage:storage
                      conditions:conditions
                      completion:^(NSNumber *_Nullable batchID,
                                   NSSet<GDTCOREvent *> *_Nullable events) {
                        // 2. Check if there are events to upload.
                        if (!events || events.count == 0) {
                          dispatch_async(self.uploaderQueue, ^{
                            GDTCORLogDebug(@"Target %ld reported as ready for upload, but no "
                                           @"events were selected",
                                           (long)target);
                            self.isCurrentlyUploading = NO;
                            backgroundTaskCompletion();
                          });

                          return;
                        }
                        // 3. Upload events.
                        [self uploadBatchWithID:batchID
                                         events:events
                                         target:target
                                        storage:storage
                                     completion:^{
                                       backgroundTaskCompletion();
                                     }];
                      }];
  });
}

#pragma mark - Upload implementation details

/** Performs URL request, handles the result and updates the uploader state. */
- (void)uploadBatchWithID:(nullable NSNumber *)batchID
                   events:(nullable NSSet<GDTCOREvent *> *)events
                   target:(GDTCORTarget)target
                  storage:(id<GDTCORStorageProtocol>)storage
               completion:(dispatch_block_t)completion {
  [self
      sendURLRequestForBatchWithID:batchID
                            events:events
                            target:target
                 completionHandler:^(NSNumber *_Nonnull batchID,
                                     NSSet<GDTCOREvent *> *_Nullable events, NSData *_Nullable data,
                                     NSURLResponse *_Nullable response, NSError *_Nullable error) {
                   dispatch_async(self.uploaderQueue, ^{
                     [self handleURLResponse:response
                                        data:data
                                       error:error
                                      target:target
                                     storage:storage
                                     batchID:batchID];
#if !NDEBUG
                     // Post a notification when in DEBUG mode to state how many packages
                     // were uploaded. Useful for validation during tests.
                     [[NSNotificationCenter defaultCenter]
                         postNotificationName:GDTCCTUploadCompleteNotification
                                       object:@(events.count)];
#endif  // #if !NDEBUG
                     self.isCurrentlyUploading = NO;
                     completion();
                   });
                 }];
}

/** Validates events and sends URL request and calls completion with the result. Modifies uploading
 * state in the case of the failure.*/
- (void)sendURLRequestForBatchWithID:(nullable NSNumber *)batchID
                              events:(nullable NSSet<GDTCOREvent *> *)events
                              target:(GDTCORTarget)target
                   completionHandler:(GDTCCTUploaderURLTaskCompletion)completionHandler {
  dispatch_async(self.uploaderQueue, ^{
    NSData *requestProtoData = [self constructRequestProtoWithEvents:events];
    NSData *gzippedData = [GDTCCTCompressionHelper gzippedData:requestProtoData];
    BOOL usingGzipData = gzippedData != nil && gzippedData.length < requestProtoData.length;
    NSData *dataToSend = usingGzipData ? gzippedData : requestProtoData;
    NSURLRequest *request = [self constructRequestForTarget:target data:dataToSend];
    GDTCORLogDebug(@"CTT: request containing %lu events created: %@", (unsigned long)events.count,
                   request);
    NSSet<GDTCOREvent *> *eventsForDebug;
#if !NDEBUG
    eventsForDebug = events;
#endif
    self.currentTask = [self.uploaderSession
        uploadTaskWithRequest:request
                     fromData:dataToSend
            completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response,
                                NSError *_Nullable error) {
              completionHandler(batchID, eventsForDebug, data, response, error);
            }];
    GDTCORLogDebug(@"%@", @"CCT: The upload task is about to begin.");
    [self.currentTask resume];
  });
}

/** Handles URL request response. */
- (void)handleURLResponse:(nullable NSURLResponse *)response
                     data:(nullable NSData *)data
                    error:(nullable NSError *)error
                   target:(GDTCORTarget)target
                  storage:(id<GDTCORStorageProtocol>)storage
                  batchID:(NSNumber *)batchID {
  GDTCORLogDebug(@"%@", @"CCT: request completed");
  if (error) {
    GDTCORLogWarning(GDTCORMCWUploadFailed, @"There was an error uploading events: %@", error);
  }
  NSError *decodingError;
  GDTCORClock *futureUploadTime;
  if (data) {
    gdt_cct_LogResponse logResponse = GDTCCTDecodeLogResponse(data, &decodingError);
    if (!decodingError && logResponse.has_next_request_wait_millis) {
      GDTCORLogDebug(@"CCT: The backend responded asking to not upload for %lld millis from now.",
                     logResponse.next_request_wait_millis);
      futureUploadTime =
          [GDTCORClock clockSnapshotInTheFuture:logResponse.next_request_wait_millis];
    } else if (decodingError) {
      GDTCORLogDebug(@"There was a response decoding error: %@", decodingError);
    }
    pb_release(gdt_cct_LogResponse_fields, &logResponse);
  }
  if (!futureUploadTime) {
    GDTCORLogDebug(@"%@", @"CCT: The backend response failed to parse, so the next request "
                          @"won't occur until 15 minutes from now");
    // 15 minutes from now.
    futureUploadTime = [GDTCORClock clockSnapshotInTheFuture:15 * 60 * 1000];
  }
  switch (target) {
    case kGDTCORTargetCCT:
      self->_CCTNextUploadTime = futureUploadTime;
      break;

    case kGDTCORTargetFLL:
      // Falls through.
    case kGDTCORTargetINT:
      // Falls through.
    case kGDTCORTargetCSH:
      self->_FLLNextUploadTime = futureUploadTime;
      break;
    default:
      break;
  }

  // Only retry if one of these codes is returned, or there was an error.
  if (error || ((NSHTTPURLResponse *)response).statusCode == 429 ||
      ((NSHTTPURLResponse *)response).statusCode == 503) {
    // Move the events back to the main storage to be uploaded on the next attempt.
    [storage removeBatchWithID:batchID deleteEvents:NO onComplete:nil];
  } else {
    GDTCORLogDebug(@"%@", @"CCT: package delivered");
    [storage removeBatchWithID:batchID deleteEvents:YES onComplete:nil];
  }

  self.currentTask = nil;
}

#pragma mark - Stored events upload

/** Fetches a batch of pending events for the specified target and conditions. Passes `nil` to
 * completion if there are no suitable events to upload. */
- (void)batchToUploadForTarget:(GDTCORTarget)target
                       storage:(id<GDTCORStorageProtocol>)storage
                    conditions:(GDTCORUploadConditions)conditions
                    completion:(GDTCCTUploaderEventBatchBlock)completion {
  // 1. Check if the conditions for the target are suitable.
  if (![self readyToUploadTarget:target conditions:conditions]) {
    completion(nil, nil);
    return;
  }

  // 2. Remove previously attempted batches
  [self removeBatchesForTarget:target
                       storage:storage
                    onComplete:^{
                      // There may be a big amount of events stored, so creating a batch may be an
                      // expensive operation.

                      // 3. Do a lightweight check if there are any events for the target first to
                      // finish early if there are no.
                      [storage hasEventsForTarget:target
                                       onComplete:^(BOOL hasEvents) {
                                         // 4. Proceed with fetching the events.
                                         [self batchToUploadForTarget:target
                                                              storage:storage
                                                           conditions:conditions
                                                            hasEvents:hasEvents
                                                           completion:completion];
                                       }];
                    }];
}

/** Makes final checks before and makes */
- (void)batchToUploadForTarget:(GDTCORTarget)target
                       storage:(id<GDTCORStorageProtocol>)storage
                    conditions:(GDTCORUploadConditions)conditions
                     hasEvents:(BOOL)hasEvents
                    completion:(GDTCCTUploaderEventBatchBlock)completion {
  dispatch_async(self.uploaderQueue, ^{
    if (!hasEvents) {
      // No events to upload.
      completion(nil, nil);
      return;
    }

    // Check if the conditions are still met before starting upload.
    if (![self readyToUploadTarget:target conditions:conditions]) {
      completion(nil, nil);
      return;
    }

    // All conditions have been checked and met. Lock uploader for this target to prevent other
    // targets upload attempts.
    self.isCurrentlyUploading = YES;

    // Fetch a batch to upload and pass along.
    GDTCORStorageEventSelector *eventSelector = [self eventSelectorTarget:target
                                                           withConditions:conditions];
    [storage batchWithEventSelector:eventSelector
                    batchExpiration:[NSDate dateWithTimeIntervalSinceNow:600]
                         onComplete:completion];
  });
}

- (void)removeBatchesForTarget:(GDTCORTarget)target
                       storage:(id<GDTCORStorageProtocol>)storage
                    onComplete:(dispatch_block_t)onComplete {
  [storage batchIDsForTarget:target
                  onComplete:^(NSSet<NSNumber *> *_Nullable batchIDs) {
                    // No stored batches, no need to remove anything.
                    if (batchIDs.count < 1) {
                      onComplete();
                      return;
                    }

                    dispatch_group_t dispatchGroup = dispatch_group_create();
                    for (NSNumber *batchID in batchIDs) {
                      dispatch_group_enter(dispatchGroup);

                      // Remove batches and moves events back to the storage.
                      [storage removeBatchWithID:batchID
                                    deleteEvents:NO
                                      onComplete:^{
                                        dispatch_group_leave(dispatchGroup);
                                      }];
                    }

                    // Wait until all batches are removed and call completion handler.
                    dispatch_group_notify(dispatchGroup, self.uploaderQueue, ^{
                      onComplete();
                    });
                  }];
}

#pragma mark - Private helper methods

/** */
- (BOOL)readyToUploadTarget:(GDTCORTarget)target conditions:(GDTCORUploadConditions)conditions {
  if (self.isCurrentlyUploading) {
    GDTCORLogDebug(@"%@", @"CCT: Wait until previous upload finishes. The current version supports "
                          @"only a single batch uploading at the time.");
    return NO;
  }

  // Not ready to upload with no network connection.
  // TODO: Reconsider using reachability to prevent an upload attempt.
  // See https://developer.apple.com/videos/play/wwdc2019/712/ (49:40) for more details.
  if (conditions & GDTCORUploadConditionNoNetwork) {
    GDTCORLogDebug(@"%@", @"CCT: Not ready to upload without a network connection.");
    return NO;
  }

  // Upload events when there are with no additional conditions for kGDTCORTargetCSH.
  if (target == kGDTCORTargetCSH) {
    GDTCORLogDebug(@"%@", @"CCT: kGDTCORTargetCSH events are allowed to be "
                          @"uploaded straight away.");
    return YES;
  }

  if (target == kGDTCORTargetINT) {
    GDTCORLogDebug(@"%@", @"CCT: kGDTCORTargetINT events are allowed to be "
                          @"uploaded straight away.");
    return YES;
  }

  // Upload events with no additional conditions if high priority.
  if ((conditions & GDTCORUploadConditionHighPriority) == GDTCORUploadConditionHighPriority) {
    GDTCORLogDebug(@"%@", @"CCT: a high priority event is allowing an upload");
    return YES;
  }

  // Check next upload time for the target.
  BOOL isAfterNextUploadTime = YES;
  switch (target) {
    case kGDTCORTargetCCT:
      if (self->_CCTNextUploadTime) {
        isAfterNextUploadTime = [[GDTCORClock snapshot] isAfter:self->_CCTNextUploadTime];
      }
      break;

    case kGDTCORTargetFLL:
      if (self->_FLLNextUploadTime) {
        isAfterNextUploadTime = [[GDTCORClock snapshot] isAfter:self->_FLLNextUploadTime];
      }
      break;

    default:
      // The CSH backend should be handled above.
      break;
  }

  if (isAfterNextUploadTime) {
    GDTCORLogDebug(@"CCT: can upload to target %ld because the request wait time has transpired",
                   (long)target);
  } else {
    GDTCORLogDebug(@"CCT: can't upload to target %ld because the backend asked to wait",
                   (long)target);
  }

  return isAfterNextUploadTime;
}

/** Constructs data given an upload package.
 *
 * @param events The events used to construct the request proto bytes.
 * @return Proto bytes representing a gdt_cct_LogRequest object.
 */
- (nonnull NSData *)constructRequestProtoWithEvents:(NSSet<GDTCOREvent *> *)events {
  // Segment the log events by log type.
  NSMutableDictionary<NSString *, NSMutableSet<GDTCOREvent *> *> *logMappingIDToLogSet =
      [[NSMutableDictionary alloc] init];
  [events enumerateObjectsUsingBlock:^(GDTCOREvent *_Nonnull event, BOOL *_Nonnull stop) {
    NSMutableSet *logSet = logMappingIDToLogSet[event.mappingID];
    logSet = logSet ? logSet : [[NSMutableSet alloc] init];
    [logSet addObject:event];
    logMappingIDToLogSet[event.mappingID] = logSet;
  }];

  gdt_cct_BatchedLogRequest batchedLogRequest =
      GDTCCTConstructBatchedLogRequest(logMappingIDToLogSet);

  NSData *data = GDTCCTEncodeBatchedLogRequest(&batchedLogRequest);
  pb_release(gdt_cct_BatchedLogRequest_fields, &batchedLogRequest);
  return data ? data : [[NSData alloc] init];
}

/** Constructs a request to FLL given a URL and request body data.
 *
 * @param target The target backend to send the request to.
 * @param data The request body data.
 * @return A new NSURLRequest ready to be sent to FLL.
 */
- (nullable NSURLRequest *)constructRequestForTarget:(GDTCORTarget)target data:(NSData *)data {
  if (data == nil || data.length == 0) {
    GDTCORLogDebug(@"There was no data to construct a request for target %ld.", (long)target);
    return nil;
  }
  NSURL *URL = [self serverURLForTarget:target];
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
  NSString *targetString;
  switch (target) {
    case kGDTCORTargetCCT:
      targetString = @"cct";
      break;

    case kGDTCORTargetFLL:
      targetString = @"fll";
      break;

    case kGDTCORTargetCSH:
      targetString = @"csh";
      break;
    case kGDTCORTargetINT:
      targetString = @"int";
      break;

    default:
      targetString = @"unknown";
      break;
  }
  NSString *userAgent =
      [NSString stringWithFormat:@"datatransport/%@ %@support/%@ apple/", kGDTCORVersion,
                                 targetString, kGDTCCTSupportSDKVersion];
  if (target == kGDTCORTargetFLL || target == kGDTCORTargetCSH) {
    [request setValue:[self FLLAndCSHandINTAPIKey] forHTTPHeaderField:@"X-Goog-Api-Key"];
  }

  if (target == kGDTCORTargetINT) {
    [request setValue:[self FLLAndCSHandINTAPIKey] forHTTPHeaderField:@"X-Goog-Api-Key"];
  }

  if ([GDTCCTCompressionHelper isGzipped:data]) {
    [request setValue:@"gzip" forHTTPHeaderField:@"Content-Encoding"];
  }
  [request setValue:@"application/x-protobuf" forHTTPHeaderField:@"Content-Type"];
  [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
  [request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
  request.HTTPMethod = @"POST";
  [request setHTTPBody:data];
  return request;
}

/** */
- (nullable GDTCORStorageEventSelector *)eventSelectorTarget:(GDTCORTarget)target
                                              withConditions:(GDTCORUploadConditions)conditions {
  id<GDTCORStorageProtocol> storage = GDTCORStorageInstanceForTarget(target);
  if ((conditions & GDTCORUploadConditionHighPriority) == GDTCORUploadConditionHighPriority) {
    return [GDTCORStorageEventSelector eventSelectorForTarget:target];
  }
  NSMutableSet<NSNumber *> *qosTiers = [[NSMutableSet alloc] init];
  if (conditions & GDTCORUploadConditionWifiData) {
    [qosTiers addObjectsFromArray:@[
      @(GDTCOREventQoSFast), @(GDTCOREventQoSWifiOnly), @(GDTCOREventQosDefault),
      @(GDTCOREventQoSTelemetry), @(GDTCOREventQoSUnknown)
    ]];
  }
  if (conditions & GDTCORUploadConditionMobileData) {
    [qosTiers addObjectsFromArray:@[ @(GDTCOREventQoSFast), @(GDTCOREventQosDefault) ]];
  }

  __block NSInteger lastDayOfDailyUpload;
  NSString *lastDailyUploadDataKey = [NSString
      stringWithFormat:@"%@LastDailyUpload-%ld", NSStringFromClass([self class]), (long)target];
  [storage libraryDataForKey:lastDailyUploadDataKey
      onFetchComplete:^(NSData *_Nullable data, NSError *_Nullable error) {
        [data getBytes:&lastDayOfDailyUpload length:sizeof(NSInteger)];
      }
      setNewValue:^NSData *_Nullable {
        if (lastDayOfDailyUpload != kWeekday) {
          return [NSData dataWithBytes:&lastDayOfDailyUpload length:sizeof(NSInteger)];
        }
        return nil;
      }];

  return [[GDTCORStorageEventSelector alloc] initWithTarget:target
                                                   eventIDs:nil
                                                 mappingIDs:nil
                                                   qosTiers:qosTiers];
}

#pragma mark - GDTCORLifecycleProtocol

- (void)appWillForeground:(GDTCORApplication *)app {
  dispatch_async(_uploaderQueue, ^{
    NSDateComponents *dateComponents = [[NSDateComponents alloc] init];
    NSCalendar *gregorianCalendar =
        [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDate *date = [gregorianCalendar dateFromComponents:dateComponents];
    kWeekday = [gregorianCalendar component:NSCalendarUnitWeekday fromDate:date];
  });
}

- (void)appWillTerminate:(GDTCORApplication *)application {
  dispatch_sync(_uploaderQueue, ^{
    [self.currentTask cancel];
  });
}

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session
                          task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response
                    newRequest:(NSURLRequest *)request
             completionHandler:(void (^)(NSURLRequest *_Nullable))completionHandler {
  if (!completionHandler) {
    return;
  }
  if (response.statusCode == 302 || response.statusCode == 301) {
    if ([request.URL isEqual:[self serverURLForTarget:kGDTCORTargetFLL]]) {
      NSURLRequest *newRequest = [self constructRequestForTarget:kGDTCORTargetCCT
                                                            data:task.originalRequest.HTTPBody];
      completionHandler(newRequest);
    }
  } else {
    completionHandler(request);
  }
}

@end

NS_ASSUME_NONNULL_END
