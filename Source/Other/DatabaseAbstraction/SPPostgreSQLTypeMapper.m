//
//  SPPostgreSQLTypeMapper.m
//  Sequel Ace
//
//  OID constants from PostgreSQL's pg_type.h (stable across versions).
//

#import "SPPostgreSQLTypeMapper.h"

// Common PostgreSQL type OIDs
static const unsigned int kPGOIDBool          = 16;
static const unsigned int kPGOIDBytea         = 17;
static const unsigned int kPGOIDChar          = 18;
static const unsigned int kPGOIDName          = 19;
static const unsigned int kPGOIDInt8          = 20;   // BIGINT
static const unsigned int kPGOIDInt2          = 21;   // SMALLINT
static const unsigned int kPGOIDInt4          = 23;   // INTEGER
static const unsigned int kPGOIDText          = 25;
static const unsigned int kPGOIDOID           = 26;
static const unsigned int kPGOIDFloat4        = 700;  // REAL
static const unsigned int kPGOIDFloat8        = 701;  // DOUBLE PRECISION
static const unsigned int kPGOIDMoney         = 790;
static const unsigned int kPGOIDVarchar       = 1043; // CHARACTER VARYING
static const unsigned int kPGOIDDate          = 1082;
static const unsigned int kPGOIDTime          = 1083;
static const unsigned int kPGOIDTimestamp     = 1114;
static const unsigned int kPGOIDTimestampTZ   = 1184;
static const unsigned int kPGOIDInterval      = 1186;
static const unsigned int kPGOIDTimeTZ        = 1266;
static const unsigned int kPGOIDBit           = 1560;
static const unsigned int kPGOIDVarbit        = 1562;
static const unsigned int kPGOIDNumeric       = 1700;
static const unsigned int kPGOIDUUID          = 2950;
static const unsigned int kPGOIDJSON          = 114;
static const unsigned int kPGOIDJSONB         = 3802;
static const unsigned int kPGOIDXML           = 142;
static const unsigned int kPGOIDInt2Array     = 1005;
static const unsigned int kPGOIDInt4Array     = 1007;
static const unsigned int kPGOIDTextArray     = 1009;
static const unsigned int kPGOIDVarcharArray  = 1015;
static const unsigned int kPGOIDInt8Array     = 1016;
static const unsigned int kPGOIDFloat4Array   = 1021;
static const unsigned int kPGOIDFloat8Array   = 1022;

@implementation SPPostgreSQLTypeMapper

+ (NSString *)typeNameForOID:(unsigned int)oid {
    switch (oid) {
        case 16:   return @"BOOLEAN";
        case 17:   return @"BYTEA";
        case 18:   return @"CHAR";
        case 19:   return @"NAME";
        case 20:   return @"BIGINT";
        case 21:   return @"SMALLINT";
        case 23:   return @"INTEGER";
        case 25:   return @"TEXT";
        case 26:   return @"OID";
        case 114:  return @"JSON";
        case 142:  return @"XML";
        case 700:  return @"REAL";
        case 701:  return @"DOUBLE PRECISION";
        case 790:  return @"MONEY";
        case 1005: return @"SMALLINT[]";
        case 1007: return @"INTEGER[]";
        case 1009: return @"TEXT[]";
        case 1015: return @"VARCHAR[]";
        case 1016: return @"BIGINT[]";
        case 1021: return @"REAL[]";
        case 1022: return @"DOUBLE PRECISION[]";
        case 1042: return @"CHAR(n)";
        case 1043: return @"VARCHAR";
        case 1082: return @"DATE";
        case 1083: return @"TIME";
        case 1114: return @"TIMESTAMP";
        case 1184: return @"TIMESTAMPTZ";
        case 1186: return @"INTERVAL";
        case 1266: return @"TIMETZ";
        case 1560: return @"BIT";
        case 1562: return @"VARBIT";
        case 1700: return @"NUMERIC";
        case 2950: return @"UUID";
        case 3802: return @"JSONB";
        default:   return [NSString stringWithFormat:@"OID(%u)", oid];
    }
}

+ (BOOL)isIntegerOID:(unsigned int)oid {
    return oid == kPGOIDInt2 || oid == kPGOIDInt4 || oid == kPGOIDInt8
        || oid == kPGOIDOID  || oid == 2278 /* void */;
}

+ (BOOL)isFloatOID:(unsigned int)oid {
    return oid == kPGOIDFloat4 || oid == kPGOIDFloat8 || oid == kPGOIDNumeric || oid == kPGOIDMoney;
}

+ (BOOL)isStringOID:(unsigned int)oid {
    return oid == kPGOIDText || oid == kPGOIDVarchar || oid == kPGOIDChar
        || oid == kPGOIDName || oid == kPGOIDXML;
}

+ (BOOL)isDateTimeOID:(unsigned int)oid {
    return oid == kPGOIDDate || oid == kPGOIDTime || oid == kPGOIDTimeTZ
        || oid == kPGOIDTimestamp || oid == kPGOIDTimestampTZ || oid == kPGOIDInterval;
}

@end
