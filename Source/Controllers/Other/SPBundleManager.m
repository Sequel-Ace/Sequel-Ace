//
//  SPBundleNamager.m
//  Sequel Ace
//
//  Created by James on 5/12/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SPBundleManager.h"
#import "SPFunctions.h"
#import "SPAppController.h"
#import "SPTooltip.h"
#import "SPBundleHTMLOutputController.h"
#import "SPBundleCommandRunner.h"
#import "SPChooseMenuItemDialog.h"
#import "SPTextView.h"
#import "SPCopyTable.h"
#import "SPBundleEditorController.h"
#import "SPDatabaseDocument.h"


#import "sequel-ace-Swift.h"


/*
What do we want this to do?

 - (void)openUserBundleAtPath:(NSString *)filePath
 ☑️ - (NSMutableDictionary*)findLegacyStrings:(NSString *)filePath{
 ☑️ - (void)replaceLegacyString:(NSMutableDictionary*)filesContainingLegacyString{
 ☑️ - (void)renameLegacyBundles{
 ☑️ - (IBAction)reloadBundles:(id)sender --> Rebuild Bundles main menu item
 ☑️ - (void)removeBundle:(NSString*)bundle{

 ☑️ - (IBAction)bundleCommandDispatcher:(id)sender
 ☑️ - (IBAction)executeBundleItemForApp:(id)sender


 Do we need a singleton, always available? Yes for bundleCommandDispatcher

*/

@interface SPBundleManager()

@property (readwrite, strong) SPBundleEditorController *bundleEditorController;
@property (readwrite, strong) NSFileManager *fileManager;
@property (readwrite, strong) NSMutableArray *migratedLegacyBundles;
@property (readwrite, strong) NSMutableArray<NSString *> *badBundles;

@end


@implementation SPBundleManager

@synthesize fileManager, bundleEditorController;
@synthesize alreadyBeeped;
@synthesize badBundles, foundInstalledBundles;
@synthesize migratedLegacyBundles;
@synthesize bundleItems, bundleTriggers, bundleCategories, bundleUsedScopes, bundleKeyEquivalents, bundleHTMLOutputController, installedBundleUUIDs;

static SPBundleManager *sharedSPBundleManager = nil;

+ (SPBundleManager *)sharedSPBundleManager
{
	static dispatch_once_t onceToken;

	if (sharedSPBundleManager == nil) {
		dispatch_once_on_main_thread(&onceToken, ^{
			sharedSPBundleManager = [[SPBundleManager alloc] init];
		});
	}

	return sharedSPBundleManager;
}

- (instancetype)init
{
	if ((self = [super init])) {

        fileManager                = [NSFileManager defaultManager];
        alreadyBeeped              = [[NSMutableDictionary alloc] init];
        badBundles                 = [[NSMutableArray alloc] init];
        migratedLegacyBundles      = [[NSMutableArray alloc] init];
        bundleItems                = [[NSMutableDictionary alloc] initWithCapacity:1];
        bundleCategories           = [[NSMutableDictionary alloc] initWithCapacity:1];
        bundleTriggers             = [[NSMutableDictionary alloc] initWithCapacity:1];
        bundleUsedScopes           = [[NSMutableArray alloc] initWithCapacity:1];
		bundleHTMLOutputController = [[NSMutableArray alloc] initWithCapacity:1];
        bundleKeyEquivalents       = [[NSMutableDictionary alloc] initWithCapacity:1];
        installedBundleUUIDs       = [[NSMutableDictionary alloc] initWithCapacity:1];



		return self;
	}

	return nil;
}

#pragma mark - legacy string methods
- (NSMutableDictionary*)findLegacyStrings:(NSString *)filePath{

	SPLog(@"findLegacyStrings for %@", filePath);

	NSMutableArray *filesContainingLegacyStringArr = [NSMutableArray array];
	NSMutableDictionary *filesContainingLegacyString = [NSMutableDictionary dictionary];

	// enumerate dir
	NSDirectoryEnumerator *enumerator = [fileManager
										 enumeratorAtURL:[NSURL fileURLWithPath:filePath]
										 includingPropertiesForKeys:@[NSURLIsRegularFileKey]
										 options:NSDirectoryEnumerationSkipsHiddenFiles
										 errorHandler:nil];

	// check each file for legacy sequelpro string
	for (NSURL *fileURL in enumerator) {
		// Read the contents of the file into a string.
		NSError *error = nil;
		NSString *fileContentsString = [NSString stringWithContentsOfURL:fileURL
																encoding:NSUTF8StringEncoding
																   error:&error];

		// Make sure that the file has been read, log an error if it hasn't.
		if (!fileContentsString) {
			SPLog(@"Error reading file: %@", fileURL.absoluteString);
			continue;
		}

		// Search the file contents for the given string, put the results into an NSRange structure
		NSRange result = [fileContentsString rangeOfString:SPBundleLegacyAppSchema];

		// -rangeOfString returns the location of the string NSRange.location or NSNotFound.
		if (result.location == NSNotFound) {
			SPLog(@"sequelpro NOT found in file: %@", fileURL.absoluteString);
		}
		else{
			SPLog(@"sequelpro found in file: %@", fileURL.absoluteString);
			SPLog(@"match: %@", [fileContentsString substringWithRange:result]);
			SPLog(@"result: %lu, %lu", result.location, result.length);

			[filesContainingLegacyStringArr addObject:fileURL.absoluteString.lastPathComponent];

			// replace and save in case they want to proceed
			NSString *str = [fileContentsString stringByReplacingOccurrencesOfString:SPBundleLegacyAppSchema withString:SPBundleAppSchema];

			NSDictionary *tmpDict = @{ @"file" : fileURL.absoluteString.lastPathComponent, @"newString" : str };

			[filesContainingLegacyString safeSetObject:tmpDict forKey:fileURL];
		}
	}

	return filesContainingLegacyString;

}

- (void)replaceLegacyString:(NSMutableDictionary*)filesContainingLegacyString{
	// filesContainingLegacyString:
	// key = file URL
	// val = dict - key:@file = bundle filename
	//				key:@newstr = string for file with legacy str replaced.

	SPLog(@"replaceLegacyString");

	for(NSURL *url in filesContainingLegacyString.allKeys){

		SPLog(@"Writing new str to %@", url.absoluteString);

		NSDictionary *tmpDict = [filesContainingLegacyString safeObjectForKey:url];

		NSString *tmpStr = [tmpDict safeObjectForKey:@"newString"];

		SPLog(@"tmpDict: %@", tmpDict);
		SPLog(@"tmpStr: %@", tmpStr);

		NSError *err = nil;
		[tmpStr writeToURL:url atomically:NO encoding:NSUTF8StringEncoding error:&err];

		if(err){
			SPLog(@"failed to write new str to %@. Error: %@", url.absoluteString, err.localizedDescription);
		}
	}
}

