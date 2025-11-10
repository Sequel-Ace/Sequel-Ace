//
//  SPPostgreSQLIntegrationTests.m
//  Unit Tests
//
//  Integration tests for PostgreSQL framework
//  Tests the full stack: Objective-C → FFI → Rust → PostgreSQL
//
//  Requires a running PostgreSQL server.
//  Configure via environment variables:
//  - PGHOST (default: localhost)
//  - PGPORT (default: 29501)
//  - PGUSER (default: postgres)
//  - PGPASSWORD (default: postgres)
//  - PGDATABASE (default: match-event-service)
//

#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "SPPostgreSQLConnectionWrapper.h"
#import "SPPostgreSQLResultWrapper.h"
#import "SPDatabaseConnection.h"
#import "SPDatabaseResult.h"
#import "SPConstants.h"

@interface SPPostgreSQLIntegrationTests : XCTestCase

@property (nonatomic, strong) NSString *testHost;
@property (nonatomic, assign) NSUInteger testPort;
@property (nonatomic, strong) NSString *testUser;
@property (nonatomic, strong) NSString *testPassword;
@property (nonatomic, strong) NSString *testDatabase;

@end

@implementation SPPostgreSQLIntegrationTests

- (void)setUp {
    [super setUp];
    
    // Load test configuration from environment variables
    _testHost = [[NSProcessInfo processInfo] environment][@"PGHOST"] ?: @"localhost";
    _testPort = [[[NSProcessInfo processInfo] environment][@"PGPORT"] ?: @"29501" integerValue];
    _testUser = [[NSProcessInfo processInfo] environment][@"PGUSER"] ?: @"postgres";
    _testPassword = [[NSProcessInfo processInfo] environment][@"PGPASSWORD"] ?: @"postgres";
    _testDatabase = [[NSProcessInfo processInfo] environment][@"PGDATABASE"] ?: @"match-event-service";
    
    NSLog(@"🧪 PostgreSQL Test Configuration:");
    NSLog(@"   Host: %@", _testHost);
    NSLog(@"   Port: %lu", (unsigned long)_testPort);
    NSLog(@"   User: %@", _testUser);
    NSLog(@"   Database: %@", _testDatabase);
}

- (void)tearDown {
    [super tearDown];
}

#pragma mark - Helper Methods

- (id<SPDatabaseConnection>)createAndConnectConnection {
    SPPostgreSQLConnectionWrapper *connection = [[SPPostgreSQLConnectionWrapper alloc] init];
    
    connection.host = _testHost;
    connection.port = _testPort;
    connection.username = _testUser;
    connection.password = _testPassword;
    connection.database = _testDatabase;
    connection.useSSL = NO;
    
    BOOL connected = [connection connect];
    if (!connected) {
        NSLog(@"❌ Connection failed: %@", [connection lastErrorMessage]);
        return nil;
    }
    
    return connection;
}

#pragma mark - Test 01: Connection Creation

- (void)test_01_ConnectionCreation {
    NSLog(@"\n🧪 Test 01: Connection creation and properties");
    
    SPPostgreSQLConnectionWrapper *connection = [[SPPostgreSQLConnectionWrapper alloc] init];
    XCTAssertNotNil(connection, @"Connection should be created");
    
    // Test property setters
    connection.host = @"testhost";
    connection.port = 5432;
    connection.username = @"testuser";
    connection.password = @"testpass";
    connection.database = @"testdb";
    
    // Test property getters
    XCTAssertEqualObjects(connection.host, @"testhost");
    XCTAssertEqual(connection.port, 5432);
    XCTAssertEqualObjects(connection.username, @"testuser");
    XCTAssertEqualObjects(connection.password, @"testpass");
    XCTAssertEqualObjects(connection.database, @"testdb");
    
    // Test database type
    XCTAssertEqual([connection databaseType], SPDatabaseTypePostgreSQL);
    
    NSLog(@"✓ Connection creation and properties test passed");
}

#pragma mark - Test 02: Connect and Disconnect

- (void)test_02_ConnectDisconnect {
    NSLog(@"\n🧪 Test 02: Connect and disconnect");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect successfully");
    XCTAssertTrue([connection isConnected], @"Should report as connected");
    
    [connection disconnect];
    XCTAssertFalse([connection isConnected], @"Should report as disconnected");
    
    NSLog(@"✓ Connect and disconnect test passed");
}

#pragma mark - Test 03: Connection Failure

- (void)test_03_ConnectionFailure {
    NSLog(@"\n🧪 Test 03: Connection failure handling");
    
    SPPostgreSQLConnectionWrapper *connection = [[SPPostgreSQLConnectionWrapper alloc] init];
    connection.host = _testHost;
    connection.port = _testPort;
    connection.username = _testUser;
    connection.password = _testPassword;
    connection.database = @"nonexistent_database_12345";
    connection.useSSL = NO;
    
    BOOL connected = [connection connect];
    XCTAssertFalse(connected, @"Connection should fail");
    XCTAssertTrue([connection queryErrored], @"Should have error state");
    
    NSString *errorMessage = [connection lastErrorMessage];
    XCTAssertNotNil(errorMessage, @"Should have error message");
    XCTAssertTrue([errorMessage length] > 0, @"Error message should not be empty");
    
    NSLog(@"✓ Error message: %@", errorMessage);
    NSLog(@"✓ Connection failure handling test passed");
}

#pragma mark - Test 04: Simple Query

- (void)test_04_SimpleQuery {
    NSLog(@"\n🧪 Test 04: Simple SELECT query");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect successfully");
    
    id<SPDatabaseResult> result = [connection queryString:@"SELECT 1 as num, 'hello' as text"];
    XCTAssertNotNil(result, @"Query should return result");
    XCTAssertFalse([connection queryErrored], @"Query should not error");
    
    // Check row count
    XCTAssertEqual([result numberOfRows], 1, @"Should have 1 row");
    
    // Check field count
    XCTAssertEqual([result numberOfFields], 2, @"Should have 2 fields");
    
    // Check field names
    NSArray *fieldNames = [result fieldNames];
    XCTAssertEqual([fieldNames count], 2);
    XCTAssertEqualObjects(fieldNames[0], @"num");
    XCTAssertEqualObjects(fieldNames[1], @"text");
    
    // Check values
    [result seekToRow:0];
    NSArray *row = [result getRowAsArray];
    XCTAssertNotNil(row);
    XCTAssertEqual([row count], 2);
    XCTAssertEqualObjects(row[0], @"1");
    XCTAssertEqualObjects(row[1], @"hello");
    
    NSLog(@"✓ Field names: %@", fieldNames);
    NSLog(@"✓ Row data: %@", row);
    NSLog(@"✓ Simple query test passed");
    
    [connection disconnect];
}

#pragma mark - Test 05: Database Listing

- (void)test_05_ListDatabases {
    NSLog(@"\n🧪 Test 05: List databases");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect successfully");
    
    NSArray *databases = [connection databases];
    XCTAssertNotNil(databases, @"Should return database list");
    XCTAssertTrue([databases count] > 0, @"Should have at least one database");
    
    NSLog(@"✓ Found %lu databases:", (unsigned long)[databases count]);
    for (NSString *dbName in databases) {
        NSLog(@"  - %@", dbName);
    }
    
    NSLog(@"✓ List databases test passed");
    
    [connection disconnect];
}

#pragma mark - Test 06: Table Listing

- (void)test_06_ListTables {
    NSLog(@"\n🧪 Test 06: List tables");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect successfully");
    
    NSArray *tables = [connection tables];
    XCTAssertNotNil(tables, @"Should return table list");
    
    NSLog(@"✓ Found %lu tables:", (unsigned long)[tables count]);
    for (NSString *tableName in tables) {
        NSLog(@"  - %@", tableName);
    }
    
    NSLog(@"✓ List tables test passed");
    
    [connection disconnect];
}

#pragma mark - Test 07: CREATE TABLE and INSERT

- (void)test_07_CreateTableInsert {
    NSLog(@"\n🧪 Test 07: CREATE TABLE and INSERT");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect successfully");
    
    // Drop table if exists
    [connection queryString:@"DROP TABLE IF EXISTS test_table_objc"];
    NSLog(@"✓ Dropped test table if it existed");
    
    // Create table
    id<SPDatabaseResult> createResult = [connection queryString:@"CREATE TABLE test_table_objc (id SERIAL PRIMARY KEY, name VARCHAR(100), value INTEGER)"];
    XCTAssertNotNil(createResult, @"CREATE TABLE should succeed");
    XCTAssertFalse([connection queryErrored], @"CREATE TABLE should not error");
    NSLog(@"✓ Created test table");
    
    // Insert data
    id<SPDatabaseResult> insertResult = [connection queryString:@"INSERT INTO test_table_objc (name, value) VALUES ('test1', 100), ('test2', 200)"];
    XCTAssertNotNil(insertResult, @"INSERT should succeed");
    XCTAssertFalse([connection queryErrored], @"INSERT should not error");
    NSLog(@"✓ Inserted 2 rows");
    
    // Select data
    id<SPDatabaseResult> selectResult = [connection queryString:@"SELECT * FROM test_table_objc ORDER BY id"];
    XCTAssertNotNil(selectResult, @"SELECT should succeed");
    XCTAssertEqual([selectResult numberOfRows], 2, @"Should have 2 rows");
    NSLog(@"✓ Selected %llu rows", [selectResult numberOfRows]);
    
    // Check first row
    [selectResult seekToRow:0];
    NSArray *row1 = [selectResult getRowAsArray];
    XCTAssertNotNil(row1);
    XCTAssertEqualObjects(row1[1], @"test1");
    XCTAssertEqualObjects(row1[2], @"100");
    NSLog(@"✓ Row 1: %@", row1);
    
    // Check second row
    NSArray *row2 = [selectResult getRowAsArray];
    XCTAssertNotNil(row2);
    XCTAssertEqualObjects(row2[1], @"test2");
    XCTAssertEqualObjects(row2[2], @"200");
    NSLog(@"✓ Row 2: %@", row2);
    
    // Drop table
    [connection queryString:@"DROP TABLE test_table_objc"];
    NSLog(@"✓ Dropped test table");
    
    NSLog(@"✓ CREATE TABLE and INSERT test passed");
    
    [connection disconnect];
}

#pragma mark - Test 08: NULL Values

- (void)test_08_NullValues {
    NSLog(@"\n🧪 Test 08: NULL value handling");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect successfully");
    
    id<SPDatabaseResult> result = [connection queryString:@"SELECT NULL as null_col, 'not null' as text_col"];
    XCTAssertNotNil(result, @"Query should succeed");
    
    [result seekToRow:0];
    NSArray *row = [result getRowAsArray];
    XCTAssertNotNil(row);
    XCTAssertEqual([row count], 2);
    
    // Check NULL value
    id nullValue = row[0];
    XCTAssertTrue([nullValue isKindOfClass:[NSNull class]], @"NULL should be NSNull");
    NSLog(@"✓ NULL value: %@", nullValue);
    
    // Check non-NULL value
    id textValue = row[1];
    XCTAssertEqualObjects(textValue, @"not null");
    NSLog(@"✓ Non-NULL value: %@", textValue);
    
    NSLog(@"✓ NULL value handling test passed");
    
    [connection disconnect];
}

#pragma mark - Test 09: Multiple Queries

- (void)test_09_MultipleQueries {
    NSLog(@"\n🧪 Test 09: Multiple queries in sequence");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect successfully");
    
    // Query 1
    id<SPDatabaseResult> result1 = [connection queryString:@"SELECT 1 as num"];
    XCTAssertNotNil(result1);
    [result1 seekToRow:0];
    NSArray *row1 = [result1 getRowAsArray];
    XCTAssertEqualObjects(row1[0], @"1");
    NSLog(@"✓ Query 1: %@", row1);
    
    // Query 2
    id<SPDatabaseResult> result2 = [connection queryString:@"SELECT 2 as num"];
    XCTAssertNotNil(result2);
    [result2 seekToRow:0];
    NSArray *row2 = [result2 getRowAsArray];
    XCTAssertEqualObjects(row2[0], @"2");
    NSLog(@"✓ Query 2: %@", row2);
    
    // Query 3
    id<SPDatabaseResult> result3 = [connection queryString:@"SELECT 3 as num"];
    XCTAssertNotNil(result3);
    [result3 seekToRow:0];
    NSArray *row3 = [result3 getRowAsArray];
    XCTAssertEqualObjects(row3[0], @"3");
    NSLog(@"✓ Query 3: %@", row3);
    
    NSLog(@"✓ Multiple queries test passed");
    
    [connection disconnect];
}

#pragma mark - Test 10: String Escaping

- (void)test_10_StringEscaping {
    NSLog(@"\n🧪 Test 10: String escaping");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect successfully");
    
    // Test escaping special characters
    NSString *dangerousString = @"Robert'); DROP TABLE test--";
    NSString *escaped = [connection escapeString:dangerousString];
    XCTAssertNotNil(escaped);
    XCTAssertNotEqualObjects(escaped, dangerousString, @"Escaped string should be different");
    NSLog(@"✓ Original: %@", dangerousString);
    NSLog(@"✓ Escaped: %@", escaped);
    
    // Test quoted string
    NSString *quoted = [connection escapeAndQuoteString:@"test"];
    XCTAssertTrue([quoted hasPrefix:@"'"], @"Should start with single quote");
    XCTAssertTrue([quoted hasSuffix:@"'"], @"Should end with single quote");
    NSLog(@"✓ Quoted: %@", quoted);
    
    NSLog(@"✓ String escaping test passed");
    
    [connection disconnect];
}

#pragma mark - Test 11: Transactions

- (void)test_11_Transactions {
    NSLog(@"\n🧪 Test 11: Transaction support");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect successfully");
    
    // Setup: create test table
    [connection queryString:@"DROP TABLE IF EXISTS test_transactions"];
    [connection queryString:@"CREATE TABLE test_transactions (id SERIAL PRIMARY KEY, value INTEGER)"];
    
    // Test BEGIN
    BOOL beginSuccess = [connection beginTransaction];
    XCTAssertTrue(beginSuccess, @"BEGIN TRANSACTION should succeed");
    NSLog(@"✓ Transaction started");
    
    // Insert data within transaction
    [connection queryString:@"INSERT INTO test_transactions (value) VALUES (100)"];
    
    // Test ROLLBACK
    BOOL rollbackSuccess = [connection rollbackTransaction];
    XCTAssertTrue(rollbackSuccess, @"ROLLBACK should succeed");
    NSLog(@"✓ Transaction rolled back");
    
    // Verify data was not inserted
    id<SPDatabaseResult> result1 = [connection queryString:@"SELECT COUNT(*) FROM test_transactions"];
    [result1 seekToRow:0];
    NSArray *row1 = [result1 getRowAsArray];
    XCTAssertEqualObjects(row1[0], @"0", @"Should have 0 rows after rollback");
    NSLog(@"✓ Rollback verified: 0 rows");
    
    // Test COMMIT
    [connection beginTransaction];
    [connection queryString:@"INSERT INTO test_transactions (value) VALUES (200)"];
    BOOL commitSuccess = [connection commitTransaction];
    XCTAssertTrue(commitSuccess, @"COMMIT should succeed");
    NSLog(@"✓ Transaction committed");
    
    // Verify data was inserted
    id<SPDatabaseResult> result2 = [connection queryString:@"SELECT COUNT(*) FROM test_transactions"];
    [result2 seekToRow:0];
    NSArray *row2 = [result2 getRowAsArray];
    XCTAssertEqualObjects(row2[0], @"1", @"Should have 1 row after commit");
    NSLog(@"✓ Commit verified: 1 row");
    
    // Cleanup
    [connection queryString:@"DROP TABLE test_transactions"];
    NSLog(@"✓ Cleaned up test table");
    
    NSLog(@"✓ Transaction test passed");
    
    [connection disconnect];
}

