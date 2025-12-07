//
//  SPRDSIAMAuthenticationTests.m
//  Sequel Ace
//
//  Unit tests for AWS RDS IAM authentication token generation.
//

#import <XCTest/XCTest.h>
#import "SPRDSIAMAuthentication.h"
#import "SPAWSCredentials.h"

@interface SPRDSIAMAuthenticationTests : XCTestCase
@property (nonatomic, strong) SPAWSCredentials *testCredentials;
@end

@implementation SPRDSIAMAuthenticationTests

- (void)setUp
{
    [super setUp];
    // Use AWS example credentials (not real)
    self.testCredentials = [[SPAWSCredentials alloc] initWithAccessKeyId:@"AKIAIOSFODNN7EXAMPLE"
                                                         secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
                                                            sessionToken:nil];
}

- (void)tearDown
{
    self.testCredentials = nil;
    [super tearDown];
}

#pragma mark - Region Detection Tests

- (void)testRegionFromStandardRDSHostname
{
    NSString *region = [SPRDSIAMAuthentication regionFromHostname:@"mydb.abc123def456.us-east-1.rds.amazonaws.com"];
    XCTAssertEqualObjects(region, @"us-east-1", @"Should extract us-east-1 from hostname");
}

- (void)testRegionFromAuroraHostname
{
    NSString *region = [SPRDSIAMAuthentication regionFromHostname:@"mydb-cluster.cluster-abc123.eu-west-2.rds.amazonaws.com"];
    XCTAssertEqualObjects(region, @"eu-west-2", @"Should extract eu-west-2 from Aurora hostname");
}

- (void)testRegionFromApRegionHostname
{
    NSString *region = [SPRDSIAMAuthentication regionFromHostname:@"database.xyz789.ap-southeast-1.rds.amazonaws.com"];
    XCTAssertEqualObjects(region, @"ap-southeast-1", @"Should extract ap-southeast-1 from hostname");
}

- (void)testRegionFromGovCloudHostname
{
    NSString *region = [SPRDSIAMAuthentication regionFromHostname:@"mydb.abc123.us-gov-west-1.rds.amazonaws.com"];
    XCTAssertEqualObjects(region, @"us-gov-west-1", @"Should extract us-gov-west-1 from GovCloud hostname");
}

- (void)testRegionFromInvalidHostname
{
    NSString *region = [SPRDSIAMAuthentication regionFromHostname:@"localhost"];
    XCTAssertNil(region, @"Should return nil for non-RDS hostname");
}

- (void)testRegionFromEmptyHostname
{
    NSString *region = [SPRDSIAMAuthentication regionFromHostname:@""];
    XCTAssertNil(region, @"Should return nil for empty hostname");
}

- (void)testRegionFromNilHostname
{
    NSString *region = [SPRDSIAMAuthentication regionFromHostname:nil];
    XCTAssertNil(region, @"Should return nil for nil hostname");
}

#pragma mark - RDS Hostname Detection Tests

- (void)testIsRDSHostnameWithValidRDS
{
    XCTAssertTrue([SPRDSIAMAuthentication isRDSHostname:@"mydb.abc123.us-east-1.rds.amazonaws.com"]);
    XCTAssertTrue([SPRDSIAMAuthentication isRDSHostname:@"MYDB.ABC123.US-EAST-1.RDS.AMAZONAWS.COM"]);
}

- (void)testIsRDSHostnameWithChinaRegion
{
    XCTAssertTrue([SPRDSIAMAuthentication isRDSHostname:@"mydb.abc123.cn-north-1.rds.amazonaws.com.cn"]);
}

- (void)testIsRDSHostnameWithLocalhost
{
    XCTAssertFalse([SPRDSIAMAuthentication isRDSHostname:@"localhost"]);
    XCTAssertFalse([SPRDSIAMAuthentication isRDSHostname:@"127.0.0.1"]);
}

- (void)testIsRDSHostnameWithEmpty
{
    XCTAssertFalse([SPRDSIAMAuthentication isRDSHostname:@""]);
    XCTAssertFalse([SPRDSIAMAuthentication isRDSHostname:nil]);
}

#pragma mark - Token Lifetime Tests

