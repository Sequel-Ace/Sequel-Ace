//
//  SPDataCellFormatter.m
//  sequel-pro
//
//  Created by Rowan Beentje on February 11, 2009.
//  Copyright (c) 2009 Arboreal. All rights reserved.
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

#import "SPDataCellFormatter.h"
#import "SPTooltip.h"

#import "sequel-ace-Swift.h"

@implementation SPDataCellFormatter

@synthesize textLimit;
@synthesize fieldType;

- (NSString *)stringForObjectValue:(id)anObject
{
	if (![anObject isKindOfClass:[NSString class]]) {
		return [anObject description];
	}

	return anObject;
}

// Always provide the full string when editing
- (NSString *)editingStringForObjectValue:(id)anObject
{
	return anObject;
}

- (BOOL) getObjectValue:(id*) object forString:(NSString*) string errorDescription:(NSString**) error
{
	*object = string;
	return YES;
}

/**
 * When producing an attributed string, take the opportunity to convert to a single
 * line for display, displaying placeholders for CR and LF characters.
 */
- (NSAttributedString *)attributedStringForObjectValue:(id)anObject withDefaultAttributes:(NSDictionary *)attributes
{

	// Start with a base string which has been shortened for fast display
	NSString *baseString = [self stringForObjectValue:anObject];

	// Look for any linebreaks within the string
	NSRange linebreakRange = [baseString rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet] options:NSLiteralSearch];

	// If there's no linebreaks, return a non-mutable string
	if (linebreakRange.location == NSNotFound) {
		return [[NSAttributedString alloc] initWithString:baseString attributes:attributes];
	}

	NSMutableAttributedString *mutableString;
	NSUInteger i, j, stringLength = [baseString length];
	unichar c;

	// Otherwise, prepare a mutable attributed string to alter, and walk along the string.
	mutableString = [[NSMutableAttributedString alloc] initWithString:baseString attributes:attributes];
	for (i = linebreakRange.location, j = i; i < stringLength; i++, j++) {
		c = [baseString characterAtIndex:i];
		switch (c) {
			case '\n':
				[mutableString replaceCharactersInRange:NSMakeRange(j, 1) withString:@"¶"];
				[mutableString addAttribute:NSForegroundColorAttributeName value:[NSColor lightGrayColor] range:NSMakeRange(j, 1)];
				break;
			case '\r':
			case 0x0085:
			case 0x000b:
			case 0x000c:
				[mutableString replaceCharactersInRange:NSMakeRange(j, 1) withString:@"⁋"];
				[mutableString addAttribute:NSForegroundColorAttributeName value:[NSColor lightGrayColor] range:NSMakeRange(j, 1)];
				if (c == '\r' && i + 1 < stringLength && [baseString characterAtIndex:i+1] == '\n') {
					[mutableString deleteCharactersInRange:NSMakeRange(j+1, 1)];
					i++;
				}
				break;
		}
	}

	return mutableString;
}

/**
 * Decide what an edit in progress may leave in the cell: first the column's length
 * rules, then the 0/1 rule of a BIT column. Both report to the user with a tooltip.
 *
 * @param partialString The text the edit would leave in the cell
 * @param newString Set to the text cut to the column's length when a paste overshoots it
 * @param error Unused; the rules show a tooltip instead of an error message
 * @return YES when the text is taken as it stands, NO when the edit is refused or
 *         replaced by the string returned in newString
 */
/**
 * Decide what an edit that replaces part of the cell's text may leave in it.
 * The range-aware rules keep the text behind the insertion point: only the
 * inserted text is cut, where cutting the whole prospective string would drop
 * what follows it. The length rules are decided in Swift (SACellEditLimit).
 *
 * @param partialStringPtr The text the edit would leave in the cell; set to the
 *        text with the insertion cut when it overshoots the column's length
 * @param proposedSelRangePtr Set to the insertion point behind the kept text
 * @param origString The cell's text before the edit
 * @param origSelRange The range of that text the edit replaces
 * @param error Unused; the rules show a tooltip instead of an error message
 * @return YES when the text is taken as it stands, NO when the edit is refused
 *         or replaced by the string returned in partialStringPtr
 */
