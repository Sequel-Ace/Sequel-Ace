//
//  SPTableFieldValidation.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on October 28, 2010.
//  Copyright (c) 2010 Stuart Connolly. All rights reserved.
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

#import "SPTableFieldValidation.h"

// PostgreSQL type sets for validation
static NSSet *numericTypes;
static NSSet *serialTypes;
static NSSet *dateTypes;
static NSSet *stringTypes;
static NSSet *binaryTypes;
static NSSet *geometryTypes;
static NSSet *booleanTypes;
static NSSet *networkTypes;
static NSSet *rangeTypes;
static NSSet *jsonTypes;
static NSSet *searchTypes;
static NSSet *bitTypes;
static NSSet *uuidTypes;

@interface SPTableFieldValidation ()

- (NSString *)_formatType:(NSString *)type;

@end

@implementation SPTableFieldValidation

@synthesize fieldTypes;

#pragma mark -
#pragma mark Initialization

+ (void)initialize {
	if (self == [SPTableFieldValidation class]) {
		// PostgreSQL numeric types (non-serial)
		numericTypes = [NSSet setWithArray:@[
			@"SMALLINT", @"INTEGER", @"BIGINT",
			@"DECIMAL", @"NUMERIC",
			@"REAL", @"DOUBLE PRECISION",
			@"MONEY"
		]];

		// PostgreSQL serial (auto-incrementing) types
		serialTypes = [NSSet setWithArray:@[
			@"SMALLSERIAL", @"SERIAL", @"BIGSERIAL"
		]];

		// PostgreSQL date/time types
		dateTypes = [NSSet setWithArray:@[
			@"DATE",
			@"TIME", @"TIME WITHOUT TIME ZONE", @"TIME WITH TIME ZONE", @"TIMETZ",
			@"TIMESTAMP", @"TIMESTAMP WITHOUT TIME ZONE", @"TIMESTAMP WITH TIME ZONE", @"TIMESTAMPTZ",
			@"INTERVAL"
		]];

		// PostgreSQL character/string types
		stringTypes = [NSSet setWithArray:@[
			@"CHARACTER", @"CHAR",
			@"CHARACTER VARYING", @"VARCHAR",
			@"TEXT"
		]];

		// PostgreSQL binary types
		binaryTypes = [NSSet setWithArray:@[
			@"BYTEA"
		]];

		// PostgreSQL bit string types
		bitTypes = [NSSet setWithArray:@[
			@"BIT", @"BIT VARYING", @"VARBIT"
		]];

		// PostgreSQL geometric types
		geometryTypes = [NSSet setWithArray:@[
			@"POINT", @"LINE", @"LSEG", @"BOX",
			@"PATH", @"POLYGON", @"CIRCLE"
		]];

		// PostgreSQL boolean type
		booleanTypes = [NSSet setWithArray:@[
			@"BOOLEAN", @"BOOL"
		]];

		// PostgreSQL network types
		networkTypes = [NSSet setWithArray:@[
			@"CIDR", @"INET", @"MACADDR", @"MACADDR8"
		]];

		// PostgreSQL range types
		rangeTypes = [NSSet setWithArray:@[
			@"INT4RANGE", @"INT8RANGE", @"NUMRANGE",
			@"TSRANGE", @"TSTZRANGE", @"DATERANGE"
		]];

		// PostgreSQL JSON types
		jsonTypes = [NSSet setWithArray:@[
			@"JSON", @"JSONB"
		]];

		// PostgreSQL text search types
		searchTypes = [NSSet setWithArray:@[
			@"TSVECTOR", @"TSQUERY"
		]];

		// PostgreSQL UUID type
		uuidTypes = [NSSet setWithArray:@[
			@"UUID"
		]];
	}
}

#pragma mark -
#pragma mark Public API

/**
 * Returns whether or not the supplied field type is numeric (including serial types).
 *
 * @param fieldType The field type to test
 */
- (BOOL)isFieldTypeNumeric:(NSString *)fieldType
{
	NSString *type = [self _formatType:fieldType];
	return [numericTypes containsObject:type] || [serialTypes containsObject:type];
}

/**
 * Returns whether or not the supplied field type is a serial (auto-incrementing) type.
 *
 * @param fieldType The field type to test
 */
- (BOOL)isFieldTypeSerial:(NSString *)fieldType
{
	NSString *type = [self _formatType:fieldType];
	return [serialTypes containsObject:type];
}

