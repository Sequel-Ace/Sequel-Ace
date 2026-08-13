//
//  SPParserUtilsTest.m
//  sequel-pro
//
//  Created by Max Lohrmann on 27.01.15.
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

#define USE_APPLICATION_UNIT_TEST 1

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>

#include "SPParserUtils.h"
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>
#include <signal.h>
#include <mach/mach.h>
#include <mach/thread_act.h>

#if defined(__arm64__) || defined(__aarch64__)

// Support for the over-read regression test below: run utf8strlen() with an
// arm64 hardware watchpoint armed on the bytes that follow the NUL terminator
// of the string under test, up to the end of the 8-byte word containing the
// NUL. Those bytes are exactly what the old SWAR implementation of
// utf8strlen() (GitHub issue #792) read past short buffers.

static sigjmp_buf sUtf8TrapJmp;
static volatile sig_atomic_t sUtf8TrapTripped;

static void sUtf8TrapHandler(int sig, siginfo_t *si, void *ctx)
{
	(void)sig;
	(void)si;
	(void)ctx;
	sUtf8TrapTripped = 1;
	siglongjmp(sUtf8TrapJmp, 1);
}

// Calls utf8strlen(s) for a NUL-terminated string of `len` bytes that starts
// at a 16-byte aligned address. Sets *tripped to YES if the function reads any
// byte after the NUL terminator (within the word that contains the NUL).
static size_t sUtf8strlenGuarded(const char *s, size_t len, BOOL *tripped)
{
	*tripped = NO;

	// The 8-byte word that contains the NUL terminator.
	uintptr_t nulWord = (uintptr_t)(s + len) & ~(uintptr_t)7;

	// Byte-select mask for the bytes that follow the NUL inside that word.
	uint32_t bas = 0;
	for (size_t i = len + 1; (uintptr_t)(s + i) < nulWord + 8; i++) {
		bas |= 1u << ((uintptr_t)(s + i) - nulWord);
	}

	// Arm watchpoint slot 0: DBGWCR = E (enable) | PAC = 0b11 (EL0 and EL1) |
	// LSC = 0b01 (loads only) | BAS << 5 (watched bytes, numbered from the
	// word address in DBGWVR). A watchpoint is per-thread, so only reads made
	// by this thread (i.e. by utf8strlen() itself) can trip it.
	arm_debug_state64_t state;
	memset(&state, 0, sizeof(state));
	state.__wvr[0] = (uint64_t)nulWord;
	state.__wcr[0] = (bas == 0) ? 0 : (1u | (3u << 1) | (1u << 3) | (bas << 5));
	kern_return_t kr = thread_set_state(mach_thread_self(), ARM_DEBUG_STATE64,
	                                    (thread_state_t)&state, ARM_DEBUG_STATE64_COUNT);
	if (kr != KERN_SUCCESS) {
		// Could not arm the watchpoint (unexpected on macOS); degrade to a
		// plain call so the value assertions below still run.
		return utf8strlen(s);
	}

	struct sigaction sa;
	struct sigaction oldSa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_sigaction = sUtf8TrapHandler;
	sa.sa_flags = SA_SIGINFO;
	sigemptyset(&sa.sa_mask);
	sigaction(SIGTRAP, &sa, &oldSa);

	sUtf8TrapTripped = 0;
	size_t result;
	if (sigsetjmp(sUtf8TrapJmp, 1) == 0) {
		result = utf8strlen(s);
	}
	else {
		// The watchpoint fired: a read of a byte past the NUL raised SIGTRAP.
		*tripped = YES;
		result = 0;
	}

	// Disarm the watchpoint and restore the previous SIGTRAP disposition.
	memset(&state, 0, sizeof(state));
	thread_set_state(mach_thread_self(), ARM_DEBUG_STATE64,
	                 (thread_state_t)&state, ARM_DEBUG_STATE64_COUNT);
	sigaction(SIGTRAP, &oldSa, NULL);
	return result;
}

#endif /* __arm64__ */

@interface SPParserUtilsTest : XCTestCase

- (void)testUtf8strlen;
- (void)testUtf8strlenShortStringsDoNotReadPastNul;

@end

@implementation SPParserUtilsTest

