//
//  SPStringAdditionsTests.m
//  sequel-pro
//
//  Created by Jim Knight on May 17, 2009.
//  Copyright (c) 2009 Jim Knight. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  More info at <https://github.com/sequelpro/sequelpro>

#import "SPObjectAdditions.h"
#import "SPStringAdditions.h"
#import "RegexKitLite.h"
#import "SPArrayAdditions.h"
#import "sequel-ace-Swift.h"
#import "SPTestingUtils.h"
#import "SPFunctions.h"

#include <unistd.h>
#include <sys/types.h>
#include <pwd.h>
#include <assert.h>

#import <XCTest/XCTest.h>

@interface SPStringAdditionsTests : XCTestCase

- (void)testStringByRemovingCharactersInSet;
- (void)testStringWithNewUUID;
- (void)testCreateViewSyntaxPrettifier;
- (void)testNonConsecutivelySearchStringMatchingRanges;
- (void)testStringByReplacingCharactersInSetWithString;

@end

static NSRange RangeFromArray(NSArray *a,NSUInteger idx);

@implementation SPStringAdditionsTests

// non static - 0.5s
- (void)testPerformance_stringForByteSize {
	// this is on main thread
	[self measureBlock:^{
		// Put the code you want to measure the time of here.
		int const iterations = 10000;
		for (int i = 0; i < iterations; i++) {
			@autoreleasepool {
				[NSString stringForByteSize:i];
			}
		}
	}];
}
// obj c static - 0.241s
- (void)testPerformance_stringForByteSizeObjCStatic {
	// this is on main thread
	[self measureBlock:^{
		// Put the code you want to measure the time of here.
		int const iterations = 10000;
		for (int i = 0; i < iterations; i++) {
			@autoreleasepool {
				[NSString stringForByteSize:i];
			}
		}
	}];
}

//// swift static - 0.24s
//- (void)testPerformance_stringForByteSizeStatic {
//	// this is on main thread
//	[self measureBlock:^{
//		// Put the code you want to measure the time of here.
//		int const iterations = 10000;
//		for (int i = 0; i < iterations; i++) {
//			@autoreleasepool {
//				[NSString stringForByteSize2:i];
//			}
//		}
//	}];
//}
//
//// swift static NumberLiterals - 0.239s
//- (void)testPerformance_stringForByteSizeSwiftStaticNumberLiterals {
//	// this is on main thread
//	[self measureBlock:^{
//		// Put the code you want to measure the time of here.
//		int const iterations = 10000;
//		for (int i = 0; i < iterations; i++) {
//			@autoreleasepool {
//				[NSString stringForByteSize2:i];
//			}
//		}
//	}];
//}

//- (void)testPerformance_stringForByteSize{
//	// this is on main thread
//	[self measureBlock:^{
//		// Put the code you want to measure the time of here.
//		int const iterations = 10000;
//		for (int i = 0; i < iterations; i++) {
//			@autoreleasepool {
//				[NSString stringForByteSize2:i];
//			}
//		}
//	}];
//}

// 0.0383s
- (void)testPerformance_stringByMatchingRegexSearch {
    // this is on main thread
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
        int const iterations = 1;

        NSArray *randomSSHKeyArray = [SPTestingUtils randomSSHKeyArray];

        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {

                for(NSString *str in randomSSHKeyArray){
                    NSString __unused *keyName = [str stringByMatching:@"^\\s*Enter passphrase for key \\'(.*)\\':\\s*$" capture:1L];
                }
            }
        }
    }];
}


// 0.175s - 4 times slower than regexkit
- (void)testPerformance_captureGroupForRegex {
    // this is on main thread
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
        int const iterations = 1;

        NSArray *randomSSHKeyArray = [SPTestingUtils randomSSHKeyArray];

        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {

                for(NSString *str in randomSSHKeyArray){
                    NSString __unused *keyName = [str captureGroupForRegex:@"^\\s*Enter passphrase for key \\'(.*)\\':\\s*$"];
                }
            }
        }
    }];
}


