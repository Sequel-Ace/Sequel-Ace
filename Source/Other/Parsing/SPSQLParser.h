//
//  SPSQLParser.h
//  sequel-pro
//
//  Created by Rowan Beentje on January 18, 2009.
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
 * This class provides a string class intended for SQL parsing.  It extends NSMutableString,
 * with the intention that as a string is parsed the parsed content is removed.  This also
 * allows parsing to occur in "streaming" mode, with parseable content being pulled off the
 * start of the string as additional content is appended onto the end of the string, eg from
 * a file.
 *
 * While some methods may look similar to NSScanner methods, and others look like they could be
 * achieved with Regex libraries or other string parsing libraries, this class was written with
 * the following goals in mind:
 *  - SQL comments, in "⁄* ... *⁄", "#" and "--[\s]" form, are ignored automatically while parsing -
        *but* are left in the strings in question, to allow (for example) MySQL-version specific query
		support, eg ⁄*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT *⁄
 *  - Support for quoted strings in most commands, allowing strings quoted with ", ', and ` characters -
        including support for \-escaping of the quote characters within "- and '-terminated strings.
 *  - Optional support for bracket capturing in most commands.  This can allow simpler parsing of strings
        which also contain subqueries, enums, definitions or groups.
 *  - Speed should remain high even on large strings due to specific context awareness (ie no reliance
 *      on complex lookaheads or lookbehinds to achieve the above).
 *
 * It is anticipated that characterAtIndex: is currently the parsing weak point, and that in future
 * this class could be further optimised by working with the underlying object/characters directly.
 *
 * This class is NOT thread safe!
 */
@interface SPSQLParser : NSMutableString
{
	NSMutableString *string;
	unichar *stringCharCache;
	unichar parsedToChar;
	NSInteger parsedToPosition;
	NSInteger charCacheStart;
	NSInteger charCacheEnd;
	BOOL ignoreCommentStrings;
	BOOL containsCRs;
	BOOL noBackslashEscapes;

	BOOL supportDelimiters;
	NSString *delimiter;
	NSUInteger delimiterLengthMinusOne;
	BOOL lastMatchIsDelimiter;
}

typedef enum {
	SPHashComment = 0,
	SPDoubleDashComment = 1,
	SPCStyleComment = 2
} SPCommentType;

/**
 * Return whether any carriage returns have been encountered during
 * parsing; quoted strings are not included.  May be used to determine
 * whether text needs to be normalised.
 */
- (BOOL)containsCarriageReturns;

/**
 * Set whether comment strings should be ignored during parsing.
 * Normally, comment strings are treated as dead space and ignored;
 * for certain parsing operations, characters within comments need
 * to be inspected, and setIgnoreCommentStrings can be set to YES to
 * achieve this.
 */
- (void) setIgnoreCommentStrings:(BOOL)ignoringCommentStrings;

/**
 * Set whether DELIMITER support should be enabled while parsing.
 * This is off by default; when switched on, delimiters commands will
 * be parsed out and not returned to the calling class, and any active 
 * delimiter statements will be used to override the supplied character
 * for many commands.
 */
- (void) setDelimiterSupport:(BOOL)shouldSupportDelimiters;

/**
 * This setting controls the parser equivalent of the NO_BACKSLASH_ESCAPES
 * SQL mode.
 * If set to YES, the backslash character will not have any special meaning in strings
 * and will be treated as a regular character. This also includes the self escape sequence ("\\").
 * Escaping single quotes/double quotes/backticks by doubling them is not affected by this.
 */
- (void) setNoBackslashEscapes:(BOOL)ignoreBackslashEscapes;

/**
 * Removes comments within the current string, trimming "#", "--[/s]", and "⁄* *⁄" style strings.
 */
- (void) deleteComments;

/**
 * Removes quotes surrounding the string if present, and un-escapes internal occurrences of the quote character,
 * before returning the resulting string.
 * If no quotes surround the current string, return the entire string; if the current string contains several
 * quoted strings, the first will be returned.
 */
- (NSString *) unquotedString;

/**
 * Normalise a string, readying it for queries - trims whitespace from both
 * ends, and ensures line endings which aren't in quotes are LF.
 * The setting of noBackslashEscapes controls whether backslash characters can function
 * as escape characters for single or double quotes in strings.
 */
+ (NSString *) normaliseQueryForExecution:(NSString *)queryString noBackslashEscapes:(BOOL)noBackslashEscapes;

/**
 * Convenience overload of the method above with noBackslashEscapes set to NO (i.e.
 * backslashes can be used for escaping quotes in strings)
 */
+ (NSString *) normaliseQueryForExecution:(NSString *)queryString;

/**
 * Removes characters from the string up to the first occurrence of the supplied character.
 * "inclusively" controls whether the supplied character is also removed.
 * Quoted strings are automatically ignored when looking for the character.
 * SQL comments are automatically ignored when looking for the character.
 * Returns YES if this caused the string to be shortened, or NO if the character was not encountered.
 */