- (void)testTokenLifetime
{
    NSInteger lifetime = [SPRDSIAMAuthentication tokenLifetimeSeconds];
    XCTAssertEqual(lifetime, 900, @"Token lifetime should be 900 seconds (15 minutes)");
}

#pragma mark - Token Generation Tests

- (void)testGenerateTokenWithValidInputs
{
    NSError *error = nil;
    NSString *token = [SPRDSIAMAuthentication generateAuthTokenForHost:@"mydb.abc123.us-east-1.rds.amazonaws.com"
                                                                  port:3306
                                                              username:@"admin"
                                                                region:@"us-east-1"
                                                           credentials:self.testCredentials
                                                                 error:&error];

    XCTAssertNotNil(token, @"Token should be generated");
    XCTAssertNil(error, @"No error should occur");

    // Token should contain expected components
    XCTAssertTrue([token containsString:@"mydb.abc123.us-east-1.rds.amazonaws.com:3306"], @"Token should contain host:port");
    XCTAssertTrue([token containsString:@"Action=connect"], @"Token should contain Action=connect");
    XCTAssertTrue([token containsString:@"DBUser=admin"], @"Token should contain DBUser");
    XCTAssertTrue([token containsString:@"X-Amz-Algorithm=AWS4-HMAC-SHA256"], @"Token should contain algorithm");
    XCTAssertTrue([token containsString:@"X-Amz-Signature="], @"Token should contain signature");
    XCTAssertTrue([token containsString:@"X-Amz-Expires=900"], @"Token should have 900 second expiry");
}

- (void)testGenerateTokenWithAutoDetectedRegion
{
    NSError *error = nil;
    NSString *token = [SPRDSIAMAuthentication generateAuthTokenForHost:@"mydb.abc123.eu-west-1.rds.amazonaws.com"
                                                                  port:3306
                                                              username:@"dbuser"
                                                                region:nil  // Auto-detect
                                                           credentials:self.testCredentials
                                                                 error:&error];

    XCTAssertNotNil(token, @"Token should be generated with auto-detected region");
    XCTAssertNil(error, @"No error should occur");
    XCTAssertTrue([token containsString:@"eu-west-1"], @"Token should contain auto-detected region");
}

- (void)testGenerateTokenWithDefaultPort
{
    NSError *error = nil;
    NSString *token = [SPRDSIAMAuthentication generateAuthTokenForHost:@"mydb.abc123.us-east-1.rds.amazonaws.com"
                                                                  port:0  // Should default to 3306
                                                              username:@"admin"
                                                                region:@"us-east-1"
                                                           credentials:self.testCredentials
                                                                 error:&error];

    XCTAssertNotNil(token, @"Token should be generated with default port");
    XCTAssertTrue([token containsString:@":3306"], @"Token should use default port 3306");
}

- (void)testGenerateTokenWithCustomPort
{
    NSError *error = nil;
    NSString *token = [SPRDSIAMAuthentication generateAuthTokenForHost:@"mydb.abc123.us-east-1.rds.amazonaws.com"
                                                                  port:3307
                                                              username:@"admin"
                                                                region:@"us-east-1"
                                                           credentials:self.testCredentials
                                                                 error:&error];

    XCTAssertNotNil(token, @"Token should be generated with custom port");
    XCTAssertTrue([token containsString:@":3307"], @"Token should use custom port 3307");
}

- (void)testGenerateTokenWithSessionToken
{
    SPAWSCredentials *credsWithSession = [[SPAWSCredentials alloc] initWithAccessKeyId:@"AKIAIOSFODNN7EXAMPLE"
                                                                      secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
                                                                         sessionToken:@"FwoGZXIvYXdzEBYaDExampleSessionToken"];

    NSError *error = nil;
    NSString *token = [SPRDSIAMAuthentication generateAuthTokenForHost:@"mydb.abc123.us-east-1.rds.amazonaws.com"
                                                                  port:3306
                                                              username:@"admin"
                                                                region:@"us-east-1"
                                                           credentials:credsWithSession
                                                                 error:&error];

    XCTAssertNotNil(token, @"Token should be generated with session token");
    XCTAssertTrue([token containsString:@"X-Amz-Security-Token="], @"Token should contain security token parameter");
}

#pragma mark - Error Handling Tests

