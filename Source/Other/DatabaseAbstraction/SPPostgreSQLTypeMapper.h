//
//  SPPostgreSQLTypeMapper.h
//  Sequel Ace
//
//  Created by Sequel Ace on 2024.
//  Copyright (c) 2024 Sequel Ace. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Helper class to map PostgreSQL type OIDs to type names and groupings
 * Based on PostgreSQL catalog/pg_type.dat
 */
@interface SPPostgreSQLTypeMapper : NSObject

/**
 * Get the type name for a PostgreSQL OID
 * @param oid PostgreSQL type OID
 * @return Type name string (e.g., "varchar", "integer", "timestamp")
 */
+ (NSString *)typeNameForOID:(uint32_t)oid;

/**
 * Get the type grouping for a PostgreSQL OID
 * @param oid PostgreSQL type OID
 * @return Type grouping string (e.g., "string", "integer", "float", "date", "geometry")
 */
+ (NSString *)typeGroupingForOID:(uint32_t)oid;

@end

NS_ASSUME_NONNULL_END

