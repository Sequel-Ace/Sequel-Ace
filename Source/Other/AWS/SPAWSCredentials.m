//
//  SPAWSCredentials.m
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

#import "SPAWSCredentials.h"

static NSString * const SPAWSCredentialsErrorDomain = @"SPAWSCredentialsErrorDomain";

@interface SPAWSCredentials ()
@property (nonatomic, copy, readwrite) NSString *accessKeyId;
@property (nonatomic, copy, readwrite) NSString *secretAccessKey;
@property (nonatomic, copy, readwrite, nullable) NSString *sessionToken;
@property (nonatomic, copy, readwrite, nullable) NSString *profileName;
@property (nonatomic, copy, readwrite, nullable) NSString *roleArn;
@property (nonatomic, copy, readwrite, nullable) NSString *mfaSerial;
@property (nonatomic, copy, readwrite, nullable) NSString *sourceProfile;
@property (nonatomic, copy, readwrite, nullable) NSString *region;
@end

@implementation SPAWSCredentials

- (instancetype)initWithAccessKeyId:(NSString *)accessKeyId
                    secretAccessKey:(NSString *)secretAccessKey
                       sessionToken:(nullable NSString *)sessionToken {
    self = [super init];
    if (self) {
        _accessKeyId = [accessKeyId copy];
        _secretAccessKey = [secretAccessKey copy];
        _sessionToken = [sessionToken copy];
        _profileName = nil;
    }
    return self;
}

- (nullable instancetype)initWithProfile:(nullable NSString *)profileName
                                   error:(NSError **)error {
    self = [super init];
    if (self) {
        NSString *effectiveProfile = profileName ?: @"default";
        _profileName = [effectiveProfile copy];

        NSDictionary *credentials = [self loadCredentialsForProfile:effectiveProfile error:error];
        if (!credentials) {
            return nil;
        }

        _accessKeyId = credentials[@"aws_access_key_id"];
        _secretAccessKey = credentials[@"aws_secret_access_key"];
        _sessionToken = credentials[@"aws_session_token"];

        // Store profile configuration for role assumption
        _roleArn = credentials[@"role_arn"];
        _mfaSerial = credentials[@"mfa_serial"];
        _sourceProfile = credentials[@"source_profile"];
        _region = credentials[@"region"];

        if (![self isValid]) {
            if (error) {
                *error = [NSError errorWithDomain:SPAWSCredentialsErrorDomain
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Profile '%@' is missing required credentials (aws_access_key_id or aws_secret_access_key)", effectiveProfile]}];
            }
            return nil;
        }
    }
    return self;
}

- (nullable NSDictionary *)loadCredentialsForProfile:(NSString *)profileName error:(NSError **)error {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    BOOL foundProfile = NO;

    // First, try to load from ~/.aws/credentials
    NSString *credentialsPath = [[self class] credentialsFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:credentialsPath]) {
        NSString *contents = [NSString stringWithContentsOfFile:credentialsPath
                                                       encoding:NSUTF8StringEncoding
                                                          error:nil];
        if (contents) {
            NSDictionary *creds = [self parseAWSFile:contents forProfile:profileName isConfigFile:NO];
            if (creds) {
                [result addEntriesFromDictionary:creds];
                foundProfile = YES;
            }
        }
    }

    // Also check ~/.aws/config for additional settings (region, source_profile, role_arn, etc.)
    NSString *configPath = [[self class] configFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:configPath]) {
        NSString *contents = [NSString stringWithContentsOfFile:configPath
                                                       encoding:NSUTF8StringEncoding
                                                          error:nil];
        if (contents) {
            NSDictionary *config = [self parseAWSFile:contents forProfile:profileName isConfigFile:YES];
            if (config) {
                // Merge config into result (credentials take precedence)
                for (NSString *key in config) {
                    if (!result[key]) {
                        result[key] = config[key];
                    }
                }
                foundProfile = YES;
            }
        }
    }

    // If profile has source_profile, load credentials from that profile
    NSString *sourceProfile = result[@"source_profile"];
    if (sourceProfile && !result[@"aws_access_key_id"]) {
        NSDictionary *sourceCredentials = [self loadCredentialsForProfile:sourceProfile error:nil];
        if (sourceCredentials) {
            // Only copy credential keys from source profile
            if (sourceCredentials[@"aws_access_key_id"]) {
                result[@"aws_access_key_id"] = sourceCredentials[@"aws_access_key_id"];
            }
            if (sourceCredentials[@"aws_secret_access_key"]) {
                result[@"aws_secret_access_key"] = sourceCredentials[@"aws_secret_access_key"];
            }
            if (sourceCredentials[@"aws_session_token"] && !result[@"aws_session_token"]) {
                result[@"aws_session_token"] = sourceCredentials[@"aws_session_token"];
            }
        }
    }

    if (!foundProfile) {
        if (error) {
            *error = [NSError errorWithDomain:SPAWSCredentialsErrorDomain
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Profile '%@' not found in credentials or config file", profileName]}];
        }
        return nil;
    }

    return result;
}

