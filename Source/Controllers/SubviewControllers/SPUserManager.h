//
//  SPUserManager.h
//  sequel-pro
//
//  Created by Mark Townsend on Jan 1, 2009.
//  Copyright (c) 2009 Mark Townsend. All rights reserved.
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

@class SPServerSupport;
@class SPMySQLConnection;
@class SPSplitView;
@class SPDatabaseDocument;
@class SPUserMO;
@class SPPrivilegesMO;

static inline NSString *SPUserManagerPrivilegeOperationErrorMessageForServerError(NSString *serverError, NSArray *privileges, NSString *operation, NSString *database, NSString *user, NSString *host, NSString *statement, BOOL isMariaDB, BOOL supportsShowCreateRoutine)
{
	NSString *operationDescription = [operation length] ? operation : NSLocalizedString(@"change", @"fallback privilege operation description");
	NSString *scopeDescription = [database length] ? [NSString stringWithFormat:NSLocalizedString(@"database \"%@\"", @"privilege operation database scope"), database] : NSLocalizedString(@"all databases", @"privilege operation all databases scope");
	NSString *accountDescription = [NSString stringWithFormat:@"%@%@", [user length] ? user : @"", [host length] ? [NSString stringWithFormat:@"@%@", host] : @""];
	if (![accountDescription length]) {
		accountDescription = NSLocalizedString(@"the selected account", @"fallback privilege operation account description");
	}

	NSString *privilegesDescription = nil;
	if ([privileges count]) {
		privilegesDescription = [[privileges componentsJoinedByString:@", "] uppercaseString];
	}
	else if ([statement length]) {
		NSString *upperStatement = [statement uppercaseString];
		if ([upperStatement hasPrefix:@"GRANT ALL "] || [upperStatement hasPrefix:@"REVOKE ALL "]) {
			privilegesDescription = NSLocalizedString(@"ALL PRIVILEGES", @"all privileges operation description");
		}
	}
	if (![privilegesDescription length]) {
		privilegesDescription = NSLocalizedString(@"the selected privileges", @"fallback privileges operation description");
	}

	NSString *message = [NSString stringWithFormat:NSLocalizedString(@"Could not %@ %@ on %@ for %@.\n\nMySQL said: %@", @"privilege operation error message"), operationDescription, privilegesDescription, scopeDescription, accountDescription, serverError];

	if (!isMariaDB || !supportsShowCreateRoutine) {
		return message;
	}

	BOOL showCreateRoutineRequested = NO;
	for (NSString *privilege in privileges)
	{
		if ([[privilege uppercaseString] isEqualToString:@"SHOW CREATE ROUTINE"]) {
			showCreateRoutineRequested = YES;
			break;
		}
	}

	if (!showCreateRoutineRequested && [statement length]) {
		NSString *upperStatement = [statement uppercaseString];
		showCreateRoutineRequested = [upperStatement rangeOfString:@"SHOW CREATE ROUTINE"].location != NSNotFound ||
			[upperStatement hasPrefix:@"GRANT ALL "] ||
			[upperStatement hasPrefix:@"REVOKE ALL "];
	}

	if (!showCreateRoutineRequested) {
		return message;
	}

	return [message stringByAppendingString:NSLocalizedString(@"\n\nThis MariaDB server supports SHOW CREATE ROUTINE, but the connected account was not allowed to grant or revoke it. This can happen after upgrading MariaDB before the new privilege has been added back to an administrative account. Check SHOW GRANTS FOR CURRENT_USER(), then grant SHOW CREATE ROUTINE WITH GRANT OPTION to the account or repair the server's grant tables.", @"mariadb show create routine grant error explanation")];
}

static inline NSSet *SPUserManagerMySQLDynamicPrivilegeKeysRequiringUnderscoreGrantNames(void)
{
	return [NSSet setWithObjects:
			@"allow_nonexistent_definer_priv",
			@"binlog_admin_priv",
			@"connection_admin_priv",
			@"read_only_admin_priv",
			@"replication_slave_admin_priv",
			@"set_any_definer_priv",
			nil];
}

