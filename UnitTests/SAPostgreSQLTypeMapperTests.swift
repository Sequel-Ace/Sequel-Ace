//
//  SAPostgreSQLTypeMapperTests.swift
//  Unit Tests
//

import XCTest

final class SAPostgreSQLTypeMapperTests: XCTestCase {

    func testKnownOIDs() {
        XCTAssertEqual(SPPostgreSQLTypeMapper.typeName(forOID: 23), "INTEGER")
        XCTAssertEqual(SPPostgreSQLTypeMapper.typeName(forOID: 25), "TEXT")
        XCTAssertEqual(SPPostgreSQLTypeMapper.typeName(forOID: 16), "BOOLEAN")
        XCTAssertEqual(SPPostgreSQLTypeMapper.typeName(forOID: 700), "REAL")
        XCTAssertEqual(SPPostgreSQLTypeMapper.typeName(forOID: 701), "DOUBLE PRECISION")
        XCTAssertEqual(SPPostgreSQLTypeMapper.typeName(forOID: 1700), "NUMERIC")
        XCTAssertEqual(SPPostgreSQLTypeMapper.typeName(forOID: 1114), "TIMESTAMP")
        XCTAssertEqual(SPPostgreSQLTypeMapper.typeName(forOID: 1082), "DATE")
    }

    func testUnknownOIDReturnsFallback() {
        let name = SPPostgreSQLTypeMapper.typeName(forOID: 99999)
        XCTAssertTrue(name.hasPrefix("OID("))
    }

    func testIntegerCategorisation() {
        XCTAssertTrue(SPPostgreSQLTypeMapper.isInteger(oid: 23))
        XCTAssertTrue(SPPostgreSQLTypeMapper.isInteger(oid: 20))
        XCTAssertTrue(SPPostgreSQLTypeMapper.isInteger(oid: 21))
        XCTAssertFalse(SPPostgreSQLTypeMapper.isInteger(oid: 25))
    }

    func testFloatCategorisation() {
        XCTAssertTrue(SPPostgreSQLTypeMapper.isFloat(oid: 700))
        XCTAssertTrue(SPPostgreSQLTypeMapper.isFloat(oid: 701))
        XCTAssertTrue(SPPostgreSQLTypeMapper.isFloat(oid: 1700))
    }

    func testStringCategorisation() {
        XCTAssertTrue(SPPostgreSQLTypeMapper.isString(oid: 25))
        XCTAssertTrue(SPPostgreSQLTypeMapper.isString(oid: 1043))
    }

    func testDateTimeCategorisation() {
        XCTAssertTrue(SPPostgreSQLTypeMapper.isDateTime(oid: 1114))
        XCTAssertTrue(SPPostgreSQLTypeMapper.isDateTime(oid: 1082))
        XCTAssertTrue(SPPostgreSQLTypeMapper.isDateTime(oid: 1083))
    }

    func testMySQLWrapperReportsNotPostgreSQL() {
        let wrapper = SPMySQLConnectionWrapper(connection: SPMySQLConnection())
        XCTAssertFalse(wrapper.isPostgreSQL())
    }

    func testPostgreSQLWrapperReportsPostgreSQL() {
        let wrapper = SPPostgreSQLConnectionWrapper()
        XCTAssertTrue(wrapper.isPostgreSQL())
    }
}