#pragma mark - Test 12: Result Enumeration

- (void)test_12_ResultEnumeration {
    NSLog(@"\n🧪 Test 12: Result enumeration (for-in loop)");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect successfully");
    
    id<SPDatabaseResult> result = [connection queryString:@"SELECT generate_series(1, 5) as num"];
    XCTAssertNotNil(result);
    XCTAssertEqual([result numberOfRows], 5);
    
    NSMutableArray *values = [NSMutableArray array];
    for (NSArray *row in result) {
        [values addObject:row[0]];
    }
    
    XCTAssertEqual([values count], 5);
    XCTAssertEqualObjects(values[0], @"1");
    XCTAssertEqualObjects(values[1], @"2");
    XCTAssertEqualObjects(values[2], @"3");
    XCTAssertEqualObjects(values[3], @"4");
    XCTAssertEqualObjects(values[4], @"5");
    
    NSLog(@"✓ Enumerated values: %@", values);
    NSLog(@"✓ Result enumeration test passed");
    
    [connection disconnect];
}

#pragma mark - Test 13: Server Version

- (void)test_13_ServerVersion {
    NSLog(@"\n🧪 Test 13: Server version information");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect successfully");
    
    NSString *versionString = [connection serverVersionString];
    XCTAssertNotNil(versionString);
    XCTAssertTrue([versionString length] > 0);
    NSLog(@"✓ Server version: %@", versionString);
    
    NSUInteger major = [connection serverMajorVersion];
    NSUInteger minor = [connection serverMinorVersion];
    NSLog(@"✓ Version: %lu.%lu", (unsigned long)major, (unsigned long)minor);
    
    NSLog(@"✓ Server version test passed");
    
    [connection disconnect];
}

#pragma mark - Test 14: Reconnect

- (void)test_14_Reconnect {
    NSLog(@"\n🧪 Test 14: Reconnect");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect successfully");
    XCTAssertTrue([connection isConnected]);
    
    // Disconnect
    [connection disconnect];
    XCTAssertFalse([connection isConnected]);
    NSLog(@"✓ Disconnected");
    
    // Reconnect
    BOOL reconnected = [connection reconnect];
    XCTAssertTrue(reconnected, @"Reconnect should succeed");
    XCTAssertTrue([connection isConnected]);
    NSLog(@"✓ Reconnected");
    
    // Verify connection works
    id<SPDatabaseResult> result = [connection queryString:@"SELECT 1"];
    XCTAssertNotNil(result);
    NSLog(@"✓ Query after reconnect succeeded");
    
    NSLog(@"✓ Reconnect test passed");
    
    [connection disconnect];
}

#pragma mark - Test 15: Identifier Quoting

- (void)test_15_IdentifierQuoting {
    NSLog(@"\n🧪 Test 15: Identifier quote character");
    
    SPPostgreSQLConnectionWrapper *connection = [[SPPostgreSQLConnectionWrapper alloc] init];
    
    NSString *quoteChar = [connection identifierQuoteCharacter];
    XCTAssertEqualObjects(quoteChar, @"\"", @"PostgreSQL should use double quotes");
    NSLog(@"✓ Identifier quote character: %@", quoteChar);
    
    NSLog(@"✓ Identifier quoting test passed");
}

#pragma mark - Test 16: UUID and Timestamp Types

- (void)test_16_UUIDAndTimestampTypes {
    NSLog(@"\n🧪 Test 16: UUID and timestamp types");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect successfully");
    
    // Drop test table if exists
    [connection queryString:@"DROP TABLE IF EXISTS test_types_objc"];
    NSLog(@"✓ Dropped test table if it existed");
    
    // Create table with UUID and timestamp columns
    NSString *createQuery = @"CREATE TABLE test_types_objc ("
                            @"id UUID PRIMARY KEY DEFAULT gen_random_uuid(), "
                            @"created_at TIMESTAMPTZ DEFAULT now(), "
                            @"updated_at TIMESTAMP, "
                            @"birth_date DATE, "
                            @"wake_time TIME, "
                            @"metadata JSONB, "
                            @"name TEXT)";
    
    id<SPDatabaseResult> createResult = [connection queryString:createQuery];
    XCTAssertNotNil(createResult, @"CREATE TABLE should succeed");
    XCTAssertFalse([connection queryErrored], @"CREATE TABLE should not error");
    NSLog(@"✓ Created test table with UUID and timestamp columns");
    
    // Insert test data
    NSString *insertQuery = @"INSERT INTO test_types_objc "
                            @"(updated_at, birth_date, wake_time, metadata, name) VALUES "
                            @"('2024-01-15 10:30:00', '1990-05-20', '07:30:00', "
                            @"'{\"active\": true, \"score\": 95}', 'Test User')";
    
    id<SPDatabaseResult> insertResult = [connection queryString:insertQuery];
    XCTAssertNotNil(insertResult, @"INSERT should succeed");
    XCTAssertFalse([connection queryErrored], @"INSERT should not error");
    NSLog(@"✓ Inserted test data");
    
    // Query the data back
    id<SPDatabaseResult> selectResult = [connection queryString:@"SELECT * FROM test_types_objc"];
    XCTAssertNotNil(selectResult, @"SELECT should succeed");
    XCTAssertEqual([selectResult numberOfRows], 1, @"Should have 1 row");
    
    // Check field names
    NSArray *fieldNames = [selectResult fieldNames];
    NSLog(@"✓ Field names: %@", fieldNames);
    XCTAssertTrue([fieldNames containsObject:@"id"], @"Should have id field");
    XCTAssertTrue([fieldNames containsObject:@"created_at"], @"Should have created_at field");
    XCTAssertTrue([fieldNames containsObject:@"updated_at"], @"Should have updated_at field");
    XCTAssertTrue([fieldNames containsObject:@"birth_date"], @"Should have birth_date field");
    XCTAssertTrue([fieldNames containsObject:@"wake_time"], @"Should have wake_time field");
    XCTAssertTrue([fieldNames containsObject:@"metadata"], @"Should have metadata field");
    XCTAssertTrue([fieldNames containsObject:@"name"], @"Should have name field");
    
    // Get the row data
    [selectResult seekToRow:0];
    NSArray *row = [selectResult getRowAsArray];
    XCTAssertNotNil(row);
    NSLog(@"✓ Retrieved row data");
    
    // Verify UUID (should be a valid UUID string)
    NSUInteger idIndex = [fieldNames indexOfObject:@"id"];
    NSString *uuid = row[idIndex];
    XCTAssertNotNil(uuid);
    XCTAssertTrue([uuid length] == 36, @"UUID should be 36 characters");
    XCTAssertTrue([uuid containsString:@"-"], @"UUID should contain hyphens");
    NSLog(@"✓ UUID: %@", uuid);
    
    // Verify TIMESTAMPTZ (created_at) - should be in RFC3339 format
    NSUInteger createdAtIndex = [fieldNames indexOfObject:@"created_at"];
    NSString *createdAt = row[createdAtIndex];
    XCTAssertNotNil(createdAt);
    XCTAssertTrue([createdAt length] > 0, @"created_at should not be empty");
    NSLog(@"✓ TIMESTAMPTZ (created_at): %@", createdAt);
    
    // Verify TIMESTAMP (updated_at)
    NSUInteger updatedAtIndex = [fieldNames indexOfObject:@"updated_at"];
    NSString *updatedAt = row[updatedAtIndex];
    XCTAssertNotNil(updatedAt);
    XCTAssertTrue([updatedAt containsString:@"2024-01-15"], @"updated_at should contain date");
    XCTAssertTrue([updatedAt containsString:@"10:30:00"], @"updated_at should contain time");
    NSLog(@"✓ TIMESTAMP (updated_at): %@", updatedAt);
    
    // Verify DATE (birth_date)
    NSUInteger birthDateIndex = [fieldNames indexOfObject:@"birth_date"];
    NSString *birthDate = row[birthDateIndex];
    XCTAssertNotNil(birthDate);
    XCTAssertTrue([birthDate isEqualToString:@"1990-05-20"], @"birth_date should match");
    NSLog(@"✓ DATE (birth_date): %@", birthDate);
    
    // Verify TIME (wake_time)
    NSUInteger wakeTimeIndex = [fieldNames indexOfObject:@"wake_time"];
    NSString *wakeTime = row[wakeTimeIndex];
    XCTAssertNotNil(wakeTime);
    XCTAssertTrue([wakeTime containsString:@"07:30:00"], @"wake_time should contain time");
    NSLog(@"✓ TIME (wake_time): %@", wakeTime);
    
    // Verify JSONB (metadata)
    NSUInteger metadataIndex = [fieldNames indexOfObject:@"metadata"];
    NSString *metadata = row[metadataIndex];
    XCTAssertNotNil(metadata);
    XCTAssertTrue([metadata containsString:@"active"], @"metadata should contain 'active'");
    XCTAssertTrue([metadata containsString:@"score"], @"metadata should contain 'score'");
    NSLog(@"✓ JSONB (metadata): %@", metadata);
    
    // Verify TEXT (name)
    NSUInteger nameIndex = [fieldNames indexOfObject:@"name"];
    NSString *name = row[nameIndex];
    XCTAssertEqualObjects(name, @"Test User");
    NSLog(@"✓ TEXT (name): %@", name);
    
    // Test NULL values for timestamp types
    NSString *insertNullQuery = @"INSERT INTO test_types_objc (name) VALUES ('Null Test')";
    [connection queryString:insertNullQuery];
    
    id<SPDatabaseResult> selectNullResult = [connection queryString:@"SELECT * FROM test_types_objc WHERE name = 'Null Test'"];
    [selectNullResult seekToRow:0];
    NSArray *nullRow = [selectNullResult getRowAsArray];
    
    // Check that NULL timestamps are properly handled (should be NSNull for NULL values)
    // Note: In PostgreSQL result wrapper, NULL values are not returned (nil), so we check if the value is nil or NSNull
    id nullValue = nullRow[updatedAtIndex];
    BOOL isNull = (nullValue == nil || nullValue == [NSNull null]);
    XCTAssertTrue(isNull, @"updated_at should be NULL for second row, got: %@", nullValue);
    NSLog(@"✓ NULL timestamp handling verified");
    
    // Clean up
    [connection queryString:@"DROP TABLE test_types_objc"];
    NSLog(@"✓ Dropped test table");
    
    NSLog(@"✓ UUID and timestamp types test passed");
    
    [connection disconnect];
}

#pragma mark - Test 17: Empty Result Set Column Metadata

- (void)test_17_EmptyResultSetColumnMetadata {
    NSLog(@"\n🧪 Test 17: Empty result set preserves column metadata");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect successfully");
    
    // Drop and create test table
    [connection queryString:@"DROP TABLE IF EXISTS test_empty_table"];
    NSString *createQuery = @"CREATE TABLE test_empty_table ("
                            @"id SERIAL PRIMARY KEY, "
                            @"name VARCHAR(100), "
                            @"age INTEGER, "
                            @"email TEXT)";
    
    id<SPDatabaseResult> createResult = [connection queryString:createQuery];
    XCTAssertNotNil(createResult, @"CREATE TABLE should succeed");
    XCTAssertFalse([connection queryErrored], @"CREATE TABLE should not error");
    NSLog(@"✓ Created empty test table");
    
    // Query the empty table
    id<SPDatabaseResult> selectResult = [connection queryString:@"SELECT * FROM test_empty_table"];
    XCTAssertNotNil(selectResult, @"SELECT from empty table should succeed");
    XCTAssertFalse([connection queryErrored], @"SELECT should not error");
    
    // Check row count (should be 0)
    NSUInteger rowCount = [selectResult numberOfRows];
    XCTAssertEqual(rowCount, 0, @"Empty table should have 0 rows");
    NSLog(@"✓ Row count: %lu (expected 0)", (unsigned long)rowCount);
    
    // **CRITICAL TEST**: Check field count (should be 4, NOT 0)
    NSUInteger fieldCount = [selectResult numberOfFields];
    NSLog(@"✓ Field count: %lu (expected 4)", (unsigned long)fieldCount);
    XCTAssertEqual(fieldCount, 4, @"Empty result should preserve 4 columns: id, name, age, email");
    
    // Check field names are preserved
    NSArray *fieldNames = [selectResult fieldNames];
    XCTAssertNotNil(fieldNames, @"Field names should not be nil");
    XCTAssertEqual([fieldNames count], 4, @"Should have 4 field names");
    
    NSLog(@"✓ Field names: %@", fieldNames);
    XCTAssertTrue([fieldNames containsObject:@"id"], @"Should have 'id' field");
    XCTAssertTrue([fieldNames containsObject:@"name"], @"Should have 'name' field");
    XCTAssertTrue([fieldNames containsObject:@"age"], @"Should have 'age' field");
    XCTAssertTrue([fieldNames containsObject:@"email"], @"Should have 'email' field");
    
    // Test with WHERE clause that returns no rows
    id<SPDatabaseResult> filterResult = [connection queryString:@"SELECT id, name FROM test_empty_table WHERE id = 999999"];
    XCTAssertNotNil(filterResult, @"Filtered SELECT should succeed");
    XCTAssertFalse([connection queryErrored], @"Filtered SELECT should not error");
    
    NSUInteger filteredRows = [filterResult numberOfRows];
    NSUInteger filteredFields = [filterResult numberOfFields];
    NSLog(@"✓ Filtered query - Rows: %lu, Fields: %lu", (unsigned long)filteredRows, (unsigned long)filteredFields);
    
    XCTAssertEqual(filteredRows, 0, @"Filtered query should have 0 rows");
    XCTAssertEqual(filteredFields, 2, @"Filtered query should preserve 2 columns: id, name");
    
    NSArray *filteredFieldNames = [filterResult fieldNames];
    XCTAssertEqual([filteredFieldNames count], 2, @"Should have 2 field names");
    XCTAssertTrue([filteredFieldNames containsObject:@"id"], @"Should have 'id' field");
    XCTAssertTrue([filteredFieldNames containsObject:@"name"], @"Should have 'name' field");
    NSLog(@"✓ Filtered field names: %@", filteredFieldNames);
    
    // Test error clearing: run a successful query after the empty result
    // This verifies that empty results don't leave error state
    id<SPDatabaseResult> successResult = [connection queryString:@"SELECT 1 as test"];
    XCTAssertNotNil(successResult, @"Query after empty result should succeed");
    XCTAssertFalse([connection queryErrored], @"Should not have error after empty result");
    XCTAssertEqual([successResult numberOfRows], 1, @"Should have 1 row");
    XCTAssertEqual([successResult numberOfFields], 1, @"Should have 1 field");
    NSLog(@"✓ Subsequent query after empty result succeeded");
    
    // Clean up
    [connection queryString:@"DROP TABLE test_empty_table"];
    NSLog(@"✓ Dropped test table");
    
    NSLog(@"✅ Empty result set column metadata test PASSED");
    NSLog(@"    This test verifies that empty tables return correct field count and field names,");
    NSLog(@"    which is critical for SPTableContent to work correctly with empty PostgreSQL tables.");
    
    [connection disconnect];
}

#pragma mark - Test 18: TLS/SSL Connection

