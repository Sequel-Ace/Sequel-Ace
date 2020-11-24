//
//  SPBundleFunctions.h
//  Sequel Ace
//
//  Created by James on 25/11/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.

#import "SPBundleFunctions.h"
#import <ShortcutRecorder/ShortcutRecorder.h>
#import "SPBundleEditorController.h"


BOOL SPMigateBundleToNewFormat(NSDictionary * cmdData, NSString *bundleFilePath)
{

	if(!bundleFilePath.length){
		SPLog(@"bundleFilePath was invalid");

		return NO;
	}
	if(!cmdData.count){
		SPLog(@"cmdData was empty");
		return NO;
	}

	if(![bundleFilePath.pathExtension.lowercaseString isEqualToString:SPUserBundleFileExtension.lowercaseString]){
		SPLog(@"Need path to bunlde file. e.g. ~/Library/Containers/com.sequel-ace.sequel-ace/Data/Library/Application Support/Sequel Ace/Bundles/CopyasCSV.spBundle");
		return NO;
	}

	if([cmdData objectForKey:SPBundleNewShortcutKey]){
		SPLog(@"Already migrated: %@", (bundleFilePath.lastPathComponent).stringByDeletingPathExtension);
		return NO;
	}

	if([cmdData objectForKey:SPBundleFileIsDefaultBundleKey]){
		SPLog(@"It's a default bundle with no shortcut: %@", (bundleFilePath.lastPathComponent).stringByDeletingPathExtension);
		return NO;
	}

	NSFileManager *fileManager = [NSFileManager defaultManager];

	if ([fileManager fileExistsAtPath:bundleFilePath isDirectory:nil]) {
		SPLog(@"fileExistsAtPath = YES: %@",bundleFilePath);
	}
	else{
		SPLog(@"fileExistsAtPath = NO: %@",bundleFilePath);
		return NO;
	}

	// check for other files
	BOOL hasDirPath = NO;
	NSMutableArray *dirsToCreate = [NSMutableArray array];
	NSMutableArray *filesToCreate = [NSMutableArray array];

	NSArray *prefetchedProperties = @[ NSURLIsRegularFileKey, NSURLIsDirectoryKey ];
	NSURL *directoryURL = [NSURL fileURLWithPath:bundleFilePath];

	NSDirectoryEnumerator *enumerator = [fileManager
				   enumeratorAtURL:directoryURL
		includingPropertiesForKeys:prefetchedProperties
						   options:NSDirectoryEnumerationSkipsHiddenFiles
					  errorHandler:^BOOL(NSURL *_Nonnull url, NSError *_Nonnull error) {
						return YES;
					  }];


	for (NSURL *fileURL in enumerator) {
		if(![fileURL.absoluteString hasSuffix:@"plist"]){
			SPLog(@"JIMMY found In Bundles: %@",fileURL.absoluteString);
			if(fileURL.hasDirectoryPath){
				hasDirPath = YES;
				[dirsToCreate addObject:fileURL];
			}
			else {

				NSNumber *isRegularFile;
				[fileURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
				if (isRegularFile.boolValue) {
					[filesToCreate addObject:fileURL];
				}
			}
		}
	}

	SPLog(@"Migrating: %@",bundleFilePath);

	BOOL ret = NO;

	SPBundleEditorController *bundleEditorController = [[SPBundleEditorController alloc] init];

	//CopyasCSV.spBundle will be written to CopyasCSV.2.spBundle

	NSString *filename = (bundleFilePath.lastPathComponent).stringByDeletingPathExtension;
	NSString *path = (bundleFilePath.stringByDeletingPathExtension).stringByDeletingLastPathComponent;

	NSString *newPath = [NSString stringWithFormat:@"%@/%@.2.%@", path, filename, SPUserBundleFileExtension];

	SPLog(@"newPath: %@",newPath);

	if([cmdData objectForKey:SPBundleFileInternalKeyEquivalentKey]){

		SPLog(@"JIMMY got: %@", SPBundleFileInternalKeyEquivalentKey);

		NSDictionary *internalKey = [cmdData objectForKey:SPBundleFileInternalKeyEquivalentKey];
		SPLog(@"internalKey %@", internalKey);
		SPLog(@"SPBundleFileNameKey %@", [cmdData objectForKey:SPBundleFileNameKey]);

		SRShortcut *newShortcut = [SRShortcut shortcutWithDictionary:internalKey];

		if(newShortcut != nil){

			SPLog(@"newShortcut %@", newShortcut.dictionaryRepresentation);

			NSMutableDictionary *cmdDataMut = [NSMutableDictionary dictionaryWithDictionary:cmdData];

			NSData *tmp = [NSKeyedArchiver archivedDataWithRootObject:newShortcut];

			[cmdDataMut setObject:tmp forKey:SPBundleNewShortcutKey];

			if(![bundleEditorController saveBundle:cmdDataMut atPath:newPath]){
				SPLog(@"save failed for %@", newPath);
			}
			else{
				SPLog(@"save suceeded for %@", newPath);
				ret = YES;
			}
		}
		else{
			SPLog(@"shortcut is nil for : %@", SPBundleFileInternalKeyEquivalentKey);
		}
	}
	else if ([cmdData objectForKey:SPBundleInternKeyEquivalentKey]){
		SPLog(@"JIMMY got: %@", SPBundleInternKeyEquivalentKey);

		NSString *keyEq = [cmdData objectForKey:SPBundleInternKeyEquivalentKey];

		if(keyEq.length > 0){

			SRShortcut *newShortcut = [SRKeyBindingTransformer.sharedTransformer transformedValue:keyEq];

			SPLog(@"newShortcut2 %@", newShortcut);

			NSMutableDictionary *cmdDataMut = [NSMutableDictionary dictionaryWithDictionary:cmdData];

			NSData *tmp = [NSKeyedArchiver archivedDataWithRootObject:newShortcut];

			[cmdDataMut setObject:tmp forKey:SPBundleNewShortcutKey];

			if(![bundleEditorController saveBundle:cmdDataMut atPath:newPath]){
				SPLog(@"save failed for %@", newPath);
			}
			else{
				SPLog(@"save suceeded for %@", newPath);
				ret = YES;
			}
		}
		else{
			SPLog(@"No value for: %@ for: %@", SPBundleInternKeyEquivalentKey, [cmdData objectForKey:SPBundleFileNameKey]);
		}
	}

	// do we need to copy files?
	if(dirsToCreate.count > 0){
		// create dirs in new bundle
		for (NSURL *fileURL in dirsToCreate) {

			NSMutableString *filePathMut = [fileURL.path mutableCopy];

			[filePathMut replaceOccurrencesOfString:@".spBundle" withString:@".2.spBundle" options:NSBackwardsSearch range: NSMakeRange(0, filePathMut.length)];

			SPLog(@"creating %@", filePathMut);

			BOOL isDir = YES;

			if(![fileManager fileExistsAtPath:filePathMut isDirectory:&isDir]) {
				SPLog(@"dir does not exist %@", filePathMut);
				if([fileManager createDirectoryAtPath:filePathMut withIntermediateDirectories:YES attributes:nil error:nil]){
					SPLog(@"created %@", filePathMut);
				}
				else{
					SPLog(@"ERROR creation failed for: %@", filePathMut);
				}
			}
			else{
				SPLog(@"dir already exists %@", filePathMut);

			}
		}
	}

	if(filesToCreate.count > 0){
		// copy files to bundle
		for (NSURL *fileURL in filesToCreate) {
			NSMutableString *destPath = [fileURL.path mutableCopy];
			[destPath replaceOccurrencesOfString:@".spBundle" withString:@".2.spBundle" options:NSBackwardsSearch range: NSMakeRange(0, destPath.length)];

			SPLog(@"copying %@ to %@", fileURL.path, destPath);

			if([fileManager copyItemAtPath:fileURL.path toPath:destPath error:nil]){
				SPLog(@"copy suceeded");
			}
			else{
				SPLog(@"ERROR copy failed for: %@", destPath);
			}
		}
	}

	return ret;
}

