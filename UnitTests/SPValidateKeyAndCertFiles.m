//
//  SPValidateKeyAndCertFiles.m
//  Unit Tests
//
//  Created by James on 23/6/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

#import <XCTest/XCTest.h>

@interface SPValidateKeyAndCertFiles : XCTestCase

@end

@implementation SPValidateKeyAndCertFiles

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testGoodKeysWithDifferentLF {

	NSError *err=nil;
	
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	NSArray *testKeys = @[@"client-key-lf", @"client-key-cr", @"client-key-crlf"];
	
	for( NSString *file in testKeys){
		
		NSString *path = [bundle pathForResource:file ofType:@"pem"];
				
		NSURL *url = [NSURL fileURLWithPath:path isDirectory:NO];
		
		BOOL ret = [self validateKeyFile:url error:&err];
		
		XCTAssertTrue(ret, @"invalid key file, should be valid");
	}
}

- (void)testBadKeys {

	NSError *err=nil;
	
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	NSArray *testKeys = @[@"client-key-bad-start",@"client-key-bad-end"];
	
	for( NSString *file in testKeys){
		
		NSString *path = [bundle pathForResource:file ofType:@"pem"];
				
		NSURL *url = [NSURL fileURLWithPath:path isDirectory:NO];
		
		BOOL ret = [self validateKeyFile:url error:&err];
		
		XCTAssertFalse(ret, @"valid key file, should be invalid");
	}
}

- (void)testGoodCertsWithDifferentLF {

	NSError *err=nil;
	
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	NSArray *testKeys = @[@"client-cert-lf", @"client-cert-cr", @"client-cert-crlf"];
	
	for( NSString *file in testKeys){
		
		NSString *path = [bundle pathForResource:file ofType:@"pem"];
				
		NSURL *url = [NSURL fileURLWithPath:path isDirectory:NO];
		
		BOOL ret = [self validateCertFile:url error:&err];
		
		XCTAssertTrue(ret, @"invalid cert file, should be valid");
	}
}

- (void)testBadCerts {

	NSError *err=nil;
	
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	NSArray *testKeys = @[@"client-cert-bad-start",@"client-cert-bad-end"];
	
	for( NSString *file in testKeys){
		
		NSString *path = [bundle pathForResource:file ofType:@"pem"];
				
		NSURL *url = [NSURL fileURLWithPath:path isDirectory:NO];
		
		BOOL ret = [self validateCertFile:url error:&err];
		
		XCTAssertFalse(ret, @"valid cert file, should be invalid");
	}
}

// I've just copied the code
// to instantiate a real SPConnectionController means adding just about the etire codebase to the unit test target
-(BOOL)validateKeyFile:(NSURL *)url error:(NSError **)outError{
	
	NSError *err = nil;
	NSData *file = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&err];
	if(err) {
		*outError = err;
		return NO;
	}
	
	NSString *stringFromData = [[NSString alloc] initWithData:file encoding:NSASCIIStringEncoding];
	
	BOOL __block foundValidFirstLine = NO;
	BOOL __block foundValidLastLine = NO;
	
	if(stringFromData){
		NSRange range = NSMakeRange(0, stringFromData.length);
		
		[stringFromData enumerateSubstringsInRange:range
										   options:NSStringEnumerationByParagraphs
										usingBlock:^(NSString * _Nullable paragraph, NSRange paragraphRange, NSRange enclosingRange, BOOL * _Nonnull stop) {
			
			if ([paragraph containsString:@"PRIVATE KEY-----"] && [paragraph containsString:@"-----BEGIN"]) {
				foundValidFirstLine = YES;
			}
			if ([paragraph containsString:@"PRIVATE KEY-----"] && [paragraph containsString:@"-----END"]) {
				foundValidLastLine = YES;
			}
		}];
	}
	
	if(foundValidFirstLine == YES && foundValidLastLine == YES){
		return YES;
	}
	else{
		*outError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:@{
			NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedString(@"“%@” is not a valid private key file.", @"connection view : ssl : key file picker : wrong format error title"),[url lastPathComponent]],
			NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Make sure the file contains a RSA private key and is using PEM encoding.", @"connection view : ssl : key file picker : wrong format error description"),
			NSURLErrorKey: url
		}];
		
		return NO;
	}
}

-(BOOL)validateCertFile:(NSURL *)url error:(NSError **)outError{
	
	NSError *err = nil;
	NSData *file = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&err];
	if(err) {
		*outError = err;
		return NO;
	}
	
	NSString *stringFromData = [[NSString alloc] initWithData:file encoding:NSASCIIStringEncoding];

	BOOL __block foundValidFirstLine = NO;
	BOOL __block foundValidLastLine = NO;
	
	if(stringFromData){
		NSRange range = NSMakeRange(0, stringFromData.length);
		
		[stringFromData enumerateSubstringsInRange:range
										   options:NSStringEnumerationByParagraphs
										usingBlock:^(NSString * _Nullable paragraph, NSRange paragraphRange, NSRange enclosingRange, BOOL * _Nonnull stop) {
			
			if ([paragraph containsString:@"CERTIFICATE-----"] && [paragraph containsString:@"-----BEGIN"]) {
				foundValidFirstLine = YES;
			}
			if ([paragraph containsString:@"CERTIFICATE-----"] && [paragraph containsString:@"-----END"]) {
				foundValidLastLine = YES;
			}
		}];
	}
	
	if(foundValidFirstLine == YES && foundValidLastLine == YES){
		return YES;
	}
	else{
		
		*outError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:@{
			NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedString(@"“%@” is not a valid client certificate file.", @"connection view : ssl : client cert file picker : wrong format error title"),[url lastPathComponent]],
			NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Make sure the file contains a X.509 client certificate and is using PEM encoding.", @"connection view : ssl : client cert picker : wrong format error description"),
			NSURLErrorKey: url
		}];
		
		return NO;
	}
}


@end