#pragma mark - legacy bundle rename
- (void)renameLegacyBundles{

	SPLog(@"renameLegacyBundles");

	// if we find any legacy bundles we'll need to change the dict, so take a copy
	NSMutableDictionary *bundleItemsCopy = [bundleItems mutableCopy];

	[bundleItemsCopy enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSArray *obj, BOOL *stop1) {
		[obj enumerateObjectsUsingBlock:^(id obj2, NSUInteger idx, BOOL *stop){

			NSString *path = obj2[SPBundleInternPathToFileKey];

			if([path containsString:SPUserBundleFileExtension] == YES){

				SPLog(@"key: %@", key);
				SPLog(@"obj2 = %@",obj2);

				NSString *legacyPath = path.stringByDeletingLastPathComponent;

				NSMutableString *migratedPath = [[NSMutableString alloc] initWithCapacity:path.stringByDeletingLastPathComponent.length];
				[migratedPath setString:[path.stringByDeletingLastPathComponent dropSuffixWithSuffix:SPUserBundleFileExtension]];
				[migratedPath appendString:SPUserBundleFileExtensionV2];
				NSString *bundlePath = migratedPath.lastPathComponent;

				SPLog(@"migratedPath %@", migratedPath);
				SPLog(@"legacyPath %@", legacyPath);
				SPLog(@"bundlePath %@", bundlePath);

				NSError *error = nil;

				if (![fileManager fileExistsAtPath:migratedPath isDirectory:nil]) {
					SPLog(@"File DOES NOT YET exist at “%@”", migratedPath);

					if (![fileManager moveItemAtPath:legacyPath toPath:migratedPath error:&error]) {
						SPLog(@"Could not move “%@” to %@. Error: %@", legacyPath, migratedPath, error.localizedDescription);
						[self doOrDoNotBeep:legacyPath];
					}
					else{
						SPLog(@"File renamed successfully “%@”", migratedPath);
						
						[self->migratedLegacyBundles safeAddObject:migratedPath];

						// we need to add the new bundle version
						NSString *infoPath = [NSString stringWithFormat:@"%@/%@", migratedPath, SPBundleFileName];

						SPLog(@"infoPath %@", infoPath);

						// so load up the plist
						NSDictionary *cmdData = nil;

						NSError *readError = nil;

						NSData *pData = [NSData dataWithContentsOfFile:infoPath options:NSDataReadingUncached error:&readError];

						if(pData && !readError) {
							cmdData = [NSPropertyListSerialization propertyListWithData:pData
																				options:NSPropertyListImmutable
																				 format:NULL
																				  error:&readError];
						}

						if(!cmdData || readError) {
							SPLog(@"“%@” file couldn't be read. (error=%@)", infoPath, readError.localizedDescription);
							[self doOrDoNotBeep:infoPath];

							// remove the dodgy bundle
							[self removeBundle:migratedPath.lastPathComponent];

						}
						else{
							NSMutableDictionary *saveDict = [[NSMutableDictionary alloc] initWithCapacity:cmdData.count+1];
							[saveDict addEntriesFromDictionary:cmdData];
							[saveDict setObject:[NSNumber numberWithLong:SPBundleCurrentVersion] forKey:SPBundleVersionKey];

							readError = nil;

							[fileManager removeItemAtPath:infoPath error:&readError];

							if(readError) {
								SPLog(@"Could not delete %@. Error: %@", infoPath, readError.localizedDescription);
								[self doOrDoNotBeep:infoPath];
							}
							else{
								if (@available(macOS 10.13, *)) {
									readError = nil;
									[saveDict writeToURL:[NSURL fileURLWithPath:infoPath] error:&readError];
									if(readError){
										SPLog(@"Could not delete %@. Error: %@", infoPath, readError.localizedDescription);
									}
									else{
										SPLog(@"Successfully migrated: %@", migratedPath);
										// update the command path in the dict
										obj2[@"path"] = infoPath;

									}
								} else {
									[saveDict writeToFile:infoPath atomically:YES];
								}
							}
						}
					}
				}
				else{
					SPLog(@"File exists at path: %@", migratedPath);
				}
			}
			else{
                // Already migrated
			}
		}];
	}];

	// I think these shoul dbe the same... but in case
	if([bundleItems isEqualToDictionary:bundleItemsCopy]){
		SPLog(@"THE SAME!");
	}
	else{
		SPLog(@"DIFF!");
		[bundleItems setDictionary:bundleItemsCopy];
	}

	// check for legacy strings?
	if(migratedLegacyBundles.count > 0){

		SPLog(@"migratedLegacyBundles: %@", migratedLegacyBundles);

		NSMutableDictionary *filesContainingLegacyString = [NSMutableDictionary dictionary];

		for(NSString *filePath in migratedLegacyBundles){
			filesContainingLegacyString = [self findLegacyStrings:filePath];
			if(filesContainingLegacyString.count > 0){
				[self replaceLegacyString:filesContainingLegacyString];
			}
		}
	}
}

- (void)doOrDoNotBeep:(NSString*)key{

	if(![alreadyBeeped safeObjectForKey:key]){
		SPLog(@"Beeping for %@", key);
		NSBeep();
		[alreadyBeeped safeSetObject:@YES forKey:key];
	}
	else{
		SPLog(@"already beeped for %@", key);
	}
}

- (void)removeBundle:(NSString*)bundle{

	NSString *bundlePath = [fileManager applicationSupportDirectoryForSubDirectory:SPBundleSupportFolder error:nil];

	NSString *thePath = [NSString stringWithFormat:@"%@/%@", bundlePath, bundle];

	SPLog(@"the path %@", thePath);

	if(![fileManager fileExistsAtPath:thePath isDirectory:nil]) {
		SPLog(@"file does not exist %@", thePath);
		return;
	}

	NSError *error = nil;

	[fileManager removeItemAtPath:thePath error:&error];

	if(error != nil) {
		SPLog(@"file could not be deleted: %@", thePath);
		return;
	}

	SPLog(@"file was deleted: %@", thePath);
	[badBundles addObject:bundle];
}

- (IBAction)openBundleEditor:(id)sender
{
	if (!bundleEditorController) bundleEditorController = [[SPBundleEditorController alloc] init];

	[bundleEditorController showWindow:[NSApp mainWindow]];
}

