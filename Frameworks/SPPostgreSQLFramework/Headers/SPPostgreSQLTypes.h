//
//  SPPostgreSQLTypes.h
//  SPPostgreSQLFramework
//
//  Created by Sequel Ace on 2024.
//  Copyright (c) 2024 Sequel Ace. All rights reserved.
//

#import <Foundation/Foundation.h>

// Connection states
typedef NS_ENUM(NSInteger, SPPostgreSQLConnectionState) {
    SPPostgreSQLConnectionStateDisconnected = 0,
    SPPostgreSQLConnectionStateConnecting = 1,
    SPPostgreSQLConnectionStateConnected = 2,
    SPPostgreSQLConnectionStateError = 3
};

// Query error codes
typedef NS_ENUM(NSInteger, SPPostgreSQLErrorCode) {
    SPPostgreSQLErrorCodeNone = 0,
    SPPostgreSQLErrorCodeConnectionFailed = 1,
    SPPostgreSQLErrorCodeQueryFailed = 2,
    SPPostgreSQLErrorCodeNotConnected = 3,
    SPPostgreSQLErrorCodeInvalidParameter = 4
};

// Error domain
FOUNDATION_EXPORT NSErrorDomain const SPPostgreSQLErrorDomain;

