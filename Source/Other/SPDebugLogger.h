//
//  SPDebugLogger.h
//  SPPostgresFramework
//
//  Debug logger for development mode - logs to file for crash debugging
//

#import <Foundation/Foundation.h>

@interface SPDebugLogger : NSObject

+ (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
+ (void)logWithPrefix:(NSString *)prefix format:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);
+ (NSString *)logFilePath;
+ (void)clearLog;

@end