- (BOOL) trimToCharacter:(unichar)character inclusively:(BOOL)inclusive;

/**
 * As trimToCharacter: ..., but allows control over whether characters within quoted strings
 * are ignored.
 */
- (BOOL) trimToCharacter:(unichar)character inclusively:(BOOL)inclusive ignoringQuotedStrings:(BOOL)ignoreQuotedStrings;

/**
 * Returns an NSString containing characters from the string up to the first occurrence of the supplied character.
 * "inclusively" controls whether the supplied character is also returned.
 * Quoted strings are automatically ignored when looking for the character.
 * SQL comments are automatically ignored when looking for the character.
 * If the character is not found, nil is returned.
 */
- (NSString *) stringToCharacter:(unichar)character inclusively:(BOOL)inclusive;

/**
 * As stringToCharacter: ..., but allows control over whether characters within quoted strings
 * are ignored.
 */
- (NSString *) stringToCharacter:(unichar)character inclusively:(BOOL)inclusive ignoringQuotedStrings:(BOOL)ignoreQuotedStrings;

/**
 * Returns an NSString containing characters from the string up to the first occurrence of the supplied
 * character, also removing them from the string.  "trimmingInclusively" controls whether or not the
 * supplied character is removed from the string on a successful match, while "returningInclusively"
 * controls whether it is included in the returned string.
 * Quoted strings are automatically ignored when looking for the characters.
 * SQL comments are automatically ignored when looking for the characters.
 * If the character is not found, nil is returned.
 */
- (NSString *) trimAndReturnStringToCharacter:(unichar)character trimmingInclusively:(BOOL)inclusiveTrim returningInclusively:(BOOL)inclusiveReturn;

/**
 * As trimAndReturnStringToCharacter: ..., but allows control over whether characters within quoted
 * strings are ignored.
 */
- (NSString *) trimAndReturnStringToCharacter:(unichar)character trimmingInclusively:(BOOL)inclusiveTrim returningInclusively:(BOOL)inclusiveReturn ignoringQuotedStrings:(BOOL)ignoreQuotedStrings;

/**
 * Returns characters from the string up to and from the first occurrence of the supplied opening character
 * to the appropriate occurrence of the supplied closing character. "inclusively" controls whether the supplied
 * characters should also be returned.
 * Quoted strings are automatically ignored when looking for the characters.
 * SQL comments are automatically ignored when looking for the characters.
 * Returns nil if no valid matching string can be found.
 */
- (NSString *) stringFromCharacter:(unichar)fromCharacter toCharacter:(unichar)toCharacter inclusively:(BOOL)inclusive;

/**
 * As stringFromCharacter: toCharacter: ..., but allows control over whether to skip
 * over bracket-enclosed characters, as in subqueries, enums, definitions or groups
 */
- (NSString *) stringFromCharacter:(unichar)fromCharacter toCharacter:(unichar)toCharacter inclusively:(BOOL)inclusive skippingBrackets:(BOOL)skipBrackets;

/**
 * As stringFromCharacter: toCharacter: ..., but allows control over whether characters within quoted
 * strings are ignored.
 */
- (NSString *) stringFromCharacter:(unichar)fromCharacter toCharacter:(unichar)toCharacter inclusively:(BOOL)inclusive ignoringQuotedStrings:(BOOL)ignoreQuotedStrings;

/**
 * As stringFromCharacter: toCharacter: ..., but allows control over both bracketing and quoting.
 */
- (NSString *) stringFromCharacter:(unichar)fromCharacter toCharacter:(unichar)toCharacter inclusively:(BOOL)inclusive skippingBrackets:(BOOL)skipBrackets ignoringQuotedStrings:(BOOL)ignoreQuotedStrings;

/**
 * As stringFromCharacter: toCharacter: ..., but also trims the string up to the "to" character and
 * up to or including the "from" character, depending on whether "trimmingInclusively" is set.
 * "returningInclusively" controls whether the supplied characters should also be returned.
 * Returns nil if no valid matching string can be found.
 */
- (NSString *) trimAndReturnStringFromCharacter:(unichar)fromCharacter toCharacter:(unichar)toCharacter trimmingInclusively:(BOOL)inclusiveTrim returningInclusively:(BOOL)inclusiveReturn;

/**
 * As trimAndReturnStringFromCharacter: toCharacter: ..., but allows control over whether to
 * skip over bracket-enclosed characters, as in subqueries, enums, definitions or groups.
 */
- (NSString *) trimAndReturnStringFromCharacter:(unichar)fromCharacter toCharacter:(unichar)toCharacter trimmingInclusively:(BOOL)inclusiveTrim returningInclusively:(BOOL)inclusiveReturn skippingBrackets:(BOOL)skipBrackets;

/**
 * As trimAndReturnStringFromCharacter: toCharacter: ..., but allows control over whether characters
 * within quoted strings are ignored.
 */
