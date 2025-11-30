//
//  SPPostgresGeometryData.h
//  SPPostgresFramework
//
//  Created by Mehmet Karabulut (mehmetik@gmail.com) on November 30, 2025.
//  Copyright (c) 2025 Mehmet Karabulut.
//  This software is released under the GPL License.
//  This is an open-source project forked from Sequel Ace.
//

#import <Foundation/Foundation.h>

/**
 * SPPostgresGeometryData class handles PostGIS geometry data types
 * such as POINT, LINESTRING, POLYGON, etc.
 * 
 * This class provides conversion between PostgreSQL binary geometry format
 * and Well-Known Text (WKT) representation.
 */
@interface SPPostgresGeometryData : NSObject {
    NSData *geometryData;
    NSString *wktStringCache;
    NSString *geometryType;
}

/**
 * Initialize with raw geometry data from PostgreSQL
 */
- (instancetype)initWithData:(NSData *)data;

/**
 * Initialize with Well-Known Text (WKT) string
 */
- (instancetype)initWithWKTString:(NSString *)wktString;

/**
 * Returns the Well-Known Text representation of the geometry
 */
- (NSString *)wktString;

/**
 * Returns a SQL function call to convert WKT to geometry
 * e.g., "ST_GeomFromText('POINT(1 2)', 4326)"
 */
- (NSString *)getGeomFromTextString;

/**
 * Returns the geometry type (POINT, LINESTRING, POLYGON, etc.)
 */
- (NSString *)geometryType;

/**
 * Returns the raw binary data
 */
- (NSData *)data;

/**
 * Creates geometry from coordinates (for simple POINT geometries)
 */
+ (instancetype)geometryWithX:(double)x y:(double)y;

@end
