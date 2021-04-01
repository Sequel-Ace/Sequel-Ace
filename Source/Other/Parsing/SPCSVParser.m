//
//  SPCSVParser.m
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

#import "SPCSVParser.h"

/**
 * Please see the header files for a general description of the purpose of this class.
 */

@implementation SPCSVParser

#pragma mark -
#pragma mark Retrieving data from the CSV string

/**
 * Retrieve the entire two-dimensional array represented by the current string.
 * Serves as a convenience method and also an example of how to use getRow:.
 */
- (NSArray *) array
{
	NSMutableArray *csvArray = [[NSMutableArray alloc] init];
	NSArray *csvRowArray;

	// Ensure that the full string is being parsed by resetting the parser position
	parserPosition = trimPosition;
	totalLengthParsed = 0;

	// Loop through the results fetching process
	while ((csvRowArray = [self getRowAsArrayAndTrimString:NO stringIsComplete:YES]))
	{
		CFArrayAppendValue((CFMutableArrayRef)csvArray, (__bridge const void *)(csvRowArray));
	}

	// Return the array
	return csvArray;
}

/**
 * Convenience method to retrieve the next row from the CSV string, without trimming, and
 * assuming the CSV string is fully set.
 * Returns nil if no more rows can be returned.
 */
- (NSArray *) getRowAsArray
{
	return [self getRowAsArrayAndTrimString:NO stringIsComplete:YES];
}

/**
 * Allow retrieving a row from the result set - walks along the CSV, parsing until
 * a row has been found.  The resulting row is padding with NSNulls to match the first
 * row encountered if necessary.
 * Takes two arguments: whether to trim the string, useful when processing a CSV in
 * streaming mode, and whether the current string is known to be complete.  If in streaming
 * mode, and the entire string has not yet been supplied, this should be set to NO; this
 * prevents the final row (possibly without a trailing line terminator) from being returned
 * prematurely.
 * Returns nil if no more rows can be returned.
 */