- (void)testPerformance_RegexSearch {
	// this is on main thread
	[self measureBlock:^{
		// Put the code you want to measure the time of here.
		int const iterations = 1;
		
		NSArray *queryHist = [SPTestingUtils randomHistArray];
		
		for (int i = 0; i < iterations; i++) {
			@autoreleasepool {
				NSString *ran = [[NSProcessInfo processInfo] globallyUniqueString];
				
				for(NSString *str in queryHist){
					BOOL __unused match = [str isMatchedByRegex:[NSString stringWithFormat:@"(?i).*%@.*", ran]];
				}
			}
		}
	}];
}


- (void)testPerformance_StringWithString {
	// this is on main thread
	[self measureBlock:^{
		// Put the code you want to measure the time of here.
		int const iterations = 1000000;
		
		id obj = @"JIMMY";

		for (int i = 0; i < iterations; i++) {
			@autoreleasepool {
				obj = [NSString stringWithString:obj];
			}
		}
	}];
}

// this cast method is twice as fast as stringWithString above
- (void)testPerformance_cast {
	
	[self measureBlock:^{
		// Put the code you want to measure the time of here.
		int const iterations = 1000000;
		
		id obj = @"JIMMY";

		for (int i = 0; i < iterations; i++) {
			@autoreleasepool {
				obj = [NSString cast:obj];
			}
		}
	}];
}

// this "unsafe" cast method is twice as fast as cast above
- (void)testPerformance_cast2 {
	
	[self measureBlock:^{
		// Put the code you want to measure the time of here.
		int const iterations = 1000000;
		
		id obj = @"JIMMY";

		for (int i = 0; i < iterations; i++) {
			@autoreleasepool {
				obj = (NSString*)obj;
			}
		}
	}];
}

- (void)testnumberLiterals{

    [self measureBlock:^{
        int const iterations = 1000000;

        for (int i = -100; i < iterations; i++) {
            @autoreleasepool {
                XCTAssertEqualObjects(@(i), [NSNumber numberWithDouble:i]);
            }
        }
    }];
}

// 0.198s
- (void)testSafeSubstringWithRangePerf{
    [self measureBlock:^{
        int const iterations = 1000000;

        NSString *str = @"These pretzels are making me thirsty...";

        NSRange range = NSMakeRange(0, 14);
        for (int i = -100; i < iterations; i++) {
            @autoreleasepool {
                NSString __unused *res2 = [str safeSubstringWithRange:range];
            }
        }
    }];
}

//0.19s
- (void)testSubstringWithRangePerf{
    [self measureBlock:^{
        int const iterations = 1000000;

        NSString *str = @"These pretzels are making me thirsty...";

        NSRange range = NSMakeRange(0, 14);
        for (int i = -100; i < iterations; i++) {
            @autoreleasepool {
                NSString __unused *res2 = [str substringWithRange:range];
            }
        }
    }];
}

- (void)testSHA256{

    NSString *str = @"A gold violin. Perfect in every way. But can't make music.";

    NSString *hashedString = @"39F01E659AEF48299039F8975BC7BEB2";

    NSString *newHashedStr = [str.sha256Hash substringToIndex:32];

    NSLog(@"newHashedStr    : %@", newHashedStr);
    NSLog(@"hashedString    : %@", hashedString);

    XCTAssertEqualObjects(@"39F01E659AEF48299039F8975BC7BEB2", newHashedStr);

}

- (void)testSHA256Naughty{

    NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"naughty_strings" ofType:@"txt"];

    NSLog(@"path: %@", path);

    NSError *inError = nil;
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&inError];

    [content enumerateLinesUsingBlock:^(NSString * _Nonnull line, BOOL * _Nonnull stop) {
        NSString *sha256 = line.sha256Hash;
        XCTAssertEqual(sha256.length, 64);
    }];

}

//0.133 s
- (void)testPerformanceDateStringFromUnixTimestamp{
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
        double epoch = 1641629299;

        int const iterations = 100000;

        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                // exec on bg thread
                epoch = epoch + i;
                NSString *epochStr = [NSString stringWithFormat:@"%f", epoch];
                NSString __unused *tmp = epochStr.dateStringFromUnixTimestamp;
            }
        }
    }];
}

