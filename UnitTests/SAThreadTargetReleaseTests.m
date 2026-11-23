//
//  SAThreadTargetReleaseTests.m
//  Sequel Ace
//
//  +[NSThread detachNewThreadWithName:target:selector:object:] hands its target's final release to the main
//  queue: a document controller whose tab closed while its task thread ran must not be deallocated on that thread.
//

#import <XCTest/XCTest.h>
#import "SPThreadAdditions.h"

@interface SAThreadTargetProbe : NSObject
@property (nonatomic, copy) void (^onDealloc)(BOOL onMainThread);
- (void)work:(id)argument;
@end

@implementation SAThreadTargetProbe

- (void)work:(id)argument
{
	[NSThread sleepForTimeInterval:0.05];
}

- (void)dealloc
{
	if (_onDealloc) _onDealloc([NSThread isMainThread]);
}

@end

@interface SAThreadTargetReleaseTests : XCTestCase
@end

@implementation SAThreadTargetReleaseTests

- (void)testTargetHeldOnlyByItsThreadIsDeallocatedOnTheMainThread
{
	XCTestExpectation *deallocated = [self expectationWithDescription:@"target deallocated"];
	__block BOOL deallocatedOnMainThread = NO;
	@autoreleasepool {
		SAThreadTargetProbe *probe = [[SAThreadTargetProbe alloc] init];
		probe.onDealloc = ^(BOOL onMainThread) {
			deallocatedOnMainThread = onMainThread;
			[deallocated fulfill];
		};
		[NSThread detachNewThreadWithName:@"SAThreadTargetReleaseTests probe" target:probe selector:@selector(work:) object:nil];
	}
	[self waitForExpectations:@[deallocated] timeout:5];
	XCTAssertTrue(deallocatedOnMainThread);
}

- (void)testTargetStillRunsItsSelectorWithTheArgument
{
	XCTestExpectation *ran = [self expectationWithDescription:@"selector ran"];
	NSMutableArray *received = [NSMutableArray array];
	[NSThread detachNewThreadWithName:@"SAThreadTargetReleaseTests argument" target:received selector:@selector(addObject:) object:@"payload"];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ran fulfill]; });
	[self waitForExpectations:@[ran] timeout:5];
	XCTAssertEqualObjects(received, @[@"payload"]);
}

@end
