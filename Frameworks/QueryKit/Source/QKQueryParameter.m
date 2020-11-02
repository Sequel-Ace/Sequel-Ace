//
//  $Id: QKQueryParameter.m 3432 2011-09-27 00:21:35Z stuart02 $
//
//  QKQueryParameter.m
//  QueryKit
//
//  Created by Stuart Connolly (stuconnolly.com) on September 4, 2011
//  Copyright (c) 2011 Stuart Connolly. All rights reserved.
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

#import "QKQueryParameter.h"
#import "QKQueryUtilities.h"
#import "QKQueryConstants.h"

@implementation QKQueryParameter

#pragma mark -
#pragma mark Initialisation

+ (QKQueryParameter *)queryParamWithField:(NSString *)field operator:(QKQueryOperator)op value:(id)value
{
	return [[QKQueryParameter alloc] initParamWithField:field operator:op value:value];
}

- (id)initParamWithField:(NSString *)field operator:(QKQueryOperator)op value:(id)value
{
	if ((self = [super init])) {
		[self setField:field];
		[self setOperator:op];
		[self setValue:value];
	}
	
	return self;
}

#pragma mark -

- (NSString *)description
{
	NSMutableString *string = [NSMutableString string]; 
		
    NSString *field = [self.field stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	[string appendFormat:@"%1$@%2$@%1$@", [self useQuotedIdentifier] ? _identiferQuote : EMPTY_STRING, field];
	[string appendFormat:@" %@ ", [QKQueryUtilities stringRepresentationOfQueryOperator:self.operator]];
	[string appendFormat:![self.value isKindOfClass:[NSNumber class]] ? @"'%@'" : @"%@", [self.value description]];
	
	return string;
}

@end