//0.273 s
- (void)testPerformanceDateStringFromUnixTimestamp2{
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
        NSString *epochStr = @"1641629299";
        int const iterations = 100000;

        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                // exec on bg thread
                NSString __unused *tmp = epochStr.dateStringFromUnixTimestamp;
            }
        }

    }];
}

- (void)testIsUnixTimeStamp{

    NSString *justOver100YAgo = @"-1574579624";
    XCTAssertNil(justOver100YAgo.dateStringFromUnixTimestamp);

    NSString *justUnder100YAgo = @"-1479885224";
    XCTAssertNotNil(justUnder100YAgo.dateStringFromUnixTimestamp);

    NSString *justOver100YinTheFut = @"4800012376";
    XCTAssertNil(justOver100YinTheFut.dateStringFromUnixTimestamp);

    NSString *justUnder100YinTheFut = @"4736853976";
    XCTAssertNotNil(justUnder100YinTheFut.dateStringFromUnixTimestamp);

    NSString *aboutNow = @"1612803456";
    XCTAssertNotNil(aboutNow.dateStringFromUnixTimestamp);

}

// 0.429 s
- (void)testPerformanceIsUnixTimeStamp{

    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.

        double epoch = 1542957224;
        int const iterations = 100000;
        double twoYears = epoch + 31536000 + 31536000;

        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                // exec on bg thread
                epoch = epoch + i;
                if(epoch > twoYears) epoch = 1578470899;
                NSString *epochStr = [NSString stringWithFormat:@"%f", epoch];
                NSString __unused *tmp = epochStr.dateStringFromUnixTimestamp;
            }
        }
    }];
}

//0.138 s
- (void)testPerformanceIsUnixTimeStamp2{

    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.

        double epoch = 1542957224;
        int const iterations = 100000;

        int count = 0;

        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                // exec on bg thread
                epoch = epoch + i;
                uint32_t randomNum = arc4random() % 2;

                NSString *epochStr = [NSString stringWithFormat:@"%f", epoch];

                if(randomNum > 0){
                    NSString __unused *tmp2 = epochStr.dateStringFromUnixTimestamp;
                    count++;
                }

            }
        }
    }];
}


// 0.95 s
- (void)testSHA256Perf{
    [self measureBlock:^{
        int const iterations = 100000;

        NSString *str = @"The student's eyes don't perceive the lies...";

        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                NSString __unused *newHashedStr = [str.sha256Hash substringToIndex:32];
            }
        }
    }];
}


- (void)testSafeSubstringWithRange{

    NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"naughty_strings" ofType:@"txt"];

    NSError *inError = nil;
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&inError];

    [content enumerateLinesUsingBlock:^(NSString * _Nonnull str, BOOL * _Nonnull stop) {

        NSRange range = NSMakeRange(0, str.length+1);

        //    //Raises an NSRangeException if (aRange.location - 1) or (aRange.location + aRange.length - 1) lies beyond the end of the receiver
        XCTAssertThrows([str substringWithRange:range]);
        XCTAssertNoThrow([str safeSubstringWithRange:range]);

        range = NSMakeRange(str.length+1, 1);

        XCTAssertThrows([str substringWithRange:range]);
        XCTAssertNoThrow([str safeSubstringWithRange:range]);

        range = NSMakeRange(str.length/2, (str.length/2)+2);

        XCTAssertThrows([str substringWithRange:range]);
        XCTAssertNoThrow([str safeSubstringWithRange:range]);

        range = NSMakeRange(str.length-1, 2);

        XCTAssertThrows([str substringWithRange:range]);
        XCTAssertNoThrow([str safeSubstringWithRange:range]);



        range = NSMakeRange(str.length-1, 1);

        NSString *res = [str substringWithRange:range];
        NSString *res2 = [str safeSubstringWithRange:range];

        NSLog(@"res: %@", res);

        if(res.length > 1) XCTAssertEqualObjects(res, res2);

    }];

}