- (IBAction)reloadBundles:(id)sender
{

	// Force releasing of any hidden HTML output windows, which will automatically remove them from the array.
	// Keep the visible windows.
	for (id c in bundleHTMLOutputController) {
		if (![[c window] isVisible]) {
			[[c window] performClose:SPAppDelegate];
		}
	}

	foundInstalledBundles = NO;

	NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];

	[bundleItems removeAllObjects];
	[bundleUsedScopes removeAllObjects];
	[bundleCategories removeAllObjects];
	[bundleTriggers removeAllObjects];
	[bundleKeyEquivalents removeAllObjects];
	[installedBundleUUIDs removeAllObjects];



	// Set up the bundle search paths
	// First process all in Application Support folder installed ones then Default ones
	NSError *appPathError = nil;
	NSArray *bundlePaths = [NSArray arrayWithObjects:
		[fileManager applicationSupportDirectoryForSubDirectory:SPBundleSupportFolder createIfNotExists:YES error:&appPathError],
		[NSString stringWithFormat:@"%@/Default Bundles", NSBundle.mainBundle.sharedSupportPath],
		nil];

	// If ~/Library/Application Path/Sequel Ace/Bundles couldn't be created bail
	if(appPathError != nil) {
		[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Bundles Installation Error", @"bundles installation error") message:[NSString stringWithFormat:NSLocalizedString(@"Couldn't create Application Support Bundle folder!\nError: %@", @"Couldn't create Application Support Bundle folder!\nError: %@"), [appPathError localizedDescription]] callback:nil];
		return;
	}

	BOOL processDefaultBundles = NO;

	NSArray *deletedDefaultBundles;

	if([prefs objectForKey:SPBundleDeletedDefaultBundlesKey]){
		deletedDefaultBundles = [prefs objectForKey:SPBundleDeletedDefaultBundlesKey];
	}
	else{
		deletedDefaultBundles = @[];
	}

	NSMutableString *infoAboutUpdatedDefaultBundles = [NSMutableString string];
	BOOL doBundleUpdate = ([prefs objectForKey:@"doBundleUpdate"]) ? YES : NO;

	for(NSString* bundlePath in bundlePaths) {
		if([bundlePath length]) {

			SPLog(@"processing installed bundle at path: %@",bundlePath );

			NSError *error = nil;
			NSArray *foundBundles = [fileManager contentsOfDirectoryAtPath:bundlePath error:&error];
			if (foundBundles && foundBundles.count && error == nil) {

				for(NSString* bundle in foundBundles) {
					if([bundle.pathExtension.lowercaseString isEqualToString:SPUserBundleFileExtension.lowercaseString] == NO && [bundle.pathExtension.lowercaseString isEqualToString:SPUserBundleFileExtensionV2.lowercaseString] == NO){

						continue;
					}

					foundInstalledBundles = YES;

					NSString *infoPath = [NSString stringWithFormat:@"%@/%@/%@", bundlePath, bundle, SPBundleFileName];
					NSDictionary *cmdData = nil;
					{
						NSError *readError = nil;

						NSData *pData = [NSData dataWithContentsOfFile:infoPath options:NSUncachedRead error:&readError];

						if(pData && !readError) {
							cmdData = [NSPropertyListSerialization propertyListWithData:pData
																				options:NSPropertyListImmutable
																				 format:NULL
																				  error:&readError];
						}

						if(!cmdData || readError) {
							SPLog(@"“%@” file couldn't be read. (error=%@)", infoPath, readError.localizedDescription);
							[self doOrDoNotBeep:bundle];

							// remove the dodgy bundle
							[self removeBundle:bundle];
							continue;
						}
					}

					if((![cmdData objectForKey:SPBundleFileDisabledKey] || ![[cmdData objectForKey:SPBundleFileDisabledKey] intValue])
						&& [cmdData objectForKey:SPBundleFileNameKey]
						&& [(NSString *)[cmdData objectForKey:SPBundleFileNameKey] length]
						&& [cmdData objectForKey:SPBundleFileScopeKey])
					{

						BOOL defaultBundleWasUpdated = NO;

						if([cmdData objectForKey:SPBundleFileUUIDKey] && [(NSString *)[cmdData objectForKey:SPBundleFileUUIDKey] length]) {

							if(processDefaultBundles) {

								// Skip deleted default Bundles
								BOOL bundleWasDeleted = NO;
								if([deletedDefaultBundles count]) {
									for(NSArray* item in deletedDefaultBundles) {
										if([[item objectAtIndex:0] isEqualToString:[cmdData objectForKey:SPBundleFileUUIDKey]]) {
											bundleWasDeleted = YES;
											break;
										}
									}
								}
								if(bundleWasDeleted) continue;

								// If default Bundle is already installed check for possible update,
								// if so duplicate the modified one by appending (user) and updated it
								if(doBundleUpdate || [installedBundleUUIDs objectForKey:[cmdData objectForKey:SPBundleFileUUIDKey]] == nil) {
									NSString *oldBundlePath = [NSString stringWithFormat:@"%@/%@/%@", [bundlePaths objectAtIndex:0], bundle, SPBundleFileName];
									if([installedBundleUUIDs objectForKey:[cmdData objectForKey:SPBundleFileUUIDKey]] != nil && ![([[installedBundleUUIDs objectForKey:[cmdData objectForKey:SPBundleFileUUIDKey]] objectForKey:@"path"] ?: @"") isEqualToString: @""]) {
										oldBundlePath = [[installedBundleUUIDs objectForKey:[cmdData objectForKey:SPBundleFileUUIDKey]] objectForKey:@"path"];
									}

									if([installedBundleUUIDs objectForKey:[cmdData objectForKey:SPBundleFileUUIDKey]]) {
										NSDictionary *cmdDataOld = nil;
										{
											NSError *readError = nil;

											NSData *pDataOld = [NSData dataWithContentsOfFile:oldBundlePath options:NSUncachedRead error:&readError];

											if(pDataOld && !readError) {
												cmdDataOld = [NSPropertyListSerialization propertyListWithData:pDataOld
																									   options:NSPropertyListImmutable
																										format:NULL
																										 error:&readError];
											}

											if(!cmdDataOld || readError) {
												SPLog(@"“%@” file couldn't be read. (error=%@)", oldBundlePath, readError.localizedDescription);
											}
										}

										NSString *oldBundle = [NSString stringWithFormat:@"%@/%@", [bundlePaths objectAtIndex:0], bundle];
										// Check for modifications
										if(cmdDataOld != nil && [cmdDataOld objectForKey:SPBundleFileDefaultBundleWasModifiedKey]) {

											SPLog(@"default bundle WAS modified, duplicate, change UUID and rename menu item");

											// Duplicate Bundle, change the UUID and rename the menu label
											NSString *duplicatedBundle = [NSString stringWithFormat:@"%@/%@_%ld.%@", [bundlePaths objectAtIndex:0], [bundle substringToIndex:([bundle length] - [SPUserBundleFileExtensionV2 length] - 1)], (long)(random() % 35000), SPUserBundleFileExtensionV2];
											NSError *anError = nil;

											NSMutableString *correctedOldBundle = [[NSMutableString alloc] initWithCapacity:oldBundle.length];
											if([oldBundle hasSuffixWithSuffix:SPUserBundleFileExtensionV2 caseSensitive:YES]){
												[correctedOldBundle setString:[oldBundle dropSuffixWithSuffix:SPUserBundleFileExtensionV2]];
												[correctedOldBundle appendString:SPUserBundleFileExtension];
											}
											if(![fileManager copyItemAtPath:correctedOldBundle toPath:duplicatedBundle error:&anError]) {
												SPLog(@"“%@” file couldn't be copied to update it. (error=%@)", bundle, anError.localizedDescription);
												NSBeep();
												continue;
											}
											NSString *duplicatedBundleCommand = [NSString stringWithFormat:@"%@/%@", duplicatedBundle, SPBundleFileName];
											NSMutableDictionary *dupData = [NSMutableDictionary dictionary];
											{
												NSError *readError = nil;

												NSData *dData = [NSData dataWithContentsOfFile:duplicatedBundleCommand options:NSUncachedRead error:&readError];

												if(dData && !readError) {
													NSDictionary *dDict = [NSPropertyListSerialization propertyListWithData:dData
																													options:NSPropertyListImmutable
																													 format:NULL
																													  error:&readError];

													if(dDict && !readError) {
														[dupData setDictionary:dDict];
													}
												}

												if (![dupData count] || readError) {
													SPLog(@"“%@” file couldn't be read. (error=%@)", duplicatedBundleCommand, readError.localizedDescription);
													NSBeep();
													continue;
												}
											}
											[dupData setObject:[NSString stringWithNewUUID] forKey:SPBundleFileUUIDKey];
											NSString *orgName = [dupData objectForKey:SPBundleFileNameKey];
											[dupData setObject:[NSString stringWithFormat:@"%@ (user)", orgName] forKey:SPBundleFileNameKey];
											[dupData removeObjectForKey:SPBundleFileIsDefaultBundleKey];

											if (@available(macOS 10.13, *)) {
												NSError *err = nil;
												[dupData writeToURL:[NSURL fileURLWithPath:duplicatedBundleCommand] error:&err];
												if(err){
													SPLog(@"Could not delete %@. Error: %@", duplicatedBundleCommand, err.localizedDescription);
												}
											} else {
												[dupData writeToFile:duplicatedBundleCommand atomically:YES];
											}

											error = nil;
											if(![fileManager removeItemAtPath:correctedOldBundle error:&error]) {
												SPLog(@"“%@” removeItemAtPath. (error=%@)", correctedOldBundle, error.localizedDescription);
												[fileManager removeItemAtPath:oldBundlePath error:&error];
											}
											else{
												SPLog(@"removedItemAtPath: %@\n%@\n", correctedOldBundle, oldBundlePath);
											}

											if(error != nil) {
												[NSAlert createWarningAlertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Error while moving “%@” to Trash.", @"error while moving “%@” to trash"), [[installedBundleUUIDs objectForKey:[cmdDataOld objectForKey:SPBundleFileUUIDKey]] objectForKey:@"path"]] message:[error localizedDescription] callback:nil];
												continue;
											}
											[infoAboutUpdatedDefaultBundles appendFormat:@"• %@\n", orgName];
										} else {
											SPLog(@"default bundle not modified, delete and ....");
											// If no modifications are done simply remove the old one
											if(![fileManager removeItemAtPath:oldBundle error:nil] && ![fileManager removeItemAtPath:oldBundlePath.stringByDeletingLastPathComponent error:nil]) {
												SPLog(@"Couldn't remove “%@” to update it", bundle);
												NSBeep();
												continue;
											}
											else{
												SPLog(@"removedItemAtPath: %@", oldBundle);
											}

										}
									}

									SPLog(@"copy bundle from app bundle");

									BOOL isDir;
									NSString *newInfoPath = [NSString stringWithFormat:@"%@/%@/%@", [bundlePaths objectAtIndex:0], bundle, SPBundleFileName];
									NSString *orgPath = [NSString stringWithFormat:@"%@/%@", [bundlePaths objectAtIndex:1], bundle];
									NSString *newPath = [NSString stringWithFormat:@"%@/%@", [bundlePaths objectAtIndex:0], bundle];
									if([fileManager fileExistsAtPath:newPath isDirectory:&isDir] && isDir)
										newPath = [NSString stringWithFormat:@"%@_%ld", newPath, (long)(random() % 35000)];
									error = nil;
									[fileManager copyItemAtPath:orgPath toPath:newPath error:&error];
									if(error != nil) {
										NSBeep();
										SPLog(@"Default Bundle “%@” couldn't be copied to '%@'", bundle, newInfoPath);
										continue;
									}
									infoPath = [NSString stringWithString:newInfoPath];

									defaultBundleWasUpdated = YES;

								}

								if(!defaultBundleWasUpdated) continue;

							}

							[installedBundleUUIDs setObject:[NSDictionary dictionaryWithObjectsAndKeys:
									[NSString stringWithFormat:@"%@ (%@)", bundle, [cmdData objectForKey:SPBundleFileNameKey]], @"name",
									infoPath, @"path", nil] forKey:[cmdData objectForKey:SPBundleFileUUIDKey]];

						} else {
							SPLog(@"No UUID for %@", bundle);
							NSBeep();
							continue;
						}

						// Register Bundle
						NSString *scope = [cmdData objectForKey:SPBundleFileScopeKey];

						// Register scope/category menu structure
						if(![bundleUsedScopes containsObject:scope]) {
							[bundleUsedScopes addObject:scope];
							[bundleItems setObject:[NSMutableArray array] forKey:scope];
							[bundleCategories setObject:[NSMutableArray array] forKey:scope];
							[bundleKeyEquivalents setObject:[NSMutableDictionary dictionary] forKey:scope];
						}
						if([cmdData objectForKey:SPBundleFileCategoryKey] && [(NSString *)[cmdData objectForKey:SPBundleFileCategoryKey] length] && ![[bundleCategories objectForKey:scope] containsObject:[cmdData objectForKey:SPBundleFileCategoryKey]])
							[[bundleCategories objectForKey:scope] addObject:[cmdData objectForKey:SPBundleFileCategoryKey]];

						NSMutableDictionary *aDict = [NSMutableDictionary dictionary];
						[aDict setObject:[cmdData objectForKey:SPBundleFileNameKey] forKey:SPBundleInternLabelKey];
						[aDict setObject:infoPath forKey:SPBundleInternPathToFileKey];

						// Register trigger
						if([cmdData objectForKey:SPBundleFileTriggerKey]) {
							if(![bundleTriggers objectForKey:[cmdData objectForKey:SPBundleFileTriggerKey]])
								[bundleTriggers setObject:[NSMutableArray array] forKey:[cmdData objectForKey:SPBundleFileTriggerKey]];
							[[bundleTriggers objectForKey:[cmdData objectForKey:SPBundleFileTriggerKey]] addObject:
								[NSString stringWithFormat:@"%@|%@|%@",
									infoPath,
									[cmdData objectForKey:SPBundleFileScopeKey],
									([[cmdData objectForKey:SPBundleFileOutputActionKey] isEqualToString:SPBundleOutputActionShowAsHTML])?[cmdData objectForKey:SPBundleFileUUIDKey]:@""]];
						}

						// Register key equivalent
						if(cmdData != nil && [cmdData objectForKey:SPBundleFileKeyEquivalentKey] && [(NSString *)[cmdData objectForKey:SPBundleFileKeyEquivalentKey] length]) {

							NSString *theKey = [cmdData objectForKey:SPBundleFileKeyEquivalentKey];
							NSString *theChar = [theKey substringFromIndex:[theKey length]-1];
							NSString *theMods = [theKey substringToIndex:[theKey length]-1];
							NSEventModifierFlags mask = 0;
							if([theMods rangeOfString:@"^"].length) mask = mask | NSEventModifierFlagControl;
							if([theMods rangeOfString:@"@"].length) mask = mask | NSEventModifierFlagCommand;
							if([theMods rangeOfString:@"~"].length) mask = mask | NSEventModifierFlagOption;
							if([theMods rangeOfString:@"$"].length) mask = mask | NSEventModifierFlagShift;

							NSString *theUUID = [cmdData objectForKey:SPBundleFileUUIDKey] ?: @"";
							NSString *theTooltip = [cmdData objectForKey:SPBundleFileTooltipKey] ?: @"";
							NSString *theFilename = [cmdData objectForKey:SPBundleFileNameKey] ?: @"";

							if(![[bundleKeyEquivalents objectForKey:scope] objectForKey:[cmdData objectForKey:SPBundleFileKeyEquivalentKey]]) {
								[[bundleKeyEquivalents objectForKey:scope] setObject:[NSMutableArray array] forKey:[cmdData objectForKey:SPBundleFileKeyEquivalentKey]];
							}
							NSMutableArray *bundleKeysForKey = [[bundleKeyEquivalents objectForKey:scope] objectForKey:[cmdData objectForKey:SPBundleFileKeyEquivalentKey]] ?: [NSMutableArray array];
							for (NSDictionary *keyInfo in bundleKeysForKey) {
								if([keyInfo objectForKey:@"uuid"] == [cmdData objectForKey:SPBundleFileUUIDKey]) {
									[bundleKeysForKey removeObject:keyInfo];
								}
							}
							NSDictionary *newBundleKey = [NSDictionary dictionaryWithObjectsAndKeys:
														  infoPath ?: @"", SPBundleInternPathToFileKey,
														  theFilename, SPBundleFileTitleKey,
														  theTooltip, SPBundleFileTooltipKey,
														  theUUID, SPBundleFileUUIDKey,
														  nil];
							[bundleKeysForKey addObject: newBundleKey];
							[[bundleKeyEquivalents objectForKey:scope] setObject:bundleKeysForKey forKey:[cmdData objectForKey:SPBundleFileKeyEquivalentKey]];

							[aDict setObject:[NSArray arrayWithObjects:theChar, [NSNumber numberWithInteger:mask], nil] forKey:SPBundleInternKeyEquivalentKey];
						}


						if([cmdData objectForKey:SPBundleFileTooltipKey] && [(NSString *)[cmdData objectForKey:SPBundleFileTooltipKey] length])
							[aDict setObject:[cmdData objectForKey:SPBundleFileTooltipKey] forKey:SPBundleFileTooltipKey];

						if([cmdData objectForKey:SPBundleFileCategoryKey] && [(NSString *)[cmdData objectForKey:SPBundleFileCategoryKey] length])
							[aDict setObject:[cmdData objectForKey:SPBundleFileCategoryKey] forKey:SPBundleFileCategoryKey];

						if([cmdData objectForKey:SPBundleFileKeyEquivalentKey] && [(NSString *)[cmdData objectForKey:SPBundleFileKeyEquivalentKey] length])
							[aDict setObject:[cmdData objectForKey:SPBundleFileKeyEquivalentKey] forKey:@"key"];
						// add UUID so we can check for it
						if([cmdData objectForKey:SPBundleFileUUIDKey] && [(NSString *)[cmdData objectForKey:SPBundleFileUUIDKey] length])
							[aDict setObject:[cmdData objectForKey:SPBundleFileUUIDKey] forKey:SPBundleFileUUIDKey];

						BOOL __block alreadyAdded = NO;

						// check UUID, only add if it's different
						[bundleItems enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSArray *obj, BOOL *stop1) {
							[obj enumerateObjectsUsingBlock:^(id obj2, NSUInteger idx, BOOL *stop){
								if([obj2[SPBundleFileUUIDKey] isEqualToString:[aDict objectForKey:SPBundleFileUUIDKey]]){ // what if these are null? nothing happens...
									SPLog(@"Already added this UUID, name = %@",[cmdData objectForKey:SPBundleFileNameKey] );
									alreadyAdded = YES;
								}
							}];
						}];

						if(alreadyAdded == NO){
							[[bundleItems objectForKey:scope] addObject:aDict];
						}
					}
				}

				// Sort items for menus
				NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:SPBundleInternLabelKey ascending:YES];
				for(NSString* scope in [bundleItems allKeys]) {
					[[bundleItems objectForKey:scope] sortUsingDescriptors:@[sortDescriptor]];
					[[bundleCategories objectForKey:scope] sortUsingSelector:@selector(compare:)];
				}
			}
		}
		processDefaultBundles = YES;
	}
	// JCS: Not sure where to do this
	//
	[self renameLegacyBundles];

	if(doBundleUpdate) {
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"doBundleUpdate"];
	}

	// Inform user about default Bundle updates which were modified by the user and re-run Reload Bundles
	if([infoAboutUpdatedDefaultBundles length]) {
		[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Default Bundles Update", @"default bundles update") message:[NSString stringWithFormat:NSLocalizedString(@"The following default Bundles were updated:\n%@\nYour modifications were stored as “(user)”.", @"the following default bundles were updated:\n%@\nyour modifications were stored as “(user)”."), infoAboutUpdatedDefaultBundles] callback:nil];
		[self reloadBundles:nil];
		return;
	}


	[SPAppDelegate rebuildMenus];

	
}

