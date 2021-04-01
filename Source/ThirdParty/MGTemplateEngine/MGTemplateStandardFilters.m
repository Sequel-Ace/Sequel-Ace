//
//  MGTemplateStandardFilters.m
//
//  Created by Matt Gemmell on 13/05/2008.
//  Copyright 2008 Instinctive Code. All rights reserved.

#import "MGTemplateStandardFilters.h"

#define UPPERCASE		@"uppercase"
#define LOWERCASE		@"lowercase"
#define CAPITALIZED		@"capitalized"
#define DATE_FORMAT		@"date_format"
#define COLOR_FORMAT	@"color_format"
#define DEFAULT        @"default"

@implementation MGTemplateStandardFilters

- (NSArray *)filters
{
	return [NSArray arrayWithObjects:
			UPPERCASE, LOWERCASE, CAPITALIZED,
			DATE_FORMAT, COLOR_FORMAT,
			DEFAULT,
			nil];
}

// Returns a concatenated version of an array of strings.
- (NSString*) stringsConcatenatedWithSpaces: (NSArray*) array {
	NSMutableString* result = [NSMutableString string];
	for (NSString* item in array) {
		[result appendFormat: @"%@ ", item];
	}
	return result;
}

- (id)filterInvoked:(NSString *)filter withArguments:(NSArray *)args onValue:(id)value
{
	if ([filter isEqualToString:UPPERCASE]) {
		return [[NSString stringWithFormat:@"%@", value] uppercaseString];

	} else if ([filter isEqualToString:LOWERCASE]) {
		return [[NSString stringWithFormat:@"%@", value] lowercaseString];

	} else if ([filter isEqualToString:CAPITALIZED]) {
		return [[NSString stringWithFormat:@"%@", value] capitalizedString];

	} else if ([filter isEqualToString:DATE_FORMAT]) {
		// Formats NSDates according to Unicode syntax:
		// http://unicode.org/reports/tr35/tr35-4.html#Date_Format_Patterns
		// e.g. "dd MM yyyy" etc.
		if ([value isKindOfClass:[NSDate class]] && [args count] == 1) {
			NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
			[dateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
			NSString *format = [args objectAtIndex:0];
			[dateFormatter setDateFormat:format];
			return [dateFormatter stringFromDate:(NSDate *)value];
		}

	} else if ([filter isEqualToString:COLOR_FORMAT]) {
#if TARGET_OS_IPHONE
		if ([value isKindOfClass:[UIColor class]] && [args count] == 1) {
#else
		if ([value isKindOfClass:[NSColor class]] && [args count] == 1) {
#endif
			NSString *format = [[args objectAtIndex:0] lowercaseString];
			if ([format isEqualToString:@"hex"]) {
				// Output color in hex format RRGGBB (without leading # character).
#if TARGET_OS_IPHONE
				CGColorRef color = [(UIColor *)value CGColor];
				CGColorSpaceRef colorSpace = CGColorGetColorSpace(color);
				CGColorSpaceModel colorSpaceModel = CGColorSpaceGetModel(colorSpace);

				if (colorSpaceModel != kCGColorSpaceModelRGB)
					return @"000000";

				const CGFloat *components = CGColorGetComponents(color);
				NSString *colorHex = [NSString stringWithFormat:@"%02x%02x%02x",
									  (unsigned int)(components[0] * 255),
									  (unsigned int)(components[1] * 255),
									  (unsigned int)(components[2] * 255)];
				return colorHex;
#else
				NSColor *color = [(NSColor *)value colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
				if (!color) { // happens if the colorspace couldn't be converted
					return @"000000"; // black
				} else {
					NSString *colorHex = [NSString stringWithFormat:@"%02x%02x%02x",
										  (unsigned int)([color redComponent] * 255),
										  (unsigned int)([color greenComponent] * 255),
										  (unsigned int)([color blueComponent] * 255)];
					return colorHex;
				}
#endif
			}
		}
	} else if ([filter isEqualToString: DEFAULT]) {
		// If argument to default is either nil or the empty string, use all arguments after the default keyword instead.
		if (!value) {
			return [self stringsConcatenatedWithSpaces: args];
		}
		if ([value isKindOfClass: [NSString class]] && [(NSString*)value length] == 0) {
			return [self stringsConcatenatedWithSpaces: args];
		}
	}
	return value;
}

@end