static inline NSString *SPUserManagerGrantNameForPrivilegeKey(NSString *privilegeKey, BOOL isMariaDB)
{
	NSString *grantName = [privilegeKey stringByReplacingOccurrencesOfString:@"_priv" withString:@""];
	if (!isMariaDB && [SPUserManagerMySQLDynamicPrivilegeKeysRequiringUnderscoreGrantNames() containsObject:privilegeKey]) {
		return grantName;
	}

	return [grantName stringByReplacingOccurrencesOfString:@"_" withString:@" "];
}

static inline void SPUserManagerApplyMySQLDynamicPrivilegeSupportAvailability(NSMutableDictionary *supportedPrivileges, BOOL isAvailable)
{
	if (isAvailable) return;

	for (NSString *privilegeKey in SPUserManagerMySQLDynamicPrivilegeKeysRequiringUnderscoreGrantNames())
	{
		[supportedPrivileges removeObjectForKey:privilegeKey];
	}
}

static inline BOOL SPUserManagerShouldPreserveMySQLDynamicPrivilegeGrantOption(NSString *privilegeKey, NSSet *grantOptionPrivilegeKeys)
{
	return [SPUserManagerMySQLDynamicPrivilegeKeysRequiringUnderscoreGrantNames() containsObject:privilegeKey] &&
		[grantOptionPrivilegeKeys containsObject:privilegeKey];
}

static inline NSString *SPUserManagerGlobalShowCreateRoutinePrivilegeSupportKey(void)
{
	return @"show_create_routine_global_priv";
}

static inline BOOL SPUserManagerShouldUseAllPrivilegesShortcut(NSUInteger privilegeCount, NSUInteger supportedPrivilegeCount, BOOL isDatabaseScoped)
{
	return isDatabaseScoped && privilegeCount > 0 && privilegeCount == supportedPrivilegeCount;
}

static inline NSSet *SPUserManagerMariaDBGlobalOnlyPrivilegeKeysRequiringGlobalPrivAccess(void)
{
	return [NSSet setWithObjects:
			@"binlog_admin_priv",
			@"binlog_monitor_priv",
			@"binlog_replay_priv",
			@"connection_admin_priv",
			@"federated_admin_priv",
			@"read_only_admin_priv",
			@"replica_monitor_priv",
			@"replication_master_admin_priv",
			@"replication_slave_admin_priv",
			@"set_user_priv",
			nil];
}

static inline void SPUserManagerApplyMariaDBGlobalPrivilegeSupportAvailability(NSMutableDictionary *supportedPrivileges, BOOL isAvailable)
{
	NSString *showCreateRoutineGlobalSupportKey = SPUserManagerGlobalShowCreateRoutinePrivilegeSupportKey();
	if (isAvailable && [[supportedPrivileges objectForKey:@"show_create_routine_priv"] boolValue]) {
		[supportedPrivileges setObject:@YES forKey:showCreateRoutineGlobalSupportKey];
	}
	else {
		[supportedPrivileges removeObjectForKey:showCreateRoutineGlobalSupportKey];
	}

	if (isAvailable) return;

	for (NSString *privilegeKey in SPUserManagerMariaDBGlobalOnlyPrivilegeKeysRequiringGlobalPrivAccess())
	{
		[supportedPrivileges removeObjectForKey:privilegeKey];
	}
}

@interface SPUserManager : NSWindowController
{	
	NSPersistentStoreCoordinator *persistentStoreCoordinator;
    NSManagedObjectModel *managedObjectModel;
    NSManagedObjectContext *managedObjectContext;
	NSDictionary *privColumnToGrantMap;
	
	SPMySQLConnection *connection;
	SPDatabaseDocument *__weak databaseDocument;
	SPServerSupport *serverSupport;

	IBOutlet SPSplitView *splitView;
	IBOutlet NSOutlineView *outlineView;
	IBOutlet NSTabView *tabView;
	IBOutlet NSTreeController *treeController;
	IBOutlet NSMutableDictionary *privsSupportedByServer;
	
