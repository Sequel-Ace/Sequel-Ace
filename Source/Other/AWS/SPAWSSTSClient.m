//
//  SPAWSSTSClient.m
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

#import "SPAWSSTSClient.h"
#import "SPAWSCredentials.h"
#import <CommonCrypto/CommonHMAC.h>

NSString * const SPAWSSTSClientErrorDomain = @"SPAWSSTSClientErrorDomain";

static NSString * const kAWSAlgorithm = @"AWS4-HMAC-SHA256";
static NSString * const kAWSService = @"sts";
static NSString * const kAWSRequest = @"aws4_request";
static const NSInteger kDefaultSessionDuration = 3600; // 1 hour

@implementation SPAWSSTSClient

+ (nullable SPAWSCredentials *)assumeRole:(NSString *)roleArn
                          roleSessionName:(NSString *)roleSessionName
                          mfaSerialNumber:(nullable NSString *)mfaSerialNumber
                             mfaTokenCode:(nullable NSString *)mfaTokenCode
                          durationSeconds:(NSInteger)durationSeconds
                                   region:(NSString *)region
                              credentials:(SPAWSCredentials *)credentials
                                    error:(NSError **)error {
    // Validate inputs
    if (!credentials || ![credentials isValid]) {
        if (error) {
            *error = [NSError errorWithDomain:SPAWSSTSClientErrorDomain
                                         code:SPAWSSTSClientErrorInvalidCredentials
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid AWS credentials"}];
        }
        return nil;
    }

    if (roleArn.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:SPAWSSTSClientErrorDomain
                                         code:SPAWSSTSClientErrorInvalidParameters
                                     userInfo:@{NSLocalizedDescriptionKey: @"Role ARN is required"}];
        }
        return nil;
    }

    if (region.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:SPAWSSTSClientErrorDomain
                                         code:SPAWSSTSClientErrorInvalidParameters
                                     userInfo:@{NSLocalizedDescriptionKey: @"AWS region is required"}];
        }
        return nil;
    }

    // If MFA serial is provided, token code is required
    if (mfaSerialNumber.length > 0 && mfaTokenCode.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:SPAWSSTSClientErrorDomain
                                         code:SPAWSSTSClientErrorMFARequired
                                     userInfo:@{NSLocalizedDescriptionKey: @"MFA token code is required when MFA serial number is provided"}];
        }
        return nil;
    }

    // Generate session name if not provided
    NSString *effectiveSessionName = roleSessionName;
    if (effectiveSessionName.length == 0) {
        effectiveSessionName = [NSString stringWithFormat:@"SequelAce-%ld", (long)[[NSDate date] timeIntervalSince1970]];
    }

    // Use default duration if not specified
    NSInteger effectiveDuration = durationSeconds;
    if (effectiveDuration <= 0) {
        effectiveDuration = kDefaultSessionDuration;
    }
    // Clamp to valid range (900 - 43200 seconds)
    effectiveDuration = MAX(900, MIN(43200, effectiveDuration));

    // Build the STS endpoint
    NSString *host = [NSString stringWithFormat:@"sts.%@.amazonaws.com", region];
    NSURL *endpoint = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@/", host]];

    // Build request body
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    params[@"Action"] = @"AssumeRole";
    params[@"Version"] = @"2011-06-15";
    params[@"RoleArn"] = roleArn;
    params[@"RoleSessionName"] = effectiveSessionName;
    params[@"DurationSeconds"] = [@(effectiveDuration) stringValue];

    if (mfaSerialNumber.length > 0) {
        params[@"SerialNumber"] = mfaSerialNumber;
        params[@"TokenCode"] = mfaTokenCode;
    }

    NSString *requestBody = [self buildQueryStringFromParameters:params];

    // Get current time
    NSDate *now = [NSDate date];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    [dateFormatter setDateFormat:@"yyyyMMdd'T'HHmmss'Z'"];
    NSString *amzDate = [dateFormatter stringFromDate:now];
    [dateFormatter setDateFormat:@"yyyyMMdd"];
    NSString *dateStamp = [dateFormatter stringFromDate:now];

    // Build headers
    NSString *contentType = @"application/x-www-form-urlencoded; charset=utf-8";
    NSString *payloadHash = [self sha256Hex:requestBody];

    // Create canonical request
    NSString *canonicalHeaders = [NSString stringWithFormat:
        @"content-type:%@\nhost:%@\nx-amz-date:%@\n",
        contentType, host, amzDate];
    NSString *signedHeaders = @"content-type;host;x-amz-date";

    NSString *canonicalRequest = [NSString stringWithFormat:
        @"POST\n/\n\n%@\n%@\n%@",
        canonicalHeaders, signedHeaders, payloadHash];

    // Create string to sign
    NSString *credentialScope = [NSString stringWithFormat:@"%@/%@/%@/%@",
                                 dateStamp, region, kAWSService, kAWSRequest];
    NSString *canonicalRequestHash = [self sha256Hex:canonicalRequest];
    NSString *stringToSign = [NSString stringWithFormat:@"%@\n%@\n%@\n%@",
                              kAWSAlgorithm, amzDate, credentialScope, canonicalRequestHash];

    // Calculate signing key and signature
    NSData *signingKey = [self deriveSigningKeyWithSecretKey:credentials.secretAccessKey
                                                   dateStamp:dateStamp
                                                      region:region
                                                     service:kAWSService];
    NSString *signature = [self hmacSHA256Hex:stringToSign withKey:signingKey];

    // Build authorization header
    NSString *authorization = [NSString stringWithFormat:
        @"%@ Credential=%@/%@, SignedHeaders=%@, Signature=%@",
        kAWSAlgorithm, credentials.accessKeyId, credentialScope, signedHeaders, signature];

    // Create HTTP request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:endpoint];
    [request setHTTPMethod:@"POST"];
    [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
    [request setValue:host forHTTPHeaderField:@"Host"];
    [request setValue:amzDate forHTTPHeaderField:@"X-Amz-Date"];
    [request setValue:authorization forHTTPHeaderField:@"Authorization"];

    // Add session token if using temporary credentials
    if (credentials.sessionToken.length > 0) {
        [request setValue:credentials.sessionToken forHTTPHeaderField:@"X-Amz-Security-Token"];
    }

    [request setHTTPBody:[requestBody dataUsingEncoding:NSUTF8StringEncoding]];

    // Execute request synchronously
    __block NSData *responseData = nil;
    __block NSURLResponse *response = nil;
    __block NSError *networkError = nil;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            responseData = data;
            response = resp;
            networkError = err;
            dispatch_semaphore_signal(semaphore);
        }];
    [task resume];

    // Wait for response with timeout
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC);
    if (dispatch_semaphore_wait(semaphore, timeout) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:SPAWSSTSClientErrorDomain
                                         code:SPAWSSTSClientErrorNetworkFailure
                                     userInfo:@{NSLocalizedDescriptionKey: @"Request timed out"}];
        }
        return nil;
    }

    if (networkError) {
        if (error) {
            *error = [NSError errorWithDomain:SPAWSSTSClientErrorDomain
                                         code:SPAWSSTSClientErrorNetworkFailure
                                     userInfo:@{NSLocalizedDescriptionKey: networkError.localizedDescription,
                                                NSUnderlyingErrorKey: networkError}];
        }
        return nil;
    }

    // Check HTTP status
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    if (httpResponse.statusCode != 200) {
        NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
        NSString *errorMessage = [self parseErrorFromXML:responseString] ?: @"AssumeRole request failed";

        SPAWSSTSClientError errorCode = SPAWSSTSClientErrorInvalidResponse;
        if (httpResponse.statusCode == 403) {
            errorCode = SPAWSSTSClientErrorAccessDenied;
        }

        if (error) {
            *error = [NSError errorWithDomain:SPAWSSTSClientErrorDomain
                                         code:errorCode
                                     userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
        }
        return nil;
    }

    // Parse response
    NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
    return [self parseAssumeRoleResponse:responseString error:error];
}

