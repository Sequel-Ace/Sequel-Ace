//
//  SPPostgresGeometryData.m
//  SPPostgresFramework
//
//  Created by Mehmet Karabulut (mehmetik@gmail.com) on November 30, 2025.
//  Copyright (c) 2025 Mehmet Karabulut.
//  This software is released under the GPL License.
//  This is an open-source project forked from Sequel Ace.
//

#import "SPPostgresGeometryData.h"

@implementation SPPostgresGeometryData

- (instancetype)initWithData:(NSData *)data {
    self = [super init];
    if (self) {
        geometryData = [data copy];
        wktStringCache = nil;
        geometryType = nil;
    }
    return self;
}

- (instancetype)initWithWKTString:(NSString *)wktString {
    self = [super init];
    if (self) {
        wktStringCache = [wktString copy];
        geometryData = nil;
        
        // Extract geometry type from WKT string
        NSRange openParen = [wktString rangeOfString:@"("];
        if (openParen.location != NSNotFound) {
            geometryType = [[wktString substringToIndex:openParen.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
    }
    return self;
}

- (NSString *)wktString {
    if (wktStringCache) {
        return wktStringCache;
    }
    
    if (!geometryData || [geometryData length] == 0) {
        return @"";
    }
    
    // In a full implementation, we would parse the WKB (Well-Known Binary) format
    // and convert it to WKT (Well-Known Text).
    // For now, return a placeholder that indicates the data exists but needs parsing.
    // A complete implementation would use PostGIS or GEOS library functions.
    
    // Basic WKB parsing would go here
    // This is a simplified placeholder implementation
    wktStringCache = [NSString stringWithFormat:@"GEOMETRY(binary data: %lu bytes)", (unsigned long)[geometryData length]];
    
    return wktStringCache;
}

- (NSString *)getGeomFromTextString {
    NSString *wkt = [self wktString];
    if ([wkt length] == 0) {
        return @"NULL";
    }
    
    // PostgreSQL/PostGIS uses ST_GeomFromText function
    // Default SRID is 0 (unknown), can be configured if needed
    return [NSString stringWithFormat:@"ST_GeomFromText('%@', 0)", wkt];
}

- (NSString *)geometryType {
    if (geometryType) {
        return geometryType;
    }
    
    // Would need to parse from WKB data in full implementation
    return @"GEOMETRY";
}

- (NSData *)data {
    return geometryData;
}

+ (instancetype)geometryWithX:(double)x y:(double)y {
    NSString *wktString = [NSString stringWithFormat:@"POINT(%f %f)", x, y];
    return [[SPPostgresGeometryData alloc] initWithWKTString:wktString];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<SPPostgresGeometryData: %@>", [self wktString]];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[SPPostgresGeometryData class]]) {
        return NO;
    }
    
    SPPostgresGeometryData *other = (SPPostgresGeometryData *)object;
    return [[self wktString] isEqualToString:[other wktString]];
}

- (NSUInteger)hash {
    return [[self wktString] hash];
}

- (NSDictionary *)coordinates {
    // Returns coordinate data suitable for SPGeometryDataView
    // Parses WKT and extracts coordinates as arrays
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSString *wkt = [self wktString];
    
    if (!wkt || [wkt length] == 0) {
        return @{@"type": @"GEOMETRY", @"coordinates": @[]};
    }
    
    [result setObject:[self geometryType] forKey:@"type"];
    
    // Parse coordinates from WKT string
    // Extract content between parentheses
    NSRange openParen = [wkt rangeOfString:@"("];
    NSRange closeParen = [wkt rangeOfString:@")" options:NSBackwardsSearch];
    
    if (openParen.location != NSNotFound && closeParen.location != NSNotFound && closeParen.location > openParen.location + 1) {
        NSString *coordStr = [wkt substringWithRange:NSMakeRange(openParen.location + 1, closeParen.location - openParen.location - 1)];
        
        // Parse coordinate pairs (space-separated x y values)
        NSArray *pairs = [coordStr componentsSeparatedByString:@","];
        NSMutableArray *coordArray = [NSMutableArray array];
        
        for (NSString *pair in pairs) {
            NSString *trimmedPair = [pair stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSArray *values = [trimmedPair componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            
            if ([values count] >= 2) {
                double x = [[values objectAtIndex:0] doubleValue];
                double y = [[values objectAtIndex:1] doubleValue];
                [coordArray addObject:@[@(x), @(y)]];
            }
        }
        
        [result setObject:coordArray forKey:@"coordinates"];
    } else {
        [result setObject:@[] forKey:@"coordinates"];
    }
    
    return [NSDictionary dictionaryWithDictionary:result];
}

@end
