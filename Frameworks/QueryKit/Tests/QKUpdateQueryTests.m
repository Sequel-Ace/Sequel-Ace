//
//  QKUpdateQueryTests.m
//  QueryKit
//
//  Created by Stuart Connolly (stuconnolly.com) on March 25, 2012
//  Copyright (c) 2012 Stuart Connolly. All rights reserved.
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

#import "QKUpdateQueryTests.h"
#import "QKTestConstants.h"

@implementation QKUpdateQueryTests

#pragma mark -
#pragma mark Initialisation

+ (id)defaultTestSuite
{
    XCTestSuite *testSuite = [[XCTestSuite alloc] initWithName:NSStringFromClass(self)];
	
	[self addTestForDatabase:QKDatabaseUnknown withIdentifierQuote:EMPTY_STRING toTestSuite:testSuite];
	[self addTestForDatabase:QKDatabaseMySQL withIdentifierQuote:QKMySQLIdentifierQuote toTestSuite:testSuite];
	[self addTestForDatabase:QKDatabasePostgreSQL withIdentifierQuote:QKPostgreSQLIdentifierQuote toTestSuite:testSuite];
	
    return testSuite;
}

+ (void)addTestForDatabase:(QKQueryDatabase)database withIdentifierQuote:(NSString *)quote toTestSuite:(XCTestSuite *)testSuite
{		
    for (NSInvocation *invocation in [self testInvocations]) 
	{
		XCTestCase *test = [[NSClassFromString(@"QKUpdateQueryTests") alloc] initWithInvocation:invocation database:database identifierQuote:quote];
		
		[testSuite addTest:test];
		
    }
}

#pragma mark -
#pragma mark Setup

- (void)setUp
{
	QKQuery *query = [QKQuery queryTable:QKTestTableName];
	
	[query setQueryType:QKUpdateQuery];
	[query setQueryDatabase:[self database]];
	[query setUseQuotedIdentifiers:[self identifierQuote] && [[self identifierQuote] length] > 0];
	
	[query addFieldToUpdate:QKTestFieldOne toValue:QKTestUpdateValueOne];
	[query addFieldToUpdate:QKTestFieldTwo toValue:QKTestUpdateValueTwo];
	
	[query addParameter:QKTestFieldOne operator:QKEqualityOperator value:[NSNumber numberWithUnsignedInteger:QKTestParameterOne]];
	
	[self setQuery:query];
}

#pragma mark -
#pragma mark Tests

- (void)testUpdateQueryTypeIsCorrect
{
	XCTAssertTrue([[[self query] query] hasPrefix:@"UPDATE"]);
}

- (void)testUpdateQueryUsingDatabaseAndTableIsCorrect
{	
	[[self query] setDatabase:QKTestDatabaseName];
	
	NSString *query = [NSString stringWithFormat:@"UPDATE %1$@%2$@%1$@.%1$@%3$@%1$@", [self identifierQuote], QKTestDatabaseName, QKTestTableName];
	
	XCTAssertTrue([[[self query] query] hasPrefix:query]);
}

- (void)testUpdateQueryFieldsAreCorrect
{
	NSString *query = [NSString stringWithFormat:@"UPDATE %1$@%2$@%1$@ SET %1$@%3$@%1$@ = '%4$@', %1$@%5$@%1$@ = '%6$@'", [self identifierQuote], QKTestTableName, QKTestFieldOne, QKTestUpdateValueOne, QKTestFieldTwo, QKTestUpdateValueTwo];
	
	XCTAssertTrue([[[self query] query] hasPrefix:query]);
}

- (void)testUpdateQueryConstraintIsCorrect
{
	NSString *query = [NSString stringWithFormat:@"WHERE %1$@%2$@%1$@ %3$@ %4$@", [self identifierQuote], QKTestFieldOne, [QKQueryUtilities stringRepresentationOfQueryOperator:QKEqualityOperator], [NSNumber numberWithUnsignedInteger:QKTestParameterOne]];
			
	XCTAssertTrue(([[[self query] query] rangeOfString:query].location != NSNotFound));
}

@end
