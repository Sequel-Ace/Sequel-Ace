//
//  SPPostgresResult.h
//  SPPostgresFramework
//
//  Created by Sequel-PAce on 2025.
//

#import <Foundation/Foundation.h>

@interface SPPostgresResult : NSObject

@property (nonatomic, readonly) NSUInteger numberOfRows;
@property (nonatomic, readonly) NSUInteger numberOfFields;
@property (nonatomic, readonly) NSArray *fieldNames;

- (instancetype)initWithRows:(NSArray<NSDictionary *> *)rows fieldNames:(NSArray<NSString *> *)fieldNames;

- (NSDictionary *)getRowAsDictionary;
- (NSArray *)getRowAsArray;
- (void)setReturnDataAsStrings:(BOOL)asStrings; // For compatibility

@end