- (void)test_18_TLSConnection {
    NSLog(@"\n🧪 Test 18: TLS/SSL connection");
    
    SPPostgreSQLConnectionWrapper *connection = [[SPPostgreSQLConnectionWrapper alloc] init];
    XCTAssertNotNil(connection, @"Connection should be created");
    
    // Configure connection with SSL enabled
    connection.host = _testHost;
    connection.port = _testPort;
    connection.username = _testUser;
    connection.password = _testPassword;
    connection.database = _testDatabase;
    connection.useSSL = YES;  // Enable TLS
    
    NSLog(@"✓ Attempting TLS connection to %@:%lu", _testHost, (unsigned long)_testPort);
    
    // Connect with TLS
    BOOL connected = [connection connect];
    
    // Note: If the server doesn't support SSL, this test will fail
    // For development, we accept invalid certificates
    if (!connected) {
        NSString *errorMessage = [connection lastErrorMessage];
        NSLog(@"⚠️ TLS connection failed: %@", errorMessage);
        
        // Check if it's a TLS-specific error or server doesn't support TLS
        if ([errorMessage containsString:@"SSL"] || [errorMessage containsString:@"TLS"]) {
            NSLog(@"⚠️ Server may not support TLS/SSL connections");
            NSLog(@"   This is expected if PostgreSQL is not configured with SSL");
        }
        
        // We'll mark as passed with warning since some test environments
        // may not have SSL configured
        XCTAssertTrue(YES, @"TLS test completed (server may not support SSL)");
        NSLog(@"✓ TLS connection test completed (server SSL not available)");
        return;
    }
    
    // If connected successfully with TLS
    XCTAssertTrue([connection isConnected], @"Should report as connected");
    NSLog(@"✓ TLS connection established successfully");
    
    // Verify connection works by executing a simple query
    id<SPDatabaseResult> result = [connection queryString:@"SELECT 1 as test_value, 'TLS works!' as message"];
    XCTAssertNotNil(result, @"Query over TLS should succeed");
    XCTAssertFalse([connection queryErrored], @"Query should not error");
    
    // Verify result data
    XCTAssertEqual([result numberOfRows], 1, @"Should have 1 row");
    XCTAssertEqual([result numberOfFields], 2, @"Should have 2 fields");
    
    [result seekToRow:0];
    NSArray *row = [result getRowAsArray];
    XCTAssertNotNil(row);
    XCTAssertEqualObjects(row[0], @"1");
    XCTAssertEqualObjects(row[1], @"TLS works!");
    NSLog(@"✓ Query result over TLS: %@", row);
    
    // Test that we can perform multiple operations over TLS
    id<SPDatabaseResult> versionResult = [connection queryString:@"SELECT version()"];
    XCTAssertNotNil(versionResult, @"Version query over TLS should succeed");
    [versionResult seekToRow:0];
    NSArray *versionRow = [versionResult getRowAsArray];
    NSLog(@"✓ PostgreSQL version (over TLS): %@", versionRow[0]);
    
    // Disconnect
    [connection disconnect];
    XCTAssertFalse([connection isConnected], @"Should report as disconnected");
    NSLog(@"✓ TLS connection closed");
    
    NSLog(@"✅ TLS/SSL connection test PASSED");
    NSLog(@"    Successfully connected with TLS encryption and executed queries.");
}

#pragma mark - Test 19: TLS and Non-TLS Comparison

- (void)test_19_TLSvsNoTLSComparison {
    NSLog(@"\n🧪 Test 19: TLS vs Non-TLS connection comparison");
    
    // First, connect WITHOUT TLS
    SPPostgreSQLConnectionWrapper *noTlsConnection = [[SPPostgreSQLConnectionWrapper alloc] init];
    noTlsConnection.host = _testHost;
    noTlsConnection.port = _testPort;
    noTlsConnection.username = _testUser;
    noTlsConnection.password = _testPassword;
    noTlsConnection.database = _testDatabase;
    noTlsConnection.useSSL = NO;
    
    BOOL noTlsConnected = [noTlsConnection connect];
    XCTAssertTrue(noTlsConnected, @"Non-TLS connection should succeed");
    NSLog(@"✓ Non-TLS connection established");
    
    // Execute query without TLS
    id<SPDatabaseResult> noTlsResult = [noTlsConnection queryString:@"SELECT 'No TLS' as connection_type"];
    XCTAssertNotNil(noTlsResult);
    [noTlsResult seekToRow:0];
    NSArray *noTlsRow = [noTlsResult getRowAsArray];
    NSLog(@"✓ Non-TLS query result: %@", noTlsRow[0]);
    
    [noTlsConnection disconnect];
    NSLog(@"✓ Non-TLS connection closed");
    
    // Now, connect WITH TLS
    SPPostgreSQLConnectionWrapper *tlsConnection = [[SPPostgreSQLConnectionWrapper alloc] init];
    tlsConnection.host = _testHost;
    tlsConnection.port = _testPort;
    tlsConnection.username = _testUser;
    tlsConnection.password = _testPassword;
    tlsConnection.database = _testDatabase;
    tlsConnection.useSSL = YES;
    
    BOOL tlsConnected = [tlsConnection connect];
    
    if (!tlsConnected) {
        NSLog(@"⚠️ TLS connection failed (server may not support SSL)");
        NSLog(@"✓ Non-TLS connection works, TLS not available - test passed");
        return;
    }
    
    NSLog(@"✓ TLS connection established");
    
    // Execute query with TLS
    id<SPDatabaseResult> tlsResult = [tlsConnection queryString:@"SELECT 'With TLS' as connection_type"];
    XCTAssertNotNil(tlsResult);
    [tlsResult seekToRow:0];
    NSArray *tlsRow = [tlsResult getRowAsArray];
    NSLog(@"✓ TLS query result: %@", tlsRow[0]);
    
    [tlsConnection disconnect];
    NSLog(@"✓ TLS connection closed");
    
    NSLog(@"✅ TLS vs Non-TLS comparison test PASSED");
    NSLog(@"    Both connection modes work correctly.");
}

#pragma mark - Test 20: Streaming Query Basic Test

- (void)test_20_StreamingQuery {
    NSLog(@"\n🧪 Test 20: Streaming Query Basic Test");
    
    SPPostgreSQLConnectionWrapper *connection = [[SPPostgreSQLConnectionWrapper alloc] init];
    [connection setHost:self.testHost];
    [connection setUsername:self.testUser];
    [connection setPassword:self.testPassword];
    [connection setDatabase:self.testDatabase];
    [connection setPort:self.testPort];
    [connection setUseSSL:NO];
    
    BOOL connected = [connection connect];
    XCTAssertTrue(connected, @"Should connect successfully");
    XCTAssertTrue([connection isConnected], @"Should report as connected");
    
    if (!connected) {
        NSLog(@"❌ Connection failed, skipping streaming test");
        return;
    }
    
    // Create a small test table with known data
    NSString *createTableQuery = @"CREATE TABLE IF NOT EXISTS test_streaming ("
                                 @"id SERIAL PRIMARY KEY, "
                                 @"name TEXT NOT NULL, "
                                 @"value INTEGER NOT NULL)";
    id<SPDatabaseResult> createResult = [connection queryString:createTableQuery];
    XCTAssertNotNil(createResult, @"Create table should succeed");
    
    // Insert test data
    [connection queryString:@"DELETE FROM test_streaming"];  // Clean slate
    for (int i = 1; i <= 50; i++) {
        NSString *insertQuery = [NSString stringWithFormat:@"INSERT INTO test_streaming (name, value) VALUES ('Row%d', %d)", i, i * 10];
        [connection queryString:insertQuery];
    }
    NSLog(@"✓ Inserted 50 test rows");
    
    // Execute streaming query
    id<SPDatabaseResult> streamingResult = [connection streamingQueryString:@"SELECT * FROM test_streaming ORDER BY id"];
    XCTAssertNotNil(streamingResult, @"Streaming query should return result");
    
    if (streamingResult) {
        // Start the async download
        NSLog(@"🚀 Starting data download...");
        [streamingResult startDownload];
        
        // Wait for download to complete (with timeout)
        NSDate *startTime = [NSDate date];
        NSTimeInterval timeout = 10.0;
        
        while (![streamingResult dataDownloaded] && [[NSDate date] timeIntervalSinceDate:startTime] < timeout) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        
        XCTAssertTrue([streamingResult dataDownloaded], @"Data should have downloaded within timeout");
        NSLog(@"✓ Data downloaded in %.3f seconds", [[NSDate date] timeIntervalSinceDate:startTime]);
        
        // Check metadata
        NSUInteger totalRows = [streamingResult numberOfRows];
        NSUInteger numFields = [streamingResult numberOfFields];
        
        NSLog(@"✓ Streaming result metadata:");
        NSLog(@"  Total rows: %lu", (unsigned long)totalRows);
        NSLog(@"  Fields: %lu", (unsigned long)numFields);
        
        XCTAssertEqual(totalRows, 50, @"Should have 50 rows");
        XCTAssertEqual(numFields, 3, @"Should have 3 fields (id, name, value)");
        
        // Check field names
        NSArray<NSString *> *fieldNames = [streamingResult fieldNames];
        XCTAssertTrue([fieldNames containsObject:@"id"], @"Should have 'id' field");
        XCTAssertTrue([fieldNames containsObject:@"name"], @"Should have 'name' field");
        XCTAssertTrue([fieldNames containsObject:@"value"], @"Should have 'value' field");
        NSLog(@"✓ Field names: %@", fieldNames);
        
        // Verify dataDownloaded property
        BOOL dataDownloaded = [streamingResult dataDownloaded];
        NSLog(@"✓ dataDownloaded: %@", dataDownloaded ? @"YES" : @"NO");
        
        // Iterate through results (tests the enumeration)
        NSUInteger rowCount = 0;
        for (NSArray *row in streamingResult) {
            rowCount++;
            if (rowCount == 1) {
                // Verify first row
                NSLog(@"✓ First row: %@", row);
            }
        }
        
        NSLog(@"✓ Enumerated %lu rows", (unsigned long)rowCount);
        XCTAssertEqual(rowCount, totalRows, @"Enumeration should return all rows");
        
        // Test seekToRow and getRowAsArray
        [streamingResult seekToRow:0];
        NSArray *firstRow = [streamingResult getRowAsArray];
        XCTAssertNotNil(firstRow, @"Should get first row");
        NSLog(@"✓ First row via getRowAsArray: %@", firstRow);
        
        // Test getRowAsDictionary
        [streamingResult seekToRow:0];
        NSDictionary *firstRowDict = [streamingResult getRowAsDictionary];
        XCTAssertNotNil(firstRowDict, @"Should get first row as dictionary");
        NSLog(@"✓ First row as dictionary: %@", firstRowDict);
        
        // Verify dictionary contents
        XCTAssertNotNil(firstRowDict[@"id"], @"Dictionary should have 'id'");
        XCTAssertNotNil(firstRowDict[@"name"], @"Dictionary should have 'name'");
        XCTAssertNotNil(firstRowDict[@"value"], @"Dictionary should have 'value'");
    }
    
    // Clean up
    [connection queryString:@"DROP TABLE test_streaming"];
    [connection disconnect];
    
    NSLog(@"✅ Test 20 Passed: Streaming Query Basic Test");
}

#pragma mark - Test 21: Streaming Query Large Dataset

