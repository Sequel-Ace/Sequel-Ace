//
//  SPFunctions.m
//  sequel-pro
//
//  Created by Max Lohrmann on 01.10.15.
//  Copyright (c) 2015 Max Lohrmann. All rights reserved.
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
//  More info at <https://github.com/sequelpro/sequelpro>

#import "SPFunctions.h"
#import <Security/SecRandom.h>
#import <objc/runtime.h>
#import <arpa/inet.h>
#import <netinet/in.h>

void SPMainQSync(SAVoidCompletionBlock block)
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		dispatch_queue_set_specific(dispatch_get_main_queue(), &onceToken, &onceToken, NULL);
	});
	
	if (dispatch_get_specific(&onceToken) == &onceToken) {
		block();
	}
	else {
		dispatch_sync(dispatch_get_main_queue(), block);
	}
}

void executeOnMainThreadAfterADelay(SAVoidCompletionBlock block, double delayInSeconds){

    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (dispatch_time_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void) {
        if (block) {
            block();
        }
    });
}

void executeOnLowPrioQueueAfterADelay(SAVoidCompletionBlock block, double delayInSeconds){

    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (dispatch_time_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        if (block) {
            block();
        }
    });
}

void SPMainLoopAsync(SAVoidCompletionBlock block)
{
	CFRunLoopPerformBlock(CFRunLoopGetMain(), NSDefaultRunLoopMode, block);
}

void dispatch_once_on_main_thread(dispatch_once_t *predicate,
								  dispatch_block_t block) {
	
	if ([NSThread isMainThread]) {
		dispatch_once(predicate, block);
	}
	else {
		if (DISPATCH_EXPECT(*predicate == 0L, NO)) {
			dispatch_sync(dispatch_get_main_queue(), ^{
				dispatch_once(predicate, block);
			});
		}
	}
}

void executeOnBackgroundThreadSync(SAVoidCompletionBlock block)
{
	static dispatch_once_t onceToken5;
	   dispatch_once(&onceToken5, ^{
		   dispatch_queue_set_specific(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), &onceToken5, &onceToken5, NULL);
	   });
	
   if (dispatch_get_specific(&onceToken5) == &onceToken5) {
		block();
	}
	else {
		dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), block);
	}
}

void executeOnBackgroundThread(SAVoidCompletionBlock block)
{
	static dispatch_once_t onceToken3;
	dispatch_once(&onceToken3, ^{
		dispatch_queue_set_specific(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), &onceToken3, &onceToken3, NULL);
	});

	if (dispatch_get_specific(&onceToken3) == &onceToken3) {
		block();
	} else {
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), block);
	}
}

int SPBetterRandomBytes(uint8_t *buf, size_t count)
{
	return SecRandomCopyBytes(kSecRandomDefault, count, buf);
}

NSUInteger SPIntS2U(NSInteger i)
{
	if(i < 0) [NSException raise:NSRangeException format:@"NSInteger %ld does not fit in NSUInteger",i];
	
	return (NSUInteger)i;
}

id SPBoxNil(id object)
{
	if(object == nil) return [NSNull null];
	
	return object;
}

static NSString *SPTrimmedHostCandidate(NSString *candidate)
{
    if (!candidate) return nil;

    NSString *trimmedCandidate = [candidate stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![trimmedCandidate length]) return nil;

    // SSH logs often wrap IP addresses in square brackets.
    if ([trimmedCandidate hasPrefix:@"["] && [trimmedCandidate hasSuffix:@"]"] && [trimmedCandidate length] > 2) {
        trimmedCandidate = [trimmedCandidate substringWithRange:NSMakeRange(1, [trimmedCandidate length] - 2)];
    }

    return trimmedCandidate;
}

static BOOL SPIsPrivateIPv4Address(struct in_addr address)
{
    uint32_t hostAddress = ntohl(address.s_addr);

    // Loopback is local-only and does not require Local Network privacy permission.
    if ((hostAddress & 0xFF000000) == 0x7F000000) return NO;

    // RFC1918 private ranges.
    if ((hostAddress & 0xFF000000) == 0x0A000000) return YES;   // 10.0.0.0/8
    if ((hostAddress & 0xFFF00000) == 0xAC100000) return YES;   // 172.16.0.0/12
    if ((hostAddress & 0xFFFF0000) == 0xC0A80000) return YES;   // 192.168.0.0/16

    // Common local-only ranges.
    if ((hostAddress & 0xFFFF0000) == 0xA9FE0000) return YES;   // 169.254.0.0/16 link-local
    if ((hostAddress & 0xFFC00000) == 0x64400000) return YES;   // 100.64.0.0/10 CGNAT

    return NO;
}

static BOOL SPIsPrivateIPv6Address(struct in6_addr address)
{
    if (IN6_IS_ADDR_LOOPBACK(&address)) return NO;

    // fc00::/7 (unique local), fe80::/10 (link-local)
    BOOL isUniqueLocal = ((address.s6_addr[0] & 0xFE) == 0xFC);
    BOOL isLinkLocal = (address.s6_addr[0] == 0xFE) && ((address.s6_addr[1] & 0xC0) == 0x80);

    return isUniqueLocal || isLinkLocal;
}

