//
//  SPAWSCredentialsTests.m
//  Sequel Ace
//
//  Unit tests for AWS credentials management.
//

#import <XCTest/XCTest.h>
#import "SPAWSCredentials.h"

@interface SPAWSCredentialsTests : XCTestCase
@end

@implementation SPAWSCredentialsTests

#pragma mark - Manual Credentials Tests

- (void)testInitWithValidManualCredentials
{
    SPAWSCredentials *creds = [[SPAWSCredentials alloc] initWithAccessKeyId:@"AKIAIOSFODNN7EXAMPLE"
                                                           secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
                                                              sessionToken:nil];

    XCTAssertNotNil(creds, @"Credentials should be created");
    XCTAssertEqualObjects(creds.accessKeyId, @"AKIAIOSFODNN7EXAMPLE");
    XCTAssertEqualObjects(creds.secretAccessKey, @"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY");
    XCTAssertNil(creds.sessionToken);
    XCTAssertNil(creds.profileName);
    XCTAssertTrue([creds isValid]);
}

- (void)testInitWithSessionToken
{
    SPAWSCredentials *creds = [[SPAWSCredentials alloc] initWithAccessKeyId:@"AKIAIOSFODNN7EXAMPLE"
                                                           secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
                                                              sessionToken:@"FwoGZXIvYXdzEBYaDExample"];

    XCTAssertNotNil(creds, @"Credentials should be created");
    XCTAssertEqualObjects(creds.sessionToken, @"FwoGZXIvYXdzEBYaDExample");
    XCTAssertTrue([creds isValid]);
}

- (void)testIsValidWithEmptyAccessKey
{
    SPAWSCredentials *creds = [[SPAWSCredentials alloc] initWithAccessKeyId:@""
                                                           secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
                                                              sessionToken:nil];

    XCTAssertFalse([creds isValid], @"Credentials with empty access key should be invalid");
}

- (void)testIsValidWithEmptySecretKey
{
    SPAWSCredentials *creds = [[SPAWSCredentials alloc] initWithAccessKeyId:@"AKIAIOSFODNN7EXAMPLE"
                                                           secretAccessKey:@""
                                                              sessionToken:nil];

    XCTAssertFalse([creds isValid], @"Credentials with empty secret key should be invalid");
}

#pragma mark - Profile Tests

- (void)testCredentialsFilePath
{
    NSString *path = [SPAWSCredentials credentialsFilePath];
    XCTAssertNotNil(path, @"Credentials file path should not be nil");
    XCTAssertTrue([path hasSuffix:@".aws/credentials"], @"Path should end with .aws/credentials");
}

- (void)testAvailableProfilesReturnsArray
{
    NSArray *profiles = [SPAWSCredentials availableProfiles];
    XCTAssertNotNil(profiles, @"Available profiles should return an array (possibly empty)");
    XCTAssertTrue([profiles isKindOfClass:[NSArray class]], @"Should return NSArray");
}

- (void)testInitWithNonExistentProfile
{
    NSError *error = nil;
    SPAWSCredentials *creds = [[SPAWSCredentials alloc] initWithProfile:@"this-profile-definitely-does-not-exist-12345"
                                                                  error:&error];

    // Either credentials file doesn't exist, or profile doesn't exist
    // In either case, creds should be nil and error should be set
    if (![SPAWSCredentials credentialsFileExists]) {
        XCTAssertNil(creds, @"Should return nil when credentials file doesn't exist");
        XCTAssertNotNil(error, @"Error should be set");
    } else {
        XCTAssertNil(creds, @"Should return nil for non-existent profile");
        XCTAssertNotNil(error, @"Error should be set for non-existent profile");
    }
}

#pragma mark - Description Tests

- (void)testDescription
{
    SPAWSCredentials *creds = [[SPAWSCredentials alloc] initWithAccessKeyId:@"AKIAIOSFODNN7EXAMPLE"
                                                           secretAccessKey:@"secret"
                                                              sessionToken:nil];

    NSString *desc = [creds description];
    XCTAssertNotNil(desc);
    // Description should contain partial access key but NOT the full secret
    XCTAssertTrue([desc containsString:@"AKIA"], @"Description should contain partial access key");
    XCTAssertFalse([desc containsString:@"secret"], @"Description should NOT contain secret key");
}

@end