	IBOutlet NSArrayController *grantedController;
	IBOutlet NSArrayController *availableController;
	
	IBOutlet NSTableView *schemasTableView;
	IBOutlet NSTableView *grantedTableView;
	IBOutlet NSTableView *availableTableView;
	IBOutlet NSButton *addSchemaPrivButton;
	IBOutlet NSButton *removeSchemaPrivButton;
	
	IBOutlet NSTextField *maxUpdatesTextField;
	IBOutlet NSTextField *maxConnectionsTextField;
	IBOutlet NSTextField *maxQuestionsTextField;
	
    IBOutlet NSTextField *userNameTextField;

	IBOutlet NSWindow *errorsSheet;
	IBOutlet NSTextView *errorsTextView;

	NSMutableArray *schemas;
	NSMutableArray *grantedSchemaPrivs;
	NSMutableArray *availablePrivs;
	
	NSArray *treeSortDescriptors;
	NSSortDescriptor *treeSortDescriptor;

	BOOL isSaving;
	BOOL isInitializing;
	BOOL mariaDBGlobalPrivilegeAccessDataAvailable;
	BOOL mySQLDynamicPrivilegeDataAvailable;
	NSDictionary *mySQLDynamicPrivilegeGrantOptionsByAccount;
	NSMutableString *errorsString;
	
	// MySQL 5.7.6 removes the "Password" columns and only uses the "plugin" + "authentication_string" columns
	BOOL requiresPost576PasswordHandling;
}

@property (nonatomic, strong) SPMySQLConnection *connection;
@property (nonatomic, weak) SPDatabaseDocument *databaseDocument;
@property (nonatomic, strong) SPServerSupport *serverSupport;
@property (nonatomic, strong) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (nonatomic, strong, readonly) NSManagedObjectModel *managedObjectModel;
@property (nonatomic, strong) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, strong) NSMutableDictionary *privsSupportedByServer;

@property (nonatomic, strong) NSArray *treeSortDescriptors;
@property (nonatomic, strong) NSMutableArray *schemas;
@property (nonatomic, strong) NSMutableArray *grantedSchemaPrivs;
@property (nonatomic, strong) NSMutableArray *availablePrivs;
@property (nonatomic, readonly) BOOL isInitializing;

// Add/Remove users
- (IBAction)addUser:(id)sender;
- (IBAction)removeUser:(id)sender;
- (IBAction)addHost:(id)sender;
- (void)editNewHost;
- (IBAction)removeHost:(id)sender;

// General
- (IBAction)doCancel:(id)sender;
- (IBAction)doApply:(id)sender;
- (IBAction)checkAllPrivileges:(id)sender;
- (IBAction)uncheckAllPrivileges:(id)sender;
- (IBAction)closeErrorsSheet:(id)sender;
- (IBAction)doubleClickSchemaPriv:(id)sender;

// Schema privieges
- (IBAction)addSchemaPriv:(id)sender;
- (IBAction)removeSchemaPriv:(id)sender;

// Refresh
- (IBAction)refresh:(id)sender;

// Core data notifications
- (BOOL)insertUser:(SPUserMO *)user;
- (BOOL)deleteUser:(SPUserMO *)user;
- (BOOL)updateUser:(SPUserMO *)user;
- (BOOL)updateResourcesForUser:(SPUserMO *)user;
- (BOOL)grantPrivilegesToUser:(SPUserMO *)user;
- (BOOL)grantPrivilegesToUser:(SPUserMO *)user skippingRevoke:(BOOL)skipRevoke;
- (BOOL)grantDbPrivilegesWithPrivilege:(SPPrivilegesMO *)user;
- (BOOL)grantDbPrivilegesWithPrivilege:(SPPrivilegesMO *)user skippingRevoke:(BOOL)skipRevoke;

// External
/**
 * Display the user manager as a sheet attached to a chosen window
 * @param docWindow The parent window.
 * @param callback  A callback that will be called once the window is closed again. Can be NULL.
 */
- (void)beginSheetModalForWindow:(NSWindow *)docWindow completionHandler:(void (^)(void))callback;

@end
