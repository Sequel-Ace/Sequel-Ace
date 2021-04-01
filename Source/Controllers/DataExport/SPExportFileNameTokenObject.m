//
//  SPExportFileNameTokenObject.m
//  sequel-pro
//
//  Created by Rowan Beentje on May 3, 2011.
//  Copyright (c) 2010 Rowan Beentje. All rights reserved.
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

#import "SPExportFileNameTokenObject.h"

@implementation SPExportFileNameTokenObject

@synthesize tokenId;

+ (id)tokenWithId:(NSString *)token
{
	SPExportFileNameTokenObject *obj = [[SPExportFileNameTokenObject alloc] init];
	[obj setTokenId:token];
	return obj;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%p {%@}>",self,[self tokenId]];
}

- (BOOL)isEqual:(id)object
{
	if([object isKindOfClass:[SPExportFileNameTokenObject class]]) {
		return [[self tokenId] isEqualToString:[object tokenId]];
	}
	return [super isEqual:object];
}

#pragma mark -
#pragma mark NSCoding compatibility

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init])) {
		[self setTokenId:[decoder decodeObjectForKey:@"tokenId"]];
	}
	
	return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
	[encoder encodeObject:[self tokenId] forKey:@"tokenId"];
}

@end