- (void)testMutAttrStringSafeDeleteCharactersInRange{


    NSDictionary *baseAttrs = @{NSFontAttributeName: [NSFont systemFontOfSize:11], NSParagraphStyleAttributeName: [NSParagraphStyle defaultParagraphStyle]};

    NSMutableAttributedString *str = [[NSMutableAttributedString alloc] initWithString:@"The Dude is abiding..." attributes:baseAttrs];
    NSMutableAttributedString *expectedStr = [[NSMutableAttributedString alloc] initWithString:@"The Dude is abiding.." attributes:baseAttrs];


    NSUInteger startLoc = [str length]-1;

    NSRange tmpRange = NSMakeRange(startLoc, 1);

    NSLog(@"tmpRange: %@", NSStringFromRange(tmpRange));
    NSLog(@"str.len: %lu", (unsigned long)str.length);

    [str safeDeleteCharactersInRange:tmpRange];

    NSLog(@"str: %@", str);
    NSLog(@"str.len: %lu", (unsigned long)str.length);

    XCTAssertTrue(str.length == startLoc);

    XCTAssertEqualObjects(str, expectedStr);

    tmpRange = NSMakeRange(str.length+2, 1);

    XCTAssertThrows([str deleteCharactersInRange:tmpRange]);
    XCTAssertNoThrow([str safeDeleteCharactersInRange:tmpRange]);

}

// 1.39 s
- (void)testMutAttrStringSafeDeleteCharactersInRangePerf{
    [self measureBlock:^{
        int const iterations = 1000000;

        NSDictionary *baseAttrs = @{NSFontAttributeName: [NSFont systemFontOfSize:11], NSParagraphStyleAttributeName: [NSParagraphStyle defaultParagraphStyle]};

        for (int i = 0; i < iterations; i++) {

            NSMutableAttributedString *str = [[NSMutableAttributedString alloc] initWithString:@"The tomato never really took off as a hand fruit..." attributes:baseAttrs];

            NSUInteger startLoc = [str length]-1;

            NSRange tmpRange = NSMakeRange(startLoc, 1);
            @autoreleasepool {
                [str safeDeleteCharactersInRange:tmpRange];
            }
        }
    }];
}

//1.34 s
- (void)testMutAttrStringDeleteCharactersInRangePerf{
    [self measureBlock:^{
        int const iterations = 1000000;

        NSDictionary *baseAttrs = @{NSFontAttributeName: [NSFont systemFontOfSize:11], NSParagraphStyleAttributeName: [NSParagraphStyle defaultParagraphStyle]};

        for (int i = 0; i < iterations; i++) {

            NSMutableAttributedString *str = [[NSMutableAttributedString alloc] initWithString:@"The tomato never really took off as a hand fruit..." attributes:baseAttrs];

            NSUInteger startLoc = [str length]-1;

            NSRange tmpRange = NSMakeRange(startLoc, 1);
            @autoreleasepool {
                [str deleteCharactersInRange:tmpRange];
            }
        }
    }];
}


- (void)testSafeDeleteCharactersInRange{

    NSMutableString *str = [[NSMutableString alloc] initWithString:@"How far will you go for 15 seconds of fame?"];
    NSMutableString *expectedStr = [[NSMutableString alloc] initWithString:@"How far will you go for 15 seconds of fame"];

    NSUInteger startLoc = [str length]-1;

    NSRange tmpRange = NSMakeRange(startLoc, 1);

    NSLog(@"tmpRange: %@", NSStringFromRange(tmpRange));
    NSLog(@"str.len: %lu", (unsigned long)str.length);

    [str safeDeleteCharactersInRange:tmpRange];

    NSLog(@"str: %@", str);
    NSLog(@"str.len: %lu", (unsigned long)str.length);

    XCTAssertTrue(str.length == startLoc);

    XCTAssertEqualObjects(str, expectedStr);


    tmpRange = NSMakeRange(str.length+2, 1);

    XCTAssertThrows([str deleteCharactersInRange:tmpRange]);
    XCTAssertNoThrow([str safeDeleteCharactersInRange:tmpRange]);


}

//0.328 s
- (void)testSafeDeleteCharactersInRangePerf{
    [self measureBlock:^{
        int const iterations = 1000000;
        
        for (int i = 0; i < iterations; i++) {
            NSMutableString *str = [[NSMutableString alloc] initWithString:@"A man's gotta have a code..."];
            
            NSUInteger startLoc = [str length]-1;
            
            NSRange tmpRange = NSMakeRange(startLoc, 1);
            @autoreleasepool {
                [str safeDeleteCharactersInRange:tmpRange];
            }
        }
    }];
}