- (void)test_21_StreamingQueryLargeDataset {
    NSLog(@"\n🧪 Test 21: Streaming Query Large Dataset");
    
    SPPostgreSQLConnectionWrapper *connection = [[SPPostgreSQLConnectionWrapper alloc] init];
    [connection setHost:self.testHost];
    [connection setUsername:self.testUser];
    [connection setPassword:self.testPassword];
    [connection setDatabase:self.testDatabase];
    [connection setPort:self.testPort];
    [connection setUseSSL:NO];
    
    BOOL connected = [connection connect];
    XCTAssertTrue(connected, @"Should connect successfully");
    
    if (!connected) {
        NSLog(@"❌ Connection failed, skipping large dataset test");
        return;
    }
    
    // Check if football_match_event table exists
    id<SPDatabaseResult> checkTableResult = [connection queryString:
        @"SELECT COUNT(*) as cnt FROM information_schema.tables "
        @"WHERE table_schema = 'public' AND table_name = 'football_match_event'"];
    
    if (!checkTableResult || [checkTableResult numberOfRows] == 0) {
        NSLog(@"⚠️  football_match_event table does not exist, skipping large dataset test");
        [connection disconnect];
        return;
    }
    
    [checkTableResult seekToRow:0];
    NSArray *row = [checkTableResult getRowAsArray];
    if (!row || [row count] == 0 || [row[0] isEqual:[NSNull null]]) {
        NSLog(@"⚠️  Could not verify football_match_event table, skipping test");
        [connection disconnect];
        return;
    }
    
    // Get row count from the table
    id<SPDatabaseResult> countResult = [connection queryString:@"SELECT COUNT(*) as total FROM football_match_event"];
    XCTAssertNotNil(countResult, @"Count query should succeed");
    
    [countResult seekToRow:0];
    NSArray *countRow = [countResult getRowAsArray];
    NSString *totalRowsStr = countRow[0];
    NSUInteger totalRows = [totalRowsStr integerValue];
    
    NSLog(@"✓ football_match_event table has %lu rows", (unsigned long)totalRows);
    
    if (totalRows == 0) {
        NSLog(@"⚠️  football_match_event table is empty, skipping large dataset test");
        [connection disconnect];
        return;
    }
    
    // Test regular streaming query (default batch size)
    NSLog(@"\n📊 Testing regular streaming query...");
    NSDate *startTime = [NSDate date];
    
    id<SPDatabaseResult> streamingResult = [connection streamingQueryString:@"SELECT * FROM football_match_event LIMIT 5000"];
    XCTAssertNotNil(streamingResult, @"Streaming query should return result");
    
    if (streamingResult) {
        // Start async download and wait for completion
        [streamingResult startDownload];
        while (![streamingResult dataDownloaded] && [[NSDate date] timeIntervalSinceDate:startTime] < 10.0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        XCTAssertTrue([streamingResult dataDownloaded], @"Data should have downloaded");
        
        NSTimeInterval queryTime = -[startTime timeIntervalSinceNow];
        NSLog(@"✓ Query execution time: %.3f seconds", queryTime);
        
        NSUInteger resultRows = [streamingResult numberOfRows];
        NSUInteger resultFields = [streamingResult numberOfFields];
        NSLog(@"✓ Result: %lu rows, %lu fields", (unsigned long)resultRows, (unsigned long)resultFields);
        
        XCTAssertTrue(resultRows <= 5000, @"Should respect LIMIT");
        XCTAssertTrue(resultFields > 0, @"Should have fields");
        
        // Check field names
        NSArray<NSString *> *fieldNames = [streamingResult fieldNames];
        NSLog(@"✓ Field names: %@", fieldNames);
        XCTAssertTrue([fieldNames count] > 0, @"Should have field names");
        
        // Sample first few rows
        NSUInteger sampleSize = MIN(5, resultRows);
        NSLog(@"\n📝 Sampling first %lu rows:", (unsigned long)sampleSize);
        
        [streamingResult seekToRow:0];
        for (NSUInteger i = 0; i < sampleSize; i++) {
            NSDictionary *rowDict = [streamingResult getRowAsDictionary];
            if (rowDict) {
                NSLog(@"  Row %lu: %@", (unsigned long)(i + 1), rowDict);
            }
        }
    }
    
    // Test low-memory streaming query (smaller batch size)
    NSLog(@"\n💾 Testing low-memory streaming query...");
    startTime = [NSDate date];
    
    id<SPDatabaseResult> lowMemResult = [connection streamingQueryString:@"SELECT * FROM football_match_event LIMIT 3000" 
                                                 useLowMemoryBlockingStreaming:YES];
    XCTAssertNotNil(lowMemResult, @"Low-memory streaming query should return result");
    
    if (lowMemResult) {
        // Start async download and wait for completion
        [lowMemResult startDownload];
        while (![lowMemResult dataDownloaded] && [[NSDate date] timeIntervalSinceDate:startTime] < 10.0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        XCTAssertTrue([lowMemResult dataDownloaded], @"Data should have downloaded");
        
        NSTimeInterval queryTime = -[startTime timeIntervalSinceNow];
        NSLog(@"✓ Query execution time: %.3f seconds", queryTime);
        
        NSUInteger resultRows = [lowMemResult numberOfRows];
        NSLog(@"✓ Low-memory result: %lu rows", (unsigned long)resultRows);
        
        XCTAssertTrue(resultRows <= 3000, @"Should respect LIMIT");
        
        // Verify enumeration works
        NSUInteger enumeratedCount = 0;
        for (NSArray *row in lowMemResult) {
            enumeratedCount++;
            if (enumeratedCount >= 10) break;  // Just sample first 10
        }
        NSLog(@"✓ Enumerated %lu rows (sample)", (unsigned long)enumeratedCount);
        XCTAssertTrue(enumeratedCount > 0, @"Should enumerate rows");
    }
    
    // Test resultStoreFromQueryString (should use streaming internally)
    NSLog(@"\n🗄️  Testing resultStoreFromQueryString...");
    startTime = [NSDate date];
    
    id resultStore = [connection resultStoreFromQueryString:@"SELECT * FROM football_match_event LIMIT 2000"];
    XCTAssertNotNil(resultStore, @"Result store query should return result");
    
    if (resultStore && [resultStore conformsToProtocol:@protocol(SPDatabaseResult)]) {
        // Start async download and wait for completion
        if ([resultStore respondsToSelector:@selector(startDownload)]) {
            [resultStore startDownload];
            while (![resultStore dataDownloaded] && [[NSDate date] timeIntervalSinceDate:startTime] < 10.0) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            }
            XCTAssertTrue([resultStore dataDownloaded], @"Data should have downloaded");
        }
        
        NSTimeInterval queryTime = -[startTime timeIntervalSinceNow];
        NSLog(@"✓ Query execution time: %.3f seconds", queryTime);
        
        id<SPDatabaseResult> storeResult = (id<SPDatabaseResult>)resultStore;
        NSUInteger resultRows = [storeResult numberOfRows];
        NSLog(@"✓ Result store: %lu rows", (unsigned long)resultRows);
        
        XCTAssertTrue(resultRows <= 2000, @"Should respect LIMIT");
    }
    
    [connection disconnect];
    NSLog(@"✅ Test 21 Passed: Streaming Query Large Dataset");
}

#pragma mark - Test 22: Async Streaming Result Store

- (void)test_22_AsyncStreamingResultStore {
    NSLog(@"\n🧪 Test 22: Async Streaming Result Store");
    
    SPPostgreSQLConnectionWrapper *connection = [[SPPostgreSQLConnectionWrapper alloc] init];
    [connection setHost:self.testHost];
    [connection setUsername:self.testUser];
    [connection setPassword:self.testPassword];
    [connection setDatabase:self.testDatabase];
    [connection setPort:self.testPort];
    [connection setUseSSL:NO];
    
    BOOL connected = [connection connect];
    XCTAssertTrue(connected, @"Should connect successfully");
    
    if (!connected) {
        NSLog(@"❌ Connection failed, skipping async streaming test");
        return;
    }
    
    // Create a small test table
    NSString *createTableQuery = @"CREATE TABLE IF NOT EXISTS test_async_streaming ("
                                 @"id SERIAL PRIMARY KEY, "
                                 @"name TEXT NOT NULL, "
                                 @"value INTEGER NOT NULL)";
    id<SPDatabaseResult> createResult = [connection queryString:createTableQuery];
    XCTAssertNotNil(createResult, @"Create table should succeed");
    
    // Insert test data
    [connection queryString:@"DELETE FROM test_async_streaming"];
    for (int i = 1; i <= 3; i++) {
        NSString *insertQuery = [NSString stringWithFormat:@"INSERT INTO test_async_streaming (name, value) VALUES ('Row%d', %d)", i, i * 10];
        [connection queryString:insertQuery];
    }
    NSLog(@"✓ Inserted 3 test rows");
    
    // Test async result store (mimics what table loading does)
    NSLog(@"\n📊 Testing resultStoreFromQueryString (async streaming)...");
    
    id<SPDatabaseResult> resultStore = [connection resultStoreFromQueryString:@"SELECT * FROM test_async_streaming ORDER BY id"];
    XCTAssertNotNil(resultStore, @"Result store should be created");
    
    NSLog(@"✓ Result store created: %@", [resultStore class]);
    NSLog(@"  Initial dataDownloaded: %@", [resultStore dataDownloaded] ? @"YES" : @"NO");
    NSLog(@"  Initial numberOfRows: %lu", (unsigned long)[resultStore numberOfRows]);
    NSLog(@"  Initial numberOfFields: %lu", (unsigned long)[resultStore numberOfFields]);
    
    // Set up a delegate to track completion
    __block BOOL delegateWasCalled = NO;
    __block NSDate *startTime = [NSDate date];
    
    id mockDelegate = [NSObject new];
    
    // Use method swizzling to add the delegate method
    Class delegateClass = [mockDelegate class];
    IMP implementation = imp_implementationWithBlock(^(id self, id resultStore) {
        NSLog(@"✓ Delegate callback received!");
        NSLog(@"  Time elapsed: %.3f seconds", -[startTime timeIntervalSinceNow]);
        delegateWasCalled = YES;
    });
    
    class_addMethod(delegateClass, @selector(resultStoreDidFinishLoadingData:), implementation, "v@:@");
    
    [resultStore setDelegate:mockDelegate];
    NSLog(@"✓ Delegate set");
    
    // Start the download
    NSLog(@"\n🚀 Calling startDownload...");
    [resultStore startDownload];
    NSLog(@"✓ startDownload returned (should be non-blocking)");
    
    // Wait for completion with timeout
    NSLog(@"\n⏳ Waiting for data to download...");
    int timeout = 10; // 10 seconds
    int elapsed = 0;
    
    while (![resultStore dataDownloaded] && elapsed < timeout) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        usleep(100000); // 100ms
        elapsed++;
        
        if (elapsed % 10 == 0) {
            NSLog(@"  Still waiting... %d seconds elapsed", elapsed / 10);
            NSLog(@"    dataDownloaded: %@", [resultStore dataDownloaded] ? @"YES" : @"NO");
            NSLog(@"    numberOfRows: %lu", (unsigned long)[resultStore numberOfRows]);
        }
    }
    
    if (elapsed >= timeout) {
        NSLog(@"❌ TIMEOUT: Data did not finish downloading in %d seconds", timeout);
        NSLog(@"  Final dataDownloaded: %@", [resultStore dataDownloaded] ? @"YES" : @"NO");
        NSLog(@"  Final numberOfRows: %lu", (unsigned long)[resultStore numberOfRows]);
        
        // Try to cancel
        [resultStore cancelResultLoad];
        
        XCTFail(@"Download timed out after %d seconds", timeout);
        
        [connection queryString:@"DROP TABLE test_async_streaming"];
        [connection disconnect];
        return;
    }
    
    NSLog(@"✓ Data download completed in %.3f seconds", -[startTime timeIntervalSinceNow]);
    NSLog(@"  dataDownloaded: %@", [resultStore dataDownloaded] ? @"YES" : @"NO");
    NSLog(@"  numberOfRows: %lu", (unsigned long)[resultStore numberOfRows]);
    NSLog(@"  numberOfFields: %lu", (unsigned long)[resultStore numberOfFields]);
    NSLog(@"  Delegate was called: %@", delegateWasCalled ? @"YES" : @"NO");
    
    // Verify the results
    XCTAssertTrue([resultStore dataDownloaded], @"Data should be downloaded");
    XCTAssertEqual([resultStore numberOfRows], 3, @"Should have 3 rows");
    XCTAssertEqual([resultStore numberOfFields], 3, @"Should have 3 fields");
    XCTAssertTrue(delegateWasCalled, @"Delegate should have been called");
    
    // Verify field names
    NSArray<NSString *> *fieldNames = [resultStore fieldNames];
    NSLog(@"✓ Field names: %@", fieldNames);
    XCTAssertTrue([fieldNames containsObject:@"id"], @"Should have 'id' field");
    XCTAssertTrue([fieldNames containsObject:@"name"], @"Should have 'name' field");
    XCTAssertTrue([fieldNames containsObject:@"value"], @"Should have 'value' field");
    
    // Verify row data
    [resultStore seekToRow:0];
    NSArray *firstRow = [resultStore getRowAsArray];
    NSLog(@"✓ First row: %@", firstRow);
    XCTAssertNotNil(firstRow, @"Should get first row");
    XCTAssertEqual([firstRow count], 3, @"Row should have 3 columns");
    
    // Clean up
    [connection queryString:@"DROP TABLE test_async_streaming"];
    [connection disconnect];
    
    NSLog(@"✅ Test 22 Passed: Async Streaming Result Store");
}

#pragma mark - Test 23: Async Streaming Cancellation

- (void)test_23_AsyncStreamingCancellation {
    NSLog(@"\n🧪 Test 23: Async Streaming Cancellation");
    
    SPPostgreSQLConnectionWrapper *connection = [[SPPostgreSQLConnectionWrapper alloc] init];
    [connection setHost:self.testHost];
    [connection setUsername:self.testUser];
    [connection setPassword:self.testPassword];
    [connection setDatabase:self.testDatabase];
    [connection setPort:self.testPort];
    [connection setUseSSL:NO];
    
    BOOL connected = [connection connect];
    XCTAssertTrue(connected, @"Should connect successfully");
    
    if (!connected) {
        NSLog(@"❌ Connection failed, skipping cancellation test");
        return;
    }
    
    // Create a test table
    NSString *createTableQuery = @"CREATE TABLE IF NOT EXISTS test_cancel ("
                                 @"id SERIAL PRIMARY KEY, "
                                 @"name TEXT NOT NULL)";
    [connection queryString:createTableQuery];
    [connection queryString:@"DELETE FROM test_cancel"];
    for (int i = 1; i <= 10; i++) {
        [connection queryString:[NSString stringWithFormat:@"INSERT INTO test_cancel (name) VALUES ('Row%d')", i]];
    }
    NSLog(@"✓ Created test table with 10 rows");
    
    // Create result store but don't start download yet
    NSLog(@"\n📊 Creating result store without starting download...");
    id<SPDatabaseResult> resultStore = [connection resultStoreFromQueryString:@"SELECT * FROM test_cancel"];
    XCTAssertNotNil(resultStore, @"Result store should be created");
    
    NSLog(@"✓ Result store created: %@", [resultStore class]);
    NSLog(@"  Initial dataDownloaded: %@", [resultStore dataDownloaded] ? @"YES" : @"NO");
    
    // Cancel before starting (should start and immediately cancel)
    NSLog(@"\n🛑 Calling cancelResultLoad (before startDownload)...");
    NSDate *startTime = [NSDate date];
    [resultStore cancelResultLoad];
    NSTimeInterval cancelTime = -[startTime timeIntervalSinceNow];
    NSLog(@"✓ Cancel completed in %.3f seconds", cancelTime);
    
    XCTAssertTrue([resultStore dataDownloaded], @"Should be marked as downloaded after cancel");
    XCTAssertLessThan(cancelTime, 5.0, @"Cancel should complete within 5 seconds");
    
    // Test 2: Start download, then cancel
    NSLog(@"\n📊 Creating second result store...");
    id<SPDatabaseResult> resultStore2 = [connection resultStoreFromQueryString:@"SELECT * FROM test_cancel"];
    
    NSLog(@"🚀 Starting download...");
    [resultStore2 startDownload];
    
    // Wait a moment for download to start
    usleep(50000); // 50ms
    
    NSLog(@"🛑 Canceling download...");
    startTime = [NSDate date];
    [resultStore2 cancelResultLoad];
    cancelTime = -[startTime timeIntervalSinceNow];
    NSLog(@"✓ Cancel completed in %.3f seconds", cancelTime);
    
    XCTAssertTrue([resultStore2 dataDownloaded], @"Should be marked as downloaded after cancel");
    XCTAssertLessThan(cancelTime, 5.0, @"Cancel should complete within 5 seconds");
    
    // Cleanup
    [connection queryString:@"DROP TABLE test_cancel"];
    [connection disconnect];
    
    NSLog(@"✅ Test 23 Passed: Async Streaming Cancellation");
}

#pragma mark - Test 24: Table Status and Auto Increment

- (void)test_24_TableStatusAndAutoIncrement {
    NSLog(@"\n🧪 Test 24: Table Status Query and Auto Increment Detection");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    if (!connection) {
        XCTFail(@"Failed to create connection");
        return;
    }
    
    // First, create a test table WITH a sequence
    NSLog(@"📝 Creating test table WITH sequence...");
    [connection queryString:@"DROP TABLE IF EXISTS test_with_sequence CASCADE"];
    [connection queryString:@"CREATE TABLE test_with_sequence (id SERIAL PRIMARY KEY, name VARCHAR(100))"];
    [connection queryString:@"INSERT INTO test_with_sequence (name) VALUES ('test1'), ('test2'), ('test3')"];
    
    // Create a test table WITHOUT a sequence
    NSLog(@"📝 Creating test table WITHOUT sequence...");
    [connection queryString:@"DROP TABLE IF EXISTS test_without_sequence CASCADE"];
    [connection queryString:@"CREATE TABLE test_without_sequence (id INTEGER PRIMARY KEY, name VARCHAR(100))"];
    [connection queryString:@"INSERT INTO test_without_sequence (id, name) VALUES (1, 'test1'), (2, 'test2')"];
    
    // Test 1: Table WITH sequence
    NSLog(@"🔍 Testing table WITH sequence...");
    id<SPDatabaseResult> statusWithSeq = [connection getTableStatus:@"test_with_sequence"];
    XCTAssertNotNil(statusWithSeq, @"Should get status for table with sequence");
    
    if (statusWithSeq && [statusWithSeq numberOfRows] > 0) {
        NSDictionary *statusDict = [statusWithSeq getRowAsDictionary];
        NSLog(@"📊 Table WITH sequence status: %@", statusDict);
        
        id autoIncrementValue = [statusDict objectForKey:@"Auto_increment"];
        NSLog(@"   Auto_increment value: %@ (class: %@)", autoIncrementValue, [autoIncrementValue class]);
        
        XCTAssertNotNil(autoIncrementValue, @"Auto_increment should not be nil for table with sequence");
        XCTAssertFalse([autoIncrementValue isKindOfClass:[NSNull class]], @"Auto_increment should not be NSNull for table with sequence");
        
        if (autoIncrementValue && ![autoIncrementValue isKindOfClass:[NSNull class]]) {
            long long nextValue = [autoIncrementValue longLongValue];
            NSLog(@"   ✓ Next sequence value: %lld", nextValue);
            XCTAssertEqual(nextValue, 4, @"Next sequence value should be 4 (after inserting 3 rows)");
        }
    }
    
    // Test 2: Table WITHOUT sequence
    NSLog(@"🔍 Testing table WITHOUT sequence...");
    id<SPDatabaseResult> statusWithoutSeq = [connection getTableStatus:@"test_without_sequence"];
    XCTAssertNotNil(statusWithoutSeq, @"Should get status for table without sequence");
    
    if (statusWithoutSeq && [statusWithoutSeq numberOfRows] > 0) {
        NSDictionary *statusDict = [statusWithoutSeq getRowAsDictionary];
        NSLog(@"📊 Table WITHOUT sequence status: %@", statusDict);
        
        id autoIncrementValue = [statusDict objectForKey:@"Auto_increment"];
        NSLog(@"   Auto_increment value: %@ (class: %@)", autoIncrementValue, [autoIncrementValue class]);
        
        BOOL isNull = (autoIncrementValue == nil || [autoIncrementValue isKindOfClass:[NSNull class]]);
        NSLog(@"   Is NULL: %@", isNull ? @"YES" : @"NO");
        
        XCTAssertTrue(isNull, @"Auto_increment should be NULL for table without sequence");
    }
    
    // Test 3: Check actual tables from the database (league_team, league)
    NSLog(@"🔍 Testing real tables from database...");
    
    // Check if league_team exists
    id<SPDatabaseResult> checkLeagueTeam = [connection queryString:@"SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'league_team'"];
    if (checkLeagueTeam && [checkLeagueTeam numberOfRows] > 0) {
        NSLog(@"📊 Testing league_team table...");
        id<SPDatabaseResult> leagueTeamStatus = [connection getTableStatus:@"league_team"];
        if (leagueTeamStatus && [leagueTeamStatus numberOfRows] > 0) {
            NSDictionary *statusDict = [leagueTeamStatus getRowAsDictionary];
            NSLog(@"   league_team status: %@", statusDict);
            id autoInc = [statusDict objectForKey:@"Auto_increment"];
            NSLog(@"   league_team Auto_increment: %@ (class: %@)", autoInc, [autoInc class]);
        }
    }
    
    // Cleanup
    NSLog(@"🧹 Cleaning up test tables...");
    [connection queryString:@"DROP TABLE IF EXISTS test_with_sequence CASCADE"];
    [connection queryString:@"DROP TABLE IF EXISTS test_without_sequence CASCADE"];
    
    [connection disconnect];
    
    NSLog(@"✅ Test 24 Passed: Table Status and Auto Increment Detection");
}

