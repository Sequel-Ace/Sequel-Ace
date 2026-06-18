//
//  SAPHPSerializedValue.h
//  sequel-ace
//
//  Created by Codex on 2026-06-15.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SAPHPSerializedValueType) {
	SAPHPSerializedValueTypeNull = 0,
	SAPHPSerializedValueTypeBoolean,
	SAPHPSerializedValueTypeInteger,
	SAPHPSerializedValueTypeDouble,
	SAPHPSerializedValueTypeString,
	SAPHPSerializedValueTypeArray,
	SAPHPSerializedValueTypeObject,
	SAPHPSerializedValueTypeCustomSerialized,
	SAPHPSerializedValueTypeReference,
};

@class SAPHPSerializedValue;

@interface SAPHPSerializedEntry : NSObject

@property(nonatomic, strong) id key;
@property(nonatomic) BOOL keyIsInteger;
@property(nonatomic, strong) SAPHPSerializedValue *value;
@property(nonatomic, weak) SAPHPSerializedEntry *parent;

@end

@interface SAPHPSerializedValue : NSObject

@property(nonatomic) SAPHPSerializedValueType type;
@property(nonatomic, copy) NSString *scalarValue;
@property(nonatomic, copy) NSString *className;
@property(nonatomic, copy) NSString *referenceType;
@property(nonatomic, strong) NSMutableArray<SAPHPSerializedEntry *> *children;

+ (instancetype)valueWithType:(SAPHPSerializedValueType)type;
+ (NSString *)normalizedIntegerStringFromEditedString:(NSString *)string;
+ (BOOL)isValidPHPIntegerString:(NSString *)string;
+ (BOOL)isValidPHPFloatString:(NSString *)string;
- (BOOL)isContainer;
- (BOOL)isScalarEditable;
- (NSString *)typeLabel;
- (NSString *)displayValue;
- (NSNumber *)nextAvailableArrayKey;
- (NSString *)uniqueObjectPropertyName;
- (BOOL)containsReference;
- (NSString *)serializedString;

@end

@interface SAPHPSerializedParser : NSObject

+ (SAPHPSerializedValue *)parseString:(NSString *)input error:(NSString **)errorMessage;

@end