- (BOOL)isPartialStringValid:(NSString * _Nonnull __autoreleasing * _Nonnull)partialStringPtr
        proposedSelectedRange:(NSRangePointer)proposedSelRangePtr
               originalString:(NSString *)origString
        originalSelectedRange:(NSRange)origSelRange
             errorDescription:(NSString * _Nullable __autoreleasing * _Nullable)error
{
	NSString *proposedString = *partialStringPtr;
	NSInteger insertionLength = (NSInteger)proposedString.length - ((NSInteger)origString.length - (NSInteger)origSelRange.length);

	// A change this method cannot locate - a deletion, or an edit the field
	// editor reports differently - is left to the whole-string rules.
	if (insertionLength < 0 || origSelRange.location + (NSUInteger)insertionLength > proposedString.length) {
		return [self isPartialStringValid:proposedString newEditingString:partialStringPtr errorDescription:error];
	}

	NSString *insertion = [proposedString substringWithRange:NSMakeRange(origSelRange.location, (NSUInteger)insertionLength)];
	NSString *nullValue = [[NSUserDefaults standardUserDefaults] objectForKey:SPNullValue];
	SACellEditLimit *decision = [SACellEditLimit evaluateCellEditOfText:origString
	                                                     replacingRange:origSelRange
	                                                         withString:insertion
	                                                              limit:textLimit
	                                                          fieldType:fieldType
	                                                          nullValue:nullValue];
	// No length rule applies: no limit, or the NULL placeholder being typed.
	// The BIT rule is skipped then, so a BIT value can still be nulled.
	if (decision.isExempt) {
		return YES;
	}

	if (!decision.allowsEdit) {
		if (decision.replacementText) {
			[SPTooltip showWithObject:[NSString stringWithFormat:NSLocalizedString(@"Maximum text length is set to %ld. Inserted text was truncated.", @"Maximum text length is set to %ld. Inserted text was truncated."), (long)textLimit]];
			*partialStringPtr = decision.replacementText;
			if (proposedSelRangePtr != NULL) {
				*proposedSelRangePtr = NSMakeRange((NSUInteger)decision.selectionLocation, 0);
			}
		}
		else {
			[SPTooltip showWithObject:[NSString stringWithFormat:NSLocalizedString(@"Maximum text length is set to %ld.", @"Maximum text length is set to %ld."), (long)textLimit]];
		}
		return NO;
	}

	return [self isBitTextValid:proposedString];
}

/**
 * The 0/1 rule of a BIT column, with its tooltip.
 *
 * @param text The text the edit would leave in the cell
 * @return YES for any other column type, or when the text holds only 0 and 1
 */
- (BOOL)isBitTextValid:(NSString *)text
{
	if (fieldType && [fieldType length] && [[fieldType uppercaseString] isEqualToString:@"BIT"]) {
		if ([text rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"01"] invertedSet]].location != NSNotFound) {
			[SPTooltip showWithObject:NSLocalizedString(@"For BIT fields only “1” or “0” are allowed.", @"For BIT fields only “1” or “0” are allowed.")];
			return NO;
		}
	}

	return YES;
}

/**
 * Decide what an edit in progress may leave in the cell when the range it
 * replaces is not known: first the column's length rules on the whole text,
 * then the 0/1 rule of a BIT column. Both report to the user with a tooltip.
 * The range-aware method above is what the field editor normally calls; this
 * one is its fallback and serves other callers.
 *
 * @param partialString The text the edit would leave in the cell
 * @param newString Set to the text cut to the column's length when a paste overshoots it
 * @param error Unused; the rules show a tooltip instead of an error message
 * @return YES when the text is taken as it stands, NO when the edit is refused or
 *         replaced by the string returned in newString
 */
- (BOOL)isPartialStringValid:(NSString *)partialString newEditingString:(NSString **)newString errorDescription:(NSString **)error
{
    // SPNullValue = @"NULL"
    NSString *nullValue = [[NSUserDefaults standardUserDefaults] objectForKey:SPNullValue];

	// The length rules are decided in Swift (SATextLimitDecision); this shows
	// their tooltip and applies the cut.
	switch ([partialString textLimitDecisionForLimit:textLimit nullValue:nullValue]) {
		case SATextLimitDecisionExempt:
			// No limit set or partialString is NULL value string allow editing
			return YES;
		case SATextLimitDecisionRefuse:
			// A single character over the length of the string - likely typed.  Prevent the change - JCS - Unless it's NULL
			[SPTooltip showWithObject:[NSString stringWithFormat:NSLocalizedString(@"Maximum text length is set to %ld.", @"Maximum text length is set to %ld."), (long)textLimit]];
			return NO;
		case SATextLimitDecisionTruncate:
			// If the string is considerably longer than the limit, likely pasted.  Accept but truncate. - JCS - Unless it's NULL
			[SPTooltip showWithObject:[NSString stringWithFormat:NSLocalizedString(@"Maximum text length is set to %ld. Inserted text was truncated.", @"Maximum text length is set to %ld. Inserted text was truncated."), (long)textLimit]];
			*newString = [NSString stringWithString:[partialString prefixOfCodePoints:textLimit]];
			return NO;
		case SATextLimitDecisionWithinLimit:
			break;
	}

	// Check for BIT fields whether 1 or 0 are typed
	return [self isBitTextValid:partialString];
}

@end
