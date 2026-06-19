//
//  SAPHPSerializedValue.m
//  sequel-ace
//
//  Created by Codex on 2026-06-15.
//

#import "SAPHPSerializedValue.h"

#include <errno.h>
#include <stdlib.h>

static const NSUInteger SAPHPSerializedParserMaximumDepth = 512;

static BOOL SAIntegerValueFromPHPSerializedString(NSString *string, NSInteger *value)
{
	if (![SAPHPSerializedValue isValidPHPIntegerString:string]) return NO;

	errno = 0;
	char *end = NULL;
	long long parsedValue = strtoll([string UTF8String], &end, 10);
	if (errno == ERANGE || !end || *end != '\0' || parsedValue < NSIntegerMin || parsedValue > NSIntegerMax) {
		return NO;
	}

	if (value) *value = (NSInteger)parsedValue;
	return YES;
}

@implementation SAPHPSerializedEntry
@end

@interface SAPHPSerializedValue ()

@property(nonatomic) NSStringEncoding stringEncoding;

- (void)setStringEncodingRecursively:(NSStringEncoding)encoding;
- (NSString *)serializedStringUsingEncoding:(NSStringEncoding)encoding error:(NSString **)errorMessage;
- (NSString *)serializedStringForKey:(SAPHPSerializedEntry *)entry encoding:(NSStringEncoding)encoding error:(NSString **)errorMessage;

@end

@implementation SAPHPSerializedValue

+ (instancetype)valueWithType:(SAPHPSerializedValueType)type
{
	SAPHPSerializedValue *value = [[SAPHPSerializedValue alloc] init];
	value.type = type;
	value.scalarValue = @"";
	value.children = [[NSMutableArray alloc] init];
	value.stringEncoding = NSUTF8StringEncoding;
	return value;
}

