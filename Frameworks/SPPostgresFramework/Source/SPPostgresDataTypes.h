//
//  SPPostgresDataTypes.h
//  SPPostgresFramework
//
//  Created by Mehmet Karabulut (mehmetik@gmail.com) on November 30, 2025.
//  Copyright (c) 2025 Mehmet Karabulut.
//  This software is released under the GPL License.
//  This is an open-source project forked from Sequel Ace.
//

#ifndef SPPostgresDataTypes_h
#define SPPostgresDataTypes_h

// Numeric types
#define SPPostgresTinyIntType       @"smallint"
#define SPPostgresSmallIntType      @"smallint"
#define SPPostgresMediumIntType     @"integer"
#define SPPostgresIntType           @"integer"
#define SPPostgresBigIntType        @"bigint"
#define SPPostgresFloatType         @"real"
#define SPPostgresDoubleType        @"double precision"
#define SPPostgresDoublePrecisionType @"double precision"
#define SPPostgresRealType          @"real"
#define SPPostgresDecimalType       @"decimal"
#define SPPostgresBitType           @"bit"
#define SPPostgresSerialType        @"serial"
#define SPPostgresBoolType          @"boolean"
#define SPPostgresBoolean           @"boolean"
#define SPPostgresDecType           @"decimal"
#define SPPostgresFixedType         @"numeric"
#define SPPostgresNumericType       @"numeric"

// String types
#define SPPostgresCharType          @"char"
#define SPPostgresVarCharType       @"varchar"
#define SPPostgresTinyTextType      @"text"
#define SPPostgresTextType          @"text"
#define SPPostgresMediumTextType    @"text"
#define SPPostgresLongTextType      @"text"

// Binary types
#define SPPostgresTinyBlobType      @"bytea"
#define SPPostgresMediumBlobType    @"bytea"
#define SPPostgresBlobType          @"bytea"
#define SPPostgresLongBlobType      @"bytea"
#define SPPostgresBinaryType        @"bytea"
#define SPPostgresVarBinaryType     @"bytea"

// Other types
#define SPPostgresJsonType          @"json"
#define SPPostgresEnumType          @"enum"
#define SPPostgresSetType           @"text[]"

// Date/Time types
#define SPPostgresDateType          @"date"
#define SPPostgresDatetimeType      @"timestamp"
#define SPPostgresTimestampType     @"timestamp"
#define SPPostgresTimeType          @"time"
#define SPPostgresYearType          @"integer"

// Geometry types
#define SPPostgresGeometryType      @"geometry"
#define SPPostgresPointType         @"point"
#define SPPostgresLineStringType    @"path"
#define SPPostgresPolygonType       @"polygon"
#define SPPostgresMultiPointType    @"geometry"
#define SPPostgresMultiLineStringType @"geometry"
#define SPPostgresMultiPolygonType  @"geometry"
#define SPPostgresGeometryCollectionType @"geometry"

#endif /* SPPostgresDataTypes_h */