+ (nullable SPAWSCredentials *)assumeRoleWithMFA:(NSString *)roleArn
                                 mfaSerialNumber:(NSString *)mfaSerialNumber
                                    mfaTokenCode:(NSString *)mfaTokenCode
                                          region:(NSString *)region
                                     credentials:(SPAWSCredentials *)credentials
                                           error:(NSError **)error {
    return [self assumeRole:roleArn
            roleSessionName:nil
            mfaSerialNumber:mfaSerialNumber
               mfaTokenCode:mfaTokenCode
            durationSeconds:kDefaultSessionDuration
                     region:region
                credentials:credentials
                      error:error];
}

#pragma mark - Response Parsing

+ (nullable SPAWSCredentials *)parseAssumeRoleResponse:(NSString *)xmlString error:(NSError **)error {
    // Parse the XML response to extract credentials
    // Response format:
    // <AssumeRoleResponse>
    //   <AssumeRoleResult>
    //     <Credentials>
    //       <AccessKeyId>...</AccessKeyId>
    //       <SecretAccessKey>...</SecretAccessKey>
    //       <SessionToken>...</SessionToken>
    //       <Expiration>...</Expiration>
    //     </Credentials>
    //   </AssumeRoleResult>
    // </AssumeRoleResponse>

    NSString *accessKeyId = [self extractValueForTag:@"AccessKeyId" fromXML:xmlString];
    NSString *secretAccessKey = [self extractValueForTag:@"SecretAccessKey" fromXML:xmlString];
    NSString *sessionToken = [self extractValueForTag:@"SessionToken" fromXML:xmlString];

    if (accessKeyId.length == 0 || secretAccessKey.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:SPAWSSTSClientErrorDomain
                                         code:SPAWSSTSClientErrorInvalidResponse
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse credentials from STS response"}];
        }
        return nil;
    }

    return [[SPAWSCredentials alloc] initWithAccessKeyId:accessKeyId
                                        secretAccessKey:secretAccessKey
                                           sessionToken:sessionToken];
}