/**
 * Action for any Bundle menu menuItem; show menuItem dialog if user pressed key equivalent
 * which is assigned to more than one bundle command inside the same scope
 */
- (IBAction)bundleCommandDispatcher:(id)sender
{

	NSEvent *event = [NSApp currentEvent];
	BOOL checkForKeyEquivalents = ([event type] == NSEventTypeKeyDown) ? YES : NO;

	id firstResponder = [[NSApp keyWindow] firstResponder];

	NSString *scope = [[sender representedObject] objectForKey:@"scope"];
	NSString *keyEqKey = nil;
	NSMutableArray *assignedKeyEquivalents = nil;

	if(checkForKeyEquivalents) {

		// Get the current scope in order to find out which command with a specific key
		// should run
		if([firstResponder respondsToSelector:@selector(executeBundleItemForInputField:)])
			scope = SPBundleScopeInputField;
		else if([firstResponder respondsToSelector:@selector(executeBundleItemForDataTable:)])
			scope = SPBundleScopeDataTable;
		else
			scope = SPBundleScopeGeneral;

		keyEqKey = [[sender representedObject] objectForKey:@"key"];

		assignedKeyEquivalents = [NSMutableArray array];
		[assignedKeyEquivalents setArray:[[bundleKeyEquivalents objectForKey:scope] objectForKey:keyEqKey]];
		// Fall back to general scope and check for key
		if(![assignedKeyEquivalents count]) {
			scope = SPBundleScopeGeneral;
			[assignedKeyEquivalents setArray:[[bundleKeyEquivalents objectForKey:scope] objectForKey:keyEqKey]];
		}
		// Nothing found thus bail
		if(![assignedKeyEquivalents count]) {
			NSBeep();
			return;
		}

		// Sort if more than one found
		if([assignedKeyEquivalents count] > 1) {
			NSSortDescriptor *aSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"title" ascending:YES selector:@selector(caseInsensitiveCompare:)];
			NSArray *sorted = [assignedKeyEquivalents sortedArrayUsingDescriptors:@[aSortDescriptor]];
			[assignedKeyEquivalents setArray:sorted];
		}
	}

	if([scope isEqualToString:SPBundleScopeInputField] && [firstResponder respondsToSelector:@selector(executeBundleItemForInputField:)]) {
		if(checkForKeyEquivalents && [assignedKeyEquivalents count]) {
			NSInteger idx = 0;
			if([assignedKeyEquivalents count] > 1)
				idx = [SPChooseMenuItemDialog withItems:assignedKeyEquivalents atPosition:[NSEvent mouseLocation]];

			if(idx > -1) {
				NSDictionary *eq = [assignedKeyEquivalents objectAtIndex:idx];
				if(eq && [eq count]) {
					NSMenuItem *aMenuItem = [[NSMenuItem alloc] init];
					[aMenuItem setTag:0];
					[aMenuItem setToolTip:[eq objectForKey:@"path"]];
					[(SPTextView *)firstResponder executeBundleItemForInputField:aMenuItem];
				}
			}
		} else {
			[firstResponder executeBundleItemForInputField:sender];
		}
	}
	else if([scope isEqualToString:SPBundleScopeDataTable] && [firstResponder respondsToSelector:@selector(executeBundleItemForDataTable:)]) {
		if(checkForKeyEquivalents && [assignedKeyEquivalents count]) {
			NSInteger idx = 0;
			if([assignedKeyEquivalents count] > 1)
				idx = [SPChooseMenuItemDialog withItems:assignedKeyEquivalents atPosition:[NSEvent mouseLocation]];

			if(idx > -1) {
				NSDictionary *eq = [assignedKeyEquivalents objectAtIndex:idx];
				if(eq && [eq count]) {
					NSMenuItem *aMenuItem = [[NSMenuItem alloc] init];
					[aMenuItem setTag:0];
					[aMenuItem setToolTip:[eq objectForKey:@"path"]];
					[(SPCopyTable *)firstResponder executeBundleItemForDataTable:aMenuItem];
				}
			}
		} else {
			[firstResponder executeBundleItemForDataTable:sender];
		}
	}
	else if([scope isEqualToString:SPBundleScopeGeneral]) {
		if(checkForKeyEquivalents && [assignedKeyEquivalents count]) {
			NSInteger idx = 0;
			if([assignedKeyEquivalents count] > 1)
				idx = [SPChooseMenuItemDialog withItems:assignedKeyEquivalents atPosition:[NSEvent mouseLocation]];

			if(idx > -1) {
				NSDictionary *eq = [assignedKeyEquivalents objectAtIndex:idx];
				if(eq && [eq count]) {
					NSMenuItem *aMenuItem = [[NSMenuItem alloc] init];
					[aMenuItem setTag:0];
					[aMenuItem setToolTip:[eq objectForKey:@"path"]];
					[self executeBundleItemForApp:aMenuItem];
				}
			}
		} else {
			[self executeBundleItemForApp:sender];
		}
	} else {
		NSBeep();
	}
}

