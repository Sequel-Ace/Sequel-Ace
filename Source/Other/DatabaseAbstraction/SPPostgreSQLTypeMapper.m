//
//  SPPostgreSQLTypeMapper.m
//  Sequel Ace
//
//  Created by Sequel Ace on 2024.
//  Copyright (c) 2024 Sequel Ace. All rights reserved.
//

#import "SPPostgreSQLTypeMapper.h"

@implementation SPPostgreSQLTypeMapper

+ (NSString *)typeNameForOID:(uint32_t)oid {
    // PostgreSQL built-in type OIDs from pg_type.dat
    // Reference: https://github.com/postgres/postgres/blob/master/src/include/catalog/pg_type.dat
    
    switch (oid) {
        // Boolean
        case 16: return @"bool";
        
        // Integers
        case 20: return @"bigint";
        case 21: return @"smallint";
        case 23: return @"integer";
        
        // Floating point
        case 700: return @"real";
        case 701: return @"double precision";
        case 1700: return @"numeric";
        
        // Character types
        case 18: return @"char";
        case 19: return @"name";
        case 25: return @"text";
        case 1042: return @"char";
        case 1043: return @"varchar";
        
        // Binary
        case 17: return @"bytea";
        
        // Date/Time
        case 1082: return @"date";
        case 1083: return @"time";
        case 1114: return @"timestamp";
        case 1184: return @"timestamptz";
        case 1186: return @"interval";
        case 1266: return @"timetz";
        
        // Network types
        case 869: return @"inet";
        case 650: return @"cidr";
        case 829: return @"macaddr";
        case 774: return @"macaddr8";
        
        // Bit strings
        case 1560: return @"bit";
        case 1562: return @"varbit";
        
        // UUID
        case 2950: return @"uuid";
        
        // JSON
        case 114: return @"json";
        case 3802: return @"jsonb";
        
        // XML
        case 142: return @"xml";
        
        // Geometric types
        case 600: return @"point";
        case 601: return @"lseg";
        case 602: return @"path";
        case 603: return @"box";
        case 604: return @"polygon";
        case 628: return @"line";
        case 718: return @"circle";
        
        // Money
        case 790: return @"money";
        
        // Arrays (some common ones)
        case 1007: return @"_int4";
        case 1016: return @"_int8";
        case 1009: return @"_text";
        case 1015: return @"_varchar";
        case 1182: return @"_date";
        case 1185: return @"_timestamptz";
        case 2951: return @"_uuid";
        
        // Range types
        case 3904: return @"int4range";
        case 3926: return @"int8range";
        case 3906: return @"numrange";
        case 3908: return @"tsrange";
        case 3910: return @"tstzrange";
        case 3912: return @"daterange";
        
        // Other common types
        case 2205: return @"regclass";
        case 3614: return @"tsvector";
        case 3615: return @"tsquery";
        case 26: return @"oid";
        
        default:
            // Unknown type, return text as fallback
            return @"text";
    }
}

+ (NSString *)typeGroupingForOID:(uint32_t)oid {
    // Group types similar to MySQL's type groupings
    // This helps the UI treat similar types consistently
    
    switch (oid) {
        // Boolean
        case 16:
            return @"integer";  // Treat boolean as integer for consistency
        
        // Integers
        case 20:  // bigint
        case 21:  // smallint
        case 23:  // integer
        case 26:  // oid
            return @"integer";
        
        // Floating point
        case 700:  // real
        case 701:  // double precision
        case 1700: // numeric
        case 790:  // money
            return @"float";
        
        // Character types
        case 18:   // char
        case 19:   // name
        case 25:   // text
        case 1042: // bpchar
        case 1043: // varchar
        case 142:  // xml
            return @"string";
        
        // Binary
        case 17:   // bytea
            return @"binary";
        
        // Date/Time
        case 1082: // date
        case 1083: // time
        case 1114: // timestamp
        case 1184: // timestamptz
        case 1186: // interval
        case 1266: // timetz
            return @"date";
        
        // JSON
        case 114:  // json
        case 3802: // jsonb
            return @"textdata";  // Use textdata for structured text
        
        // UUID
        case 2950: // uuid
            return @"string";
        
        // Network types
        case 869:  // inet
        case 650:  // cidr
        case 829:  // macaddr
        case 774:  // macaddr8
            return @"string";
        
        // Bit strings
        case 1560: // bit
        case 1562: // varbit
            return @"binary";
        
        // Geometric types
        case 600:  // point
        case 601:  // lseg
        case 602:  // path
        case 603:  // box
        case 604:  // polygon
        case 628:  // line
        case 718:  // circle
            return @"geometry";
        
        // Arrays
        case 1007: // _int4
        case 1016: // _int8
        case 1009: // _text
        case 1015: // _varchar
        case 1182: // _date
        case 1185: // _timestamptz
        case 2951: // _uuid
            return @"string";  // Treat arrays as strings for now
        
        // Range types
        case 3904: // int4range
        case 3926: // int8range
        case 3906: // numrange
        case 3908: // tsrange
        case 3910: // tstzrange
        case 3912: // daterange
            return @"string";
        
        // Text search
        case 3614: // tsvector
        case 3615: // tsquery
            return @"textdata";
        
        // Other
        case 2205: // regclass
            return @"string";
        
        default:
            // Unknown type, use string as fallback
            return @"string";
    }
}

@end

