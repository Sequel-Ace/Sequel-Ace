//
//  SPRDSIAMAuthentication.m
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

#import "SPRDSIAMAuthentication.h"
#import "SPAWSCredentials.h"
#import <CommonCrypto/CommonHMAC.h>

NSString * const SPRDSIAMAuthenticationErrorDomain = @"SPRDSIAMAuthenticationErrorDomain";

// AWS Signature Version 4 constants
static NSString * const kAWSAlgorithm = @"AWS4-HMAC-SHA256";
static NSString * const kAWSService = @"rds-db";
static NSString * const kAWSRequest = @"aws4_request";
static NSString * const kRDSConnectAction = @"connect";
static const NSInteger kTokenExpirationSeconds = 900; // 15 minutes

@implementation SPRDSIAMAuthentication

+ (nullable NSString *)generateAuthTokenForHost:(NSString *)hostname
                                           port:(NSInteger)port
                                       username:(NSString *)username
                                         region:(nullable NSString *)region
                                    credentials:(SPAWSCredentials *)credentials
                                          error:(NSError **)error {
    // Validate inputs
    if (!credentials || ![credentials isValid]) {
        if (error) {
            *error = [NSError errorWithDomain:SPRDSIAMAuthenticationErrorDomain
                                         code:SPRDSIAMAuthenticationErrorInvalidCredentials
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid AWS credentials"}];
        }
        return nil;
    }

    if (hostname.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:SPRDSIAMAuthenticationErrorDomain
                                         code:SPRDSIAMAuthenticationErrorInvalidParameters
                                     userInfo:@{NSLocalizedDescriptionKey: @"Hostname is required"}];
        }
        return nil;
    }

    if (username.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:SPRDSIAMAuthenticationErrorDomain
                                         code:SPRDSIAMAuthenticationErrorInvalidParameters
                                     userInfo:@{NSLocalizedDescriptionKey: @"Username is required"}];
        }
        return nil;
    }

    // Determine region
    NSString *effectiveRegion = region;
    if (effectiveRegion.length == 0) {
        effectiveRegion = [self regionFromHostname:hostname];
    }
    if (effectiveRegion.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:SPRDSIAMAuthenticationErrorDomain
                                         code:SPRDSIAMAuthenticationErrorInvalidParameters
                                     userInfo:@{NSLocalizedDescriptionKey: @"AWS region is required and could not be determined from hostname"}];
        }
        return nil;
    }

    // Use port 3306 as default for MySQL
    NSInteger effectivePort = port > 0 ? port : 3306;

    // Generate the presigned URL token
    return [self buildPresignedTokenForHost:hostname
                                       port:effectivePort
                                   username:username
                                     region:effectiveRegion
                                credentials:credentials
                                      error:error];
}

+ (nullable NSString *)buildPresignedTokenForHost:(NSString *)hostname
                                             port:(NSInteger)port
                                         username:(NSString *)username
                                           region:(NSString *)region
                                      credentials:(SPAWSCredentials *)credentials
                                            error:(NSError **)error {
    // Get current time in UTC
    NSDate *now = [NSDate date];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];

    // Format: YYYYMMDD'T'HHMMSS'Z'
    [dateFormatter setDateFormat:@"yyyyMMdd'T'HHmmss'Z'"];
    NSString *amzDate = [dateFormatter stringFromDate:now];

    // Format: YYYYMMDD
    [dateFormatter setDateFormat:@"yyyyMMdd"];
    NSString *dateStamp = [dateFormatter stringFromDate:now];

    // Build the canonical request components
    NSString *hostWithPort = [NSString stringWithFormat:@"%@:%ld", hostname, (long)port];
    NSString *httpMethod = @"GET";
    NSString *canonicalUri = @"/";

    // Build credential scope
    NSString *credentialScope = [NSString stringWithFormat:@"%@/%@/%@/%@",
                                 dateStamp, region, kAWSService, kAWSRequest];

    // URL-encode the database user
    NSString *encodedUsername = [self urlEncode:username];

    // Build query parameters (must be sorted alphabetically)
    // X-Amz-Security-Token IS included in the canonical query string and signature calculation
    // Alphabetical order: Se comes before Si, so Security-Token before SignedHeaders
    NSString *canonicalQueryString;
    if (credentials.sessionToken.length > 0) {
        canonicalQueryString = [NSString stringWithFormat:
            @"Action=%@&DBUser=%@&X-Amz-Algorithm=%@&X-Amz-Credential=%@&X-Amz-Date=%@&X-Amz-Expires=%ld&X-Amz-Security-Token=%@&X-Amz-SignedHeaders=host",
            kRDSConnectAction,
            encodedUsername,
            kAWSAlgorithm,
            [self urlEncode:[NSString stringWithFormat:@"%@/%@", credentials.accessKeyId, credentialScope]],
            amzDate,
            (long)kTokenExpirationSeconds,
            [self urlEncode:credentials.sessionToken]];
    } else {
        canonicalQueryString = [NSString stringWithFormat:
            @"Action=%@&DBUser=%@&X-Amz-Algorithm=%@&X-Amz-Credential=%@&X-Amz-Date=%@&X-Amz-Expires=%ld&X-Amz-SignedHeaders=host",
            kRDSConnectAction,
            encodedUsername,
            kAWSAlgorithm,
            [self urlEncode:[NSString stringWithFormat:@"%@/%@", credentials.accessKeyId, credentialScope]],
            amzDate,
            (long)kTokenExpirationSeconds];
    }

    // Canonical headers - for RDS, we only include the host header
    NSString *canonicalHeaders = [NSString stringWithFormat:@"host:%@\n", hostWithPort];
    NSString *signedHeaders = @"host";

    // For RDS IAM auth token (GET request), payload hash is SHA256 of empty string
    // e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 = SHA256("")
    NSString *payloadHash = @"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

    // Build canonical request
    NSString *canonicalRequest = [NSString stringWithFormat:@"%@\n%@\n%@\n%@\n%@\n%@",
                                  httpMethod,
                                  canonicalUri,
                                  canonicalQueryString,
                                  canonicalHeaders,
                                  signedHeaders,
                                  payloadHash];

    // Create string to sign
    NSString *canonicalRequestHash = [self sha256Hex:canonicalRequest];
    NSString *stringToSign = [NSString stringWithFormat:@"%@\n%@\n%@\n%@",
                              kAWSAlgorithm,
                              amzDate,
                              credentialScope,
                              canonicalRequestHash];

    // Calculate signing key
    NSData *signingKey = [self deriveSigningKeyWithSecretKey:credentials.secretAccessKey
                                                   dateStamp:dateStamp
                                                      region:region
                                                     service:kAWSService];

    // Calculate signature
    NSString *signature = [self hmacSHA256Hex:stringToSign withKey:signingKey];

    // Build final token (presigned URL format, but without the scheme)
    // Signature is appended at the end
    NSString *token = [NSString stringWithFormat:@"%@/?%@&X-Amz-Signature=%@",
                       hostWithPort,
                       canonicalQueryString,
                       signature];

    return token;
}

