//
//  SPCSVParser.h
//  sequel-pro
//
//  Created by Rowan Beentje on September 16, 2009.
//  Copyright (c) 2009 Rowan Beentje. All rights reserved.
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

/**
 * This class provides a string class intended for CSV parsing.  Unlike SPSQLParser, this
 * does not extend NSMutableString and instead provides only a subset of similar methods.
 * Internally, an approach similar to NSScanner is used to support multi-character strings.
 * The methods are designed with the intention that as a string is parsed the parsed content
 * is removed.  This also allows parsing to occur in "streaming" mode, with parseable content
 * being pulled off the start of the string as additional content is appended onto the end of
 * the string, eg from a file.
 *
 * Supports:
 *  - Control of field terminator, line terminator, string enclosures and escape characters.
 *  - Multi-character field terminator, line terminator, string enclosures, and escape strings.
 *  - Stream-based processing (recommended that strings split by \n or \r are used when streaming
 *    to minimise multibyte issues)
 *  - Correct treatment of line terminators within quoted strings and proper escape support
 *    including escape characters matching the quote characters in Excel style
 *
 * The internal usage of string range finding, similar to the NSScanner approach, means this
 * could be significantly sped up for single-character terminators.
 */

#define SPCSVPARSER_TRIM_ENACT_LENGTH 250000

@interface SPCSVParser : NSObject
{
	NSMutableString *csvString;

	NSUInteger trimPosition;
	NSUInteger parserPosition;
	NSUInteger totalLengthParsed;
	NSUInteger csvStringLength;
	NSInteger fieldCount;

	NSString *nullReplacementString;
	NSString *fieldEndString;
	NSString *lineEndString;
	NSString *fieldQuoteString;
	NSString *escapeString;
	NSString *escapedFieldEndString;
	NSString *escapedLineEndString;
	NSString *escapedFieldQuoteString;
	NSString *escapedEscapeString;
	NSInteger fieldEndLength;
	NSInteger lineEndLength;
	NSInteger fieldQuoteLength;
	NSInteger escapeLength;
	NSCharacterSet *skipCharacterSet;
	NSScanner *csvScanner;

	BOOL escapeStringIsFieldQuoteString;
	BOOL useStrictEscapeMatching;
}

/* Retrieving data from the CSV string */
- (NSArray *) array;
- (NSArray *) getRowAsArray;
- (NSArray *) getRowAsArrayAndTrimString:(BOOL)trimString stringIsComplete:(BOOL)stringComplete;

/* Adding new data to the string */
- (void) appendString:(NSString *)aString;
- (void) setString:(NSString *)aString;

/* Basic information */
- (NSUInteger) length;
- (NSString *) string;
- (NSUInteger) parserPosition;
- (NSUInteger) totalLengthParsed;

/* Setting the terminator, quote, escape and null character replacement strings */
- (void) setFieldTerminatorString:(NSString *)theString convertDisplayStrings:(BOOL)convertString;
- (void) setLineTerminatorString:(NSString *)theString convertDisplayStrings:(BOOL)convertString;
- (void) setFieldQuoteString:(NSString *)theString convertDisplayStrings:(BOOL)convertString;
- (void) setEscapeString:(NSString *)theString convertDisplayStrings:(BOOL)convertString;
- (void) setNullReplacementString:(NSString *)nullString;
- (void) setEscapeStringsAreMatchedStrictly:(BOOL)strictMatching;

/* Init and internal update methods */
- (void) _initialiseCSVParserDefaults;
- (void) _moveParserPastSkippableCharacters;
- (NSUInteger) _getDistanceToString:(NSString *)theString;
- (void) _updateState;
- (NSString *) _convertDisplayString:(NSString *)theString;
- (void) _updateSkipCharacterSet;

/* Initialisation and teardown */
#pragma mark -

- (id) init;
- (id) initWithString:(NSString *)aString;
- (id) initWithContentsOfFile:(NSString *)path encoding:(NSStringEncoding)enc error:(NSError **)error;
- (void) dealloc;

@end
