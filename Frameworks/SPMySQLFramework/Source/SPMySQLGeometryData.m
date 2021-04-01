//
//  SPMySQLGeometryData.m
//  sequel-pro
//
//  Created by Hans-Jörg Bibiko on October 07, 2010
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

#import "SPMySQLGeometryData.h"
#include <stdlib.h>
#include <string.h>

enum wkbType
{
	wkb_point = 1,
	wkb_linestring = 2,
	wkb_polygon = 3,
	wkb_multipoint = 4,
	wkb_multilinestring = 5,
	wkb_multipolygon = 6,
	wkb_geometrycollection = 7
};

typedef struct st_point_2d_
{
	double x;
	double y;
} st_point_2d;

#define SIZEOF_STORED_UINT32 4
#define SIZEOF_STORED_DOUBLE 8
#define POINT_DATA_SIZE (SIZEOF_STORED_DOUBLE*2)
#define WKB_HEADER_SIZE (1+SIZEOF_STORED_UINT32)
#define BUFFER_START 0

@implementation SPMySQLGeometryData

/**
 * Initialize the SPMySQLGeometryData object
 */
- (instancetype)init
{
	if ((self = [super init])) {
		geoBuffer = nil;
		bufferLength = 0;
	}
	return self;
}

/**
 * Initialize the SPMySQLGeometryData object with the WKB data
 */
- (instancetype)initWithBytes:(const void *)geoData length:(NSUInteger)length
{
	if ((self = [self init])) {
		bufferLength = length;
		geoBuffer = malloc(bufferLength);
		memcpy(geoBuffer, geoData, bufferLength);
	}
	return self;
}

- (nonnull id)copyWithZone:(nullable NSZone *)zone {
    return [self copy];
}

/**
 * Return an autorelease SPMySQLGeometryData object
 */
+ (instancetype)dataWithBytes:(const void *)geoData length:(NSUInteger)length
{
	return [[SPMySQLGeometryData alloc] initWithBytes:geoData length:length];
}

/**
 * Return the hex representation of the WKB buffer (only for convenience)
 */
- (NSString*)description
{
	return [[NSData dataWithBytes:geoBuffer length:bufferLength] description];
}

/**
 * Return the length of the WKB buffer
 */
- (NSUInteger)length
{
	return bufferLength;
}

/**
 * Return NSData pointer of the WKB buffer
 */
- (NSData *)data
{
	return [NSData dataWithBytes:geoBuffer length:bufferLength];
}

/**
 * Return a human readable WKT string of the internal format (imitating the SQL function AsText()).
 */