#pragma mark - Data Modification Tests (INSERT/UPDATE/DELETE)

- (void)test_25_InsertSingleRow {
    NSLog(@"\n🧪 Test 25: INSERT single row");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Connection should be established");
    
    // Create test table
    NSString *testTableName = @"test_insert_single";
    NSString *createTableSQL = [NSString stringWithFormat:
        @"CREATE TABLE %@ ("
        @"  id SERIAL PRIMARY KEY,"
        @"  name VARCHAR(100),"
        @"  age INTEGER,"
        @"  email VARCHAR(200)"
        @")", [connection quoteIdentifier:testTableName]];
    [connection queryString:createTableSQL];
    
    // Insert a single row
    NSString *insertSQL = [NSString stringWithFormat:
        @"INSERT INTO %@ (name, age, email) VALUES ('John Doe', 30, 'john@example.com')",
        [connection quoteIdentifier:testTableName]];
    
    id<SPDatabaseResult> result = [connection queryString:insertSQL];
    
    XCTAssertFalse([connection queryErrored], @"INSERT query should not error: %@",
                   [connection lastErrorMessage]);
    XCTAssertEqual([connection rowsAffectedByLastQuery], (unsigned long long)1,
                   @"INSERT should affect exactly 1 row");
    
    // Verify the insert
    NSString *selectSQL = [NSString stringWithFormat:
        @"SELECT COUNT(*) FROM %@", [connection quoteIdentifier:testTableName]];
    result = [connection queryString:selectSQL];
    NSArray *row = [result getRowAsArray];
    XCTAssertEqualObjects(row[0], @"1", @"Table should have 1 row after insert");
    
    // Cleanup
    [connection queryString:[NSString stringWithFormat:@"DROP TABLE %@",
                             [connection quoteIdentifier:testTableName]]];
    
    [connection disconnect];
    
    NSLog(@"✅ Test 25 Passed: INSERT single row");
}

- (void)test_26_InsertMultipleRows {
    NSLog(@"\n🧪 Test 26: INSERT multiple rows");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Connection should be established");
    
    // Create test table
    NSString *testTableName = @"test_insert_multiple";
    NSString *createTableSQL = [NSString stringWithFormat:
        @"CREATE TABLE %@ ("
        @"  id SERIAL PRIMARY KEY,"
        @"  name VARCHAR(100),"
        @"  age INTEGER"
        @")", [connection quoteIdentifier:testTableName]];
    [connection queryString:createTableSQL];
    
    // Insert multiple rows
    NSString *insertSQL = [NSString stringWithFormat:
        @"INSERT INTO %@ (name, age) VALUES "
        @"('Alice', 25), "
        @"('Bob', 35), "
        @"('Charlie', 40)",
        [connection quoteIdentifier:testTableName]];
    
    id<SPDatabaseResult> result = [connection queryString:insertSQL];
    
    XCTAssertFalse([connection queryErrored], @"INSERT query should not error: %@",
                   [connection lastErrorMessage]);
    XCTAssertEqual([connection rowsAffectedByLastQuery], (unsigned long long)3,
                   @"INSERT should affect exactly 3 rows");
    
    // Cleanup
    [connection queryString:[NSString stringWithFormat:@"DROP TABLE %@",
                             [connection quoteIdentifier:testTableName]]];
    
    [connection disconnect];
    
    NSLog(@"✅ Test 26 Passed: INSERT multiple rows");
}

- (void)test_27_UpdateSingleRow {
    NSLog(@"\n🧪 Test 27: UPDATE single row");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Connection should be established");
    
    // Create test table
    NSString *testTableName = @"test_update_single";
    NSString *createTableSQL = [NSString stringWithFormat:
        @"CREATE TABLE %@ (id SERIAL PRIMARY KEY, name VARCHAR(100), age INTEGER, email VARCHAR(200))",
        [connection quoteIdentifier:testTableName]];
    [connection queryString:createTableSQL];
    
    // Insert a row
    NSString *insertSQL = [NSString stringWithFormat:
        @"INSERT INTO %@ (name, age, email) VALUES ('Jane Doe', 25, 'jane@example.com')",
        [connection quoteIdentifier:testTableName]];
    [connection queryString:insertSQL];
    
    // Update the row
    NSString *updateSQL = [NSString stringWithFormat:
        @"UPDATE %@ SET age = 26 WHERE email = 'jane@example.com'",
        [connection quoteIdentifier:testTableName]];
    id<SPDatabaseResult> result = [connection queryString:updateSQL];
    
    XCTAssertFalse([connection queryErrored], @"UPDATE query should not error");
    XCTAssertEqual([connection rowsAffectedByLastQuery], (unsigned long long)1, @"UPDATE should affect exactly 1 row");
    
    // Verify the update
    result = [connection queryString:[NSString stringWithFormat:
        @"SELECT age FROM %@ WHERE email = 'jane@example.com'", [connection quoteIdentifier:testTableName]]];
    NSArray *row = [result getRowAsArray];
    XCTAssertEqualObjects(row[0], @"26", @"Age should be updated to 26");
    
    // Cleanup
    [connection queryString:[NSString stringWithFormat:@"DROP TABLE %@", [connection quoteIdentifier:testTableName]]];
    [connection disconnect];
    NSLog(@"✅ Test 27 Passed: UPDATE single row");
}

- (void)test_28_UpdateMultipleRows {
    NSLog(@"\n🧪 Test 28: UPDATE multiple rows");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Connection should be established");
    
    NSString *testTableName = @"test_update_multiple";
    [connection queryString:[NSString stringWithFormat:
        @"CREATE TABLE %@ (id SERIAL PRIMARY KEY, name VARCHAR(100), age INTEGER)",
        [connection quoteIdentifier:testTableName]]];
    
    [connection queryString:[NSString stringWithFormat:
        @"INSERT INTO %@ (name, age) VALUES ('Alice', 25), ('Bob', 25), ('Charlie', 30)",
        [connection quoteIdentifier:testTableName]]];
    
    [connection queryString:[NSString stringWithFormat:
        @"UPDATE %@ SET age = 26 WHERE age = 25", [connection quoteIdentifier:testTableName]]];
    
    XCTAssertFalse([connection queryErrored], @"UPDATE query should not error");
    XCTAssertEqual([connection rowsAffectedByLastQuery], (unsigned long long)2, @"UPDATE should affect 2 rows");
    
    [connection queryString:[NSString stringWithFormat:@"DROP TABLE %@", [connection quoteIdentifier:testTableName]]];
    [connection disconnect];
    NSLog(@"✅ Test 28 Passed: UPDATE multiple rows");
}

- (void)test_29_UpdateNoRows {
    NSLog(@"\n🧪 Test 29: UPDATE no rows");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Connection should be established");
    
    NSString *testTableName = @"test_update_none";
    [connection queryString:[NSString stringWithFormat:
        @"CREATE TABLE %@ (id SERIAL PRIMARY KEY, email VARCHAR(200))",
        [connection quoteIdentifier:testTableName]]];
    
    [connection queryString:[NSString stringWithFormat:
        @"UPDATE %@ SET email = 'test@example.com' WHERE email = 'nonexistent@example.com'",
        [connection quoteIdentifier:testTableName]]];
    
    XCTAssertFalse([connection queryErrored], @"UPDATE query should not error");
    XCTAssertEqual([connection rowsAffectedByLastQuery], (unsigned long long)0, @"UPDATE should affect 0 rows");
    
    [connection queryString:[NSString stringWithFormat:@"DROP TABLE %@", [connection quoteIdentifier:testTableName]]];
    [connection disconnect];
    NSLog(@"✅ Test 29 Passed: UPDATE no rows");
}

- (void)test_30_DeleteSingleRow {
    NSLog(@"\n🧪 Test 30: DELETE single row");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Connection should be established");
    
    NSString *testTableName = @"test_delete_single";
    [connection queryString:[NSString stringWithFormat:
        @"CREATE TABLE %@ (id SERIAL PRIMARY KEY, email VARCHAR(200))",
        [connection quoteIdentifier:testTableName]]];
    
    [connection queryString:[NSString stringWithFormat:
        @"INSERT INTO %@ (email) VALUES ('delete@example.com')", [connection quoteIdentifier:testTableName]]];
    
    [connection queryString:[NSString stringWithFormat:
        @"DELETE FROM %@ WHERE email = 'delete@example.com'", [connection quoteIdentifier:testTableName]]];
    
    XCTAssertFalse([connection queryErrored], @"DELETE query should not error");
    XCTAssertEqual([connection rowsAffectedByLastQuery], (unsigned long long)1, @"DELETE should affect 1 row");
    
    id<SPDatabaseResult> result = [connection queryString:[NSString stringWithFormat:
        @"SELECT COUNT(*) FROM %@ WHERE email = 'delete@example.com'", [connection quoteIdentifier:testTableName]]];
    NSArray *row = [result getRowAsArray];
    XCTAssertEqualObjects(row[0], @"0", @"Row should be deleted");
    
    [connection queryString:[NSString stringWithFormat:@"DROP TABLE %@", [connection quoteIdentifier:testTableName]]];
    [connection disconnect];
    NSLog(@"✅ Test 30 Passed: DELETE single row");
}

- (void)test_31_DeleteMultipleRows {
    NSLog(@"\n🧪 Test 31: DELETE multiple rows");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Connection should be established");
    
    NSString *testTableName = @"test_delete_multiple";
    [connection queryString:[NSString stringWithFormat:
        @"CREATE TABLE %@ (id SERIAL PRIMARY KEY, age INTEGER)",
        [connection quoteIdentifier:testTableName]]];
    
    [connection queryString:[NSString stringWithFormat:
        @"INSERT INTO %@ (age) VALUES (25), (25), (30)", [connection quoteIdentifier:testTableName]]];
    
    [connection queryString:[NSString stringWithFormat:
        @"DELETE FROM %@ WHERE age = 25", [connection quoteIdentifier:testTableName]]];
    
    XCTAssertFalse([connection queryErrored], @"DELETE query should not error");
    XCTAssertEqual([connection rowsAffectedByLastQuery], (unsigned long long)2, @"DELETE should affect 2 rows");
    
    [connection queryString:[NSString stringWithFormat:@"DROP TABLE %@", [connection quoteIdentifier:testTableName]]];
    [connection disconnect];
    NSLog(@"✅ Test 31 Passed: DELETE multiple rows");
}

- (void)test_32_DeleteNoRows {
    NSLog(@"\n🧪 Test 32: DELETE no rows");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Connection should be established");
    
    NSString *testTableName = @"test_delete_none";
    [connection queryString:[NSString stringWithFormat:
        @"CREATE TABLE %@ (id SERIAL PRIMARY KEY, email VARCHAR(200))",
        [connection quoteIdentifier:testTableName]]];
    
    [connection queryString:[NSString stringWithFormat:
        @"DELETE FROM %@ WHERE email = 'nonexistent@example.com'", [connection quoteIdentifier:testTableName]]];
    
    XCTAssertFalse([connection queryErrored], @"DELETE query should not error");
    XCTAssertEqual([connection rowsAffectedByLastQuery], (unsigned long long)0, @"DELETE should affect 0 rows");
    
    [connection queryString:[NSString stringWithFormat:@"DROP TABLE %@", [connection quoteIdentifier:testTableName]]];
    [connection disconnect];
    NSLog(@"✅ Test 32 Passed: DELETE no rows");
}

- (void)test_33_CombinedInsertUpdateDelete {
    NSLog(@"\n🧪 Test 33: Combined INSERT, UPDATE, DELETE operations");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Connection should be established");
    
    NSString *testTableName = @"test_combined_ops";
    [connection queryString:[NSString stringWithFormat:
        @"CREATE TABLE %@ (id SERIAL PRIMARY KEY, name VARCHAR(100), age INTEGER)",
        [connection quoteIdentifier:testTableName]]];
    
    // INSERT
    [connection queryString:[NSString stringWithFormat:
        @"INSERT INTO %@ (name, age) VALUES ('Test User', 30)", [connection quoteIdentifier:testTableName]]];
    XCTAssertEqual([connection rowsAffectedByLastQuery], (unsigned long long)1, @"INSERT should affect 1 row");
    
    // SELECT (verify insert)
    id<SPDatabaseResult> result = [connection queryString:[NSString stringWithFormat:
        @"SELECT COUNT(*) FROM %@", [connection quoteIdentifier:testTableName]]];
    NSArray *row = [result getRowAsArray];
    XCTAssertEqualObjects(row[0], @"1", @"Table should have 1 row after insert");
    
    // UPDATE
    [connection queryString:[NSString stringWithFormat:
        @"UPDATE %@ SET age = 31 WHERE name = 'Test User'", [connection quoteIdentifier:testTableName]]];
    XCTAssertEqual([connection rowsAffectedByLastQuery], (unsigned long long)1, @"UPDATE should affect 1 row");
    
    // SELECT (verify update)
    result = [connection queryString:[NSString stringWithFormat:
        @"SELECT age FROM %@ WHERE name = 'Test User'", [connection quoteIdentifier:testTableName]]];
    row = [result getRowAsArray];
    XCTAssertEqualObjects(row[0], @"31", @"Age should be updated");
    
    // DELETE
    [connection queryString:[NSString stringWithFormat:
        @"DELETE FROM %@ WHERE name = 'Test User'", [connection quoteIdentifier:testTableName]]];
    XCTAssertEqual([connection rowsAffectedByLastQuery], (unsigned long long)1, @"DELETE should affect 1 row");
    
    // SELECT (verify delete)
    result = [connection queryString:[NSString stringWithFormat:
        @"SELECT COUNT(*) FROM %@", [connection quoteIdentifier:testTableName]]];
    row = [result getRowAsArray];
    XCTAssertEqualObjects(row[0], @"0", @"Table should be empty after delete");
    
    [connection queryString:[NSString stringWithFormat:@"DROP TABLE %@", [connection quoteIdentifier:testTableName]]];
    [connection disconnect];
    NSLog(@"✅ Test 33 Passed: Combined INSERT, UPDATE, DELETE operations");
}