- (void)testUtf8strlen {
	// NOTE!!: Those test do not verify that the utf8strlen() function works according to spec,
	//         but whether it produces the same results as NSString for the same input.
	
	const char *empty = "";
	NSString *emptyString = [NSString stringWithCString:empty encoding:NSUTF8StringEncoding];
	XCTAssertEqual(utf8strlen(empty),[emptyString length], @"empty string");
	
	// This is just a little safeguard.
	// If any of those conditions fail, all of the following assumptions are moot.
	const char *charSeq = "\xF0\x9F\x8D\x8F"; //🍏
	NSString *charString = [NSString stringWithCString:charSeq encoding:NSUTF8StringEncoding];
	XCTAssertEqual(strlen(charSeq),     (size_t)4, @"assumption about storage for binary C string");
	XCTAssertEqual([charString length], (NSUInteger)2, @"assumption about NSString internal storage of string");
	
	const char *singleByteSeq = "Hello World!";
	NSString *singleByteString = [NSString stringWithCString:singleByteSeq encoding:NSUTF8StringEncoding];
	XCTAssertEqual(utf8strlen(singleByteSeq), [singleByteString length], @"ASCII UTF-8 subset");
	
	const char *twoByteSeq = "H\xC3\xA4ll\xC3\xB6 W\xC3\x9Crld\xC3\x9F!"; // Hällö WÜrldß!
	NSString *twoByteString = [NSString stringWithCString:twoByteSeq encoding:NSUTF8StringEncoding];
	XCTAssertEqual(utf8strlen(twoByteSeq), [twoByteString length], @"String containing two-byte utf8 characters");
	
	const char *threeByteSeq = "\xE3\x81\x93.\xE3\x82\x93.\xE3\x81\xAB.\xE3\x81\xA1.\xE3\x81\xAF"; // こ.ん.に.ち.は
	NSString *threeByteString = [NSString stringWithCString:threeByteSeq encoding:NSUTF8StringEncoding];
	XCTAssertEqual(utf8strlen(threeByteSeq), [threeByteString length], @"String containing three-byte utf8 characters");
	
	const char *fourByteSeq = "\xF0\x9F\x8D\x8F\xF0\x9F\x8D\x8B\xF0\x9F\x8D\x92"; //🍏🍋🍒
	NSString *fourByteString = [NSString stringWithCString:fourByteSeq encoding:NSUTF8StringEncoding];
	XCTAssertEqual(utf8strlen(fourByteSeq), [fourByteString length], @"String containing only 4-byte utf8 characters (outside BMP)");

	const char *mixedSeq = "\xE3\x81\x82\xE3\x82\x81\xE3\x80\x90\xE9\xA3\xB4\xE3\x80\x91\xF0\x9F\x8D\xAD \xE2\x89\x88 S\xC3\xBC\xC3\x9Figkeit"; // あめ【飴】🍭 ≈ Süßigkeit
	NSString *mixedString = [NSString stringWithCString:mixedSeq encoding:NSUTF8StringEncoding];
	XCTAssertEqual(utf8strlen(mixedSeq), [mixedString length], @"utf8 characters with all 4 lengths mixed together.");
	
	//composed vs. decomposed chars
	const char *decompSeq = "\xC3\xA4 - a\xCC\x88"; // ä - ä
	NSString *decompString = [NSString stringWithCString:decompSeq encoding:NSUTF8StringEncoding];
	XCTAssertEqual(utf8strlen(decompSeq), [decompString length], @"\"LATIN SMALL LETTER A WITH DIAERESIS\" vs. \"LATIN SMALL LETTER A\" + \"COMBINING DIAERESIS\"");
}

// Regression test for issue #792. The old SWAR implementation of utf8strlen()
// read one 8-byte word per iteration: whenever the NUL terminator did not fall
// on the last byte of such a word, it also read the bytes following the NUL --
// past the end of any buffer that ended at the NUL.
//
// Neither a value assertion nor AddressSanitizer can gate this under the
// standard Unit Tests gate: the over-read bytes are never counted, and the
// scheme runs without ASan, so the old code still returns the right value and
// the test stays green. A guard page does not help either: the word load is
// 8-byte aligned and page boundaries are multiples of 8, so an aligned load can
// never cross into a protected page.
//
// What does gate it is an arm64 hardware watchpoint armed on exactly the bytes
// after the NUL (loads only, see sUtf8strlenGuarded()): the old word load
// touches them and raises SIGTRAP; the byte-wise implementation stops at the
// NUL and never does. "selec" (5 bytes) is the reproducer from the issue.
- (void)testUtf8strlenShortStringsDoNotReadPastNul {
	NSArray<NSString *> *cases = @[
		@"", @"a", @"ab", @"abc", @"abcd", @"selec", @"abcdef", @"abcdefg",
		@"ä",                    // 2-byte UTF-8          -> NSString length 1
		@"こ",                    // 3-byte UTF-8          -> NSString length 1
		@"\U0001F34F",           // 4-byte UTF-8, non-BMP -> NSString length 2
		@"\U0001F34F\U0001F34B"  // two of them           -> NSString length 4
	];
	for (NSString *str in cases) {
		const char *cStr = [str UTF8String];
		size_t len = strlen(cStr);
		// Heap buffer with a poisoned tail; malloc() is 16-byte aligned, so the
		// string starts word-aligned like the strings in issue #792 did.
		char *buf = malloc(64);
		memset(buf, 0xEE, 64);
		memcpy(buf, cStr, len + 1);

		BOOL tripped = NO;
		size_t actual;
#if defined(__arm64__) || defined(__aarch64__)
		actual = sUtf8strlenGuarded(buf, len, &tripped);
#else
		// No hardware watchpoint support compiled in: still verify the values.
		actual = utf8strlen(buf);
#endif
		free(buf);

		XCTAssertEqual(actual, [str length], @"character count for \"%@\" (%zu bytes)", str, len);
		XCTAssertFalse(tripped, @"utf8strlen() read past the NUL terminator of \"%@\" (%zu bytes) — issue #792 regression", str, len);
	}
}

@end
