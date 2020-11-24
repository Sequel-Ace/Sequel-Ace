//
//  SPBundleFunctions.h
//  Sequel Ace
//
//  Created by James on 25/11/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.

/**
 * Loads on old style bundle, and saves in the new format with the newShortcut NSData field. to a duplicate bundle with a new filename. e.g. CopyasCSV.spBundle -> CopyasCSV.2.spBundle
 * @param cmdData - NSDictionary containg old command list
 * @param bundleFilePath - NSString path for the existing bundle. e.g. ~/Library/Containers/com.sequel-ace.sequel-ace/Data/Library/Application Support/Sequel Ace/Bundles/CopyasCSV.spBundle
 * @return BOOL - success or fail of the new bundle write to file
 */
BOOL SPMigateBundleToNewFormat(NSDictionary * _Nonnull cmdData, NSString * _Nonnull bundleFilePath);
