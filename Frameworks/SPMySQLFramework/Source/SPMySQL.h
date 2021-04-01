//
//  SPMySQL.h
//  SPMySQLFramework
//
//  Created by Rowan Beentje (rowan.beent.je) on January 22, 2012
//  Copyright (c) 2012 Rowan Beentje. All rights reserved.
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

@class SPMySQLConnection, SPMySQLResult, SPMySQLStreamingResult, SPMySQLFastStreamingResult, SPMySQLStreamingResultStore;

// Global include file for the framework.
// Constants
#import <SPMySQL/SPMySQLConstants.h>
#import <SPMySQL/SPMySQLDataTypes.h>

// Required category additions
#import <SPMySQL/SPMySQLStringAdditions.h>

// MySQL Connection Delegate and Proxy protocols
#import <SPMySQL/SPMySQLConnectionDelegate.h>
#import <SPMySQL/SPMySQLConnectionProxy.h>

// MySQL Connection class and public categories
#import <SPMySQL/SPMySQLConnection.h>
#import <SPMySQL/Delegate & Proxy.h>
#import <SPMySQL/Databases & Tables.h>
#import <SPMySQL/Max Packet Size.h>
#import <SPMySQL/Querying & Preparation.h>
#import <SPMySQL/Encoding.h>
#import <SPMySQL/Server Info.h>

// MySQL result set, streaming subclasses of same, and associated categories
#import <SPMySQL/SPMySQLResult.h>
#import <SPMySQL/SPMySQLEmptyResult.h>
#import <SPMySQL/SPMySQLStreamingResult.h>
#import <SPMySQL/SPMySQLFastStreamingResult.h>
#import <SPMySQL/SPMySQLStreamingResultStore.h>
#import <SPMySQL/Field Definitions.h>
#import <SPMySQL/Convenience Methods.h>

// MySQL result store delegate protocol
#import <SPMySQL/SPMySQLStreamingResultStoreDelegate.h>

// Result data objects
#import <SPMySQL/SPMySQLGeometryData.h>