//0.33 s
- (void)testDeleteCharactersInRangePerf{
    [self measureBlock:^{
        int const iterations = 1000000;

        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                NSMutableString *str = [[NSMutableString alloc] initWithString:@"A man's gotta have a code..."];

                NSUInteger startLoc = [str length]-1;

                NSRange tmpRange = NSMakeRange(startLoc, 1);
                [str deleteCharactersInRange:tmpRange];
            }
        }
    }];
}

- (void)testSeparatedIntoLines{

    NSString *str = @"SELECT * FROM `HKWarningsLog` LIMIT 1000\nSELECT * FROM `HKWarningsLog` LIMIT 1000\nSELECT * FROM `HKWarningsLog` LIMIT 1000\n";
    NSArray *expectedArray = @[@"SELECT * FROM `HKWarningsLog` LIMIT 1000", @"SELECT * FROM `HKWarningsLog` LIMIT 1000", @"SELECT * FROM `HKWarningsLog` LIMIT 1000"];

    NSArray *arr = [str separatedIntoLinesObjC];

    XCTAssertEqualObjects(expectedArray, arr);

    NSLog(@"arr: %@", arr);

}

- (void)testSeparatedIntoLinesByCharsetObjC{

    NSString *str = @"SELECT * FROM `HKWarningsLog`\n LIMIT 1000;\nSELECT * FROM `HKWarningsLog`\n LIMIT 1000;\nSELECT * FROM `HKWarningsLog` LIMIT 1000\n;";
    NSArray *expectedArray = @[@"SELECT * FROM `HKWarningsLog`\n LIMIT 1000",@"\nSELECT * FROM `HKWarningsLog`\n LIMIT 1000", @"\nSELECT * FROM `HKWarningsLog` LIMIT 1000\n"];

    NSArray *arr = [str separatedIntoLinesByCharsetObjC];

    XCTAssertEqualObjects(expectedArray, arr);

}


- (void)testContains{

    NSString *str = @"When I say ATMOS, you say FEAR.";

    XCTAssertTrue([str contains:@"ATMOS"]);
    XCTAssertTrue([str contains:@"."]);
    XCTAssertFalse([str contains:@"JIMMY"]);
    XCTAssertFalse([str contains:@"ATMOS say"]);
    XCTAssertFalse([str contains:@"Say"]);

}

// 0.145 s
- (void)testContainsPerf{
    [self measureBlock:^{
        int const iterations = 1000000;

        NSString *str = @"When I say ATMOS, you say FEAR.";

        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                BOOL __unused res = [str contains:@"ATMOS"];
            }
        }
    }];
}

// 0.13 s
- (void)testContainsStringPerf{
    [self measureBlock:^{
        int const iterations = 1000000;

        NSString *str = @"When I say ATMOS, you say FEAR.";

        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                BOOL __unused res = [str containsString:@"ATMOS"];
            }
        }
    }];
}

/**
 * stringByRemovingCharactersInSet test case.
 */
- (void)testStringByRemovingCharactersInSet
{
	NSString *SPASCIITestString = @"this is a big, crazy test st'ring  with som'e random  spaces and quot'es";
	NSString *SPUTFTestString   = @"In der Kürze liegt die Würz";
	
	NSString *charsToRemove = @"abc',ü";
	
	NSCharacterSet *junk = [NSCharacterSet characterSetWithCharactersInString:charsToRemove];
	
	NSString *actualUTFString = SPUTFTestString;
	NSString *actualASCIIString = SPASCIITestString;
	
	NSString *expectedUTFString = @"In der Krze liegt die Wrz";
	NSString *expectedASCIIString = @"this is  ig rzy test string  with some rndom  spes nd quotes";
	
	XCTAssertEqualObjects([actualASCIIString stringByRemovingCharactersInSet:junk], 
						 expectedASCIIString, 
						 @"The following characters should have been removed %@", 
						 charsToRemove);
	
	XCTAssertEqualObjects([actualUTFString stringByRemovingCharactersInSet:junk], 
						 expectedUTFString, 
						 @"The following characters should have been removed %@", 
						 charsToRemove);
}

