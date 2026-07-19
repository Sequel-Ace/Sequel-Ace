//
//  SPPostgreSQLTypes.h
//  SPPostgreSQLFramework
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SPPostgreSQLConnectionState) {
    SPPostgreSQLConnectionStateDisconnected = 0,
    SPPostgreSQLConnectionStateConnecting   = 1,
    SPPostgreSQLConnectionStateConnected    = 2,
    SPPostgreSQLConnectionStateError        = 3,
};

typedef NS_ENUM(NSInteger, SPPostgreSQLErrorCode) {
    SPPostgreSQLErrorCodeNone             = 0,
    SPPostgreSQLErrorCodeConnectionFailed = 1,
    SPPostgreSQLErrorCodeQueryFailed      = 2,
    SPPostgreSQLErrorCodeNotConnected     = 3,
    SPPostgreSQLErrorCodeInvalidParameter = 4,
};

FOUNDATION_EXPORT NSErrorDomain const SPPostgreSQLErrorDomain;
