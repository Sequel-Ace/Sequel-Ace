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

@end