- (NSArray *) getRowAsArrayAndTrimString:(BOOL)trimString stringIsComplete:(BOOL)stringComplete
{
	NSMutableArray *csvRowArray;
	NSMutableString *csvCellString = [NSMutableString string];
	NSUInteger startingParserPosition, nextQuoteDistance, nextFieldEndDistance, nextLineEndDistance;
	NSInteger skipLength, j;
	BOOL fieldIsQuoted, isEscaped;
	BOOL nonStrictEscapeMatchingFallback = NO;
	BOOL lineEndingEncountered = NO;

	if (fieldCount == NSNotFound)
		csvRowArray = [NSMutableArray array];
	else
		csvRowArray = [NSMutableArray arrayWithCapacity:fieldCount];

	// Store the starting parser position so it can be restored if necessary
	startingParserPosition = parserPosition;

	// Loop along the CSV string, parsing.
	while (parserPosition < csvStringLength && !lineEndingEncountered) {
		[csvCellString setString:@""];
		fieldIsQuoted = NO;

		// Skip unescaped, unquoted whitespace where possible
		[self _moveParserPastSkippableCharacters];

		// Check the start of the string for the quote character, and loop along the string
		// if so to capture the entire quoted string.
		if (fieldQuoteLength && parserPosition + fieldQuoteLength <= csvStringLength
			&& [[csvString substringWithRange:NSMakeRange(parserPosition, fieldQuoteLength)] isEqualToString:fieldQuoteString])
		{
			parserPosition += fieldQuoteLength;
			fieldIsQuoted = YES;

			while (parserPosition < csvStringLength) {

				// Find the next quote string
				nextQuoteDistance = [self _getDistanceToString:fieldQuoteString];

				// Check to see if the quote string encountered was escaped... or an escaper
				if (escapeLength && nextQuoteDistance != NSNotFound) {
					j = 1;
					isEscaped = NO;
					nonStrictEscapeMatchingFallback = NO;
					if (!escapeStringIsFieldQuoteString) {
						while (j * escapeLength <= (NSInteger)nextQuoteDistance
								&& ([[csvString substringWithRange:NSMakeRange((parserPosition + nextQuoteDistance - (j*escapeLength)), escapeLength)] isEqualToString:escapeString]))
						{
							isEscaped = !isEscaped;
							j++;
						}
						skipLength = fieldQuoteLength;
						if (!useStrictEscapeMatching && !isEscaped) nonStrictEscapeMatchingFallback = YES;
					}
					
					// If the escape string is the field quote string, check for doubled (Excel-style) usage.
					// Also, if the parser is in loose mode, also support field end strings quoted by using
					// another field end string, as used by Excel
					if (escapeStringIsFieldQuoteString || nonStrictEscapeMatchingFallback) {
						if (parserPosition + nextQuoteDistance + (2 * fieldQuoteLength) <= csvStringLength
							&& [[csvString substringWithRange:NSMakeRange(parserPosition + nextQuoteDistance + fieldQuoteLength, fieldQuoteLength)] isEqualToString:fieldQuoteString])
						{
							isEscaped = YES;
							skipLength = 2 * fieldQuoteLength;
						}
					}

					// If it was escaped, keep processing the field.
					if (isEscaped) {
						
						// Append the matched string, together with the field quote character
						// which has been determined to be within the string - but append the
						// field end character unescaped to avoid later processing.
						if (escapeStringIsFieldQuoteString || nonStrictEscapeMatchingFallback) {
							[csvCellString appendString:[csvString substringWithRange:NSMakeRange(parserPosition, nextQuoteDistance+fieldQuoteLength)]];
						} else {
							[csvCellString appendString:[csvString substringWithRange:NSMakeRange(parserPosition, nextQuoteDistance - escapeLength)]];
							[csvCellString appendString:fieldQuoteString];
						}

						// Move the parser location to beyond the field end character[s]
						parserPosition += nextQuoteDistance + skipLength;
						continue;
					}
				}
				
				// Add on the scanned string up to the terminating quote character.
				if (nextQuoteDistance != NSNotFound) {
					[csvCellString appendString:[csvString substringWithRange:NSMakeRange(parserPosition, nextQuoteDistance)]];
					parserPosition += nextQuoteDistance + fieldQuoteLength;
				} else {
					[csvCellString appendString:[csvString substringWithRange:NSMakeRange(parserPosition, csvStringLength - parserPosition)]];
					parserPosition = csvStringLength;
				}

				// We should now be at the end of the field - continue on past the quote,
				// and remove whitespace if possible.
				if (parserPosition < csvStringLength) {
					[self _moveParserPastSkippableCharacters];
				}

				// Break out of the quoted field processing loop.
				break;
			}
		}

		// With quoted strings processed, now process the field until the next field end
		// character, or the next line end character, both of which may terminate the current
		// field.  This also handles unquoted strings/numbers.
		while (parserPosition < csvStringLength) {

			// Determine whether a line end or a field end occurs first
			nextFieldEndDistance = [self _getDistanceToString:fieldEndString];
			nextLineEndDistance = [self _getDistanceToString:lineEndString];
			if (nextLineEndDistance != NSNotFound
				&& (nextLineEndDistance < nextFieldEndDistance
					|| nextFieldEndDistance == NSNotFound))
			{
				nextFieldEndDistance = nextLineEndDistance;
				lineEndingEncountered = YES;
				skipLength = lineEndLength;
			} else if (nextFieldEndDistance != NSNotFound) {
				skipLength = fieldEndLength;
			} else {
				[csvCellString appendString:[csvString substringWithRange:NSMakeRange(parserPosition, csvStringLength - parserPosition)]];
				parserPosition = csvStringLength;
				break;
			}

			// Check to see if the termination character was escaped
			if (escapeLength) {
				j = 1;
				isEscaped = NO;
				while (j * escapeLength <= (NSInteger)nextFieldEndDistance
						&& ([[csvString substringWithRange:NSMakeRange((parserPosition + nextFieldEndDistance - (j*escapeLength)), escapeLength)] isEqualToString:escapeString]))
				{
					isEscaped = !isEscaped;
					j++;
				}

				// If it was, continue processing the field
				if (isEscaped) {
				
					// Append the matched string, together with the field/line character
					// which was encountered - but append the string unescaped to avoid
					// later processing.
					[csvCellString appendString:[csvString substringWithRange:NSMakeRange(parserPosition, nextFieldEndDistance - escapeLength)]];
					if (lineEndingEncountered) {
						[csvCellString appendString:lineEndString];
						lineEndingEncountered = NO;
					} else {
						[csvCellString appendString:fieldEndString];
					}

					// Update the parser location as appropriate
					parserPosition += nextFieldEndDistance + skipLength;
					continue;
				}
			}

			// Add on the scanned string up to the terminating character
			[csvCellString appendString:[csvString substringWithRange:NSMakeRange(parserPosition, nextFieldEndDistance)]];
			parserPosition += nextFieldEndDistance + skipLength;

			break;
		}

		// We now have a field content string.
		// Insert a NSNull object if the cell contains an unescaped null character or 
		// an unquoted string which matches the set null replacement string.
		if ([csvCellString isEqualToString:@"\\N"]
			|| (!fieldIsQuoted && nullReplacementString && [csvCellString isEqualToString:nullReplacementString]))
		{
			[csvRowArray addObject:[NSNull null]];
		} else {
				
			// Clean up escaped characters
			if (escapeLength) {
				if (fieldIsQuoted && fieldEndLength)
					[csvCellString replaceOccurrencesOfString:escapedFieldEndString withString:fieldEndString options:NSLiteralSearch range:NSMakeRange(0, [csvCellString length])];
				if (!fieldIsQuoted && fieldQuoteLength)
					[csvCellString replaceOccurrencesOfString:escapedFieldQuoteString withString:fieldQuoteString options:NSLiteralSearch range:NSMakeRange(0, [csvCellString length])];
				if (fieldIsQuoted && lineEndLength)
					[csvCellString replaceOccurrencesOfString:escapedLineEndString withString:lineEndString options:NSLiteralSearch range:NSMakeRange(0, [csvCellString length])];
				if (!escapeStringIsFieldQuoteString)
					[csvCellString replaceOccurrencesOfString:escapedEscapeString withString:escapeString options:NSLiteralSearch range:NSMakeRange(0, [csvCellString length])];
			}

			// Add the field to the row array
			[csvRowArray addObject:[NSString stringWithString:csvCellString]];
		}
	}

	// If no line ending was encountered, as stringIsComplete is set to NO, return nil
	// to ensure we don't return a "row" which is incomplete
	if (!lineEndingEncountered && !stringComplete) {
		parserPosition = startingParserPosition;
		return nil;
	}

	// Update the total parsed length (differs from parserPosition following trims)
	totalLengthParsed += parserPosition - startingParserPosition;

	// Skip empty rows.  Note the NSNull pointer comparison; as [NSNull null] is a singleton this works correctly.
	if ([csvRowArray count] == 0
		|| ([csvRowArray count] == 1
			&& ([csvRowArray objectAtIndex:0] == [NSNull null]
				|| ![[csvRowArray objectAtIndex:0] length])))
	{

		// If the parser is at the end of the string, return nil
		if (parserPosition == csvStringLength) return nil;

		// Otherwise, retrieve the next row and return that instead
		return [self getRowAsArrayAndTrimString:trimString stringIsComplete:stringComplete];
	}

	// Update the string trim state if appropriate, and lazily trigger trims
	if (trimString) {
		trimPosition = parserPosition;
		[self _updateState];
	}

	// Capture the length of the first row when processing, and ensure that all
	// subsequent rows contain that many cells (fill them with [SPNotLoaded notLoaded]
	// to allow to replace these by the table column's DEFAULT value)
	if (fieldCount == NSNotFound) {
		fieldCount = [csvRowArray count];
	} else if ([csvRowArray count] < (NSUInteger)fieldCount) {
		for (j = [csvRowArray count]; j < fieldCount; j++) [csvRowArray addObject:[SPNotLoaded notLoaded]];
	}

	// Return the row
	return csvRowArray;
}