/**
 * stringWithNewUUID test case.
 */
- (void)testStringWithNewUUID
{	
	NSString *uuid = [NSString stringWithNewUUID];
		
	XCTAssertTrue([uuid isMatchedByRegex:@"[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}"], @"UUID %@ doesn't match regex", uuid);
}

//- (void)testDropPrefix {
//	NSString *string = @"prefixString";
//	string = [string dropPrefixWithPrefix:@"prefix"];
//	XCTAssertTrue([string isEqualToString:@"String"]);
//}
//
//- (void)testHasPrefix {
//	NSString *string = @"prefixString";
//	XCTAssertTrue([string hasPrefixWithPrefix:@"prefix" caseSensitive:NO]);
//}
//
//- (void)testDropSuffix {
//	NSString *string = @"stringSuffix";
//	string = [string dropSuffixWithSuffix:@"Suffix"];
//	XCTAssertTrue([string isEqualToString:@"string"]);
//}
//
//- (void)testHasSuffix {
//	NSString *string = @"stringSuffix";
//	XCTAssertTrue([string hasSuffixWithSuffix:@"Suffix" caseSensitive: NO]);
//}
//
//- (void)testHasSuffixCaseSensitive {
//	NSString *string = @"stringSuffix";
//	XCTAssertFalse([string hasSuffixWithSuffix:@"suffix" caseSensitive: YES]);
//	XCTAssertTrue([string hasSuffixWithSuffix:@"Suffix" caseSensitive: YES]);
//}
//
//- (void)testHasPrefixCaseSensitive {
//	NSString *string = @"prefixString";
//	XCTAssertFalse([string hasPrefixWithPrefix:@"Prefix" caseSensitive:YES]);
//	XCTAssertTrue([string hasPrefixWithPrefix:@"prefix" caseSensitive:YES]);
//}
//
//- (void)testTrim {
//	NSString *string = @"  \n\nstring\n\n  ";
//	string = [string trimWhitespacesAndNewlines];
//	XCTAssertTrue([string isEqualToString:@"string"]);
//
//	string = @" \n \n string \n \n  ";
//	string = [string trimWhitespacesAndNewlines];
//	XCTAssertTrue([string isEqualToString:@"string"]);
//
//	string = @"..  ..string... ";
//	string = [string trimWhitespacesAndNewlines];
//	XCTAssertTrue([string isEqualToString:@"..  ..string..."]);
//
//	string = @"str ing";
//	string = [string trimWhitespacesAndNewlines];
//	XCTAssertTrue([string isEqualToString:@"str ing"]);
//
//	string = @"\nstr\ning\n";
//	string = [string trimWhitespacesAndNewlines];
//	XCTAssertTrue([string isEqualToString:@"str\ning"]);
//}
/**
 * createViewSyntaxPrettifier test case.
 */
- (void)testCreateViewSyntaxPrettifier
{
	NSString *originalSyntax = @"CREATE VIEW `test_view` AS select `test_table`.`id` AS `id` from `test_table`;";
	NSString *expectedSyntax = @"CREATE VIEW `test_view`\nAS SELECT\n   `test_table`.`id` AS `id`\nFROM `test_table`;";
	
	NSString *actualSyntax = [originalSyntax createViewSyntaxPrettifier];
	
	XCTAssertEqualObjects([actualSyntax description], [expectedSyntax description], @"Actual view syntax '%@' does not equal expected syntax '%@'", actualSyntax, expectedSyntax);
}

