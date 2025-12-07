//
//  SPAWSCredentials.h
//  Sequel Ace
//
//  Created for AWS IAM authentication support.
//  Copyright (c) 2024 Sequel-Ace. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Represents AWS credentials (access key, secret key, and optional session token).
 * Can be loaded from AWS credentials file profiles or set manually.
 */
@interface SPAWSCredentials : NSObject

@property (nonatomic, copy, readonly) NSString *accessKeyId;
@property (nonatomic, copy, readonly) NSString *secretAccessKey;
@property (nonatomic, copy, readonly, nullable) NSString *sessionToken;
@property (nonatomic, copy, readonly, nullable) NSString *profileName;

// Profile configuration (for role assumption with MFA)
@property (nonatomic, copy, readonly, nullable) NSString *roleArn;
@property (nonatomic, copy, readonly, nullable) NSString *mfaSerial;
@property (nonatomic, copy, readonly, nullable) NSString *sourceProfile;
@property (nonatomic, copy, readonly, nullable) NSString *region;

/**
 * Initialize with explicit credentials.
 */
- (instancetype)initWithAccessKeyId:(NSString *)accessKeyId
                    secretAccessKey:(NSString *)secretAccessKey
                       sessionToken:(nullable NSString *)sessionToken;

/**
 * Initialize by loading credentials from a named profile in ~/.aws/credentials
 * @param profileName The AWS profile name (use nil or "default" for default profile)
 * @param error Error output if credentials cannot be loaded
 * @return Credentials instance or nil on failure
 */
- (nullable instancetype)initWithProfile:(nullable NSString *)profileName
                                   error:(NSError **)error;

/**
 * Get a list of available profile names from ~/.aws/credentials and ~/.aws/config
 */
+ (NSArray<NSString *> *)availableProfiles;

/**
 * Check if AWS credentials file exists
 */
+ (BOOL)credentialsFileExists;

/**
 * Path to the AWS credentials file (~/.aws/credentials)
 */
+ (NSString *)credentialsFilePath;

/**
 * Path to the AWS config file (~/.aws/config)
 */
+ (NSString *)configFilePath;

/**
 * Validates that the credentials have the required fields
 */
- (BOOL)isValid;

/**
 * Check if this profile requires MFA for role assumption
 */
- (BOOL)requiresMFA;

/**
 * Check if this profile requires role assumption (has role_arn)
 */
- (BOOL)requiresRoleAssumption;

/**
 * Get profile configuration info for a profile without loading credentials
 * @return Dictionary with role_arn, mfa_serial, source_profile, region if present
 */
+ (nullable NSDictionary *)profileConfigurationForProfile:(NSString *)profileName;

@end

NS_ASSUME_NONNULL_END