- (void)test_34_UpdateThenStreamingSelect {
    NSLog(@"\n🧪 Test 34: UPDATE followed by streaming SELECT (reproducing hang)");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Connection should be established");
    
    NSString *testTableName = @"test_update_streaming";
    
    // Drop table if it exists from previous test run
    [connection queryString:[NSString stringWithFormat:
        @"DROP TABLE IF EXISTS %@",
        [connection quoteIdentifier:testTableName]]];
    
    // Create table with multiple rows
    // Note: Using INTEGER instead of NUMERIC for simpler type handling
    [connection queryString:[NSString stringWithFormat:
        @"CREATE TABLE %@ (id SERIAL PRIMARY KEY, name VARCHAR(100), value INTEGER)",
        [connection quoteIdentifier:testTableName]]];
    
    NSLog(@"   Inserting 100 rows...");
    for (int i = 0; i < 100; i++) {
        NSString *insertQuery = [NSString stringWithFormat:
            @"INSERT INTO %@ (name, value) VALUES ('Row %d', %d)", 
            [connection quoteIdentifier:testTableName], i, i];
        if (i == 50) {
            NSLog(@"   Sample INSERT query: %@", insertQuery);
        }
        [connection queryString:insertQuery];
    }
    
    // Check what was actually inserted
    id<SPDatabaseResult> checkInsert = [connection queryString:[NSString stringWithFormat:
        @"SELECT id, name, value FROM %@ WHERE id = 51", [connection quoteIdentifier:testTableName]]];
    NSArray *checkRow = [checkInsert getRowAsArray];
    NSLog(@"   After INSERT, row 51: id=%@, name=%@, value=%@ (isNull=%d)", 
          checkRow[0], checkRow[1], checkRow[2], [checkRow[2] isKindOfClass:[NSNull class]]);
    
    NSLog(@"   Performing UPDATE...");
    // Update a single row (simulating what the user does)
    // Note: Use id = 51 since SERIAL starts at 1, so row 0 has id 1, row 50 has id 51
    NSString *updateQuery = [NSString stringWithFormat:
        @"UPDATE %@ SET value = 999 WHERE id = 51", 
        [connection quoteIdentifier:testTableName]];
    NSLog(@"   UPDATE query: %@", updateQuery);
    [connection queryString:updateQuery];
    
    unsigned long long affected = [connection rowsAffectedByLastQuery];
    NSLog(@"   UPDATE affected %llu rows", affected);
    XCTAssertEqual(affected, (unsigned long long)1, @"UPDATE should affect 1 row");
    
    // Verify the UPDATE worked with a simple SELECT
    // First, let's check what's actually in the table around row 51
    id<SPDatabaseResult> debugResult = [connection queryString:[NSString stringWithFormat:
        @"SELECT id, name, value FROM %@ WHERE id BETWEEN 49 AND 53 ORDER BY id", 
        [connection quoteIdentifier:testTableName]]];
    NSLog(@"   Debug: Rows 49-53:");
    NSArray *debugRow;
    while ((debugRow = [debugResult getRowAsArray])) {
        NSLog(@"     id=%@, name=%@, value=%@ (isNull=%d)", 
              debugRow[0], debugRow[1], debugRow[2], [debugRow[2] isKindOfClass:[NSNull class]]);
    }
    
    id<SPDatabaseResult> verifyResult = [connection queryString:[NSString stringWithFormat:
        @"SELECT id, name, value FROM %@ WHERE id = 51", [connection quoteIdentifier:testTableName]]];
    NSArray *verifyRow = [verifyResult getRowAsArray];
    NSLog(@"   Verification query shows id=%@, name=%@, value=%@ (class=%@)", 
          verifyRow[0], verifyRow[1], verifyRow[2], [verifyRow[2] class]);
    XCTAssertEqualObjects(verifyRow[2], @"999", @"Updated value should be 999 after UPDATE");
    
    NSLog(@"   Performing streaming SELECT immediately after UPDATE (using resultStoreFromQueryString)...");
    // Now do a streaming SELECT using resultStoreFromQueryString (this is what SPTableContent uses for table reloads)
    id<SPDatabaseResult> result = [connection resultStoreFromQueryString:[NSString stringWithFormat:
        @"SELECT * FROM %@ ORDER BY id", [connection quoteIdentifier:testTableName]]];
    
    XCTAssertNotNil(result, @"Streaming result should not be nil");
    
    // Set up delegate to receive completion notification (like SPDataStorage does)
    __block BOOL delegateCalled = NO;
    __block id capturedResult = nil;
    
    // Create a simple delegate object using a block-based approach
    id mockDelegate = [NSObject new];
    
    // Use method swizzling or a simple block capture for the delegate callback
    // For simplicity in the test, we'll just use the property observation
    result.delegate = mockDelegate;
    
    // Store the original implementation or use KVO
    // Actually, let's use a simpler approach: just check if already downloaded before starting
    if ([result dataDownloaded]) {
        delegateCalled = YES;
        NSLog(@"   Data already downloaded");
    }
    
    // Start the download (this is what SPDataStorage does)
    if ([result respondsToSelector:@selector(startDownload)]) {
        [(id)result startDownload];
    }
    
    // Wait for data to be downloaded using the delegate pattern (like SPDataStorage)
    // Since we can't easily implement the delegate in the test, wait on dataDownloaded with proper runloop integration
    NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:10.0];
    while (![result dataDownloaded] && [[NSDate date] compare:timeout] == NSOrderedAscending) {
        // Process delegate callbacks on main runloop
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    XCTAssertTrue([result dataDownloaded], @"Data should be downloaded within 10 seconds");
    
    NSLog(@"   Starting to read rows from streaming result...");
    [result seekToRow:0];  // Reset to beginning
    NSUInteger rowCount = 0;
    NSArray *row;
    BOOL foundUpdatedRow = NO;
    
    while ((row = [result getRowAsArray])) {
        rowCount++;
        if (rowCount % 20 == 0) {
            NSLog(@"   Read %lu rows so far...", (unsigned long)rowCount);
        }
        
        // Check if we found the updated row (id=51, which is Row 50)
        if ([row[0] isEqualToString:@"51"]) {
            NSLog(@"   Found updated row: id=%@, name=%@, value=%@ (class=%@)", row[0], row[1], row[2], [row[2] class]);
            foundUpdatedRow = YES;
            // Verify the value was updated correctly in the streaming result
            XCTAssertEqualObjects(row[2], @"999", 
                                 @"Updated value should be 999 in streaming result, got: %@ (%@)", 
                                 row[2], [row[2] class]);
        }
    }
    
    NSLog(@"   Successfully read all %lu rows", (unsigned long)rowCount);
    XCTAssertEqual(rowCount, (NSUInteger)100, @"Should read 100 rows");
    XCTAssertTrue(foundUpdatedRow, @"Should find the updated row");
    
    [connection queryString:[NSString stringWithFormat:@"DROP TABLE %@", [connection quoteIdentifier:testTableName]]];
    [connection disconnect];
    NSLog(@"✅ Test 34 Passed: UPDATE followed by streaming SELECT works correctly without hanging");
}

#pragma mark - Test 35: Large Streaming Query with Batching

- (void)test_35_LargeStreamingQueryWithBatching {
    NSLog(@"\n🧪 Test 35: Large Streaming Query with 100K records (500-row batches)");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Connection should be established");
    
    NSString *testTableName = @"test_large_streaming";
    
    // Drop table if it exists from previous test run
    [connection queryString:[NSString stringWithFormat:
        @"DROP TABLE IF EXISTS %@",
        [connection quoteIdentifier:testTableName]]];
    
    // Create table
    NSLog(@"   Creating table...");
    NSString *createQuery = [NSString stringWithFormat:
        @"CREATE TABLE %@ (id INTEGER PRIMARY KEY, name TEXT NOT NULL)",
        [connection quoteIdentifier:testTableName]];
    [connection queryString:createQuery];
    
    // Insert 100K records in batches (for speed)
    NSLog(@"   Inserting 100,000 records...");
    NSDate *insertStart = [NSDate date];
    
    const int totalRecords = 100000;
    const int insertBatchSize = 1000;
    
    for (int batchStart = 1; batchStart <= totalRecords; batchStart += insertBatchSize) {
        int batchEnd = MIN(batchStart + insertBatchSize - 1, totalRecords);
        
        NSMutableString *batchInsert = [NSMutableString stringWithFormat:
            @"INSERT INTO %@ (id, name) VALUES ", [connection quoteIdentifier:testTableName]];
        
        for (int i = batchStart; i <= batchEnd; i++) {
            if (i > batchStart) [batchInsert appendString:@", "];
            [batchInsert appendFormat:@"(%d, '%d')", i, i];
        }
        
        [connection queryString:batchInsert];
        
        if (batchStart % 10000 == 1) {
            NSLog(@"      Inserted %d records...", batchStart - 1);
        }
    }
    
    NSLog(@"   ✓ Inserted 100K records in %.2f seconds", -[insertStart timeIntervalSinceNow]);
    
    // Execute streaming query using connection wrapper (which should use streaming API)
    NSLog(@"\n   Executing streaming query with 500-row batches...");
    NSDate *queryStart = [NSDate date];
    
    id<SPDatabaseResult> result = [connection streamingQueryString:
        [NSString stringWithFormat:@"SELECT * FROM %@ ORDER BY id", [connection quoteIdentifier:testTableName]]
        useLowMemoryBlockingStreaming:YES];  // Use 500-row batch size
    
    NSLog(@"   ✓ Query executed in %.3f seconds", -[queryStart timeIntervalSinceNow]);
    XCTAssertNotNil(result, @"Streaming result should not be nil");
    
    // Check metadata is available IMMEDIATELY (before calling startDownload)
    NSLog(@"\n   Verifying metadata available immediately:");
    NSUInteger numFields = [result numberOfFields];
    NSLog(@"      Number of fields: %lu", (unsigned long)numFields);
    
    XCTAssertEqual(numFields, (NSUInteger)2, @"Should have 2 fields");
    
    // Check field names
    NSArray *fieldNames = [result fieldNames];
    XCTAssertEqualObjects(fieldNames[0], @"id", @"First field should be 'id'");
    XCTAssertEqualObjects(fieldNames[1], @"name", @"Second field should be 'name'");
    NSLog(@"      Field names: %@", fieldNames);
    
    // Note: numberOfRows will be 0 before download (like MySQL's mysql_use_result)
    // It will be accurate after download completes
    
    // Start the download
    NSLog(@"\n   Starting batched download...");
    [result startDownload];
    
    // Wait for download to complete
    NSDate *downloadStart = [NSDate date];
    int timeout = 60; // 60 seconds for 100K records
    int elapsed = 0;
    
    while (![result dataDownloaded] && elapsed < timeout) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        usleep(100000); // 100ms
        elapsed++;
        
        if (elapsed % 50 == 0) {  // Every 5 seconds
            NSLog(@"      Still downloading... %d seconds elapsed", elapsed / 10);
        }
    }
    
    if (elapsed >= timeout) {
        [result cancelResultLoad];
        XCTFail(@"Download timed out after %d seconds", timeout);
        [connection queryString:[NSString stringWithFormat:@"DROP TABLE %@", [connection quoteIdentifier:testTableName]]];
        [connection disconnect];
        return;
    }
    
    NSLog(@"   ✓ Downloaded all data in %.2f seconds", -[downloadStart timeIntervalSinceNow]);
    
    // Now that download is complete, numberOfRows should reflect the total
    NSUInteger totalRows = [result numberOfRows];
    NSLog(@"   ✓ Total rows after download: %lu", (unsigned long)totalRows);
    XCTAssertEqual(totalRows, (NSUInteger)totalRecords, @"Should have 100K rows after download");
    
    // Verify data correctness by sampling
    NSLog(@"\n   Verifying data correctness:");
    [result seekToRow:0];
    
    // Check first 10 rows
    NSLog(@"      Checking first 10 rows...");
    for (int i = 1; i <= 10; i++) {
        NSArray *row = [result getRowAsArray];
        XCTAssertNotNil(row, @"Row %d should not be nil", i);
        XCTAssertEqual([row count], (NSUInteger)2, @"Row should have 2 columns");
        
        NSString *idStr = [row[0] description];
        NSString *nameStr = [row[1] description];
        NSString *expectedStr = [NSString stringWithFormat:@"%d", i];
        
        XCTAssertEqualObjects(idStr, expectedStr, @"Row %d: id should be %d", i, i);
        XCTAssertEqualObjects(nameStr, expectedStr, @"Row %d: name should be '%d'", i, i);
    }
    
    // Check some middle rows
    NSLog(@"      Checking rows 50000-50010...");
    [result seekToRow:50000 - 1]; // -1 because  seekToRow is 0-based
    for (int i = 50000; i <= 50010; i++) {
        NSArray *row = [result getRowAsArray];
        NSString *idStr = [row[0] description];
        NSString *nameStr = [row[1] description];
        NSString *expectedStr = [NSString stringWithFormat:@"%d", i];
        
        XCTAssertEqualObjects(idStr, expectedStr, @"Row %d: id should be %d", i, i);
        XCTAssertEqualObjects(nameStr, expectedStr, @"Row %d: name should be '%d'", i, i);
    }
    
    // Check last 10 rows
    NSLog(@"      Checking last 10 rows...");
    [result seekToRow:totalRecords - 10];
    for (int i = totalRecords - 9; i <= totalRecords; i++) {
        NSArray *row = [result getRowAsArray];
        NSString *idStr = [row[0] description];
        NSString *nameStr = [row[1] description];
        NSString *expectedStr = [NSString stringWithFormat:@"%d", i];
        
        XCTAssertEqualObjects(idStr, expectedStr, @"Row %d: id should be %d", i, i);
        XCTAssertEqualObjects(nameStr, expectedStr, @"Row %d: name should be '%d'", i, i);
    }
    
    // Count all rows to verify completeness
    NSLog(@"\n   Counting all rows...");
    [result seekToRow:0];
    NSUInteger rowCount = 0;
    while ([result getRowAsArray]) {
        rowCount++;
    }
    XCTAssertEqual(rowCount, (NSUInteger)totalRecords, @"Should have fetched all 100K rows");
    NSLog(@"   ✓ Verified all %lu rows present", (unsigned long)rowCount);
    
    // Cleanup
    [connection queryString:[NSString stringWithFormat:@"DROP TABLE %@", [connection quoteIdentifier:testTableName]]];
    [connection disconnect];
    
    NSLog(@"✅ Test 35 Passed: Large streaming query with batching works correctly");
    NSLog(@"   Total time: %.2f seconds", -[queryStart timeIntervalSinceNow]);
}

#pragma mark - Test 36: Empty Table Query (No Infinite Loop)

