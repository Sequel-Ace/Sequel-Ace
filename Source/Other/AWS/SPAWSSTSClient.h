//
//  SPAWSSTSClient.h
//  Sequel Ace
//
//  Created for AWS IAM authentication support with MFA.
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

@class SPAWSCredentials;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const SPAWSSTSClientErrorDomain;

typedef NS_ENUM(NSInteger, SPAWSSTSClientError) {
    SPAWSSTSClientErrorInvalidCredentials = 1,
    SPAWSSTSClientErrorInvalidParameters = 2,
    SPAWSSTSClientErrorNetworkFailure = 3,
    SPAWSSTSClientErrorInvalidResponse = 4,
    SPAWSSTSClientErrorAccessDenied = 5,
    SPAWSSTSClientErrorMFARequired = 6
};

/**
 * AWS STS (Security Token Service) client for assuming roles with MFA support.
 *
 * This client implements the AWS STS AssumeRole API with Signature Version 4 signing.
 */
@interface SPAWSSTSClient : NSObject

/**
 * Assume an IAM role and get temporary credentials.
 *
 * @param roleArn The ARN of the role to assume (e.g., arn:aws:iam::123456789012:role/MyRole)
 * @param roleSessionName A name for the assumed role session
 * @param mfaSerialNumber The MFA device serial number (optional, but required if MFA is enforced)
 * @param mfaTokenCode The 6-digit MFA token code (required if mfaSerialNumber is provided)
 * @param durationSeconds Session duration in seconds (900-43200, default 3600)
 * @param region The AWS region for STS endpoint (e.g., us-east-1)
 * @param credentials The base credentials to use for signing the AssumeRole request
 * @param error Error output if the operation fails
 * @return New SPAWSCredentials with temporary credentials, or nil on failure
 */
+ (nullable SPAWSCredentials *)assumeRole:(NSString *)roleArn
                          roleSessionName:(NSString *)roleSessionName
                          mfaSerialNumber:(nullable NSString *)mfaSerialNumber
                             mfaTokenCode:(nullable NSString *)mfaTokenCode
                          durationSeconds:(NSInteger)durationSeconds
                                   region:(NSString *)region
                              credentials:(SPAWSCredentials *)credentials
                                    error:(NSError **)error;

/**
 * Convenience method to assume a role with MFA.
 */
+ (nullable SPAWSCredentials *)assumeRoleWithMFA:(NSString *)roleArn
                                 mfaSerialNumber:(NSString *)mfaSerialNumber
                                    mfaTokenCode:(NSString *)mfaTokenCode
                                          region:(NSString *)region
                                     credentials:(SPAWSCredentials *)credentials
                                           error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