+ (nullable NSString *)extractValueForTag:(NSString *)tag fromXML:(NSString *)xml {
    NSString *openTag = [NSString stringWithFormat:@"<%@>", tag];
    NSString *closeTag = [NSString stringWithFormat:@"</%@>", tag];

    NSRange openRange = [xml rangeOfString:openTag];
    NSRange closeRange = [xml rangeOfString:closeTag];

    if (openRange.location == NSNotFound || closeRange.location == NSNotFound) {
        return nil;
    }

    NSUInteger start = openRange.location + openRange.length;
    NSUInteger length = closeRange.location - start;

    if (start >= xml.length || start + length > xml.length) {
        return nil;
    }

    return [xml substringWithRange:NSMakeRange(start, length)];
}

+ (nullable NSString *)parseErrorFromXML:(NSString *)xml {
    NSString *message = [self extractValueForTag:@"Message" fromXML:xml];
    if (message) {
        return message;
    }

    NSString *code = [self extractValueForTag:@"Code" fromXML:xml];
    if (code) {
        return [NSString stringWithFormat:@"AWS Error: %@", code];
    }

    return nil;
}

#pragma mark - Query String Building

+ (NSString *)buildQueryStringFromParameters:(NSDictionary *)params {
    NSMutableArray *pairs = [NSMutableArray array];
    NSArray *sortedKeys = [[params allKeys] sortedArrayUsingSelector:@selector(compare:)];

    for (NSString *key in sortedKeys) {
        NSString *encodedKey = [self urlEncode:key];
        NSString *encodedValue = [self urlEncode:params[key]];
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", encodedKey, encodedValue]];
    }

    return [pairs componentsJoinedByString:@"&"];
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
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [string stringByAddingPercentEncodingWithAllowedCharacters:allowed];
}

@end