/**
 * Returns whether or not the supplied field type is a date/time type.
 *
 * @param fieldType The field type to test
 */
- (BOOL)isFieldTypeDate:(NSString *)fieldType
{
	NSString *type = [self _formatType:fieldType];
	return [dateTypes containsObject:type];
}

/**
 * Returns whether or not the supplied field type is a geometry type.
 *
 * @param fieldType The field type to test
 */
- (BOOL)isFieldTypeGeometry:(NSString *)fieldType
{
	NSString *type = [self _formatType:fieldType];
	return [geometryTypes containsObject:type];
}

/**
 * Returns whether or not the supplied field type is a string/character type.
 *
 * @param fieldType The field type to test
 */
- (BOOL)isFieldTypeString:(NSString *)fieldType
{
	NSString *type = [self _formatType:fieldType];
	return [stringTypes containsObject:type];
}

/**
 * Returns whether or not the supplied field type allows binary content.
 * In PostgreSQL, this applies to bytea type.
 *
 * @param fieldType The field type to test
 */
- (BOOL)isFieldTypeAllowBinary:(NSString *)fieldType
{
	NSString *type = [self _formatType:fieldType];
	return [binaryTypes containsObject:type];
}

/**
 * Returns whether or not the supplied field type is a boolean type.
 *
 * @param fieldType The field type to test
 */
- (BOOL)isFieldTypeBoolean:(NSString *)fieldType
{
	NSString *type = [self _formatType:fieldType];
	return [booleanTypes containsObject:type];
}

/**
 * Returns whether or not the supplied field type is a network type.
 *
 * @param fieldType The field type to test
 */
- (BOOL)isFieldTypeNetwork:(NSString *)fieldType
{
	NSString *type = [self _formatType:fieldType];
	return [networkTypes containsObject:type];
}

/**
 * Returns whether or not the supplied field type is a range type.
 *
 * @param fieldType The field type to test
 */
- (BOOL)isFieldTypeRange:(NSString *)fieldType
{
	NSString *type = [self _formatType:fieldType];
	return [rangeTypes containsObject:type];
}

/**
 * Returns whether or not the supplied field type is a JSON type.
 *
 * @param fieldType The field type to test
 */
- (BOOL)isFieldTypeJSON:(NSString *)fieldType
{
	NSString *type = [self _formatType:fieldType];
	return [jsonTypes containsObject:type];
}

/**
 * Returns whether or not the supplied field type is a bit string type.
 *
 * @param fieldType The field type to test
 */
- (BOOL)isFieldTypeBit:(NSString *)fieldType
{
	NSString *type = [self _formatType:fieldType];
	return [bitTypes containsObject:type];
}

/**
 * Returns whether or not the supplied field type is a UUID type.
 *
 * @param fieldType The field type to test
 */
- (BOOL)isFieldTypeUUID:(NSString *)fieldType
{
	NSString *type = [self _formatType:fieldType];
	return [uuidTypes containsObject:type];
}

/**
 * Returns whether or not the supplied field type is a text search type.
 *
 * @param fieldType The field type to test
 */
- (BOOL)isFieldTypeTextSearch:(NSString *)fieldType
{
	NSString *type = [self _formatType:fieldType];
	return [searchTypes containsObject:type];
}

/**
 * Returns whether or not the supplied field type requires a length specification.
 * In PostgreSQL, only character, character varying, bit, and bit varying typically need length.
 *
 * @param fieldType The field type to test
 */
- (BOOL)isFieldTypeRequiresLength:(NSString *)fieldType
{
	NSString *type = [self _formatType:fieldType];
	// Types that can have optional length in PostgreSQL
	return ([type isEqualToString:@"CHARACTER"] ||
			[type isEqualToString:@"CHAR"] ||
			[type isEqualToString:@"CHARACTER VARYING"] ||
			[type isEqualToString:@"VARCHAR"] ||
			[type isEqualToString:@"BIT"] ||
			[type isEqualToString:@"BIT VARYING"] ||
			[type isEqualToString:@"VARBIT"] ||
			[type isEqualToString:@"NUMERIC"] ||
			[type isEqualToString:@"DECIMAL"]);
}

#pragma mark -
#pragma mark Private API

/**
 * Formats, i.e. removes whitespace and newlines as well as uppercases the supplied field type string.
 *
 * @param type The field type string to format
 */
- (NSString *)_formatType:(NSString *)type
{
	return [[type stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
}

@end