- (IBAction)executeBundleItemForApp:(id)sender
{

	SPMainLoopAsync(^{
		NSInteger idx = [sender tag] - 1000000;
		NSString *infoPath = nil;
		NSArray *scopeBundleItems = [self bundleItemsForScope:SPBundleScopeGeneral];
		if(idx >=0 && idx < (NSInteger)[scopeBundleItems count]) {
			infoPath = [[scopeBundleItems objectAtIndex:idx] objectForKey:SPBundleInternPathToFileKey];
		} else {
			if([sender tag] == 0 && [[sender toolTip] length]) {
				infoPath = [sender toolTip];
			}
		}

		if(!infoPath) {
			SPLog(@"No path to Bundle command passed");
			NSBeep();
			return;
		}

		NSDictionary *cmdData = nil;
		{
			NSError *error = nil;

			NSData *pData = [NSData dataWithContentsOfFile:infoPath options:NSUncachedRead error:&error];

			if(pData && !error) {
				cmdData = [NSPropertyListSerialization propertyListWithData:pData
																	options:NSPropertyListImmutable
																	 format:NULL
																	  error:&error];
			}

			if(!cmdData || error) {
				SPLog(@"“%@” file couldn't be read. (error=%@)", infoPath, error);
				NSBeep();
				return;
			}
		}

		if([cmdData objectForKey:SPBundleFileCommandKey] && [(NSString *)[cmdData objectForKey:SPBundleFileCommandKey] length]) {

			NSString *cmd = [cmdData objectForKey:SPBundleFileCommandKey];
			NSError *err = nil;
			NSString *uuid = [NSString stringWithNewUUID];
			NSString *bundleInputFilePath = [NSString stringWithFormat:@"%@_%@", [SPBundleTaskInputFilePath stringByExpandingTildeInPath], uuid];

			[self->fileManager removeItemAtPath:bundleInputFilePath error:nil];

			NSMutableDictionary *env = [NSMutableDictionary dictionary];
			[env setObject:[infoPath stringByDeletingLastPathComponent] forKey:SPBundleShellVariableBundlePath];
			[env setObject:bundleInputFilePath forKey:SPBundleShellVariableInputFilePath];
			[env setObject:SPBundleScopeGeneral forKey:SPBundleShellVariableBundleScope];
			[env setObject:[SPURLSchemeQueryResultPathHeader stringByExpandingTildeInPath] forKey:SPBundleShellVariableQueryResultFile];
			[env setObject:[SPURLSchemeQueryResultStatusPathHeader stringByExpandingTildeInPath] forKey:SPBundleShellVariableQueryResultStatusFile];

			NSString *input = @"";
			NSError *inputFileError = nil;
			if(input == nil) input = @"";
			[input writeToFile:bundleInputFilePath
					atomically:YES
					  encoding:NSUTF8StringEncoding
						 error:&inputFileError];

			if(inputFileError != nil) {
				NSString *errorMessage  = [inputFileError localizedDescription];
				[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Bundle Error", @"bundle error") message:[NSString stringWithFormat:@"%@ “%@”:\n%@", NSLocalizedString(@"Error for", @"error for message"), [cmdData objectForKey:@"name"], errorMessage] callback:nil];
				return;
			}

			NSString *output = [SPBundleCommandRunner runBashCommand:cmd
													 withEnvironment:env
											  atCurrentDirectoryPath:nil
													  callerInstance:self
														 contextInfo:[NSDictionary dictionaryWithObjectsAndKeys:
																	  ([cmdData objectForKey:SPBundleFileNameKey])?:@"-", @"name",
																	  NSLocalizedString(@"General", @"general menu item label"), @"scope",
																	  uuid, SPBundleFileInternalexecutionUUID, nil]
															   error:&err];

			[self->fileManager removeItemAtPath:bundleInputFilePath error:nil];

			NSString *action = SPBundleOutputActionNone;
			if([cmdData objectForKey:SPBundleFileOutputActionKey] && [(NSString *)[cmdData objectForKey:SPBundleFileOutputActionKey] length])
				action = [[cmdData objectForKey:SPBundleFileOutputActionKey] lowercaseString];

			// Redirect due exit code
			if(err != nil) {
				if([err code] == SPBundleRedirectActionNone) {
					action = SPBundleOutputActionNone;
					err = nil;
				}
				else if([err code] == SPBundleRedirectActionReplaceSection) {
					action = SPBundleOutputActionReplaceSelection;
					err = nil;
				}
				else if([err code] == SPBundleRedirectActionReplaceContent) {
					action = SPBundleOutputActionReplaceContent;
					err = nil;
				}
				else if([err code] == SPBundleRedirectActionInsertAsText) {
					action = SPBundleOutputActionInsertAsText;
					err = nil;
				}
				else if([err code] == SPBundleRedirectActionInsertAsSnippet) {
					action = SPBundleOutputActionInsertAsSnippet;
					err = nil;
				}
				else if([err code] == SPBundleRedirectActionShowAsHTML) {
					action = SPBundleOutputActionShowAsHTML;
					err = nil;
				}
				else if([err code] == SPBundleRedirectActionShowAsTextTooltip) {
					action = SPBundleOutputActionShowAsTextTooltip;
					err = nil;
				}
				else if([err code] == SPBundleRedirectActionShowAsHTMLTooltip) {
					action = SPBundleOutputActionShowAsHTMLTooltip;
					err = nil;
				}
			}

			if(err == nil && output) {
				if(![action isEqualToString:SPBundleOutputActionNone]) {
					NSPoint pos = [NSEvent mouseLocation];
					pos.y -= 16;

					if([action isEqualToString:SPBundleOutputActionShowAsTextTooltip]) {
						[SPTooltip showWithObject:output atLocation:pos];
					}

					else if([action isEqualToString:SPBundleOutputActionShowAsHTMLTooltip]) {
						[SPTooltip showWithObject:output atLocation:pos ofType:@"html"];
					}

					else if([action isEqualToString:SPBundleOutputActionShowAsHTML]) {
						BOOL correspondingWindowFound = NO;
						for(id win in [NSApp windows]) {
							if([[win delegate] isKindOfClass:[SPBundleHTMLOutputController class]]) {
								if([[[win delegate] windowUUID] isEqualToString:[cmdData objectForKey:SPBundleFileUUIDKey]]) {
									correspondingWindowFound = YES;
									[[win delegate] setDocUUID:uuid];
									[[win delegate] displayHTMLContent:output withOptions:nil];
									break;
								}
							}
						}
						if(!correspondingWindowFound) {
							SPBundleHTMLOutputController *c = [[SPBundleHTMLOutputController alloc] init];
							[c setWindowUUID:[cmdData objectForKey:SPBundleFileUUIDKey]];
							[c setDocUUID:uuid];
							[c displayHTMLContent:output withOptions:nil];
							[self addHTMLOutputController:c];
						}
					}
				}
			} else if ([err code] != 9) { // Suppress an error message if command was killed
				NSString *errorMessage  = [err localizedDescription];
				[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"BASH Error", @"bash error") message:[NSString stringWithFormat:@"%@ “%@”:\n%@", NSLocalizedString(@"Error for", @"error for message"), [cmdData objectForKey:@"name"], errorMessage] callback:nil];
			}
		}
	});
}