- (NSString *) trimAndReturnStringFromCharacter:(unichar)fromCharacter toCharacter:(unichar)toCharacter trimmingInclusively:(BOOL)inclusiveTrim returningInclusively:(BOOL)inclusiveReturn ignoringQuotedStrings:(BOOL)ignoreQuotedStrings;

/**
 * As trimAndReturnStringFromCharacter: toCharacter: ..., but allows control over both bracketing
 * and quoting.
 */
- (NSString *) trimAndReturnStringFromCharacter:(unichar)fromCharacter toCharacter:(unichar)toCharacter trimmingInclusively:(BOOL)inclusiveTrim returningInclusively:(BOOL)inclusiveReturn skippingBrackets:(BOOL)skipBrackets ignoringQuotedStrings:(BOOL)ignoreQuotedStrings;

/**
 * Split a string on the boundaries formed by the supplied character, returning an array of strings.
 * Quoted strings are automatically ignored when looking for the characters.
 * SQL comments are automatically ignored when looking for the characters.
 * Returns an array with one element containing the entire string if the supplied character is not found.
 */
- (NSArray *) splitStringByCharacter:(unichar)character;

/**
 * As splitStringByCharacter: ..., but allows control over whether to skip over bracket-enclosed
 * characters, as in subqueries, enums, definitions or groups.
 */
- (NSArray *) splitStringByCharacter:(unichar)character skippingBrackets:(BOOL)skipBrackets;

/**
 * As splitStringByCharacter:, but allows control over whether characters
 * within quoted strings are ignored.
 */
- (NSArray *) splitStringByCharacter:(unichar)character ignoringQuotedStrings:(BOOL)ignoreQuotedStrings;

/**
 * As splitStringByCharacter: ..., but allows control over both bracketing and quoting.
 */
- (NSArray *) splitStringByCharacter:(unichar)character skippingBrackets:(BOOL)skipBrackets ignoringQuotedStrings:(BOOL)ignoreQuotedStrings;

/**
 * As splitStringByCharacter:, but returning only the ranges of queries, stored as NSValues.
 * Quoted strings are automatically ignored when looking for the characters.
 * SQL comments are automatically ignored when looking for the characters.
 * Returns an array with one range covering the entire string if the supplied character is not found.
 */
- (NSArray *) splitStringIntoRangesByCharacter:(unichar)character;

/**
 * Methods used internally by this class to power the methods above:
 */
- (NSUInteger) firstOccurrenceOfCharacter:(unichar)character ignoringQuotedStrings:(BOOL)ignoreQuotedStrings;
- (NSUInteger) firstOccurrenceOfCharacter:(unichar)character afterIndex:(NSInteger)startIndex ignoringQuotedStrings:(BOOL)ignoreQuotedStrings;
- (NSUInteger) firstOccurrenceOfCharacter:(unichar)character afterIndex:(NSInteger)startIndex skippingBrackets:(BOOL)skipBrackets ignoringQuotedStrings:(BOOL)ignoreQuotedStrings;
- (NSUInteger) endIndexOfStringQuotedByCharacter:(unichar)quoteCharacter startingAtIndex:(NSInteger)index;
- (NSUInteger) endIndexOfCommentOfType:(SPCommentType)commentType startingAtIndex:(NSInteger)index;

/* Required and primitive methods to allow subclassing class cluster */
#pragma mark -
- (id) init;
- (id) initWithBytes:(const void *)bytes length:(NSUInteger)length encoding:(NSStringEncoding)encoding;
- (id) initWithBytesNoCopy:(void *)bytes length:(NSUInteger)length encoding:(NSStringEncoding)encoding freeWhenDone:(BOOL)flag;
- (id) initWithCapacity:(NSUInteger)capacity;
- (id) initWithCharactersNoCopy:(unichar *)chars length:(NSUInteger)length freeWhenDone:(BOOL)flag;
- (id) initWithContentsOfFile:(id)path;
- (id) initWithContentsOfFile:(NSString *)path encoding:(NSStringEncoding)enc error:(NSError **)error;
- (id) initWithCString:(const char *)nullTerminatedCString encoding:(NSStringEncoding)encoding;
- (id) initWithFormat:(NSString *)format, ...;
- (id) initWithFormat:(NSString *)format arguments:(va_list)argList;
- (void) initSQLExtensions;
- (NSUInteger) length;
- (unichar) characterAtIndex:(NSUInteger)index;
- (id) description;
- (NSUInteger) replaceOccurrencesOfString:(NSString *)target withString:(NSString *)replacement options:(NSUInteger)opts range:(NSRange)searchRange;
- (void) setString:(NSString *)string;
- (void) replaceCharactersInRange:(NSRange)range withString:(NSString *)string;
- (void) deleteCharactersInRange:(NSRange)aRange;
- (void) insertString:(NSString *)aString atIndex:(NSUInteger)anIndex;
- (void) dealloc;

@end