#pragma mark -
#pragma mark Adding new data to the string

/**
 * Append additional data to the CSV string, for example to allow streaming parsing.
 */
- (void) appendString:(NSString *)aString
{
	[csvString appendString:aString];
	csvStringLength += [aString length];
}

/**
 * Completely replace the underlying CSV string.
 */
- (void) setString:(NSString *)aString
{
	trimPosition = 0;
	totalLengthParsed = 0;
	[csvString setString:aString];
	csvStringLength = [csvString length];
}

#pragma mark -
#pragma mark Basic information

/**
 * Retrieve the string length.
 */
- (NSUInteger) length
{
	return csvStringLength - trimPosition;
}

/**
 * Retrieve the underlying CSV string.
 */
- (NSString *) string
{
	return [csvString substringWithRange:NSMakeRange(trimPosition, csvStringLength - trimPosition)];
}

/**
 * Return the parser position
 */
- (NSUInteger) parserPosition
{
	return parserPosition;
}

/**
 * Return the total length of CSV parsed so far - differs from the parser position in
 * streaming/trimming situations
 */
- (NSUInteger) totalLengthParsed
{
	return totalLengthParsed;
}

#pragma mark -
#pragma mark Setting the terminator, quote, escape and null character replacement strings

/**
 * Allow setting the field terminator string.
 * If passing in fields from a user interface which are representative, eg the user typing in
 * \ and t for a tab character, pass in YES as the second character. (eg "\t" => \t)
 */