- (nullable NSDictionary *)parseAWSFile:(NSString *)contents
                             forProfile:(NSString *)profileName
                           isConfigFile:(BOOL)isConfigFile {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSString *currentProfile = nil;
    BOOL foundProfile = NO;

    // In config file, profile sections are named "profile xyz" except for "default"
    NSString *targetSection = profileName;
    NSString *targetSectionAlt = nil;
    if (isConfigFile && ![profileName isEqualToString:@"default"]) {
        targetSection = [NSString stringWithFormat:@"profile %@", profileName];
        targetSectionAlt = profileName; // Some configs don't use "profile " prefix
    }

    NSArray<NSString *> *lines = [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    for (NSString *rawLine in lines) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        // Skip empty lines and comments
        if (line.length == 0 || [line hasPrefix:@"#"] || [line hasPrefix:@";"]) {
            continue;
        }

        // Check for profile header [profile_name]
        if ([line hasPrefix:@"["] && [line hasSuffix:@"]"]) {
            currentProfile = [[line substringWithRange:NSMakeRange(1, line.length - 2)]
                              stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

            BOOL isTargetProfile = [currentProfile isEqualToString:targetSection] ||
                                   (targetSectionAlt && [currentProfile isEqualToString:targetSectionAlt]);

            if (isTargetProfile) {
                foundProfile = YES;
            } else if (foundProfile) {
                // We've moved past our target profile
                break;
            }
            continue;
        }

        // Parse key=value pairs within the target profile
        if (foundProfile) {
            NSRange equalRange = [line rangeOfString:@"="];
            if (equalRange.location != NSNotFound) {
                NSString *key = [[line substringToIndex:equalRange.location]
                                 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                NSString *value = [[line substringFromIndex:equalRange.location + 1]
                                   stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

                if (key.length > 0 && value.length > 0) {
                    result[key] = value;
                }
            }
        }
    }

    if (!foundProfile) {
        return nil;
    }

    return result;
}

+ (NSArray<NSString *> *)availableProfiles {
    NSMutableSet<NSString *> *profileSet = [NSMutableSet set];

    // Scan ~/.aws/credentials
    [self addProfilesFromFile:[self credentialsFilePath] toSet:profileSet isConfigFile:NO];

    // Scan ~/.aws/config
    [self addProfilesFromFile:[self configFilePath] toSet:profileSet isConfigFile:YES];

    // Sort profiles alphabetically, but put "default" first if present
    NSMutableArray<NSString *> *profiles = [[profileSet allObjects] mutableCopy];
    [profiles sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    if ([profiles containsObject:@"default"]) {
        [profiles removeObject:@"default"];
        [profiles insertObject:@"default" atIndex:0];
    }

    return profiles;
}

+ (void)addProfilesFromFile:(NSString *)filePath toSet:(NSMutableSet<NSString *> *)profileSet isConfigFile:(BOOL)isConfigFile {
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        return;
    }

    NSError *readError = nil;
    NSString *contents = [NSString stringWithContentsOfFile:filePath
                                                   encoding:NSUTF8StringEncoding
                                                      error:&readError];
    if (readError || !contents) {
        return;
    }

    NSArray<NSString *> *lines = [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    for (NSString *rawLine in lines) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        if ([line hasPrefix:@"["] && [line hasSuffix:@"]"]) {
            NSString *profile = [[line substringWithRange:NSMakeRange(1, line.length - 2)]
                                 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

            // In config file, profiles are named "profile xyz" except for "default"
            if (isConfigFile && [profile hasPrefix:@"profile "]) {
                profile = [[profile substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            }

            if (profile.length > 0) {
                [profileSet addObject:profile];
            }
        }
    }
}

+ (NSString *)configFilePath {
    // Check for AWS_CONFIG_FILE environment variable first
    NSString *envPath = [[[NSProcessInfo processInfo] environment] objectForKey:@"AWS_CONFIG_FILE"];
    if (envPath.length > 0) {
        return envPath;
    }

    // Default to ~/.aws/config
    return [NSHomeDirectory() stringByAppendingPathComponent:@".aws/config"];
}

+ (BOOL)credentialsFileExists {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self credentialsFilePath]];
}

+ (NSString *)credentialsFilePath {
    // Check for AWS_SHARED_CREDENTIALS_FILE environment variable first
    NSString *envPath = [[[NSProcessInfo processInfo] environment] objectForKey:@"AWS_SHARED_CREDENTIALS_FILE"];
    if (envPath.length > 0) {
        return envPath;
    }

    // Default to ~/.aws/credentials
    return [NSHomeDirectory() stringByAppendingPathComponent:@".aws/credentials"];
}

- (BOOL)isValid {
    return self.accessKeyId.length > 0 && self.secretAccessKey.length > 0;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: profile=%@, accessKeyId=%@...>",
            NSStringFromClass([self class]),
            self.profileName ?: @"(manual)",
            [self.accessKeyId substringToIndex:MIN(4, self.accessKeyId.length)]];
}

- (BOOL)requiresMFA {
    return self.mfaSerial.length > 0;
}

- (BOOL)requiresRoleAssumption {
    return self.roleArn.length > 0;
}

+ (nullable NSDictionary *)profileConfigurationForProfile:(NSString *)profileName {
    NSString *effectiveProfile = profileName ?: @"default";
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    // Check ~/.aws/config first (where role_arn and mfa_serial are typically defined)
    NSString *configPath = [self configFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:configPath]) {
        NSString *contents = [NSString stringWithContentsOfFile:configPath
                                                       encoding:NSUTF8StringEncoding
                                                          error:nil];
        if (contents) {
            NSDictionary *config = [[self alloc] parseAWSFile:contents forProfile:effectiveProfile isConfigFile:YES];
            if (config) {
                [result addEntriesFromDictionary:config];
            }
        }
    }

    // Also check ~/.aws/credentials
    NSString *credentialsPath = [self credentialsFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:credentialsPath]) {
        NSString *contents = [NSString stringWithContentsOfFile:credentialsPath
                                                       encoding:NSUTF8StringEncoding
                                                          error:nil];
        if (contents) {
            NSDictionary *creds = [[self alloc] parseAWSFile:contents forProfile:effectiveProfile isConfigFile:NO];
            if (creds) {
                // Merge, but don't override existing config values
                for (NSString *key in creds) {
                    if (!result[key]) {
                        result[key] = creds[key];
                    }
                }
            }
        }
    }

    return result.count > 0 ? result : nil;
}

@end
