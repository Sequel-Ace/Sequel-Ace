//
//  SPRDSIAMAuthentication.h
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

@class SPAWSCredentials;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const SPRDSIAMAuthenticationErrorDomain;

typedef NS_ENUM(NSInteger, SPRDSIAMAuthenticationError) {
    SPRDSIAMAuthenticationErrorInvalidCredentials = 1,
    SPRDSIAMAuthenticationErrorInvalidParameters = 2,
    SPRDSIAMAuthenticationErrorSigningFailed = 3
};

/**
 * Generates AWS RDS IAM authentication tokens using AWS Signature Version 4.
 *
 * The token is a presigned URL that can be used as a password to authenticate
 * to RDS/Aurora MySQL databases with IAM authentication enabled.
 *
 * Tokens are valid for 15 minutes from generation.
 */
@interface SPRDSIAMAuthentication : NSObject

/**
 * Generate an RDS authentication token.
 *
 * @param hostname The RDS instance hostname (e.g., mydb.123456789012.us-east-1.rds.amazonaws.com)
 * @param port The database port (typically 3306 for MySQL)
 * @param username The database username (must match the IAM user/role)
 * @param region The AWS region (e.g., us-east-1). If nil, will attempt to extract from hostname.
 * @param credentials The AWS credentials to use for signing
 * @param error Error output if token generation fails
 * @return The authentication token to use as a password, or nil on failure
 */
+ (nullable NSString *)generateAuthTokenForHost:(NSString *)hostname
                                           port:(NSInteger)port
                                       username:(NSString *)username
                                         region:(nullable NSString *)region
                                    credentials:(SPAWSCredentials *)credentials
                                          error:(NSError **)error;

/**
 * Extract AWS region from an RDS hostname.
 * @param hostname The RDS hostname (e.g., mydb.123456789012.us-east-1.rds.amazonaws.com)
 * @return The region string, or nil if not extractable
 */
+ (nullable NSString *)regionFromHostname:(NSString *)hostname;

/**
 * Check if the given hostname appears to be an RDS endpoint.
 */
+ (BOOL)isRDSHostname:(NSString *)hostname;

/**
 * Token lifetime in seconds (900 = 15 minutes)
 */
+ (NSInteger)tokenLifetimeSeconds;

@end

NS_ASSUME_NONNULL_END
