//
//  SPBundleManager.h
//  sequel-ace
//
//  Created by James on 5/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

#ifndef SPBundleManager_h
#define SPBundleManager_h

@import Firebase;

@interface SPBundleManager : NSObject

@property (readwrite, strong) NSMutableDictionary *alreadyBeeped;
@property (readwrite, strong) NSMutableDictionary *bundleItems;
@property (readwrite, strong) NSMutableDictionary *bundleCategories;
@property (readwrite, strong) NSMutableDictionary *bundleTriggers;
@property (readwrite, strong) NSMutableArray *bundleUsedScopes;
@property (readwrite, strong) NSMutableArray *bundleHTMLOutputController;
@property (readwrite, strong) NSMutableDictionary *bundleKeyEquivalents;
@property (readwrite, strong) NSMutableDictionary *installedBundleUUIDs;



- (IBAction)bundleCommandDispatcher:(id)sender;
- (void)removeBundle:(NSString*)bundle;
- (void)doOrDoNotBeep:(NSString*)key;

- (void)replaceLegacyString:(NSMutableDictionary*)filesContainingLegacyString;
- (NSMutableDictionary*)findLegacyStrings:(NSString *)filePath;
- (void)renameLegacyBundles;

- (void)addHTMLOutputController:(id)controller;
- (void)removeHTMLOutputController:(id)controller;

- (NSArray *)bundleCategoriesForScope:(NSString *)scope;
- (NSArray *)bundleItemsForScope:(NSString *)scope;
- (NSArray *)bundleCommandsForTrigger:(NSString *)trigger;
- (NSDictionary *)bundleKeyEquivalentsForScope:(NSString *)scope;

@end

#endif /* BundleManager_h */
