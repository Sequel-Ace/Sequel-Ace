//
//  SPParserUtils.c
//  sequel-pro
//
//  Created by Max Lohrmann on 27.01.15.
//  Relocated from existing files. Previous copyright applies.
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

#include "SPParserUtils.h"
#include <stdint.h>

// Count the number of characters (not bytes) in a NUL-terminated UTF-8 C string.
// Result is kept parity-equal to -[NSString length] for the same bytes: each
// non-leading (continuation) byte subtracts one from the byte count, and each
// 4-byte (non-BMP) start byte subtracts one more (NSString counts surrogate
// pairs as length 2).
//
// NOTE: the previous implementation used a SWAR word-aligned inner loop that
// performed an 8-byte read (`*(size_t*)s`) and a 256-byte prefetch on every
// iteration. On inputs shorter than 8 bytes those reads ran past the end of the
// buffer -- undefined behaviour reported by AddressSanitizer as
// heap-buffer-overflow (GitHub issue #792). This byte-wise loop is safe and,
// because the inputs here are short SQL/CSV cell strings, the SWAR speed-up is
// irrelevant. Counting math is byte-for-byte identical to the old prologue and
// epilogue loops, so all existing return values are preserved.
size_t utf8strlen(const char * _s)
{
	const char *s;
	long count = 0;
	unsigned char b;

	for (s = _s; ; s++) {
		b = (unsigned char)*s;

		/* Exit at the NUL terminator. */
		if (b == '\0') {
			break;
		}

		/* +1 if this byte is NOT the first byte of a character (a continuation byte). */
		count += (b >> 7) & ((~b) >> 6);

		/* CORRECT: subtract one extra for each 4-byte (non-BMP) start byte so the
		 * result matches -[NSString length], which counts a surrogate pair as 2. */
		count -= (b & 0xf0) == 0xf0;
	}

	return (size_t)((s - _s) - count);
}
