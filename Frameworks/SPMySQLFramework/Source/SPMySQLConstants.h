//
//  SPMySQLConstants.h
//  SPMySQLFramework
//
//  Created by Rowan Beentje (rowan.beent.je) on January 14, 2012
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

// Connection state
typedef enum {
	SPMySQLDisconnected               = 0,
	SPMySQLConnecting                 = 1,
	SPMySQLConnected                  = 2,
	SPMySQLConnectionLostInBackground = 3,
	SPMySQLDisconnecting              = 4
} SPMySQLConnectionState;

// Connection lock state
typedef enum {
	SPMySQLConnectionIdle = 0,
	SPMySQLConnectionBusy = 1
} SPMySQLConnectionLockState;

// Decision on how to handle lost connections
// Connection check constants
typedef enum {
	SPMySQLConnectionLostDisconnect = 0,
	SPMySQLConnectionLostReconnect  = 1
} SPMySQLConnectionLostDecision;

// Result set row types
typedef enum {
	SPMySQLResultRowAsDefault    = 0,
	SPMySQLResultRowAsArray      = 1,
	SPMySQLResultRowAsDictionary = 2
} SPMySQLResultRowType;

// Result charset list
typedef struct {
	NSUInteger nr;
	const char *name;
	const char *collation;
	NSUInteger char_minlen;
	NSUInteger char_maxlen;
} SPMySQLResultCharset;

// Query result types
typedef enum {
	SPMySQLResultAsResult                = 0,
	SPMySQLResultAsFastStreamingResult   = 1,
	SPMySQLResultAsLowMemStreamingResult = 2,
	SPMySQLResultAsStreamingResultStore  = 3
} SPMySQLResultType;

// Redeclared from mysql_com.h (private header)
typedef NS_OPTIONS(unsigned long, SPMySQLClientFlags) {
	SPMySQLClientFlagCompression  = 32,          // CLIENT_COMPRESS
	SPMySQLClientFlagInteractive  = 1024,        // CLIENT_INTERACTIVE
	SPMySQLClientFlagMultiResults = (1UL << 17)  // CLIENT_MULTI_RESULTS = 131072
};

typedef struct {
	unsigned int inTransaction:1;
	unsigned int autocommit:1;
	unsigned int _reserved1:1;
	unsigned int moreResultsExists:1;
	unsigned int queryNoGoodIndexUsed:1;
	unsigned int queryNoIndexUsed:1;
	unsigned int cursorExists:1;
	unsigned int lastRowSent:1;
	unsigned int dbDropped:1;
	unsigned int noBackslashEscapes:1;
	unsigned int metadataChanged:1;
	unsigned int queryWasSlow:1;
	unsigned int psOutParams:1;
	unsigned int inTransReadonly:1;
	unsigned int sessionStateChanged:1;
	unsigned int _reserved2:1;
} SPMySQLServerStatusBits;