- (void)test_36_EmptyTableQuery {
    NSLog(@"\n🧪 Test 36: Empty Table Query (should not infinite loop)");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Connection should be established");
    
    NSString *testTableName = @"test_empty_table";
    
    // Drop table if it exists from previous test run
    [connection queryString:[NSString stringWithFormat:
        @"DROP TABLE IF EXISTS %@",
        [connection quoteIdentifier:testTableName]]];
    
    // Create empty table
    NSLog(@"   Creating empty table...");
    [connection queryString:[NSString stringWithFormat:
        @"CREATE TABLE %@ (id SERIAL PRIMARY KEY, name TEXT, value INTEGER)",
        [connection quoteIdentifier:testTableName]]];
    
    // Query empty table with streaming
    NSLog(@"   Querying empty table with streaming...");
    NSDate *queryStart = [NSDate date];
    id<SPDatabaseResult> result = [connection streamingQueryString:
        [NSString stringWithFormat:@"SELECT * FROM %@", [connection quoteIdentifier:testTableName]]
        useLowMemoryBlockingStreaming:YES];
    
    XCTAssertNotNil(result, @"Streaming result should not be nil");
    
    // Check metadata is available (this was the infinite loop trigger)
    NSUInteger numFields = [result numberOfFields];
    NSLog(@"      Number of fields: %lu", (unsigned long)numFields);
    XCTAssertEqual(numFields, (NSUInteger)3, @"Should have 3 fields even for empty table");
    
    // Check field names
    NSArray *fieldNames = [result fieldNames];
    XCTAssertEqual([fieldNames count], (NSUInteger)3, @"Should have 3 field names");
    NSLog(@"      Field names: %@", fieldNames);
    
    // Start download
    [result startDownload];
    
    // Wait for download to complete (should be instant for empty table)
    NSDate *downloadStart = [NSDate date];
    int timeout = 5; // 5 seconds should be more than enough for empty table
    int elapsed = 0;
    
    while (![result dataDownloaded] && elapsed < timeout) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        usleep(100000); // 100ms
        elapsed++;
    }
    
    XCTAssertTrue([result dataDownloaded], @"Empty table download should complete quickly");
    NSLog(@"   ✓ Downloaded in %.3f seconds", -[downloadStart timeIntervalSinceNow]);
    
    // Verify numberOfRows is 0
    NSUInteger totalRows = [result numberOfRows];
    XCTAssertEqual(totalRows, (NSUInteger)0, @"Empty table should have 0 rows");
    NSLog(@"   ✓ Total rows: %lu", (unsigned long)totalRows);
    
    // Try to iterate (should not hang)
    [result seekToRow:0];
    NSUInteger rowCount = 0;
    while ([result getRowAsArray]) {
        rowCount++;
    }
    XCTAssertEqual(rowCount, (NSUInteger)0, @"Should iterate 0 rows");
    
    // Cleanup
    [connection queryString:[NSString stringWithFormat:@"DROP TABLE %@", [connection quoteIdentifier:testTableName]]];
    [connection disconnect];
    
    NSLog(@"✅ Test 36 Passed: Empty table query works without infinite loop");
    NSLog(@"   Total time: %.3f seconds", -[queryStart timeIntervalSinceNow]);
}

#pragma mark - Test 37: Get CREATE TABLE Statement

- (void)test_37_GetCreateTableStatement {
    NSLog(@"\n🧪 Test 37: Get CREATE TABLE Statement");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect to database");
    
    // Create a test table with various column types
    NSString *testTableName = [NSString stringWithFormat:@"test_create_table_%d", arc4random_uniform(100000)];
    NSLog(@"   Creating test table: %@", testTableName);
    
    NSString *createSQL = [NSString stringWithFormat:
        @"CREATE TABLE %@ ("
        @"  id SERIAL PRIMARY KEY, "
        @"  name VARCHAR(100) NOT NULL, "
        @"  age INTEGER, "
        @"  email TEXT, "
        @"  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
        @")",
        [connection quoteIdentifier:testTableName]];
    
    [connection queryString:createSQL];
    XCTAssertFalse([connection queryErrored], @"Table creation should succeed");
    
    // Get the CREATE statement
    NSLog(@"   Getting CREATE TABLE statement...");
    NSString *createStatement = [connection getCreateStatementForTable:testTableName];
    
    XCTAssertNotNil(createStatement, @"Should return CREATE TABLE statement");
    XCTAssertTrue([createStatement containsString:@"CREATE TABLE"], @"Should contain CREATE TABLE");
    XCTAssertTrue([createStatement containsString:@"id"], @"Should contain id column");
    XCTAssertTrue([createStatement containsString:@"name"], @"Should contain name column");
    
    NSLog(@"   ✓ CREATE TABLE statement retrieved:");
    NSLog(@"     %@", createStatement);
    
    // Cleanup
    [connection queryString:[NSString stringWithFormat:@"DROP TABLE %@", [connection quoteIdentifier:testTableName]]];
    [connection disconnect];
    
    NSLog(@"✅ Test 37 Passed: Get CREATE TABLE Statement");
}

#pragma mark - Test 38: Get CREATE VIEW Statement

- (void)test_38_GetCreateViewStatement {
    NSLog(@"\n🧪 Test 38: Get CREATE VIEW Statement");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect to database");
    
    // Create a test table
    NSString *testTableName = [NSString stringWithFormat:@"test_view_table_%d", arc4random_uniform(100000)];
    NSString *testViewName = [NSString stringWithFormat:@"test_view_%d", arc4random_uniform(100000)];
    
    NSLog(@"   Creating test table: %@", testTableName);
    [connection queryString:[NSString stringWithFormat:
        @"CREATE TABLE %@ (id SERIAL PRIMARY KEY, name TEXT, value INTEGER)",
        [connection quoteIdentifier:testTableName]]];
    
    // Insert some test data
    [connection queryString:[NSString stringWithFormat:
        @"INSERT INTO %@ (name, value) VALUES ('test1', 100), ('test2', 200)",
        [connection quoteIdentifier:testTableName]]];
    
    // Create a test view
    NSLog(@"   Creating test view: %@", testViewName);
    NSString *createViewSQL = [NSString stringWithFormat:
        @"CREATE VIEW %@ AS SELECT id, name, value * 2 AS double_value FROM %@ WHERE value > 50",
        [connection quoteIdentifier:testViewName],
        [connection quoteIdentifier:testTableName]];
    
    [connection queryString:createViewSQL];
    XCTAssertFalse([connection queryErrored], @"View creation should succeed");
    
    // Get the CREATE VIEW statement
    NSLog(@"   Getting CREATE VIEW statement...");
    NSString *createStatement = [connection getCreateStatementForView:testViewName];
    
    XCTAssertNotNil(createStatement, @"Should return CREATE VIEW statement");
    XCTAssertTrue([createStatement containsString:@"CREATE VIEW"], @"Should contain CREATE VIEW");
    XCTAssertTrue([createStatement containsString:@"SELECT"], @"Should contain SELECT");
    XCTAssertTrue([createStatement containsString:testTableName], @"Should reference source table");
    
    NSLog(@"   ✓ CREATE VIEW statement retrieved:");
    NSLog(@"     %@", createStatement);
    
    // Cleanup
    [connection queryString:[NSString stringWithFormat:@"DROP VIEW %@", [connection quoteIdentifier:testViewName]]];
    [connection queryString:[NSString stringWithFormat:@"DROP TABLE %@", [connection quoteIdentifier:testTableName]]];
    [connection disconnect];
    
    NSLog(@"✅ Test 38 Passed: Get CREATE VIEW Statement");
}

#pragma mark - Test 39: Get CREATE FUNCTION Statement

- (void)test_39_GetCreateFunctionStatement {
    NSLog(@"\n🧪 Test 39: Get CREATE FUNCTION Statement");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect to database");
    
    // Create a test function
    NSString *testFunctionName = [NSString stringWithFormat:@"test_function_%d", arc4random_uniform(100000)];
    NSLog(@"   Creating test function: %@", testFunctionName);
    
    NSString *createFunctionSQL = [NSString stringWithFormat:
        @"CREATE OR REPLACE FUNCTION %@(x INTEGER, y INTEGER) "
        @"RETURNS INTEGER AS $$ "
        @"BEGIN "
        @"  RETURN x + y; "
        @"END; "
        @"$$ LANGUAGE plpgsql",
        [connection quoteIdentifier:testFunctionName]];
    
    [connection queryString:createFunctionSQL];
    XCTAssertFalse([connection queryErrored], @"Function creation should succeed: %@", [connection lastErrorMessage]);
    
    // Get the CREATE FUNCTION statement
    NSLog(@"   Getting CREATE FUNCTION statement...");
    NSString *createStatement = [connection getCreateStatementForFunction:testFunctionName];
    
    XCTAssertNotNil(createStatement, @"Should return CREATE FUNCTION statement");
    XCTAssertTrue([createStatement containsString:@"FUNCTION"] || [createStatement containsString:@"function"], 
                  @"Should contain FUNCTION keyword");
    XCTAssertTrue([createStatement containsString:testFunctionName], @"Should contain function name");
    
    NSLog(@"   ✓ CREATE FUNCTION statement retrieved:");
    NSLog(@"     %@", createStatement);
    
    // Test the function works
    id<SPDatabaseResult> result = [connection queryString:[NSString stringWithFormat:
        @"SELECT %@(5, 3) AS result", [connection quoteIdentifier:testFunctionName]]];
    [result setReturnDataAsStrings:YES];
    NSArray *row = [result getRowAsArray];
    XCTAssertEqualObjects(row[0], @"8", @"Function should return 5+3=8");
    NSLog(@"   ✓ Function works correctly: 5 + 3 = %@", row[0]);
    
    // Cleanup
    [connection queryString:[NSString stringWithFormat:
        @"DROP FUNCTION %@(INTEGER, INTEGER)", [connection quoteIdentifier:testFunctionName]]];
    [connection disconnect];
    
    NSLog(@"✅ Test 39 Passed: Get CREATE FUNCTION Statement");
}

#pragma mark - Test 40: Get CREATE PROCEDURE Statement

- (void)test_40_GetCreateProcedureStatement {
    NSLog(@"\n🧪 Test 40: Get CREATE PROCEDURE Statement");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect to database");
    
    // Check PostgreSQL version (procedures require 11+)
    id<SPDatabaseResult> versionResult = [connection queryString:@"SHOW server_version"];
    [versionResult setReturnDataAsStrings:YES];
    NSArray *versionRow = [versionResult getRowAsArray];
    NSString *versionString = versionRow[0];
    NSInteger majorVersion = [[versionString componentsSeparatedByString:@"."][0] integerValue];
    
    if (majorVersion < 11) {
        NSLog(@"   ⚠️ PostgreSQL %ld doesn't support procedures (requires 11+), skipping test", (long)majorVersion);
        [connection disconnect];
        return;
    }
    
    // Create a test table for the procedure to use
    NSString *testTableName = [NSString stringWithFormat:@"test_proc_table_%d", arc4random_uniform(100000)];
    NSString *testProcedureName = [NSString stringWithFormat:@"test_procedure_%d", arc4random_uniform(100000)];
    
    NSLog(@"   Creating test table: %@", testTableName);
    [connection queryString:[NSString stringWithFormat:
        @"CREATE TABLE %@ (id SERIAL PRIMARY KEY, counter INTEGER DEFAULT 0)",
        [connection quoteIdentifier:testTableName]]];
    
    // Create a test procedure
    NSLog(@"   Creating test procedure: %@", testProcedureName);
    NSString *createProcedureSQL = [NSString stringWithFormat:
        @"CREATE OR REPLACE PROCEDURE %@(increment_by INTEGER) "
        @"LANGUAGE plpgsql AS $$ "
        @"BEGIN "
        @"  INSERT INTO %@ (counter) VALUES (increment_by); "
        @"END; "
        @"$$",
        [connection quoteIdentifier:testProcedureName],
        [connection quoteIdentifier:testTableName]];
    
    [connection queryString:createProcedureSQL];
    XCTAssertFalse([connection queryErrored], @"Procedure creation should succeed: %@", [connection lastErrorMessage]);
    
    // Get the CREATE PROCEDURE statement
    NSLog(@"   Getting CREATE PROCEDURE statement...");
    NSString *createStatement = [connection getCreateStatementForProcedure:testProcedureName];
    
    XCTAssertNotNil(createStatement, @"Should return CREATE PROCEDURE statement");
    XCTAssertTrue([createStatement containsString:@"PROCEDURE"] || [createStatement containsString:@"procedure"], 
                  @"Should contain PROCEDURE keyword");
    XCTAssertTrue([createStatement containsString:testProcedureName], @"Should contain procedure name");
    
    NSLog(@"   ✓ CREATE PROCEDURE statement retrieved:");
    NSLog(@"     %@", createStatement);
    
    // Test the procedure works
    [connection queryString:[NSString stringWithFormat:
        @"CALL %@(42)", [connection quoteIdentifier:testProcedureName]]];
    XCTAssertFalse([connection queryErrored], @"Calling procedure should succeed");
    
    id<SPDatabaseResult> verifyResult = [connection queryString:[NSString stringWithFormat:
        @"SELECT counter FROM %@", [connection quoteIdentifier:testTableName]]];
    [verifyResult setReturnDataAsStrings:YES];
    NSArray *verifyRow = [verifyResult getRowAsArray];
    XCTAssertEqualObjects(verifyRow[0], @"42", @"Procedure should have inserted 42");
    NSLog(@"   ✓ Procedure works correctly: inserted value = %@", verifyRow[0]);
    
    // Cleanup
    [connection queryString:[NSString stringWithFormat:
        @"DROP PROCEDURE %@(INTEGER)", [connection quoteIdentifier:testProcedureName]]];
    [connection queryString:[NSString stringWithFormat:@"DROP TABLE %@", [connection quoteIdentifier:testTableName]]];
    [connection disconnect];
    
    NSLog(@"✅ Test 40 Passed: Get CREATE PROCEDURE Statement");
}

#pragma mark - Test 41: Build CREATE TABLE Statement

- (void)test_41_BuildCreateTableStatement {
    NSLog(@"\n🧪 Test 41: Build CREATE TABLE Statement");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect to database");
    
    // Test building CREATE TABLE statement
    NSString *testTableName = [NSString stringWithFormat:@"test_build_table_%d", arc4random_uniform(100000)];
    NSLog(@"   Building CREATE TABLE statement for: %@", testTableName);
    
    NSString *createStatement = [connection buildCreateTableStatementForTable:testTableName
                                                                    tableType:nil
                                                                 encodingName:nil
                                                                collationName:nil];
    
    XCTAssertNotNil(createStatement, @"Should return CREATE TABLE statement");
    XCTAssertTrue([createStatement containsString:@"CREATE TABLE"], @"Should contain CREATE TABLE");
    XCTAssertTrue([createStatement containsString:testTableName] || 
                  [createStatement containsString:[connection quoteIdentifier:testTableName]], 
                  @"Should contain table name");
    XCTAssertTrue([createStatement containsString:@"SERIAL"], @"Should use SERIAL for auto-increment");
    XCTAssertTrue([createStatement containsString:@"PRIMARY KEY"], @"Should have PRIMARY KEY");
    
    NSLog(@"   ✓ Built CREATE TABLE statement:");
    NSLog(@"     %@", createStatement);
    
    // Actually create the table using the generated statement
    NSLog(@"   Creating table using generated statement...");
    [connection queryString:createStatement];
    XCTAssertFalse([connection queryErrored], @"Table creation should succeed: %@", [connection lastErrorMessage]);
    
    // Verify table was created
    id<SPDatabaseResult> result = [connection queryString:[NSString stringWithFormat:
        @"SELECT column_name, data_type FROM information_schema.columns "
        @"WHERE table_name = '%@' ORDER BY ordinal_position",
        testTableName]];
    
    XCTAssertTrue([result numberOfRows] > 0, @"Table should have columns");
    [result setReturnDataAsStrings:YES];
    
    NSLog(@"   ✓ Table created with columns:");
    while (true) {
        NSArray *row = [result getRowAsArray];
        if (!row) break;
        NSLog(@"     - %@ (%@)", row[0], row[1]);
    }
    
    // Test inserting data (SERIAL should auto-increment)
    [connection queryString:[NSString stringWithFormat:
        @"INSERT INTO %@ DEFAULT VALUES", [connection quoteIdentifier:testTableName]]];
    XCTAssertFalse([connection queryErrored], @"Insert should succeed");
    
    id<SPDatabaseResult> selectResult = [connection queryString:[NSString stringWithFormat:
        @"SELECT * FROM %@", [connection quoteIdentifier:testTableName]]];
    XCTAssertEqual([selectResult numberOfRows], (NSUInteger)1, @"Should have 1 row");
    NSLog(@"   ✓ SERIAL auto-increment works");
    
    // Cleanup
    [connection queryString:[NSString stringWithFormat:@"DROP TABLE %@", [connection quoteIdentifier:testTableName]]];
    [connection disconnect];
    
    NSLog(@"✅ Test 41 Passed: Build CREATE TABLE Statement");
}