#pragma mark - AWS Signature V4 Helper Methods

+ (NSData *)deriveSigningKeyWithSecretKey:(NSString *)secretKey
                                dateStamp:(NSString *)dateStamp
                                   region:(NSString *)region
                                  service:(NSString *)service {
    NSString *kSecret = [NSString stringWithFormat:@"AWS4%@", secretKey];
    NSData *kDate = [self hmacSHA256:[dateStamp dataUsingEncoding:NSUTF8StringEncoding]
                             withKey:[kSecret dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *kRegion = [self hmacSHA256:[region dataUsingEncoding:NSUTF8StringEncoding]
                               withKey:kDate];
    NSData *kService = [self hmacSHA256:[service dataUsingEncoding:NSUTF8StringEncoding]
                                withKey:kRegion];
    NSData *kSigning = [self hmacSHA256:[kAWSRequest dataUsingEncoding:NSUTF8StringEncoding]
                                withKey:kService];
    return kSigning;
}

+ (NSData *)hmacSHA256:(NSData *)data withKey:(NSData *)key {
    unsigned char result[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, data.bytes, data.length, result);
    return [NSData dataWithBytes:result length:CC_SHA256_DIGEST_LENGTH];
}

+ (NSString *)hmacSHA256Hex:(NSString *)string withKey:(NSData *)key {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSData *hmac = [self hmacSHA256:data withKey:key];
    return [self hexEncode:hmac];
}

+ (NSString *)sha256Hex:(NSString *)string {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char result[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, result);
    NSData *hash = [NSData dataWithBytes:result length:CC_SHA256_DIGEST_LENGTH];
    return [self hexEncode:hash];
}

+ (NSString *)hexEncode:(NSData *)data {
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
    const unsigned char *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return hex;
}

+ (NSString *)urlEncode:(NSString *)string {
    // AWS requires specific URL encoding (RFC 3986)
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [string stringByAddingPercentEncodingWithAllowedCharacters:allowed];
}

#pragma mark - Region Detection

+ (nullable NSString *)regionFromHostname:(NSString *)hostname {
    if (hostname.length == 0) {
        return nil;
    }

    // RDS hostnames typically follow these patterns:
    // - Standard: <identifier>.<account-id>.<region>.rds.amazonaws.com
    // - Aurora: <cluster-identifier>.<random>.<region>.rds.amazonaws.com
    // - Proxy: <proxy-endpoint>.<region>.rds.amazonaws.com

    NSArray<NSString *> *components = [hostname componentsSeparatedByString:@"."];

    // Find the component that looks like a region (e.g., us-east-1, eu-west-2)
    // Regions typically come before "rds" in the hostname
    for (NSUInteger i = 0; i < components.count; i++) {
        NSString *component = components[i];

        // Check if this looks like a region
        if ([self isValidAWSRegion:component]) {
            return component;
        }
    }

    return nil;
}

+ (BOOL)isValidAWSRegion:(NSString *)string {
    // AWS regions follow patterns like: us-east-1, eu-west-2, ap-southeast-1, etc.
    // Also includes special regions like: us-gov-west-1, cn-north-1
    NSString *regionPattern = @"^(us|eu|ap|sa|ca|me|af|cn|us-gov|us-iso|us-isob)-(east|west|north|south|central|northeast|southeast|northwest|southwest)-[1-9]$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regionPattern
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:nil];
    NSRange range = NSMakeRange(0, string.length);
    return [regex numberOfMatchesInString:string options:0 range:range] > 0;
}

+ (BOOL)isRDSHostname:(NSString *)hostname {
    if (hostname.length == 0) {
        return NO;
    }

    NSString *lowercased = [hostname lowercaseString];

    // Check for common RDS hostname patterns
    return [lowercased hasSuffix:@".rds.amazonaws.com"] ||
           [lowercased hasSuffix:@".rds.amazonaws.com.cn"] ||
           [lowercased containsString:@".rds."];
}

+ (NSInteger)tokenLifetimeSeconds {
    return kTokenExpirationSeconds;
}

@end