- (void) setFieldTerminatorString:(NSString *)theString convertDisplayStrings:(BOOL)convertString
{
	if (convertString) {
		theString = [self _convertDisplayString:theString];
	}
	fieldEndString = [[NSString alloc] initWithString:theString];
	fieldEndLength = [fieldEndString length];
	escapedFieldEndString = [[NSString alloc] initWithFormat:@"%@%@", escapeString, fieldEndString];

	[self _updateSkipCharacterSet];
}

/**
 * Allow setting the field terminator string.
 * If passing in fields from a user interface which are representative, eg the user typing in
 * \ and t for a tab character, pass in YES as the second character. (eg "\t" => \t)
 */
- (void) setLineTerminatorString:(NSString *)theString convertDisplayStrings:(BOOL)convertString
{
	if (convertString) {
		theString = [self _convertDisplayString:theString];
	}
	lineEndString = [[NSString alloc] initWithString:theString];
	lineEndLength = [lineEndString length];
	escapedLineEndString = [[NSString alloc] initWithFormat:@"%@%@", escapeString, lineEndString];

	[self _updateSkipCharacterSet];
}

/**
 * Allow setting the field terminator string.
 * If passing in fields from a user interface which are representative, eg the user typing in
 * \ and t for a tab character, pass in YES as the second character. (eg "\t" => \t)
 */
- (void) setFieldQuoteString:(NSString *)theString convertDisplayStrings:(BOOL)convertString
{
	if (convertString) {
		theString = [self _convertDisplayString:theString];
	}
	fieldQuoteString = [[NSString alloc] initWithString:theString];
	fieldQuoteLength = [fieldQuoteString length];
	escapedFieldQuoteString = [[NSString alloc] initWithFormat:@"%@%@", escapeString, fieldQuoteString];
	escapeStringIsFieldQuoteString = [fieldQuoteString isEqualToString:escapeString];

	[self _updateSkipCharacterSet];
}

/**
 * Allow setting the field terminator string.
 * If passing in fields from a user interface which are representative, eg the user typing in
 * \ and t for a tab character, pass in YES as the second character. (eg "\t" => \t)
 */
- (void) setEscapeString:(NSString *)theString convertDisplayStrings:(BOOL)convertString
{
	if (convertString) {
		theString = [self _convertDisplayString:theString];
	}
	escapeString = [[NSString alloc] initWithString:theString];
	escapeLength = [escapeString length];
	escapedEscapeString = [[NSString alloc] initWithFormat:@"%@%@", escapeString, escapeString];
	escapeStringIsFieldQuoteString = [fieldQuoteString isEqualToString:escapeString];

	[self _updateSkipCharacterSet];
}

/**
 * Allow setting a string to be replaced by NSNull if it is encountered *unquoted*
 * during import.  Defaults to nil, so no strings are replaced.
 */
- (void) setNullReplacementString:(NSString *)nullString
{
	

	if (nullString) nullReplacementString = [[NSString alloc] initWithString:nullString];
}

/**
 * By default, field end strings aren't matched strictly - as well as the defined escape
 * character, the class will automatically match doubled-up field quote strings, as exported
 * by Excel and in common use (eg "field contains ""quotes""").  To switch escaping to strict
 * mode, set this to YES.
 */
- (void) setEscapeStringsAreMatchedStrictly:(BOOL)strictMatching
{
	useStrictEscapeMatching = strictMatching;
}

#pragma mark -
#pragma mark Init and internal update methods

/**
 * Set up the string for CSV parsing, together with class defaults.
 */
- (void) _initialiseCSVParserDefaults
{
	trimPosition = 0;
	fieldCount = NSNotFound;
	parserPosition = 0;
	totalLengthParsed = 0;
	csvStringLength = [csvString length];

	// Set up the default field and line separators, together with quote
	// and escape strings
	fieldEndString = @",";
	lineEndString = @"\n";
	fieldQuoteString = @"\"";
	escapeString = @"\\";
	escapeStringIsFieldQuoteString = NO;
	escapedFieldEndString = @"\\,";
	escapedLineEndString = @"\\\n";
	escapedFieldQuoteString = @"\\\"";
	escapedEscapeString = @"\\\\";
	useStrictEscapeMatching = NO;
	fieldEndLength = [fieldEndString length];
	lineEndLength = [lineEndString length];
	fieldQuoteLength = [fieldQuoteString length];
	escapeLength = [escapeString length];

	// Set up the default null replacement character string as nil
	nullReplacementString = nil;

	// With the default field and line separators, it's possible to skip
	// a few characters - reset the character set that can be skipped
	skipCharacterSet = nil;
	[self _updateSkipCharacterSet];
}

