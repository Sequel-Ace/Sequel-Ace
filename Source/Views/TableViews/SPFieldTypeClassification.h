//
//  SPFieldTypeClassification.h
//  sequel-pro
//
//  Created by Sequel Ace Team.
//

#import <Foundation/Foundation.h>

NS_INLINE BOOL SPFieldTypeShouldBeUnquoted(NSString *fieldTypeGroup, NSString *fieldType)
{
	if ([fieldTypeGroup isKindOfClass:[NSString class]]) {
		NSString *normalizedGroup = [[fieldTypeGroup lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([normalizedGroup isEqualToString:@"bit"] || [normalizedGroup isEqualToString:@"integer"] || [normalizedGroup isEqualToString:@"float"]) {
			return YES;
		}
	}

	if (![fieldType isKindOfClass:[NSString class]]) return NO;

	NSString *normalizedFieldType = [fieldType stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *baseType = [[normalizedFieldType componentsSeparatedByString:@"("] firstObject];
	NSString *typeToken = nil;

	for (NSString *part in [baseType componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
		if ([part length]) {
			typeToken = part;
			break;
		}
	}

	NSString *normalizedType = [typeToken uppercaseString];

	static NSSet<NSString *> *unquotedFieldTypes = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		unquotedFieldTypes = [NSSet setWithArray:@[@"BIT", @"TINYINT", @"SMALLINT", @"MEDIUMINT", @"INT", @"INTEGER", @"BIGINT", @"FLOAT", @"DOUBLE", @"REAL", @"DECIMAL", @"DEC", @"NUMERIC", @"FIXED"]];
	});

	return [unquotedFieldTypes containsObject:normalizedType];
}