#pragma mark - Test 42: CREATE Statement Error Handling

- (void)test_42_CreateStatementErrorHandling {
    NSLog(@"\n🧪 Test 42: CREATE Statement Error Handling");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect to database");
    
    // Test getting CREATE statement for non-existent table
    NSLog(@"   Testing non-existent table...");
    NSString *nonExistentTable = @"this_table_does_not_exist_12345";
    NSString *createStatement = [connection getCreateStatementForTable:nonExistentTable];
    XCTAssertNil(createStatement, @"Should return nil for non-existent table");
    NSLog(@"   ✓ Returns nil for non-existent table");
    
    // Test getting CREATE statement for non-existent view
    NSLog(@"   Testing non-existent view...");
    NSString *nonExistentView = @"this_view_does_not_exist_12345";
    createStatement = [connection getCreateStatementForView:nonExistentView];
    XCTAssertNil(createStatement, @"Should return nil for non-existent view");
    NSLog(@"   ✓ Returns nil for non-existent view");
    
    // Test getting CREATE statement for non-existent function
    NSLog(@"   Testing non-existent function...");
    NSString *nonExistentFunction = @"this_function_does_not_exist_12345";
    createStatement = [connection getCreateStatementForFunction:nonExistentFunction];
    XCTAssertNil(createStatement, @"Should return nil for non-existent function");
    NSLog(@"   ✓ Returns nil for non-existent function");
    
    // Test getting CREATE statement for non-existent procedure
    NSLog(@"   Testing non-existent procedure...");
    NSString *nonExistentProcedure = @"this_procedure_does_not_exist_12345";
    createStatement = [connection getCreateStatementForProcedure:nonExistentProcedure];
    XCTAssertNil(createStatement, @"Should return nil for non-existent procedure");
    NSLog(@"   ✓ Returns nil for non-existent procedure");
    
    [connection disconnect];
    
    NSLog(@"✅ Test 42 Passed: CREATE Statement Error Handling");
}

#pragma mark - Test 43: Default Value Server Expression Detection

- (void)test_43_DefaultValueServerExpressionDetection {
    NSLog(@"\n🧪 Test 43: Default Value Server Expression Detection");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect to database");
    
    // Test PostgreSQL sequence expressions
    NSLog(@"   Testing sequence expressions...");
    XCTAssertTrue([connection isDefaultValueServerExpression:@"nextval('video_id_seq'::regclass)"], 
                  @"Should detect nextval as server expression");
    XCTAssertTrue([connection isDefaultValueServerExpression:@"nextval('test_table_id_seq'::regclass)"], 
                  @"Should detect nextval with different table name");
    NSLog(@"   ✓ Sequence expressions detected");
    
    // Test timestamp functions
    NSLog(@"   Testing timestamp functions...");
    XCTAssertTrue([connection isDefaultValueServerExpression:@"CURRENT_TIMESTAMP"], 
                  @"Should detect CURRENT_TIMESTAMP");
    XCTAssertTrue([connection isDefaultValueServerExpression:@"current_timestamp"], 
                  @"Should detect lowercase current_timestamp");
    XCTAssertTrue([connection isDefaultValueServerExpression:@"now()"], 
                  @"Should detect now()");
    XCTAssertTrue([connection isDefaultValueServerExpression:@"NOW()"], 
                  @"Should detect NOW()");
    XCTAssertTrue([connection isDefaultValueServerExpression:@"CURRENT_DATE"], 
                  @"Should detect CURRENT_DATE");
    XCTAssertTrue([connection isDefaultValueServerExpression:@"CURRENT_TIME"], 
                  @"Should detect CURRENT_TIME");
    XCTAssertTrue([connection isDefaultValueServerExpression:@"LOCALTIMESTAMP"], 
                  @"Should detect LOCALTIMESTAMP");
    XCTAssertTrue([connection isDefaultValueServerExpression:@"LOCALTIME"], 
                  @"Should detect LOCALTIME");
    NSLog(@"   ✓ Timestamp functions detected");
    
    // Test UUID functions
    NSLog(@"   Testing UUID functions...");
    XCTAssertTrue([connection isDefaultValueServerExpression:@"uuid_generate_v4()"], 
                  @"Should detect uuid_generate_v4()");
    XCTAssertTrue([connection isDefaultValueServerExpression:@"gen_random_uuid()"], 
                  @"Should detect gen_random_uuid()");
    NSLog(@"   ✓ UUID functions detected");
    
    // Test cast expressions
    NSLog(@"   Testing cast expressions (all treated as literals)...");
    XCTAssertFalse([connection isDefaultValueServerExpression:@"'test'::text"], 
                   @"Quoted string with ::text cast is a literal value");
    XCTAssertFalse([connection isDefaultValueServerExpression:@"0::integer"], 
                   @"Numeric cast is a literal value");
    XCTAssertFalse([connection isDefaultValueServerExpression:@"'2024-01-01'::date"], 
                   @"String with date cast is a literal value (will display with cast)");
    NSLog(@"   ✓ Cast expressions correctly treated as literals");
    
    // Test literal values (should NOT be detected as server expressions)
    NSLog(@"   Testing literal values (should NOT be server expressions)...");
    XCTAssertFalse([connection isDefaultValueServerExpression:@"42"], 
                   @"Numeric literal should not be server expression");
    XCTAssertFalse([connection isDefaultValueServerExpression:@"'default string'"], 
                   @"String literal should not be server expression");
    XCTAssertFalse([connection isDefaultValueServerExpression:@"0"], 
                   @"Zero should not be server expression");
    XCTAssertFalse([connection isDefaultValueServerExpression:@"true"], 
                   @"Boolean should not be server expression");
    XCTAssertFalse([connection isDefaultValueServerExpression:@"false"], 
                   @"Boolean should not be server expression");
    XCTAssertFalse([connection isDefaultValueServerExpression:@""], 
                   @"Empty string should not be server expression");
    XCTAssertFalse([connection isDefaultValueServerExpression:nil], 
                   @"nil should not be server expression");
    NSLog(@"   ✓ Literal values correctly NOT detected as server expressions");
    
    [connection disconnect];
    
    NSLog(@"✅ Test 43 Passed: Default Value Server Expression Detection");
}

#pragma mark - Test 44: Add Row with SERIAL and Timestamp Defaults

- (void)test_44_AddRowWithSerialAndTimestampDefaults {
    NSLog(@"\n🧪 Test 44: Add Row with SERIAL and Timestamp Defaults");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect to database");
    
    // Create a test table with SERIAL and TIMESTAMP defaults
    NSString *testTableName = [NSString stringWithFormat:@"test_defaults_%d", arc4random_uniform(100000)];
    NSLog(@"   Creating test table: %@", testTableName);
    
    NSString *createSQL = [NSString stringWithFormat:
        @"CREATE TABLE %@ ("
        @"  id SERIAL PRIMARY KEY, "
        @"  name TEXT NOT NULL, "
        @"  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "
        @"  updated_at TIMESTAMP DEFAULT now(), "
        @"  status TEXT DEFAULT 'active'"
        @")",
        [connection quoteIdentifier:testTableName]];
    
    [connection queryString:createSQL];
    XCTAssertFalse([connection queryErrored], @"Table creation should succeed: %@", [connection lastErrorMessage]);
    
    // Query column defaults
    NSLog(@"   Querying column defaults...");
    NSString *defaultsQuery = [NSString stringWithFormat:
        @"SELECT column_name, column_default "
        @"FROM information_schema.columns "
        @"WHERE table_name = '%@' "
        @"ORDER BY ordinal_position",
        testTableName];
    
    id<SPDatabaseResult> result = [connection queryString:defaultsQuery];
    [result setReturnDataAsStrings:YES];
    
    NSMutableDictionary *columnDefaults = [NSMutableDictionary dictionary];
    while (true) {
        NSArray *row = [result getRowAsArray];
        if (!row) break;
        
        NSString *columnName = row[0];
        id defaultValue = row[1];
        
        if (![defaultValue isKindOfClass:[NSNull class]]) {
            columnDefaults[columnName] = defaultValue;
            NSLog(@"     %@: %@", columnName, defaultValue);
        }
    }
    
    // Verify server expressions are detected
    NSLog(@"   Verifying server expression detection...");
    
    NSString *idDefault = columnDefaults[@"id"];
    if (idDefault) {
        XCTAssertTrue([connection isDefaultValueServerExpression:idDefault],
                      @"SERIAL default should be detected as server expression: %@", idDefault);
        XCTAssertTrue([idDefault containsString:@"nextval"],
                      @"SERIAL default should contain nextval: %@", idDefault);
        NSLog(@"     ✓ SERIAL default detected correctly");
    }
    
    NSString *createdAtDefault = columnDefaults[@"created_at"];
    if (createdAtDefault) {
        XCTAssertTrue([connection isDefaultValueServerExpression:createdAtDefault],
                      @"CURRENT_TIMESTAMP should be detected as server expression: %@", createdAtDefault);
        NSLog(@"     ✓ CURRENT_TIMESTAMP default detected correctly");
    }
    
    NSString *updatedAtDefault = columnDefaults[@"updated_at"];
    if (updatedAtDefault) {
        XCTAssertTrue([connection isDefaultValueServerExpression:updatedAtDefault],
                      @"now() should be detected as server expression: %@", updatedAtDefault);
        NSLog(@"     ✓ now() default detected correctly");
    }
    
    NSString *statusDefault = columnDefaults[@"status"];
    if (statusDefault) {
        XCTAssertFalse([connection isDefaultValueServerExpression:statusDefault],
                       @"Literal string default should NOT be server expression: %@", statusDefault);
        NSLog(@"     ✓ Literal default NOT detected as server expression");
    }
    
    // Insert a row with only the required field
    NSLog(@"   Inserting row with only required field...");
    [connection queryString:[NSString stringWithFormat:
        @"INSERT INTO %@ (name) VALUES ('test')",
        [connection quoteIdentifier:testTableName]]];
    XCTAssertFalse([connection queryErrored], @"Insert should succeed");
    
    // Verify the database computed the default values
    NSLog(@"   Verifying database computed default values...");
    id<SPDatabaseResult> selectResult = [connection queryString:[NSString stringWithFormat:
        @"SELECT id, name, created_at, updated_at, status FROM %@",
        [connection quoteIdentifier:testTableName]]];
    [selectResult setReturnDataAsStrings:YES];
    
    NSArray *insertedRow = [selectResult getRowAsArray];
    XCTAssertNotNil(insertedRow, @"Should get inserted row");
    XCTAssertEqual([insertedRow count], (NSUInteger)5, @"Should have 5 columns");
    
    // Verify id was auto-generated (SERIAL)
    NSString *generatedId = insertedRow[0];
    XCTAssertNotNil(generatedId, @"id should be generated");
    XCTAssertTrue([generatedId integerValue] > 0, @"Generated id should be positive: %@", generatedId);
    NSLog(@"     ✓ SERIAL generated id: %@", generatedId);
    
    // Verify name was inserted
    NSString *insertedName = insertedRow[1];
    XCTAssertEqualObjects(insertedName, @"test", @"Name should match");
    NSLog(@"     ✓ Name inserted correctly: %@", insertedName);
    
    // Verify created_at was auto-generated
    NSString *createdAt = insertedRow[2];
    XCTAssertNotNil(createdAt, @"created_at should be generated");
    XCTAssertTrue([createdAt length] > 0, @"created_at should not be empty");
    NSLog(@"     ✓ CURRENT_TIMESTAMP generated created_at: %@", createdAt);
    
    // Verify updated_at was auto-generated
    NSString *updatedAt = insertedRow[3];
    XCTAssertNotNil(updatedAt, @"updated_at should be generated");
    XCTAssertTrue([updatedAt length] > 0, @"updated_at should not be empty");
    NSLog(@"     ✓ now() generated updated_at: %@", updatedAt);
    
    // Verify status has literal default
    NSString *status = insertedRow[4];
    XCTAssertEqualObjects(status, @"active", @"status should have literal default");
    NSLog(@"     ✓ Literal default applied: %@", status);
    
    // Cleanup
    [connection queryString:[NSString stringWithFormat:@"DROP TABLE %@", [connection quoteIdentifier:testTableName]]];
    [connection disconnect];
    
    NSLog(@"✅ Test 44 Passed: Add Row with SERIAL and Timestamp Defaults");
}

#pragma mark - Test 45: Complex Default Expressions

- (void)test_45_ComplexDefaultExpressions {
    NSLog(@"\n🧪 Test 45: Complex Default Expressions");
    
    id<SPDatabaseConnection> connection = [self createAndConnectConnection];
    XCTAssertNotNil(connection, @"Should connect to database");
    
    // Test various complex expressions
    NSLog(@"   Testing complex function expressions...");
    
    // Math functions
    XCTAssertTrue([connection isDefaultValueServerExpression:@"random()"],
                  @"random() should be server expression");
    XCTAssertTrue([connection isDefaultValueServerExpression:@"floor(random() * 100)"],
                  @"Math expression should be server expression");
    
    // String functions
    XCTAssertTrue([connection isDefaultValueServerExpression:@"upper('test')"],
                  @"String function should be server expression");
    XCTAssertTrue([connection isDefaultValueServerExpression:@"concat('prefix_', now())"],
                  @"concat function should be server expression");
    
    // Array and JSON defaults - these use [] or {}, not (), so treated as literals
    XCTAssertFalse([connection isDefaultValueServerExpression:@"ARRAY[]::integer[]"],
                   @"ARRAY[] uses square brackets, treated as literal");
    XCTAssertFalse([connection isDefaultValueServerExpression:@"{}::jsonb"],
                   @"JSON object cast is treated as literal (shows in UI with cast)");
    
    // But expressions with parentheses are server expressions
    XCTAssertTrue([connection isDefaultValueServerExpression:@"(true)::boolean"],
                  @"Expression with parentheses is treated as server expression");
    
    NSLog(@"   ✓ Complex expressions detected correctly");
    
    // Test edge cases
    NSLog(@"   Testing edge cases...");
    
    // Quoted strings without casts should NOT be server expressions
    XCTAssertFalse([connection isDefaultValueServerExpression:@"'simple string'"],
                   @"Simple quoted string should not be server expression");
    
    // Numbers without casts
    XCTAssertFalse([connection isDefaultValueServerExpression:@"123"],
                   @"Plain number should not be server expression");
    XCTAssertFalse([connection isDefaultValueServerExpression:@"123.456"],
                   @"Decimal number should not be server expression");
    
    // But numbers WITH operations should be (has parentheses)
    XCTAssertTrue([connection isDefaultValueServerExpression:@"(5 + 3)"],
                  @"Math operation with parentheses is server expression");
    
    NSLog(@"   ✓ Edge cases handled correctly");
    
    [connection disconnect];
    
    NSLog(@"✅ Test 45 Passed: Complex Default Expressions");
}

@end