BOOL SPIsLikelyLocalNetworkHost(NSString *host)
{
    NSString *trimmedHost = SPTrimmedHostCandidate(host);
    if (![trimmedHost length]) return NO;

    NSString *normalizedHost = [trimmedHost lowercaseString];

    if ([normalizedHost isEqualToString:@"localhost"] || [normalizedHost isEqualToString:@"::1"]) return NO;
    if ([normalizedHost hasSuffix:@".local"]) return YES;

    struct in_addr ipv4Address;
    if (inet_pton(AF_INET, [normalizedHost UTF8String], &ipv4Address) == 1) {
        return SPIsPrivateIPv4Address(ipv4Address);
    }

    struct in6_addr ipv6Address;
    if (inet_pton(AF_INET6, [normalizedHost UTF8String], &ipv6Address) == 1) {
        return SPIsPrivateIPv6Address(ipv6Address);
    }

    // Hostnames without a DNS suffix are often local/intranet aliases.
    if ([normalizedHost rangeOfString:@"."].location == NSNotFound) {
        return YES;
    }

    return NO;
}

static void SPAddSSHRegexMatches(NSMutableOrderedSet<NSString *> *candidates, NSString *debugDetail, NSString *pattern)
{
    if (![debugDetail length]) return;

    NSError *regexError = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&regexError];
    if (regexError || !regex) return;

    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:debugDetail options:0 range:NSMakeRange(0, [debugDetail length])];
    for (NSTextCheckingResult *result in matches) {
        if ([result numberOfRanges] < 2) continue;
        NSRange captureRange = [result rangeAtIndex:1];
        if (captureRange.location == NSNotFound) continue;
        NSString *candidate = SPTrimmedHostCandidate([debugDetail substringWithRange:captureRange]);
        if ([candidate length]) [candidates addObject:candidate];
    }
}

BOOL SPSSHNoRouteToHostLikelyLocalNetworkPrivacyIssue(NSString *errorMessage, NSString *debugDetail, NSString *sshHost)
{
    NSMutableString *combinedMessage = [NSMutableString string];
    if ([errorMessage length]) [combinedMessage appendString:errorMessage];
    if ([debugDetail length]) {
        if ([combinedMessage length]) [combinedMessage appendString:@"\n"];
        [combinedMessage appendString:debugDetail];
    }

    if ([combinedMessage rangeOfString:@"No route to host" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        return NO;
    }

    NSMutableOrderedSet<NSString *> *candidates = [NSMutableOrderedSet orderedSet];
    NSString *trimmedSSHHost = SPTrimmedHostCandidate(sshHost);
    if ([trimmedSSHHost length]) [candidates addObject:trimmedSSHHost];

    SPAddSSHRegexMatches(candidates, debugDetail, @"connect to address ([^\\s]+)\\s+port\\s+\\d+:\\s+No route to host");
    SPAddSSHRegexMatches(candidates, debugDetail, @"Connecting to .*?\\[([^\\]]+)\\]\\s+port\\s+\\d+");

    for (NSString *candidate in candidates) {
        if (SPIsLikelyLocalNetworkHost(candidate)) return YES;
    }

    return NO;
}

void SP_swizzleInstanceMethod(Class c, SEL original, SEL replacement)
{
	Method a = class_getInstanceMethod(c, original);
	Method b = class_getInstanceMethod(c, replacement);
	if (class_addMethod(c, original, method_getImplementation(b), method_getTypeEncoding(b)))
	{
		class_replaceMethod(c, replacement, method_getImplementation(a), method_getTypeEncoding(a));
	}
	else
	{
		method_exchangeImplementations(a, b);
	}
}

id DumpObjCMethods(Class clz) {
    
    unsigned int i=0;
    unsigned int mc = 0;
    Method * mlist = class_copyMethodList(object_getClass(clz), &mc);
    
    NSMutableArray *arr = [[NSMutableArray alloc] initWithCapacity:mc];
    
    SPLog(@"%d class methods", mc);
    for(i=0;i<mc;i++){
        SPLog(@"Class Method no #%d: %s", i, sel_getName(method_getName(mlist[i])));
        [arr addObject:[[NSString alloc] initWithCString:sel_getName(method_getName(mlist[i])) encoding:NSUTF8StringEncoding]];
    }
    
    free(mlist);
    
    return arr;
}

NSInteger intSortDesc(id num1, id num2, void *context)
{
    // JCS not: I want descending, so I've swapped the return values
    // from the ifs
    int v1 = [num1 intValue];
    int v2 = [num2 intValue];
    if (v1 < v2)
        return NSOrderedDescending;
    else if (v1 > v2)
        return NSOrderedAscending;
    else
        return NSOrderedSame;
}