- (NSString *)wktString
{
	char byteOrder;
	uint32_t geoType, numberOfItems, numberOfSubItems, numberOfSubSubItems, numberOfCollectionItems;
	int32_t srid;
	st_point_2d aPoint;

	uint32_t i, j, k, n;          // Loop counter for numberOf...Items
	uint32_t ptr = BUFFER_START;  // pointer to geoBuffer while parsing

	NSMutableString *wkt = [NSMutableString string];

	if (bufferLength < WKB_HEADER_SIZE) return @"";

	memcpy(&srid, &geoBuffer[0], SIZEOF_STORED_UINT32);
	ptr += SIZEOF_STORED_UINT32;

	byteOrder = (char)geoBuffer[ptr];

	if (byteOrder != 0x1) return @"Byte order not yet supported";

	ptr++;
	geoType = geoBuffer[ptr];
	ptr += SIZEOF_STORED_UINT32;

	switch (geoType) {

		case wkb_point:
			memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
			return [NSString stringWithFormat:@"POINT(%.16g %.16g)%@", aPoint.x, aPoint.y, (srid) ? [NSString stringWithFormat:@",%d",srid]: @""];
		break;

		case wkb_linestring:
			[wkt setString:@"LINESTRING("];
			memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
			ptr += SIZEOF_STORED_UINT32;
			for (i=0; i < numberOfItems; i++) {
				memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
				[wkt appendFormat:@"%.16g %.16g%@", aPoint.x, aPoint.y, (i < numberOfItems-1) ? @"," : @""];
				ptr += POINT_DATA_SIZE;
			}
			[wkt appendFormat:@")%@", (srid) ? [NSString stringWithFormat:@",%d",srid]: @""];
			return wkt;
		break;

		case wkb_polygon:
			[wkt setString:@"POLYGON("];
			memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
			ptr += SIZEOF_STORED_UINT32;
			for (i=0; i < numberOfItems; i++) {
				memcpy(&numberOfSubItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
				ptr += SIZEOF_STORED_UINT32;
				[wkt appendString:@"("];
				for (j=0; j < numberOfSubItems; j++) {
					memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
					[wkt appendFormat:@"%.16g %.16g%@", aPoint.x, aPoint.y, (j < numberOfSubItems-1) ? @"," : @""];
					ptr += POINT_DATA_SIZE;
				}
				[wkt appendFormat:@")%@", (i < numberOfItems-1) ? @"," : @""];
			}
			[wkt appendFormat:@")%@", (srid) ? [NSString stringWithFormat:@",%d",srid]: @""];
			return wkt;
		break;

		case wkb_multipoint:
			[wkt setString:@"MULTIPOINT("];
			memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
			ptr += SIZEOF_STORED_UINT32+WKB_HEADER_SIZE;
			for (i=0; i < numberOfItems; i++) {
				memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
				[wkt appendFormat:@"%.16g %.16g%@", aPoint.x, aPoint.y, (i < numberOfItems-1) ? @"," : @""];
				ptr += POINT_DATA_SIZE+WKB_HEADER_SIZE;
			}
			[wkt appendFormat:@")%@", (srid) ? [NSString stringWithFormat:@",%d",srid]: @""];
			return wkt;
		break;

		case wkb_multilinestring:
			[wkt setString:@"MULTILINESTRING("];
			memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
			ptr += SIZEOF_STORED_UINT32+WKB_HEADER_SIZE;
			for (i=0; i < numberOfItems; i++) {
				memcpy(&numberOfSubItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
				ptr += SIZEOF_STORED_UINT32;
				[wkt appendString:@"("];
				for (j=0; j < numberOfSubItems; j++) {
					memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
					[wkt appendFormat:@"%.16g %.16g%@", aPoint.x, aPoint.y, (j < numberOfSubItems-1) ? @"," : @""];
					ptr += POINT_DATA_SIZE;
				}
				ptr += WKB_HEADER_SIZE;
				[wkt appendFormat:@")%@", (i < numberOfItems-1) ? @"," : @""];
			}
			[wkt appendFormat:@")%@", (srid) ? [NSString stringWithFormat:@",%d",srid]: @""];
			return wkt;
		break;

		case wkb_multipolygon:
			[wkt setString:@"MULTIPOLYGON("];
			memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
			ptr += SIZEOF_STORED_UINT32+WKB_HEADER_SIZE;
			for (i=0; i < numberOfItems; i++) {
				memcpy(&numberOfSubItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
				ptr += SIZEOF_STORED_UINT32;
				[wkt appendString:@"("];
				for (j=0; j < numberOfSubItems; j++) {
					memcpy(&numberOfSubSubItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
					ptr += SIZEOF_STORED_UINT32;
					[wkt appendString:@"("];
					for (k=0; k < numberOfSubSubItems; k++) {
						memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
						[wkt appendFormat:@"%.16g %.16g%@", aPoint.x, aPoint.y, (k < numberOfSubSubItems-1) ? @"," : @""];
						ptr += POINT_DATA_SIZE;
					}
					[wkt appendFormat:@")%@", (j < numberOfSubItems-1) ? @"," : @""];
				}
				ptr += WKB_HEADER_SIZE;
				[wkt appendFormat:@")%@", (i < numberOfItems-1) ? @"," : @""];
			}
			[wkt appendFormat:@")%@", (srid) ? [NSString stringWithFormat:@",%d",srid]: @""];
			return wkt;
		break;

		case wkb_geometrycollection:
			[wkt setString:@"GEOMETRYCOLLECTION("];
			numberOfCollectionItems = geoBuffer[ptr];
			ptr += SIZEOF_STORED_UINT32;

			for (n=0; n < numberOfCollectionItems; n++) {

				byteOrder = (char)geoBuffer[ptr];

				if(byteOrder != 0x1) return @"Byte order not yet supported";

				ptr++;
				geoType = geoBuffer[ptr];
				ptr += SIZEOF_STORED_UINT32;

				switch(geoType) {

					case wkb_point:
						memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
						[wkt appendFormat:@"POINT(%.16g %.16g)", aPoint.x, aPoint.y];
						ptr += POINT_DATA_SIZE;
					break;

					case wkb_linestring:
						[wkt appendString:@"LINESTRING("];
						memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
						ptr += SIZEOF_STORED_UINT32;
						for (i=0; i < numberOfItems; i++) {
							memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
							[wkt appendFormat:@"%.16g %.16g%@", aPoint.x, aPoint.y, (i < numberOfItems-1) ? @"," : @""];
							ptr += POINT_DATA_SIZE;
						}
						[wkt appendString:@")"];
					break;

					case wkb_polygon:
						[wkt appendString:@"POLYGON("];
						memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
						ptr += SIZEOF_STORED_UINT32;
						for (i=0; i < numberOfItems; i++) {
							memcpy(&numberOfSubItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
							ptr += SIZEOF_STORED_UINT32;
							[wkt appendString:@"("];
							for (j=0; j < numberOfSubItems; j++) {
								memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
								[wkt appendFormat:@"%.16g %.16g%@", aPoint.x, aPoint.y, (j < numberOfSubItems-1) ? @"," : @""];
								ptr += POINT_DATA_SIZE;
							}
							[wkt appendFormat:@")%@", (i < numberOfItems-1) ? @"," : @""];
						}
						[wkt appendString:@")"];
					break;

					case wkb_multipoint:
						[wkt appendString:@"MULTIPOINT("];
						memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
						ptr += SIZEOF_STORED_UINT32+WKB_HEADER_SIZE;
						for (i=0; i < numberOfItems; i++) {
							memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
							[wkt appendFormat:@"%.16g %.16g%@", aPoint.x, aPoint.y, (i < numberOfItems-1) ? @"," : @""];
							ptr += POINT_DATA_SIZE+WKB_HEADER_SIZE;
						}
						ptr -= WKB_HEADER_SIZE;
						[wkt appendString:@")"];
					break;

					case wkb_multilinestring:
						[wkt appendString:@"MULTILINESTRING("];
						memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
						ptr += SIZEOF_STORED_UINT32+WKB_HEADER_SIZE;
						for (i=0; i < numberOfItems; i++) {
							memcpy(&numberOfSubItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
							ptr += SIZEOF_STORED_UINT32;
							[wkt appendString:@"("];
							for (j=0; j < numberOfSubItems; j++) {
								memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
								[wkt appendFormat:@"%.16g %.16g%@", aPoint.x, aPoint.y, (j < numberOfSubItems-1) ? @"," : @""];
								ptr += POINT_DATA_SIZE;
							}
							ptr += WKB_HEADER_SIZE;
							[wkt appendFormat:@")%@", (i < numberOfItems-1) ? @"," : @""];
						}
						ptr -= WKB_HEADER_SIZE;
						[wkt appendString:@")"];
					break;

					case wkb_multipolygon:
						[wkt appendString:@"MULTIPOLYGON("];
						memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
						ptr += SIZEOF_STORED_UINT32+WKB_HEADER_SIZE;
						for (i=0; i < numberOfItems; i++) {
							memcpy(&numberOfSubItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
							ptr += SIZEOF_STORED_UINT32;
							[wkt appendString:@"("];
							for (j=0; j < numberOfSubItems; j++) {
								memcpy(&numberOfSubSubItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
								ptr += SIZEOF_STORED_UINT32;
								[wkt appendString:@"("];
								for (k=0; k < numberOfSubSubItems; k++) {
									memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
									[wkt appendFormat:@"%.16g %.16g%@", aPoint.x, aPoint.y, (k < numberOfSubSubItems-1) ? @"," : @""];
									ptr += POINT_DATA_SIZE;
								}
								[wkt appendFormat:@")%@", (j < numberOfSubItems-1) ? @"," : @""];
							}
							ptr += WKB_HEADER_SIZE;
							[wkt appendFormat:@")%@", (i < numberOfItems-1) ? @"," : @""];
						}
						ptr -= WKB_HEADER_SIZE;
						[wkt appendString:@")"];
					break;

					default:
						return @"Error geometrycollection type parsing";
				}
				[wkt appendString:(n < numberOfCollectionItems-1) ? @"," : @""];
			}
			[wkt appendFormat:@")%@", (srid) ? [NSString stringWithFormat:@",%d",srid]: @""];
			return wkt;
		break;

		default:
			return @"Error geometry type parsing";
	}

	return @"Error while parsing";
}

/**
 * Return a dictionary of coordinates, bbox, etc. to be able to draw the given geometry.
 *
 * @return A dictionary having the following keys: "bbox" as NSArray of NSNumbers of x_min x_max y_min y_max, "coordinates" as NSArray containing the 
 * the to be drawn points as NSPoint strings, "type" as NSString
 */
- (NSDictionary *)coordinates
{
	char byteOrder;
	uint32_t geoType, numberOfItems, numberOfSubItems, numberOfSubSubItems, numberOfCollectionItems;
	int32_t srid;
	st_point_2d aPoint;

	uint32_t i, j, k, n;          // Loop counter for numberOf...Items
	uint32_t ptr = BUFFER_START;  // pointer to geoBuffer while parsing

	double x_min = DBL_MAX;
	double x_max = -DBL_MAX;
	double y_min = DBL_MAX;
	double y_max = -DBL_MAX;

	NSMutableArray *coordinates = [NSMutableArray array];
	NSMutableArray *subcoordinates = [NSMutableArray array];
	NSMutableArray *pointcoordinates = [NSMutableArray array];
	NSMutableArray *linecoordinates = [NSMutableArray array];
	NSMutableArray *linesubcoordinates = [NSMutableArray array];
	NSMutableArray *polygoncoordinates = [NSMutableArray array];
	NSMutableArray *polygonsubcoordinates = [NSMutableArray array];

	if (bufferLength < WKB_HEADER_SIZE) return nil;

	memcpy(&srid, &geoBuffer[0], SIZEOF_STORED_UINT32);
	ptr += SIZEOF_STORED_UINT32;

	byteOrder = (char)geoBuffer[ptr];

	if (byteOrder != 0x1) return nil;

	ptr++;
	geoType = geoBuffer[ptr];
	ptr += SIZEOF_STORED_UINT32;

	switch(geoType) {

		case wkb_point:
			memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
			x_min = aPoint.x;
			x_max = aPoint.x;
			y_min = aPoint.y;
			y_max = aPoint.y;
			[coordinates addObject:NSStringFromPoint(NSMakePoint((CGFloat)aPoint.x, (CGFloat)aPoint.y))];
			return [NSDictionary dictionaryWithObjectsAndKeys:
				[NSArray arrayWithObjects:
					[NSNumber numberWithDouble:x_min],
					[NSNumber numberWithDouble:x_max],
					[NSNumber numberWithDouble:y_min],
					[NSNumber numberWithDouble:y_max],
					nil], @"bbox",
				coordinates, @"coordinates",
				[NSNumber numberWithInt:srid], @"srid",
				@"POINT", @"type",
				nil];
		break;

		case wkb_linestring:
			memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
			ptr += SIZEOF_STORED_UINT32;
			for (i=0; i < numberOfItems; i++) {
				memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
				x_min = (aPoint.x < x_min) ? aPoint.x : x_min;
				x_max = (aPoint.x > x_max) ? aPoint.x : x_max;
				y_min = (aPoint.y < y_min) ? aPoint.y : y_min;
				y_max = (aPoint.y > y_max) ? aPoint.y : y_max;
				[coordinates addObject:NSStringFromPoint(NSMakePoint((CGFloat)aPoint.x, (CGFloat)aPoint.y))];
				ptr += POINT_DATA_SIZE;
			}
			return [NSDictionary dictionaryWithObjectsAndKeys:
				[NSArray arrayWithObjects:
					[NSNumber numberWithDouble:x_min],
					[NSNumber numberWithDouble:x_max],
					[NSNumber numberWithDouble:y_min],
					[NSNumber numberWithDouble:y_max],
					nil], @"bbox",
				[NSArray arrayWithObjects:coordinates,nil], @"coordinates",
				@"LINESTRING", @"type",
				nil];
		break;

		case wkb_polygon:
			memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
			ptr += SIZEOF_STORED_UINT32;
			for (i=0; i < numberOfItems; i++) {
				memcpy(&numberOfSubItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
				ptr += SIZEOF_STORED_UINT32;
				for (j=0; j < numberOfSubItems; j++) {
					memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
					x_min = (aPoint.x < x_min) ? aPoint.x : x_min;
					x_max = (aPoint.x > x_max) ? aPoint.x : x_max;
					y_min = (aPoint.y < y_min) ? aPoint.y : y_min;
					y_max = (aPoint.y > y_max) ? aPoint.y : y_max;
					[subcoordinates addObject:NSStringFromPoint(NSMakePoint((CGFloat)aPoint.x, (CGFloat)aPoint.y))];
					ptr += POINT_DATA_SIZE;
				}
				[coordinates addObject:[subcoordinates copy]];
				[subcoordinates removeAllObjects];
			}
			return [NSDictionary dictionaryWithObjectsAndKeys:
				[NSArray arrayWithObjects:
					[NSNumber numberWithDouble:x_min],
					[NSNumber numberWithDouble:x_max],
					[NSNumber numberWithDouble:y_min],
					[NSNumber numberWithDouble:y_max],
					nil], @"bbox",
				coordinates, @"coordinates",
				[NSNumber numberWithInt:srid], @"srid",
				@"POLYGON", @"type",
				nil];
		break;

		case wkb_multipoint:
			memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
			ptr += SIZEOF_STORED_UINT32+WKB_HEADER_SIZE;
			for (i=0; i < numberOfItems; i++) {
				memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
				x_min = (aPoint.x < x_min) ? aPoint.x : x_min;
				x_max = (aPoint.x > x_max) ? aPoint.x : x_max;
				y_min = (aPoint.y < y_min) ? aPoint.y : y_min;
				y_max = (aPoint.y > y_max) ? aPoint.y : y_max;
				[coordinates addObject:NSStringFromPoint(NSMakePoint((CGFloat)aPoint.x, (CGFloat)aPoint.y))];
				ptr += POINT_DATA_SIZE+WKB_HEADER_SIZE;
			}
			return [NSDictionary dictionaryWithObjectsAndKeys:
				[NSArray arrayWithObjects:
					[NSNumber numberWithDouble:x_min],
					[NSNumber numberWithDouble:x_max],
					[NSNumber numberWithDouble:y_min],
					[NSNumber numberWithDouble:y_max],
					nil], @"bbox",
				coordinates, @"coordinates",
				[NSNumber numberWithInt:srid], @"srid",
				@"MULTIPOINT", @"type",
				nil];
		break;
		
		case wkb_multilinestring:
			memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
			ptr += SIZEOF_STORED_UINT32+WKB_HEADER_SIZE;
			for (i=0; i < numberOfItems; i++) {
				memcpy(&numberOfSubItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
				ptr += SIZEOF_STORED_UINT32;
				for (j=0; j < numberOfSubItems; j++) {
					memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
					x_min = (aPoint.x < x_min) ? aPoint.x : x_min;
					x_max = (aPoint.x > x_max) ? aPoint.x : x_max;
					y_min = (aPoint.y < y_min) ? aPoint.y : y_min;
					y_max = (aPoint.y > y_max) ? aPoint.y : y_max;
					[subcoordinates addObject:NSStringFromPoint(NSMakePoint((CGFloat)aPoint.x, (CGFloat)aPoint.y))];
					ptr += POINT_DATA_SIZE;
				}
				ptr += WKB_HEADER_SIZE;
				[coordinates addObject:[subcoordinates copy]];
				[subcoordinates removeAllObjects];
			}
			return [NSDictionary dictionaryWithObjectsAndKeys:
				[NSArray arrayWithObjects:
					[NSNumber numberWithDouble:x_min],
					[NSNumber numberWithDouble:x_max],
					[NSNumber numberWithDouble:y_min],
					[NSNumber numberWithDouble:y_max],
					nil], @"bbox",
				coordinates, @"coordinates",
				[NSNumber numberWithInt:srid], @"srid",
				@"MULTILINESTRING", @"type",
				nil];
		break;
		
		case wkb_multipolygon:
			memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
			ptr += SIZEOF_STORED_UINT32+WKB_HEADER_SIZE;
			for (i=0; i < numberOfItems; i++) {
				memcpy(&numberOfSubItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
				ptr += SIZEOF_STORED_UINT32;
				for (j=0; j < numberOfSubItems; j++) {
					memcpy(&numberOfSubSubItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
					ptr += SIZEOF_STORED_UINT32;
					for (k=0; k < numberOfSubSubItems; k++) {
						memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
						x_min = (aPoint.x < x_min) ? aPoint.x : x_min;
						x_max = (aPoint.x > x_max) ? aPoint.x : x_max;
						y_min = (aPoint.y < y_min) ? aPoint.y : y_min;
						y_max = (aPoint.y > y_max) ? aPoint.y : y_max;
						[subcoordinates addObject:NSStringFromPoint(NSMakePoint((CGFloat)aPoint.x, (CGFloat)aPoint.y))];
						ptr += POINT_DATA_SIZE;
					}
					[coordinates addObject:[subcoordinates copy]];
					[subcoordinates removeAllObjects];
				}
				ptr += WKB_HEADER_SIZE;
			}
			return [NSDictionary dictionaryWithObjectsAndKeys:
				[NSArray arrayWithObjects:
					[NSNumber numberWithDouble:x_min],
					[NSNumber numberWithDouble:x_max],
					[NSNumber numberWithDouble:y_min],
					[NSNumber numberWithDouble:y_max],
					nil], @"bbox",
				coordinates, @"coordinates",
				[NSNumber numberWithInt:srid], @"srid",
				@"MULTIPOLYGON", @"type",
				nil];
		break;
		
		case wkb_geometrycollection:
			numberOfCollectionItems = geoBuffer[ptr];
			ptr += SIZEOF_STORED_UINT32;
			
			for (n=0; n < numberOfCollectionItems; n++) {
			
				byteOrder = (char)geoBuffer[ptr];
			
				if (byteOrder != 0x1)
					return nil;
			
				ptr++;
				geoType = geoBuffer[ptr];
				ptr += SIZEOF_STORED_UINT32;
			
				switch(geoType) {
			
					case wkb_point:
						memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
						x_min = (aPoint.x < x_min) ? aPoint.x : x_min;
						x_max = (aPoint.x > x_max) ? aPoint.x : x_max;
						y_min = (aPoint.y < y_min) ? aPoint.y : y_min;
						y_max = (aPoint.y > y_max) ? aPoint.y : y_max;
						[pointcoordinates addObject:NSStringFromPoint(NSMakePoint((CGFloat)aPoint.x, (CGFloat)aPoint.y))];
						ptr += POINT_DATA_SIZE;
					break;
			
					case wkb_linestring:
						memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
						ptr += SIZEOF_STORED_UINT32;
						for (i=0; i < numberOfItems; i++) {
							memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
							x_min = (aPoint.x < x_min) ? aPoint.x : x_min;
							x_max = (aPoint.x > x_max) ? aPoint.x : x_max;
							y_min = (aPoint.y < y_min) ? aPoint.y : y_min;
							y_max = (aPoint.y > y_max) ? aPoint.y : y_max;
							[linesubcoordinates addObject:NSStringFromPoint(NSMakePoint((CGFloat)aPoint.x, (CGFloat)aPoint.y))];
							ptr += POINT_DATA_SIZE;
						}
						[linecoordinates addObject:[linesubcoordinates copy]];
						[linesubcoordinates removeAllObjects];
					break;
			
					case wkb_polygon:
						memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
						ptr += SIZEOF_STORED_UINT32;
						for (i=0; i < numberOfItems; i++) {
							memcpy(&numberOfSubItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
							ptr += SIZEOF_STORED_UINT32;
							for (j=0; j < numberOfSubItems; j++) {
								memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
								x_min = (aPoint.x < x_min) ? aPoint.x : x_min;
								x_max = (aPoint.x > x_max) ? aPoint.x : x_max;
								y_min = (aPoint.y < y_min) ? aPoint.y : y_min;
								y_max = (aPoint.y > y_max) ? aPoint.y : y_max;
								[polygonsubcoordinates addObject:NSStringFromPoint(NSMakePoint((CGFloat)aPoint.x, (CGFloat)aPoint.y))];
								ptr += POINT_DATA_SIZE;
							}
							[polygoncoordinates addObject:[polygonsubcoordinates copy]];
							[polygonsubcoordinates removeAllObjects];
						}
					break;
			
					case wkb_multipoint:
						memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
						ptr += SIZEOF_STORED_UINT32+WKB_HEADER_SIZE;
						for (i=0; i < numberOfItems; i++) {
							memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
							x_min = (aPoint.x < x_min) ? aPoint.x : x_min;
							x_max = (aPoint.x > x_max) ? aPoint.x : x_max;
							y_min = (aPoint.y < y_min) ? aPoint.y : y_min;
							y_max = (aPoint.y > y_max) ? aPoint.y : y_max;
							[pointcoordinates addObject:NSStringFromPoint(NSMakePoint((CGFloat)aPoint.x, (CGFloat)aPoint.y))];
							ptr += POINT_DATA_SIZE+WKB_HEADER_SIZE;
						}
						ptr -= WKB_HEADER_SIZE;
					break;
			
					case wkb_multilinestring:
						memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
						ptr += SIZEOF_STORED_UINT32+WKB_HEADER_SIZE;
						for (i=0; i < numberOfItems; i++) {
							memcpy(&numberOfSubItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
							ptr += SIZEOF_STORED_UINT32;
							for (j=0; j < numberOfSubItems; j++) {
								memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
								x_min = (aPoint.x < x_min) ? aPoint.x : x_min;
								x_max = (aPoint.x > x_max) ? aPoint.x : x_max;
								y_min = (aPoint.y < y_min) ? aPoint.y : y_min;
								y_max = (aPoint.y > y_max) ? aPoint.y : y_max;
								[linesubcoordinates addObject:NSStringFromPoint(NSMakePoint((CGFloat)aPoint.x, (CGFloat)aPoint.y))];
								ptr += POINT_DATA_SIZE;
							}
							[linecoordinates addObject:[linesubcoordinates copy]];
							[linesubcoordinates removeAllObjects];
							ptr += WKB_HEADER_SIZE;
						}
						ptr -= WKB_HEADER_SIZE;
					break;
			
					case wkb_multipolygon:
						memcpy(&numberOfItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
						ptr += SIZEOF_STORED_UINT32+WKB_HEADER_SIZE;
						for (i=0; i < numberOfItems; i++) {
							memcpy(&numberOfSubItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
							ptr += SIZEOF_STORED_UINT32;
							for (j=0; j < numberOfSubItems; j++) {
								memcpy(&numberOfSubSubItems, &geoBuffer[ptr], SIZEOF_STORED_UINT32);
								ptr += SIZEOF_STORED_UINT32;
								for (k=0; k < numberOfSubSubItems; k++) {
									memcpy(&aPoint, &geoBuffer[ptr], POINT_DATA_SIZE);
									x_min = (aPoint.x < x_min) ? aPoint.x : x_min;
									x_max = (aPoint.x > x_max) ? aPoint.x : x_max;
									y_min = (aPoint.y < y_min) ? aPoint.y : y_min;
									y_max = (aPoint.y > y_max) ? aPoint.y : y_max;
									[polygonsubcoordinates addObject:NSStringFromPoint(NSMakePoint((CGFloat)aPoint.x, (CGFloat)aPoint.y))];
									ptr += POINT_DATA_SIZE;
								}
								[polygoncoordinates addObject:[polygonsubcoordinates copy]];
								[polygonsubcoordinates removeAllObjects];
							}
							ptr += WKB_HEADER_SIZE;
						}
						ptr -= WKB_HEADER_SIZE;
					break;
			
					default:
						return nil;
				}
			}
			return [NSDictionary dictionaryWithObjectsAndKeys:
				[NSArray arrayWithObjects:
					[NSNumber numberWithDouble:x_min],
					[NSNumber numberWithDouble:x_max],
					[NSNumber numberWithDouble:y_min],
					[NSNumber numberWithDouble:y_max],
					nil], @"bbox",
				[NSArray arrayWithObjects:pointcoordinates, linecoordinates, polygoncoordinates, nil], @"coordinates",
				@"GEOMETRYCOLLECTION", @"type",
				nil];
		break;

		default:
			return nil;
	}

	return nil;
}

/**
 * Return the WKB type of the geoBuffer ie if buffer represents a POINT, LINESTRING, etc.
 * according to stored wkbType in header file. It returns -1 if an error occurred.
 */
- (NSInteger)wkbType
{
	char byteOrder;
	SInt32 geoType;

	NSUInteger ptr = BUFFER_START;  // pointer to geoBuffer while parsing

	if (bufferLength < WKB_HEADER_SIZE) return -1;

	byteOrder = (char)geoBuffer[ptr];

	if (byteOrder != 0x1) return -1;

	ptr++;
	geoType = geoBuffer[ptr];
	
	if (geoType > 0 && geoType < 8) return geoType;

	return -1;
}

/**
 * Return the WKT type of the geoBuffer ie if buffer represents a POINT, LINESTRING, etc.
 * according to stored wkbType in header file. It returns nil if an error occurred.
 */
- (NSString *)wktType
{
	switch ([self wkbType])
	{
		case wkb_point:
			return @"POINT";
		case wkb_linestring:
			return @"LINESTRING";
		case wkb_polygon:
			return @"POLYGON";
		case wkb_multipoint:
			return @"MULTIPOINT";
		case wkb_multilinestring:
			return @"MULTILINESTRING";
		case wkb_multipolygon:
			return @"MULTIPOLYGON";
		case wkb_geometrycollection:
			return @"GEOMETRYCOLLECTION";
		default:
			return nil;
	}
	return nil;
}

- (void)dealloc
{
    if (geoBuffer && bufferLength) {
        free(geoBuffer);
    }
}

@end