- (void)testGenerateTokenWithEmptyHostname
{
    NSError *error = nil;
    NSString *token = [SPRDSIAMAuthentication generateAuthTokenForHost:@""
                                                                  port:3306
                                                              username:@"admin"
                                                                region:@"us-east-1"
                                                           credentials:self.testCredentials
                                                                 error:&error];

    XCTAssertNil(token, @"Token should be nil for empty hostname");
    XCTAssertNotNil(error, @"Error should be set");
    XCTAssertEqual(error.code, SPRDSIAMAuthenticationErrorInvalidParameters);
}

- (void)testGenerateTokenWithEmptyUsername
{
    NSError *error = nil;
    NSString *token = [SPRDSIAMAuthentication generateAuthTokenForHost:@"mydb.abc123.us-east-1.rds.amazonaws.com"
                                                                  port:3306
                                                              username:@""
                                                                region:@"us-east-1"
                                                           credentials:self.testCredentials
                                                                 error:&error];

    XCTAssertNil(token, @"Token should be nil for empty username");
    XCTAssertNotNil(error, @"Error should be set");
    XCTAssertEqual(error.code, SPRDSIAMAuthenticationErrorInvalidParameters);
}

- (void)testGenerateTokenWithNilCredentials
{
    NSError *error = nil;
    NSString *token = [SPRDSIAMAuthentication generateAuthTokenForHost:@"mydb.abc123.us-east-1.rds.amazonaws.com"
                                                                  port:3306
                                                              username:@"admin"
                                                                region:@"us-east-1"
                                                           credentials:nil
                                                                 error:&error];

    XCTAssertNil(token, @"Token should be nil for nil credentials");
    XCTAssertNotNil(error, @"Error should be set");
    XCTAssertEqual(error.code, SPRDSIAMAuthenticationErrorInvalidCredentials);
}

- (void)testGenerateTokenWithMissingRegion
{
    NSError *error = nil;
    // Use a hostname that doesn't have a recognizable region
    NSString *token = [SPRDSIAMAuthentication generateAuthTokenForHost:@"localhost"
                                                                  port:3306
                                                              username:@"admin"
                                                                region:nil  // Can't auto-detect from localhost
                                                           credentials:self.testCredentials
                                                                 error:&error];

    XCTAssertNil(token, @"Token should be nil when region can't be determined");
    XCTAssertNotNil(error, @"Error should be set");
    XCTAssertEqual(error.code, SPRDSIAMAuthenticationErrorInvalidParameters);
}

#pragma mark - Token Uniqueness Tests

- (void)testTokensAreDifferentOverTime
{
    // Generate two tokens with a small delay - they should be different due to timestamp
    NSError *error1 = nil;
    NSString *token1 = [SPRDSIAMAuthentication generateAuthTokenForHost:@"mydb.abc123.us-east-1.rds.amazonaws.com"
                                                                   port:3306
                                                               username:@"admin"
                                                                 region:@"us-east-1"
                                                            credentials:self.testCredentials
                                                                  error:&error1];

    // Sleep briefly to ensure timestamp changes
    [NSThread sleepForTimeInterval:1.1];

    NSError *error2 = nil;
    NSString *token2 = [SPRDSIAMAuthentication generateAuthTokenForHost:@"mydb.abc123.us-east-1.rds.amazonaws.com"
                                                                   port:3306
                                                               username:@"admin"
                                                                 region:@"us-east-1"
                                                            credentials:self.testCredentials
                                                                  error:&error2];

    XCTAssertNotNil(token1);
    XCTAssertNotNil(token2);
    XCTAssertNotEqualObjects(token1, token2, @"Tokens generated at different times should be different");
}

#pragma mark - URL Encoding Tests

- (void)testUsernameWithSpecialCharactersIsEncoded
{
    NSError *error = nil;
    NSString *token = [SPRDSIAMAuthentication generateAuthTokenForHost:@"mydb.abc123.us-east-1.rds.amazonaws.com"
                                                                  port:3306
                                                              username:@"user@domain.com"
                                                                region:@"us-east-1"
                                                           credentials:self.testCredentials
                                                                 error:&error];

    XCTAssertNotNil(token, @"Token should be generated for username with special characters");
    // @ should be URL encoded as %40
    XCTAssertTrue([token containsString:@"DBUser=user%40domain.com"], @"Username should be URL encoded");
}

@end
