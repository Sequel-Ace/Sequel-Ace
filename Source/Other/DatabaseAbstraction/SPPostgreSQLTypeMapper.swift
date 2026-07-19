//
//  SPPostgreSQLTypeMapper.swift
//  Sequel Ace
//

import Foundation

@objc(SPPostgreSQLTypeMapper)
final class SPPostgreSQLTypeMapper: NSObject {

    private static let oidBool: UInt32 = 16
    private static let oidInt8: UInt32 = 20
    private static let oidInt2: UInt32 = 21
    private static let oidInt4: UInt32 = 23
    private static let oidText: UInt32 = 25
    private static let oidFloat4: UInt32 = 700
    private static let oidFloat8: UInt32 = 701
    private static let oidMoney: UInt32 = 790
    private static let oidVarchar: UInt32 = 1043
    private static let oidDate: UInt32 = 1082
    private static let oidTime: UInt32 = 1083
    private static let oidTimestamp: UInt32 = 1114
    private static let oidTimestampTZ: UInt32 = 1184
    private static let oidInterval: UInt32 = 1186
    private static let oidTimeTZ: UInt32 = 1266
    private static let oidNumeric: UInt32 = 1700

    @objc(typeNameForOID:)
    static func typeName(forOID oid: UInt32) -> String {
        switch oid {
        case 16: return "BOOLEAN"
        case 17: return "BYTEA"
        case 18: return "CHAR"
        case 19: return "NAME"
        case 20: return "BIGINT"
        case 21: return "SMALLINT"
        case 23: return "INTEGER"
        case 25: return "TEXT"
        case 26: return "OID"
        case 114: return "JSON"
        case 142: return "XML"
        case 700: return "REAL"
        case 701: return "DOUBLE PRECISION"
        case 790: return "MONEY"
        case 1005: return "SMALLINT[]"
        case 1007: return "INTEGER[]"
        case 1009: return "TEXT[]"
        case 1015: return "VARCHAR[]"
        case 1016: return "BIGINT[]"
        case 1021: return "REAL[]"
        case 1022: return "DOUBLE PRECISION[]"
        case 1042: return "CHAR(n)"
        case 1043: return "VARCHAR"
        case 1082: return "DATE"
        case 1083: return "TIME"
        case 1114: return "TIMESTAMP"
        case 1184: return "TIMESTAMPTZ"
        case 1186: return "INTERVAL"
        case 1266: return "TIMETZ"
        case 1560: return "BIT"
        case 1562: return "VARBIT"
        case 1700: return "NUMERIC"
        case 2950: return "UUID"
        case 3802: return "JSONB"
        default: return "OID(\(oid))"
        }
    }

    @objc(isIntegerOID:)
    static func isInteger(oid: UInt32) -> Bool {
        oid == oidInt2 || oid == oidInt4 || oid == oidInt8 || oid == 26 || oid == 2278
    }

    @objc(isFloatOID:)
    static func isFloat(oid: UInt32) -> Bool {
        oid == oidFloat4 || oid == oidFloat8 || oid == oidNumeric || oid == oidMoney
    }

    @objc(isStringOID:)
    static func isString(oid: UInt32) -> Bool {
        oid == oidText || oid == oidVarchar || oid == 18 || oid == 19 || oid == 142
    }

    @objc(isDateTimeOID:)
    static func isDateTime(oid: UInt32) -> Bool {
        oid == oidDate || oid == oidTime || oid == oidTimeTZ
            || oid == oidTimestamp || oid == oidTimestampTZ || oid == oidInterval
    }
}
