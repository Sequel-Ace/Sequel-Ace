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

// ==================== NUMERIC TYPES ====================
#define SPPostgresSmallIntType      @"smallint"      // 2 bytes, -32768 to +32767
#define SPPostgresIntegerType       @"integer"       // 4 bytes, -2147483648 to +2147483647
#define SPPostgresBigIntType        @"bigint"        // 8 bytes, -9223372036854775808 to +9223372036854775807
#define SPPostgresDecimalType       @"decimal"       // variable, user-specified precision
#define SPPostgresNumericType       @"numeric"       // variable, user-specified precision (alias)
#define SPPostgresRealType          @"real"          // 4 bytes, 6 decimal digits precision
#define SPPostgresDoublePrecisionType @"double precision" // 8 bytes, 15 decimal digits precision
#define SPPostgresSmallSerialType   @"smallserial"   // 2 bytes, autoincrementing
#define SPPostgresSerialType        @"serial"        // 4 bytes, autoincrementing
#define SPPostgresBigSerialType     @"bigserial"     // 8 bytes, autoincrementing
#define SPPostgresMoneyType         @"money"         // 8 bytes, currency amount

// ==================== CHARACTER TYPES ====================
#define SPPostgresCharType          @"character"     // fixed-length, blank padded
#define SPPostgresVarCharType       @"character varying" // variable-length with limit
#define SPPostgresTextType          @"text"          // variable unlimited length

// ==================== BINARY TYPES ====================
#define SPPostgresByteaType         @"bytea"         // variable-length binary string

// ==================== DATE/TIME TYPES ====================
#define SPPostgresDateType          @"date"          // 4 bytes, date only
#define SPPostgresTimeType          @"time"          // 8 bytes, time without timezone
#define SPPostgresTimeTZType        @"time with time zone"  // 12 bytes, time with timezone
#define SPPostgresTimestampType     @"timestamp"     // 8 bytes, date and time without timezone
#define SPPostgresTimestampTZType   @"timestamp with time zone" // 8 bytes, date and time with timezone
#define SPPostgresIntervalType      @"interval"      // 16 bytes, time interval

// ==================== BOOLEAN TYPE ====================
#define SPPostgresBooleanType       @"boolean"       // true/false

// ==================== NETWORK TYPES ====================
#define SPPostgresCidrType          @"cidr"          // 7 or 19 bytes, IPv4/IPv6 network
#define SPPostgresInetType          @"inet"          // 7 or 19 bytes, IPv4/IPv6 host/network
#define SPPostgresMacAddrType       @"macaddr"       // 6 bytes, MAC address
#define SPPostgresMacAddr8Type      @"macaddr8"      // 8 bytes, MAC address (EUI-64)

// ==================== BIT STRING TYPES ====================
#define SPPostgresBitType           @"bit"           // fixed-length bit string
#define SPPostgresBitVaryingType    @"bit varying"   // variable-length bit string

// ==================== UUID TYPE ====================
#define SPPostgresUUIDType          @"uuid"          // 16 bytes, universally unique identifier

// ==================== JSON TYPES ====================
#define SPPostgresJSONType          @"json"          // textual JSON data
#define SPPostgresJSONBType         @"jsonb"         // binary JSON data, faster processing

// ==================== ARRAY TYPE ====================
#define SPPostgresArrayType         @"array"         // array of any type (use type[])

// ==================== GEOMETRIC TYPES ====================
#define SPPostgresPointType         @"point"         // geometric point
#define SPPostgresLineType          @"line"          // infinite line
#define SPPostgresLsegType          @"lseg"          // line segment
#define SPPostgresBoxType           @"box"           // rectangular box
#define SPPostgresPathType          @"path"          // geometric path
#define SPPostgresPolygonType       @"polygon"       // closed geometric path
#define SPPostgresCircleType        @"circle"        // circle

// ==================== RANGE TYPES ====================
#define SPPostgresInt4RangeType     @"int4range"     // range of integer
#define SPPostgresInt8RangeType     @"int8range"     // range of bigint
#define SPPostgresNumRangeType      @"numrange"      // range of numeric
#define SPPostgresTsRangeType       @"tsrange"       // range of timestamp without timezone
#define SPPostgresTsTZRangeType     @"tstzrange"     // range of timestamp with timezone
#define SPPostgresDateRangeType     @"daterange"     // range of date

// ==================== OTHER TYPES ====================
#define SPPostgresXMLType           @"xml"           // XML data
#define SPPostgresTsVectorType      @"tsvector"      // text search document
#define SPPostgresTsQueryType       @"tsquery"       // text search query

#endif /* SPPostgresDataTypes_h */