- (void)openUserBundleAtPath:(NSString *)filePath
{

	NSString *bundlePath = [fileManager applicationSupportDirectoryForSubDirectory:SPBundleSupportFolder error:nil];

	if (!bundlePath) return;

	if (![fileManager fileExistsAtPath:bundlePath isDirectory:nil]) {
		if (![fileManager createDirectoryAtPath:bundlePath withIntermediateDirectories:YES attributes:nil error:nil]) {
			NSBeep();
			SPLog(@"Couldn't create folder “%@”", bundlePath);
			return;
		}
	}

	NSString *newPath = [NSString stringWithFormat:@"%@/%@", bundlePath, [filePath lastPathComponent]];

	NSDictionary *cmdData = nil;
	{
		NSError *error = nil;

		NSString *infoPath = [NSString stringWithFormat:@"%@/%@", filePath, SPBundleFileName];
		NSData *pData = [NSData dataWithContentsOfFile:infoPath options:NSUncachedRead error:&error];

		if(pData && !error) {
			cmdData = [NSPropertyListSerialization propertyListWithData:pData
																 options:NSPropertyListImmutable
																  format:NULL
																   error:&error];
		}

		if (!cmdData || error) {
			SPLog(@"“%@/%@” file couldn't be read. (error=%@)", filePath, SPBundleFileName, error.localizedDescription);
			[self doOrDoNotBeep:filePath];
			return;
		}
	}

	SPLog(@"cmdData %@", cmdData);


	// first lets check if it's a legacy bundle
	// don't need this, at the end of this func we call reload bundles
	// which will migrate legacy bundles


	// check for legacy strings
	NSMutableDictionary *filesContainingLegacyString = [self findLegacyStrings:filePath];

	BOOL __block retCode = YES;

	if(filesContainingLegacyString.count > 0){

		SPLog(@"filesContainingLegacyString: %@", filesContainingLegacyString.allKeys);

		NSArray *filePathArr = [filesContainingLegacyString.allKeys valueForKey:@"description"];

		NSMutableArray *affectedFiles = [NSMutableArray array];

		for(NSString *filePath2 in filePathArr){
			[affectedFiles safeAddObject:filePath2.lastPathComponent];
		}

		NSString *filesString = [affectedFiles componentsJoinedByString:@"\n"];

		[NSAlert createDefaultAlertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"‘%@’ Bundle contains legacy components", @"Bundle contains legacy components"), filePath.lastPathComponent]
									 message:[NSString stringWithFormat:NSLocalizedString(@"In these files:\n\n%@\n\nDo you still want to install the bundle and have Sequel Ace replace the legacy strings?", @"Do you want to install the bundle?"), filesString]
						  primaryButtonTitle:NSLocalizedString(@"Install", @"Install")
						primaryButtonHandler:^{
			SPLog(@"Continue, install");
			// filesContainingLegacyString:
			// key = file URL
			// val = dict - key:@file = bundle filename
			//				key:@newstr = string for file with legacy str replaced.

			[self replaceLegacyString:filesContainingLegacyString];

		} 				cancelButtonHandler:^{
			SPLog(@"ABORT install");
			retCode = NO;
		}];
	}

	if(retCode == NO){
		SPLog(@"Cancel pressed, returning without installing");
		return;
	}

	// Check for installed UUIDs
	if (![cmdData objectForKey:SPBundleFileUUIDKey]) {
		[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error while installing Bundle", @"") message:[NSString stringWithFormat:NSLocalizedString(@"The Bundle ‘%@’ has no UUID which is necessary to identify installed Bundles.", @"Open Files : Bundle: UUID : UUID-Attribute is missing in bundle's command.plist file"), [filePath lastPathComponent]] callback:nil];
		return;
	}

	// Reload Bundles if Sequel Ace didn't run
	if (![installedBundleUUIDs count]) {
		[self reloadBundles:self];
	}

	if ([[installedBundleUUIDs allKeys] containsObject:[cmdData objectForKey:SPBundleFileUUIDKey]]) {
		[NSAlert createDefaultAlertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Installing Bundle", @"Open Files : Bundle : Already-Installed : 'Update Bundle' question dialog title")]
									 message:[NSString stringWithFormat:NSLocalizedString(@"A Bundle ‘%@’ is already installed. Do you want to update it?", @"Open Files : Bundle : Already-Installed : 'Update Bundle' question dialog message"), [[installedBundleUUIDs objectForKey:[cmdData objectForKey:SPBundleFileUUIDKey]] objectForKey:@"name"]]
						  primaryButtonTitle:NSLocalizedString(@"Update", @"Open Files : Bundle : Already-Installed : Update button") primaryButtonHandler:^{
			NSError *error = nil;
			NSString *removePath = [[[self->installedBundleUUIDs objectForKey:[cmdData objectForKey:SPBundleFileUUIDKey]] objectForKey:@"path"] substringToIndex:([(NSString *)[[self->installedBundleUUIDs objectForKey:[cmdData objectForKey:SPBundleFileUUIDKey]] objectForKey:@"path"] length]-[SPBundleFileName length]-1)];
			[self->fileManager removeItemAtPath:removePath error:&error];

			if (error != nil) {
				[NSAlert createWarningAlertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Error while moving “%@” to Trash.", @"Open Files : Bundle : Already-Installed : Delete-Old-Error : Could not delete old bundle before installing new version."), removePath] message:[error localizedDescription] callback:nil];
				return;
			}
		} cancelButtonHandler:^{
			return;
		}];
	}

	if (![fileManager fileExistsAtPath:newPath isDirectory:nil]) {
		if (![fileManager moveItemAtPath:filePath toPath:newPath error:nil]) {
			NSBeep();
			SPLog(@"Couldn't move “%@” to “%@”", filePath, newPath);
			return;
		}

		// Update Bundle Editor if it was already initialized
		for (NSWindow *win in [NSApp windows])
		{
			if ([[win delegate] class] == [SPBundleEditorController class]) {
				[((SPBundleEditorController *)[win delegate]) reloadBundles:nil];
				break;
			}
		}

		// Update Bundle's menu
		[self reloadBundles:self];

	}
	else {
		[NSAlert createWarningAlertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Error while installing Bundle", @"Open Files : Bundle : Install-Error : error dialog title")] message:[NSString stringWithFormat:NSLocalizedString(@"The Bundle ‘%@’ already exists.", @"Open Files : Bundle : Install-Error : Destination path already exists error dialog message"), [filePath lastPathComponent]] callback:nil];
	}
}

// dont think this is called
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	return YES;
}


- (NSArray *)bundleCategoriesForScope:(NSString*)scope
{
	return [bundleCategories objectForKey:scope];
}

- (NSArray *)bundleCommandsForTrigger:(NSString*)trigger
{
	return [bundleTriggers objectForKey:trigger];
}

- (NSArray *)bundleItemsForScope:(NSString*)scope
{
	return [bundleItems objectForKey:scope];
}

- (NSDictionary *)bundleKeyEquivalentsForScope:(NSString*)scope
{
	return [bundleKeyEquivalents objectForKey:scope];
}

- (void)addHTMLOutputController:(id)controller
{
	[bundleHTMLOutputController addObject:controller];
}

- (void)removeHTMLOutputController:(id)controller
{
	[bundleHTMLOutputController removeObject:controller];
}

@end