- (void)testNonConsecutivelySearchStringMatchingRanges
{
	//basic tests
	{
		NSArray *matches = nil;
		XCTAssertTrue([@"" nonConsecutivelySearchString:@"" matchingRanges:&matches], @"Equality of empty strings");
		XCTAssertTrue(([matches count] == 1) && NSEqualRanges(NSMakeRange(0, 0), RangeFromArray(matches, 0)), @"Returned matches in empty string");
	}
	
	{
		NSArray *matches = (__bridge NSArray *)((void *)0xdeadbeef);
		XCTAssertFalse([@"" nonConsecutivelySearchString:@"R" matchingRanges:&matches], @"Inequality with empty left side");
		XCTAssertTrue((matches == (void *)0xdeadbeef), @"out variable not touched by mismatch");
	}
	
	XCTAssertFalse([@"L" nonConsecutivelySearchString:@"" matchingRanges:NULL], @"Inequality with empty right side");
	
	{
		NSArray *matches = nil;
		XCTAssertTrue([@"left" nonConsecutivelySearchString:@"le" matchingRanges:&matches], @"Anchored match left");
		XCTAssertTrue(([matches count] == 1) && NSEqualRanges(NSMakeRange(0, 2), RangeFromArray(matches, 0)), @"Returned matches in anchored left match");
	}
	
	{
		NSArray *matches = nil;
		XCTAssertTrue([@"right" nonConsecutivelySearchString:@"ht" matchingRanges:&matches], @"Anchored match right");
		XCTAssertTrue(([matches count] == 1) && NSEqualRanges(NSMakeRange(3, 2), RangeFromArray(matches, 0)), @"Returned matches in anchroed right match");
	}
	
	XCTAssertFalse([@"ht" nonConsecutivelySearchString:@"right" matchingRanges:NULL], @"Left and Right are not commutative");
	
	//real tests
	{
		NSArray *matches = nil;
		XCTAssertTrue([@"... is not secure anymore!" nonConsecutivelySearchString:@"NSA"  matchingRanges:&matches], @"Non-consecutive match, ignoring case");
		XCTAssertTrue(([matches count] == 3) &&
					 NSEqualRanges(NSMakeRange( 7, 1), RangeFromArray(matches, 0)) &&
					 NSEqualRanges(NSMakeRange(11, 1), RangeFromArray(matches, 1)) &&
					 NSEqualRanges(NSMakeRange(18, 1), RangeFromArray(matches, 2)), @"Returned matches in non-consecutive string");
	}
	
	XCTAssertFalse([@"Deoxyribonucleic Acid" nonConsecutivelySearchString:@"DNS"  matchingRanges:NULL], @"Non-consecutive mismatch");
	
	{
		NSArray *matches = nil;
		XCTAssertTrue([@"Turn left, then right at the corner" nonConsecutivelySearchString:@"left right" matchingRanges:&matches], @"Partly consecutive match");
		XCTAssertTrue(([matches count] == 2) &&
					 (NSEqualRanges(NSMakeRange( 5, 4), RangeFromArray(matches, 0))) &&
					 (NSEqualRanges(NSMakeRange(15, 6), RangeFromArray(matches, 1))), @"Returned matches in partly-consecutive string");
	}
	
	//optimization tests
	{
		NSArray *matches = nil;
		//  Haystack:    "central_private_rabbit_park"
		//  Needle:      "centralpark"
		//  Unoptimized: "central_private_rabbit_park"
		//                ^^^^^^^ ^   ^   ^         ^ = 5 (after optimizing consecutive atomic matches)
		//  Desired:     "central_private_rabbit_park"
		//                ^^^^^^^                ^^^^ = 2
		XCTAssertTrue([@"central_private_rabbit_park" nonConsecutivelySearchString:@"centralpark" matchingRanges:&matches], @"Optimization partly consecutive match");
		XCTAssertTrue((([matches count] == 2) &&
					  (NSEqualRanges(NSMakeRange( 0, 7), RangeFromArray(matches, 0))) &&
					  (NSEqualRanges(NSMakeRange(23, 4), RangeFromArray(matches, 1)))), @"Returned matches set is minimal");
	}
	{
		// In the previous test it was always the end of the matches array that got optimized.
		// This time we'll have two different optimizations
		//   Needle:      ".abc123"
		//   Haystack:    "a.?a?ab?abc?1?12?123?"
		//   Unoptimized:   ^ ^  ^   ^ ^  ^   ^ = 7
		//   Desired:       ^      ^^^      ^^^ = 3
		NSArray *matches = nil;
		XCTAssertTrue([@"a.?a?ab?abc?1?12?123?" nonConsecutivelySearchString:@".abc123" matchingRanges:&matches], @"Optimization non-consecutive match");
		XCTAssertTrue((([matches count] == 3) &&
					  (NSEqualRanges(NSMakeRange( 1, 1), RangeFromArray(matches, 0))) &&
					  (NSEqualRanges(NSMakeRange( 8, 3), RangeFromArray(matches, 1))) &&
					  (NSEqualRanges(NSMakeRange(17, 3), RangeFromArray(matches, 2)))), @"Returned matches set is minimal (2)");
	}
	
	//advanced tests
	
	// LATIN CAPITAL LETTER A              == LATIN SMALL LETTER A
	// LATIN SMALL LETTER O WITH DIAERESIS == LATIN SMALL LETTER O
	// FULLWIDTH LATIN SMALL LETTER b      == LATIN SMALL LETTER B
	XCTAssertTrue([@"A:\xC3\xB6:\xEF\xBD\x82" nonConsecutivelySearchString:@"aob" matchingRanges:NULL], @"Fuzzy matching of defined characters");
	
	//all bytes on the right are contained on the left, but on a character level "ä" is not contained in "Hütte Ф"
	XCTAssertFalse([@"H\xC3\xBCtte \xD0\xA4" nonConsecutivelySearchString:@"\xC3\xA4" matchingRanges:NULL], @"Mismatch of composed characters with same prefix");
	
	// ":😥:𠘄:" vs "😄" (according to wikipedia "𠘄" is the arachic variant of "印")
	// TECHNICALLY THIS SHOULD NOT MATCH!
	// However Apple doesn't correctly handle characters in the 4-Byte UTF range, so let's use this test to check for changes in Apples behaviour :)
	XCTAssertTrue([@":\xF0\x9F\x98\x84:\xF0\xA0\x98\x84:" nonConsecutivelySearchString:@"\xF0\x9F\x98\x84" matchingRanges:NULL], @"Mismatch of composed characters (4-byte) with same prefix");
	
}

