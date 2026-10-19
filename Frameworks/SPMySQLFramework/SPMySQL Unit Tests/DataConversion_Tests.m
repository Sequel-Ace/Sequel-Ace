//
//  DataConversion_Tests.m
//  SPMySQLFramework
//
//  Created by Max Lohrmann on 01.10.15.
//  Copyright (c) 2015 Max Lohrmann. All rights reserved.
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

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>

// these functions are inaccessible outside of unit tests
extern NSString * _bitStringWithBytes(const char *bytes, NSUInteger length, NSUInteger padLength);
extern NSString * _convertStringData(const void *dataBytes, NSUInteger dataLength, NSStringEncoding aStringEncoding, NSUInteger previewLength);

@interface DataConversion_Tests : XCTestCase

- (void)test_bitStringWithBytes;

@end

@implementation DataConversion_Tests

- (void)test_bitStringWithBytes
{
	// BIT(1)
	{
		const char y = '\1';
		const char n = '\0';
		XCTAssertEqualObjects(_bitStringWithBytes(&y,sizeof(y),1), @"1");
		XCTAssertEqualObjects(_bitStringWithBytes(&n,sizeof(n),1), @"0");
	}
	// BIT(3)
	{
		const char input[] = {5};
		NSUInteger bitSize = 3;
		NSString *res = _bitStringWithBytes(input,sizeof(input),bitSize);
		XCTAssertEqualObjects(res, @"101");
	}
	// BIT(16)
	{
		const char input[] = {0xcc,0xf0};
		NSUInteger bitSize = 16;
		NSString *res = _bitStringWithBytes(input,sizeof(input),bitSize);
		XCTAssertEqualObjects(res, @"1100110011110000");
	}
	// BIT(20)
	{
		const char input[] = {0x0f,0xcc,0xf0};
		NSUInteger bitSize = 20;
		NSString *res = _bitStringWithBytes(input,sizeof(input),bitSize);
		XCTAssertEqualObjects(res, @"11111100110011110000");
	}
}

/**
 * A preview counts characters, so it has to know how many bytes each character of the session's
 * character set takes. The three character sets this framework carries Chinese and Korean
 * sessions in - CP949 for euckr, EUC-CN for gb2312, and GB18030 - are one or more bytes per
 * character, and before they were named here a preview of them was cut after as many bytes as
 * characters were asked for: half the characters, the last one through the middle.
 */
- (void)test_convertStringDataPreviewCountsMultibyteCharacters
{
	// The character sets the scanner compares against are set up in the result's class
	// initialisation, which nothing in this test has reached yet.
	[NSClassFromString(@"SPMySQLResult") class];

	// Three CP949 characters, two bytes each, previewed two characters deep.
	const unsigned char cp949[] = {0xC7, 0xD1, 0xB1, 0xB9, 0xBE, 0xEE};
	NSStringEncoding korean = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingDOSKorean);
	NSString *expectedKorean = [[NSString alloc] initWithBytes:cp949 length:4 encoding:korean];
	XCTAssertEqual([expectedKorean length], (NSUInteger)2, "two characters is what four of these bytes are");
	XCTAssertEqualObjects(_convertStringData(cp949, sizeof(cp949), korean, 2),
	                      [expectedKorean stringByAppendingString:@"..."]);

	// Three EUC-CN characters, two bytes each.
	const unsigned char euccn[] = {0xD6, 0xD0, 0xCE, 0xC4, 0xBA, 0xC3};
	NSStringEncoding chinese = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingEUC_CN);
	NSString *expectedChinese = [[NSString alloc] initWithBytes:euccn length:4 encoding:chinese];
	XCTAssertEqual([expectedChinese length], (NSUInteger)2);
	XCTAssertEqualObjects(_convertStringData(euccn, sizeof(euccn), chinese, 2),
	                      [expectedChinese stringByAppendingString:@"..."]);

	// GB18030 takes four bytes where the byte after the lead is 0x30-0x39: two four-byte
	// characters followed by a two-byte one, previewed two characters deep.
	const unsigned char gb18030[] = {0x81, 0x30, 0x81, 0x30, 0x81, 0x30, 0x81, 0x31, 0xD6, 0xD0};
	NSStringEncoding gb = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
	NSString *expectedGB = [[NSString alloc] initWithBytes:gb18030 length:8 encoding:gb];
	XCTAssertNotNil(expectedGB);
	XCTAssertEqualObjects(_convertStringData(gb18030, sizeof(gb18030), gb, 2),
	                      [expectedGB stringByAppendingString:@"..."]);

	// An ASCII byte in any of them still counts as one character.
	const unsigned char mixed[] = {'a', 0xC7, 0xD1, 'b', 0xB1, 0xB9};
	NSString *expectedMixed = [[NSString alloc] initWithBytes:mixed length:3 encoding:korean];
	XCTAssertEqualObjects(_convertStringData(mixed, sizeof(mixed), korean, 2),
	                      [expectedMixed stringByAppendingString:@"..."]);
}

@end