+ (NSString *)normalizedIntegerStringFromEditedString:(NSString *)string
{
	NSString *trimmedString = [(string)?:@"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return [self isValidPHPIntegerString:trimmedString] ? trimmedString : nil;
}

+ (BOOL)isValidPHPIntegerString:(NSString *)string
{
	if (![string length]) return NO;

	NSUInteger startIndex = 0;
	if ([string characterAtIndex:0] == '-') {
		if ([string length] == 1) return NO;
		startIndex = 1;
	}

	for (NSUInteger i = startIndex; i < [string length]; i++) {
		unichar c = [string characterAtIndex:i];
		if (c < '0' || c > '9') return NO;
	}

	return YES;
}

+ (BOOL)isValidPHPFloatString:(NSString *)string
{
	if (![string length]) return NO;

	if ([string isEqualToString:@"INF"] || [string isEqualToString:@"-INF"] || [string isEqualToString:@"NAN"]) {
		return YES;
	}
	NSString *uppercaseValue = [string uppercaseString];
	if ([uppercaseValue isEqualToString:@"INF"] || [uppercaseValue isEqualToString:@"-INF"] || [uppercaseValue isEqualToString:@"NAN"]) return NO;

	NSScanner *scanner = [NSScanner scannerWithString:string];
	[scanner setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
	[scanner setCharactersToBeSkipped:nil];
	double doubleValue = 0;
	return [scanner scanDouble:&doubleValue] && [scanner isAtEnd];
}

- (BOOL)isContainer
{
	return self.type == SAPHPSerializedValueTypeArray || self.type == SAPHPSerializedValueTypeObject;
}

- (BOOL)isScalarEditable
{
	return self.type == SAPHPSerializedValueTypeNull
		|| self.type == SAPHPSerializedValueTypeBoolean
		|| self.type == SAPHPSerializedValueTypeInteger
		|| self.type == SAPHPSerializedValueTypeDouble
		|| self.type == SAPHPSerializedValueTypeString;
}

- (NSString *)typeLabel
{
	switch (self.type) {
		case SAPHPSerializedValueTypeNull:
			return @"null";
		case SAPHPSerializedValueTypeBoolean:
			return @"bool";
		case SAPHPSerializedValueTypeInteger:
			return @"int";
		case SAPHPSerializedValueTypeDouble:
			return @"float";
		case SAPHPSerializedValueTypeString:
			return @"string";
		case SAPHPSerializedValueTypeArray:
			return [NSString stringWithFormat:@"array (%lu)", (unsigned long)[self.children count]];
		case SAPHPSerializedValueTypeObject:
			return [NSString stringWithFormat:@"object %@ (%lu)", (self.className)?:@"", (unsigned long)[self.children count]];
		case SAPHPSerializedValueTypeCustomSerialized:
			return [NSString stringWithFormat:@"custom %@", (self.className)?:@""];
		case SAPHPSerializedValueTypeEnum:
			return @"enum";
		case SAPHPSerializedValueTypeReference:
			return [NSString stringWithFormat:@"%@ reference", (self.referenceType)?:@"r"];
	}
	return @"";
}

- (NSString *)displayValue
{
	switch (self.type) {
		case SAPHPSerializedValueTypeNull:
			return @"NULL";
		case SAPHPSerializedValueTypeBoolean:
			return [self.scalarValue isEqualToString:@"1"] ? @"true" : @"false";
		case SAPHPSerializedValueTypeInteger:
		case SAPHPSerializedValueTypeDouble:
		case SAPHPSerializedValueTypeString:
			return (self.scalarValue)?:@"";
		case SAPHPSerializedValueTypeCustomSerialized:
		case SAPHPSerializedValueTypeEnum:
			return (self.scalarValue)?:@"";
		case SAPHPSerializedValueTypeReference:
			return (self.scalarValue)?:@"";
		case SAPHPSerializedValueTypeArray:
		case SAPHPSerializedValueTypeObject:
			return @"";
	}
	return @"";
}

- (NSNumber *)nextAvailableArrayKey
{
	NSInteger maxIntegerKey = -1;
	NSMutableSet<NSNumber *> *usedNonNegativeKeys = [NSMutableSet set];

	for (SAPHPSerializedEntry *entry in self.children) {
		if (!entry.keyIsInteger) continue;

		NSString *keyString = [entry.key description];
		NSInteger integerKey = 0;
		if (!SAIntegerValueFromPHPSerializedString(keyString, &integerKey)) continue;
		if (integerKey > maxIntegerKey) {
			maxIntegerKey = integerKey;
		}
		if (integerKey >= 0) {
			[usedNonNegativeKeys addObject:@(integerKey)];
		}
	}

	if (maxIntegerKey >= 0 && maxIntegerKey < NSIntegerMax) {
		return @(maxIntegerKey + 1);
	}

	NSInteger candidateKey = 0;
	while ([usedNonNegativeKeys containsObject:@(candidateKey)] && candidateKey < NSIntegerMax) {
		candidateKey++;
	}

	return @(candidateKey);
}

- (NSString *)uniqueObjectPropertyName
{
	static NSString *basePropertyName = @"new_property";
	NSMutableSet<NSString *> *usedNames = [NSMutableSet set];

	for (SAPHPSerializedEntry *entry in self.children) {
		if (entry.keyIsInteger) continue;
		if (entry.key) [usedNames addObject:[entry.key description]];
	}

	if (![usedNames containsObject:basePropertyName]) {
		return basePropertyName;
	}

	NSUInteger suffix = 2;
	while (suffix < NSUIntegerMax) {
		NSString *candidate = [NSString stringWithFormat:@"%@_%lu", basePropertyName, (unsigned long)suffix];
		if (![usedNames containsObject:candidate]) {
			return candidate;
		}
		suffix++;
	}

	return [NSString stringWithFormat:@"%@_%@", basePropertyName, [[NSUUID UUID] UUIDString]];
}

- (BOOL)containsReference
{
	if (self.type == SAPHPSerializedValueTypeReference) return YES;

	for (SAPHPSerializedEntry *entry in self.children) {
		if ([entry.value containsReference]) return YES;
	}

	return NO;
}

- (void)setStringEncodingRecursively:(NSStringEncoding)encoding
{
	self.stringEncoding = encoding;

	for (SAPHPSerializedEntry *entry in self.children) {
		[entry.value setStringEncodingRecursively:encoding];
	}
}

- (NSData *)dataForSerializedString:(NSString *)string encoding:(NSStringEncoding)encoding error:(NSString **)errorMessage
{
	NSData *data = [string dataUsingEncoding:encoding allowLossyConversion:NO];
	if (!data && errorMessage) {
		*errorMessage = NSLocalizedString(@"Serialized data contains characters that cannot be encoded using the field encoding.", @"PHP serialized editor output encoding error");
	}
	return data;
}

- (NSString *)serializedStringForKey:(SAPHPSerializedEntry *)entry encoding:(NSStringEncoding)encoding error:(NSString **)errorMessage
{
	if (entry.keyIsInteger) {
		return [NSString stringWithFormat:@"i:%@;", [entry.key description]];
	}

	NSString *key = ([entry.key isKindOfClass:[NSString class]]) ? entry.key : [entry.key description];
	key = key ?: @"";
	NSData *keyData = [self dataForSerializedString:key encoding:encoding error:errorMessage];
	if (!keyData) return nil;
	return [NSString stringWithFormat:@"s:%lu:\"%@\";", (unsigned long)[keyData length], key];
}

- (NSString *)serializedString
{
	return [self serializedStringWithError:nil];
}

- (NSString *)serializedStringWithError:(NSString **)errorMessage
{
	return [self serializedStringUsingEncoding:self.stringEncoding ?: NSUTF8StringEncoding error:errorMessage];
}

- (NSString *)serializedStringUsingEncoding:(NSStringEncoding)encoding error:(NSString **)errorMessage
{
	switch (self.type) {
		case SAPHPSerializedValueTypeNull:
			return @"N;";
		case SAPHPSerializedValueTypeBoolean:
			return [NSString stringWithFormat:@"b:%@;", [self.scalarValue isEqualToString:@"1"] ? @"1" : @"0"];
		case SAPHPSerializedValueTypeInteger:
			return [NSString stringWithFormat:@"i:%@;", (self.scalarValue.length) ? self.scalarValue : @"0"];
		case SAPHPSerializedValueTypeDouble:
			return [NSString stringWithFormat:@"d:%@;", (self.scalarValue.length) ? self.scalarValue : @"0"];
		case SAPHPSerializedValueTypeString: {
			NSString *string = (self.scalarValue)?:@"";
			NSData *stringData = [self dataForSerializedString:string encoding:encoding error:errorMessage];
			if (!stringData) return nil;
			return [NSString stringWithFormat:@"s:%lu:\"%@\";", (unsigned long)[stringData length], string];
		}
		case SAPHPSerializedValueTypeArray: {
			NSMutableString *output = [NSMutableString stringWithFormat:@"a:%lu:{", (unsigned long)[self.children count]];
			for (SAPHPSerializedEntry *entry in self.children) {
				NSString *keyString = [self serializedStringForKey:entry encoding:encoding error:errorMessage];
				if (!keyString) return nil;
				NSString *valueString = [entry.value serializedStringUsingEncoding:encoding error:errorMessage];
				if (!valueString) return nil;
				[output appendString:keyString];
				[output appendString:valueString];
			}
			[output appendString:@"}"];
			return output;
		}
		case SAPHPSerializedValueTypeObject: {
			NSString *className = (self.className)?:@"stdClass";
			NSData *classData = [self dataForSerializedString:className encoding:encoding error:errorMessage];
			if (!classData) return nil;
			NSMutableString *output = [NSMutableString stringWithFormat:@"O:%lu:\"%@\":%lu:{", (unsigned long)[classData length], className, (unsigned long)[self.children count]];
			for (SAPHPSerializedEntry *entry in self.children) {
				NSString *keyString = [self serializedStringForKey:entry encoding:encoding error:errorMessage];
				if (!keyString) return nil;
				NSString *valueString = [entry.value serializedStringUsingEncoding:encoding error:errorMessage];
				if (!valueString) return nil;
				[output appendString:keyString];
				[output appendString:valueString];
			}
			[output appendString:@"}"];
			return output;
		}
		case SAPHPSerializedValueTypeCustomSerialized: {
			NSString *className = (self.className)?:@"";
			NSString *payload = (self.scalarValue)?:@"";
			NSData *classData = [self dataForSerializedString:className encoding:encoding error:errorMessage];
			if (!classData) return nil;
			NSData *payloadData = [self dataForSerializedString:payload encoding:encoding error:errorMessage];
			if (!payloadData) return nil;
			return [NSString stringWithFormat:@"C:%lu:\"%@\":%lu:{%@}", (unsigned long)[classData length], className, (unsigned long)[payloadData length], payload];
		}
		case SAPHPSerializedValueTypeEnum: {
			NSString *caseName = (self.scalarValue)?:@"";
			NSData *caseData = [self dataForSerializedString:caseName encoding:encoding error:errorMessage];
			if (!caseData) return nil;
			return [NSString stringWithFormat:@"E:%lu:\"%@\";", (unsigned long)[caseData length], caseName];
		}
		case SAPHPSerializedValueTypeReference:
			return [NSString stringWithFormat:@"%@:%@;", (self.referenceType)?:@"r", (self.scalarValue.length) ? self.scalarValue : @"1"];
	}
	return @"N;";
}

@end

@interface SAPHPSerializedParser ()

@property(nonatomic, strong) NSData *data;
@property(nonatomic) NSUInteger position;
@property(nonatomic) NSUInteger recursionDepth;
@property(nonatomic) NSStringEncoding stringEncoding;
@property(nonatomic, copy) NSString *errorMessage;

- (SAPHPSerializedValue *)parseValueAtCurrentDepth;
- (BOOL)unsignedIntegerValue:(NSUInteger *)value fromString:(NSString *)string;

@end

@implementation SAPHPSerializedParser

+ (SAPHPSerializedValue *)parseString:(NSString *)input error:(NSString **)errorMessage
{
	return [self parseString:input encoding:NSUTF8StringEncoding error:errorMessage];
}

+ (SAPHPSerializedValue *)parseString:(NSString *)input encoding:(NSStringEncoding)encoding error:(NSString **)errorMessage
{
	NSString *inputString = (input) ?: @"";
	if (![inputString length]) {
		if (errorMessage) *errorMessage = NSLocalizedString(@"No serialized data was provided.", @"PHP serialized editor empty input error");
		return nil;
	}

	NSData *inputData = [inputString dataUsingEncoding:encoding allowLossyConversion:NO];
	if (!inputData) {
		if (errorMessage) *errorMessage = NSLocalizedString(@"Serialized data cannot be encoded using the field encoding.", @"PHP serialized editor input encoding error");
		return nil;
	}

	SAPHPSerializedParser *parser = [[SAPHPSerializedParser alloc] init];
	parser.data = inputData;
	parser.position = 0;
	parser.stringEncoding = encoding;

	SAPHPSerializedValue *value = [parser parseValue];
	if (!value) {
		if (errorMessage) *errorMessage = parser.errorMessage ?: NSLocalizedString(@"Unable to parse PHP serialized data.", @"PHP serialized editor parse error");
		return nil;
	}

	if (parser.position != [parser.data length]) {
		if (errorMessage) *errorMessage = NSLocalizedString(@"Unexpected trailing characters after serialized value.", @"PHP serialized editor trailing input error");
		return nil;
	}

	[value setStringEncodingRecursively:encoding];
	return value;
}

- (unsigned char)currentByte
{
	if (self.position >= [self.data length]) return 0;
	const unsigned char *bytes = [self.data bytes];
	return bytes[self.position];
}

- (BOOL)consumeByte:(unsigned char)byte
{
	if ([self currentByte] != byte) {
		self.errorMessage = [NSString stringWithFormat:NSLocalizedString(@"Expected '%c'.", @"PHP serialized editor expected byte error"), byte];
		return NO;
	}
	self.position++;
	return YES;
}

- (NSString *)readUntilByte:(unsigned char)delimiter
{
	const unsigned char *bytes = [self.data bytes];
	NSUInteger start = self.position;
	NSUInteger length = [self.data length];
	while (self.position < length && bytes[self.position] != delimiter) {
		self.position++;
	}

	if (self.position >= length) {
		self.errorMessage = [NSString stringWithFormat:NSLocalizedString(@"Expected delimiter '%c'.", @"PHP serialized editor expected delimiter error"), delimiter];
		return nil;
	}

	NSData *subdata = [self.data subdataWithRange:NSMakeRange(start, self.position - start)];
	self.position++;
	return [[NSString alloc] initWithData:subdata encoding:NSASCIIStringEncoding];
}

- (NSString *)readBytesAsString:(NSUInteger)byteLength
{
	NSUInteger dataLength = [self.data length];
	if (self.position > dataLength || byteLength > dataLength - self.position) {
		self.errorMessage = NSLocalizedString(@"String length exceeds available serialized data.", @"PHP serialized editor string length error");
		return nil;
	}

	NSData *subdata = [self.data subdataWithRange:NSMakeRange(self.position, byteLength)];
	self.position += byteLength;

	NSString *string = [[NSString alloc] initWithData:subdata encoding:self.stringEncoding];
	if (!string && self.stringEncoding != NSUTF8StringEncoding) {
		string = [[NSString alloc] initWithData:subdata encoding:NSUTF8StringEncoding];
	}
	if (!string && self.stringEncoding != NSISOLatin1StringEncoding) {
		string = [[NSString alloc] initWithData:subdata encoding:NSISOLatin1StringEncoding];
	}
	if (!string) {
		self.errorMessage = NSLocalizedString(@"Serialized string could not be decoded as text.", @"PHP serialized editor string decoding error");
	}
	return string;
}

- (SAPHPSerializedValue *)parseValue
{
	if (self.recursionDepth >= SAPHPSerializedParserMaximumDepth) {
		self.errorMessage = NSLocalizedString(@"PHP serialized data exceeds the maximum supported nesting depth.", @"PHP serialized editor maximum nesting depth error");
		return nil;
	}

	self.recursionDepth++;
	SAPHPSerializedValue *value = [self parseValueAtCurrentDepth];
	self.recursionDepth--;
	return value;
}

- (SAPHPSerializedValue *)parseValueAtCurrentDepth
{
	if (self.position >= [self.data length]) {
		self.errorMessage = NSLocalizedString(@"Unexpected end of serialized data.", @"PHP serialized editor end of input error");
		return nil;
	}

	unsigned char typeByte = [self currentByte];
	self.position++;

	if (typeByte == 'N') {
		if (![self consumeByte:';']) return nil;
		return [SAPHPSerializedValue valueWithType:SAPHPSerializedValueTypeNull];
	}

	if (![self consumeByte:':']) return nil;

	if (typeByte == 'b') {
		NSString *raw = [self readUntilByte:';'];
		if (![raw isEqualToString:@"0"] && ![raw isEqualToString:@"1"]) {
			self.errorMessage = NSLocalizedString(@"Invalid PHP boolean value.", @"PHP serialized editor invalid boolean error");
			return nil;
		}
		SAPHPSerializedValue *value = [SAPHPSerializedValue valueWithType:SAPHPSerializedValueTypeBoolean];
		value.scalarValue = raw;
		return value;
	}

	if (typeByte == 'i') {
		NSString *raw = [self readUntilByte:';'];
		if (![SAPHPSerializedValue isValidPHPIntegerString:raw]) {
			self.errorMessage = NSLocalizedString(@"Invalid PHP integer value.", @"PHP serialized editor invalid integer error");
			return nil;
		}
		SAPHPSerializedValue *value = [SAPHPSerializedValue valueWithType:SAPHPSerializedValueTypeInteger];
		value.scalarValue = raw;
		return value;
	}

	if (typeByte == 'd') {
		NSString *raw = [self readUntilByte:';'];
		if (![SAPHPSerializedValue isValidPHPFloatString:raw]) {
			self.errorMessage = NSLocalizedString(@"Invalid PHP float value.", @"PHP serialized editor invalid float error");
			return nil;
		}
		SAPHPSerializedValue *value = [SAPHPSerializedValue valueWithType:SAPHPSerializedValueTypeDouble];
		value.scalarValue = raw;
		return value;
	}

	if (typeByte == 's') {
		NSString *lengthString = [self readUntilByte:':'];
		NSUInteger byteLength = 0;
		if (![self unsignedIntegerValue:&byteLength fromString:lengthString]) return nil;
		if (![self consumeByte:'"']) return nil;
		NSString *string = [self readBytesAsString:byteLength];
		if (!string) return nil;
		if (![self consumeByte:'"'] || ![self consumeByte:';']) return nil;

		SAPHPSerializedValue *value = [SAPHPSerializedValue valueWithType:SAPHPSerializedValueTypeString];
		value.scalarValue = string;
		return value;
	}

	if (typeByte == 'a') {
		NSString *countString = [self readUntilByte:':'];
		NSUInteger count = 0;
		if (![self unsignedIntegerValue:&count fromString:countString]) return nil;
		if (![self consumeByte:'{']) return nil;

		SAPHPSerializedValue *arrayValue = [SAPHPSerializedValue valueWithType:SAPHPSerializedValueTypeArray];
		for (NSUInteger i = 0; i < count; i++) {
			SAPHPSerializedValue *keyValue = [self parseValue];
			if (!keyValue) return nil;
			if (keyValue.type != SAPHPSerializedValueTypeInteger && keyValue.type != SAPHPSerializedValueTypeString) {
				self.errorMessage = NSLocalizedString(@"PHP array keys must be integers or strings.", @"PHP serialized editor invalid key error");
				return nil;
			}
			SAPHPSerializedValue *childValue = [self parseValue];
			if (!childValue) return nil;

			SAPHPSerializedEntry *entry = [[SAPHPSerializedEntry alloc] init];
			entry.keyIsInteger = keyValue.type == SAPHPSerializedValueTypeInteger;
			entry.key = keyValue.scalarValue;
			entry.value = childValue;
			[arrayValue.children addObject:entry];
		}

		if (![self consumeByte:'}']) return nil;
		return arrayValue;
	}

	if (typeByte == 'O') {
		NSString *classLengthString = [self readUntilByte:':'];
		NSUInteger classByteLength = 0;
		if (![self unsignedIntegerValue:&classByteLength fromString:classLengthString]) return nil;
		if (![self consumeByte:'"']) return nil;
		NSString *className = [self readBytesAsString:classByteLength];
		if (!className) return nil;
		if (![self consumeByte:'"'] || ![self consumeByte:':']) return nil;
		NSString *countString = [self readUntilByte:':'];
		NSUInteger count = 0;
		if (![self unsignedIntegerValue:&count fromString:countString]) return nil;
		if (![self consumeByte:'{']) return nil;

		SAPHPSerializedValue *objectValue = [SAPHPSerializedValue valueWithType:SAPHPSerializedValueTypeObject];
		objectValue.className = className;
		for (NSUInteger i = 0; i < count; i++) {
			SAPHPSerializedValue *keyValue = [self parseValue];
			if (!keyValue) return nil;
			if (keyValue.type != SAPHPSerializedValueTypeInteger && keyValue.type != SAPHPSerializedValueTypeString) {
				self.errorMessage = NSLocalizedString(@"PHP object property names must be integers or strings.", @"PHP serialized editor invalid property error");
				return nil;
			}
			SAPHPSerializedValue *childValue = [self parseValue];
			if (!childValue) return nil;

			SAPHPSerializedEntry *entry = [[SAPHPSerializedEntry alloc] init];
			entry.keyIsInteger = keyValue.type == SAPHPSerializedValueTypeInteger;
			entry.key = keyValue.scalarValue;
			entry.value = childValue;
			[objectValue.children addObject:entry];
		}

		if (![self consumeByte:'}']) return nil;
		return objectValue;
	}

	if (typeByte == 'C') {
		NSString *classLengthString = [self readUntilByte:':'];
		NSUInteger classByteLength = 0;
		if (![self unsignedIntegerValue:&classByteLength fromString:classLengthString]) return nil;
		if (![self consumeByte:'"']) return nil;
		NSString *className = [self readBytesAsString:classByteLength];
		if (!className) return nil;
		if (![self consumeByte:'"'] || ![self consumeByte:':']) return nil;
		NSString *payloadLengthString = [self readUntilByte:':'];
		NSUInteger payloadByteLength = 0;
		if (![self unsignedIntegerValue:&payloadByteLength fromString:payloadLengthString]) return nil;
		if (![self consumeByte:'{']) return nil;
		NSString *payload = [self readBytesAsString:payloadByteLength];
		if (!payload) return nil;
		if (![self consumeByte:'}']) return nil;

		SAPHPSerializedValue *customValue = [SAPHPSerializedValue valueWithType:SAPHPSerializedValueTypeCustomSerialized];
		customValue.className = className;
		customValue.scalarValue = payload;
		return customValue;
	}

	if (typeByte == 'E') {
		NSString *caseLengthString = [self readUntilByte:':'];
		NSUInteger caseByteLength = 0;
		if (![self unsignedIntegerValue:&caseByteLength fromString:caseLengthString]) return nil;
		if (![self consumeByte:'"']) return nil;
		NSString *caseName = [self readBytesAsString:caseByteLength];
		if (!caseName) return nil;
		if (![self consumeByte:'"'] || ![self consumeByte:';']) return nil;

		SAPHPSerializedValue *enumValue = [SAPHPSerializedValue valueWithType:SAPHPSerializedValueTypeEnum];
		enumValue.scalarValue = caseName;
		return enumValue;
	}

	if (typeByte == 'r' || typeByte == 'R') {
		NSString *reference = [self readUntilByte:';'];
		if (![self unsignedIntegerValue:NULL fromString:reference]) return nil;
		SAPHPSerializedValue *referenceValue = [SAPHPSerializedValue valueWithType:SAPHPSerializedValueTypeReference];
		referenceValue.referenceType = [NSString stringWithFormat:@"%c", typeByte];
		referenceValue.scalarValue = reference;
		return referenceValue;
	}

	self.errorMessage = [NSString stringWithFormat:NSLocalizedString(@"Unsupported PHP serialized type '%c'.", @"PHP serialized editor unsupported type error"), typeByte];
	return nil;
}

- (BOOL)unsignedIntegerValue:(NSUInteger *)value fromString:(NSString *)string
{
	if (![string length]) return NO;
	for (NSUInteger i = 0; i < [string length]; i++) {
		unichar c = [string characterAtIndex:i];
		if (c < '0' || c > '9') {
			self.errorMessage = NSLocalizedString(@"Invalid serialized length or count.", @"PHP serialized editor invalid count error");
			return NO;
		}
	}

	errno = 0;
	char *end = NULL;
	unsigned long long parsedValue = strtoull([string UTF8String], &end, 10);
	if (errno == ERANGE || !end || *end != '\0' || parsedValue > NSUIntegerMax) {
		self.errorMessage = NSLocalizedString(@"Serialized length or count is too large.", @"PHP serialized editor count overflow error");
		return NO;
	}

	if (value) *value = (NSUInteger)parsedValue;
	return YES;
}

@end