- (void)testStringByReplacingCharactersInSetWithString
{
	{
		//test against empty string
		XCTAssertEqualObjects([@"" stringByReplacingCharactersInSet:[NSCharacterSet whitespaceCharacterSet] withString:@"x"], @"", @"replacement on empty string must result in empty string");
	}
	{
		//test match at begin, middle, end / consecutive matches
		XCTAssertEqualObjects([@" ab  c " stringByReplacingCharactersInSet:[NSCharacterSet whitespaceCharacterSet] withString:@"_"], @"_ab__c_", @"Testing matches at both end, replacement of consecutive matches");
	}
	{
		//test replacement of different characters
		XCTAssertEqualObjects([@"ab\r\ncd" stringByReplacingCharactersInSet:[NSCharacterSet newlineCharacterSet] withString:@"*"], @"ab**cd", @"Testing replacement of different characters in set");
	}
	{
		// nil for replacement char
		XCTAssertEqualObjects([@"ab\r\ncd" stringByReplacingCharactersInSet:[NSCharacterSet newlineCharacterSet] withString:nil], @"abcd", @"testing replacement with nil");
	}
}

- (void)testStringByExpandingTildeAsIfNotInSandboxObjC{

    // for GitHub tests
    struct passwd *pw = getpwuid(getuid());
    assert(pw);
    NSString *homeDir = [NSString stringWithUTF8String:pw->pw_dir];

    NSString *str = @"~/.ssh";
    NSString *expectedStr = [NSString stringWithFormat:@"%@/.ssh", homeDir];

    str = str.stringByExpandingTildeAsIfNotInSandboxObjC;

    // not in sandbox so:
    XCTAssertEqualObjects(str, expectedStr);

    str = @"~/.ssh/known_hosts";
    expectedStr = [NSString stringWithFormat:@"%@/.ssh/known_hosts", homeDir];

    str = str.stringByExpandingTildeAsIfNotInSandboxObjC;

    XCTAssertEqualObjects(str, expectedStr);
    
}


@end

NSRange RangeFromArray(NSArray *a,NSUInteger idx)
{
	return [(NSValue *)[a objectAtIndex:idx] rangeValue];
}
