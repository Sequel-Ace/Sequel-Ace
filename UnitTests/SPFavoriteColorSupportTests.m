//
//  SPFavoriteColorSupportTests.m
//  Unit Tests
//
//  The favourite colour list is the vivid palette, one colour per stored index. A change to the old
//  preference-archived list (FavoriteColorList) must never swap the old 7-colour list back in.
//  Every test uses its own defaults domain, never the user's.
//

#import <XCTest/XCTest.h>

#import "SPFavoriteColorSupport.h"
#import "SPConstants.h"
#import "sequel-ace-Swift.h"

@interface SPFavoriteColorSupportTests : XCTestCase
@property (nonatomic, copy) NSString *suiteName;
@property (nonatomic, strong) NSUserDefaults *defaults;
@end

@implementation SPFavoriteColorSupportTests

- (void)setUp
{
	[super setUp];
	self.suiteName = [NSString stringWithFormat:@"SPFavoriteColorSupportTests.%@", [[NSUUID UUID] UUIDString]];
	self.defaults = [[NSUserDefaults alloc] initWithSuiteName:self.suiteName];
}

- (void)tearDown
{
	[self.defaults removePersistentDomainForName:self.suiteName];
	self.defaults = nil;
	[super tearDown];
}

/// The old archived list: seven calibrated pastel colours, as PreferenceDefaults.plist registers them.
- (NSArray<NSData *> *)oldArchivedList
{
	NSMutableArray<NSData *> *list = [NSMutableArray array];
	for (NSInteger i = 0; i < 7; i++) {
		NSColor *colour = [NSColor colorWithCalibratedRed:0.9 green:0.1 * i blue:0.5 alpha:1];
		[list addObject:[NSKeyedArchiver archivedDataWithRootObject:colour requiringSecureCoding:YES error:nil]];
	}
	return list;
}

- (void)testTheListIsTheVividPalette
{
	SPFavoriteColorSupport *support = [[SPFavoriteColorSupport alloc] initWithDefaults:self.defaults];
	XCTAssertEqual(support.userColorList.count, 10u);
	XCTAssertEqualObjects(support.userColorList, [SAFavoritePalette assetColours]);
}

- (void)testChangingTheArchivedListKeepsTheVividColours
{
	SPFavoriteColorSupport *support = [[SPFavoriteColorSupport alloc] initWithDefaults:self.defaults];
	NSArray<NSColor *> *vivid = [SAFavoritePalette assetColours];

	[self.defaults setObject:[self oldArchivedList] forKey:SPFavoriteColorList];

	XCTAssertEqual(support.userColorList.count, 10u, @"the old 7-colour list must not come back");
	XCTAssertEqualObjects(support.userColorList, vivid);
	// Teal, Blue and Pink (indices 7-9) keep their colour; nothing past the palette appears.
	for (NSInteger index = 7; index <= 9; index++) {
		XCTAssertEqualObjects([support colorForIndex:index], vivid[index], @"index %ld", (long)index);
	}
	XCTAssertNil([support colorForIndex:10]);

	[self.defaults removeObjectForKey:SPFavoriteColorList];
	XCTAssertEqualObjects(support.userColorList, vivid, @"removing the key changes nothing either");
}

@end
