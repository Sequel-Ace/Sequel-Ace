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
#include <string.h>

#define SIZET (sizeof(size_t))
#define SBYTE ((SIZET - 1) * 8)

#define ONEMASK ((size_t)(-1) / 0xFF)
#define ONEMASK8 (ONEMASK * 0x80)
#define FMASK ((size_t)(-1)*(ONEMASK*0xf)-1)

// adapted from http://www.daemonology.net/blog/2008-06-05-faster-utf8-strlen.html
size_t utf8strlen(const char *bytes, size_t byteLength)
{
	/* NSString counts characters outside the BMP as two UTF-16 code units.
	 * Here we assume that only up to 4-byte UTF-8 characters are allowed
	 * [latest UTF-8 specification]. */
	size_t continuationByteCount = 0;
	size_t fourByteLeadCount = 0;
	size_t offset = 0;

	/* Process only complete words inside the caller-provided byte span. memcpy()
	 * keeps unaligned loads defined without sacrificing the SWAR bulk path. */
	for (; byteLength - offset >= SIZET; offset += SIZET) {
		size_t word;
		memcpy(&word, bytes + offset, sizeof(word));

		size_t fourByteLeadBytes = word & FMASK;
		fourByteLeadBytes = (fourByteLeadBytes >> 7)
			& (fourByteLeadBytes >> 6)
			& (fourByteLeadBytes >> 5)
			& (fourByteLeadBytes >> 4);
		fourByteLeadCount += (fourByteLeadBytes * ONEMASK) >> SBYTE;

		size_t continuationBytes = ((word & ONEMASK8) >> 7) & ((~word) >> 6);
		continuationByteCount += (continuationBytes * ONEMASK) >> SBYTE;
	}

	/* Take care of the remaining bytes without reading beyond byteLength. */
	for (; offset < byteLength; offset++) {
		unsigned char byte = (unsigned char)bytes[offset];
		continuationByteCount += (byte & 0xc0) == 0x80;
		fourByteLeadCount += (byte & 0xf0) == 0xf0;
	}

	return byteLength - continuationByteCount + fourByteLeadCount;
}
