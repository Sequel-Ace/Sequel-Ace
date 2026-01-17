//
//  SPDebugLogger.m
//  SPPostgresFramework
//
//  Debug logger for development mode - logs to file for crash debugging
//

#import "SPDebugLogger.h"

@implementation SPDebugLogger

+ (NSString *)logFilePath {
    NSString *homeDir = NSHomeDirectory();
    return [homeDir stringByAppendingPathComponent:@"Desktop/sequel_pace_debug.log"];
}

+ (void)clearLog {
    NSString *path = [self logFilePath];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

+ (void)log:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    [self writeToLog:message withPrefix:@"DEBUG"];
}

+ (void)logWithPrefix:(NSString *)prefix format:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    [self writeToLog:message withPrefix:prefix];
}

+ (void)writeToLog:(NSString *)message withPrefix:(NSString *)prefix {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    
    NSString *logLine = [NSString stringWithFormat:@"[%@] [%@] %@\n", timestamp, prefix, message];
    
    NSString *path = [self logFilePath];
    
    // Create file if it doesn't exist
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    }
    
    // Append to file
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (fileHandle) {
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    }
    
    // Also log to console
    NSLog(@"%@", logLine);
}

@end
