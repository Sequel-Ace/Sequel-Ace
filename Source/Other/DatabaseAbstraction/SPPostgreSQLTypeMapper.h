//
//  SPPostgreSQLTypeMapper.h
//  Sequel Ace
//
//  Maps PostgreSQL OID values to human-readable SQL type strings.
//

#import <Foundation/Foundation.h>

@interface SPPostgreSQLTypeMapper : NSObject

/// Convert a PostgreSQL type OID to a SQL type name string (e.g. 23 → "INTEGER").
+ (NSString *)typeNameForOID:(unsigned int)oid;

/// Returns YES if the OID represents an integer type (SMALLINT, INTEGER, BIGINT, SERIAL, etc.).
+ (BOOL)isIntegerOID:(unsigned int)oid;

/// Returns YES if the OID represents a floating-point type.
+ (BOOL)isFloatOID:(unsigned int)oid;

/// Returns YES if the OID represents a string / text type.
+ (BOOL)isStringOID:(unsigned int)oid;

/// Returns YES if the OID represents a date or time type.
+ (BOOL)isDateTimeOID:(unsigned int)oid;

@end