/**
 * Update the string state, enacting trims lazily to trade-off memory usage and the
 * speed hit with constant string updates and NSScanner resets.
 */
- (void) _updateState
{

	// If the trim position is still before the trim enact point, do nothing.
	if (trimPosition < SPCSVPARSER_TRIM_ENACT_LENGTH) return;

	// Trim the string
	[csvString deleteCharactersInRange:NSMakeRange(0, trimPosition)];

	// Update the parse position and stored string length
	parserPosition -= trimPosition;
	csvStringLength -= trimPosition;

	// Reset the trim position
	trimPosition = 0;
}

/**
 * Takes a display string and converts representations of special characters
 * to the represented characters; for example, the string with characters \ and t
 * to the tab character.
 */
- (NSString *) _convertDisplayString:(NSString *)theString
{
	NSMutableString *conversionString = [NSMutableString stringWithString:theString];

	[conversionString replaceOccurrencesOfString:@"\\t" withString:@"\t"
										 options:NSLiteralSearch
										   range:NSMakeRange(0, [conversionString length])];
	[conversionString replaceOccurrencesOfString:@"\\n" withString:@"\n"
										 options:NSLiteralSearch
										   range:NSMakeRange(0, [conversionString length])];
	[conversionString replaceOccurrencesOfString:@"\\r" withString:@"\r"
										 options:NSLiteralSearch
										   range:NSMakeRange(0, [conversionString length])];

	return [NSString stringWithString:conversionString];
}

/**
 * Reset the character set that can be skipped when processing the CSV.
 * This is called whenever the delimiters, quotes and escapes are updated.
 */
- (void) _updateSkipCharacterSet
{
	NSMutableString *charactersToSkip;

	

	charactersToSkip = [[NSMutableString alloc] init];
	if (![fieldEndString isEqualToString:@" "] && ![fieldQuoteString isEqualToString:@" "] && ![escapeString isEqualToString:@" "] && ![lineEndString isEqualToString:@" "])
		[charactersToSkip appendString:@" "];
	if (![fieldEndString isEqualToString:@"\t"] && ![fieldQuoteString isEqualToString:@"\t"] && ![escapeString isEqualToString:@"\t"] && ![lineEndString isEqualToString:@"\t"])
		[charactersToSkip appendString:@"\t"];

	if ([charactersToSkip length])
		skipCharacterSet = [NSCharacterSet characterSetWithCharactersInString:charactersToSkip];
}

/**
 * Get the distance to the next occurence of the specified string, from the current
 * parser location. Returns NSNotFound if the string could not be found before the end
 * of the string.
 */
- (NSUInteger) _getDistanceToString:(NSString *)theString
{
	NSRange stringRange = [csvString rangeOfString:theString options:NSLiteralSearch range:NSMakeRange(parserPosition, csvStringLength - parserPosition)];

	if (stringRange.location == NSNotFound) return NSNotFound;

	return stringRange.location - parserPosition;
}

/**
 * Move the parser past any skippable characters - this should be called to effectively trim
 * whitespace from the starts and ends of cells, unless that whitespace is quoted.  By
 * maintaining a list of skippable characters, any whitespace used in quote/line end/field
 * end chars is preserved safely.
 */ 
- (void) _moveParserPastSkippableCharacters
{
	if (!skipCharacterSet) return;

	NSInteger i = 0;
	while (parserPosition + i < csvStringLength) {
		if (![skipCharacterSet characterIsMember:[csvString characterAtIndex:parserPosition+i]]) break;
		i++;
	}
	if (i) parserPosition += i;
}

/**
 * Required and primitive methods to allow subclassing class cluster
 */
#pragma mark -

- (instancetype)init {
	if (self = [super init]) {
		csvString = [[NSMutableString alloc] init];
		[self _initialiseCSVParserDefaults];
	}
	return self;
}

- (instancetype)initWithString:(NSString *)aString {
	if (self = [super init]) {
		csvString = [[NSMutableString alloc] initWithString:aString];
		[self _initialiseCSVParserDefaults];
	}
	return self;
}

- (instancetype)initWithContentsOfFile:(NSString *)path encoding:(NSStringEncoding)encoding error:(NSError **)error {
	if (self = [super init]) {
		csvString = [[NSMutableString alloc] initWithContentsOfFile:path encoding:encoding error:error];
		[self _initialiseCSVParserDefaults];
	}
	return self;
}

@end
