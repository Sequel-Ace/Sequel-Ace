//
//  SPUserManager.m
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

#import "SPUserManager.h"
#import "SPUserMO.h"
#import "SPPrivilegesMO.h"
#import "ImageAndTextCell.h"
#import "SPConnectionController.h"
#import "SPServerSupport.h"
#import "SPSplitView.h"
#import "SPDatabaseDocument.h"

#import "SPPostgresConnection.h" 

#import "sequel-pace-Swift.h"

static NSString * const SPTableViewNameColumnID = @"NameColumn";

static NSString *SPGeneralTabIdentifier = @"General";
static NSString *SPGlobalPrivilegesTabIdentifier = @"Global Privileges";
static NSString *SPResourcesTabIdentifier = @"Resources";
static NSString *SPSchemaPrivilegesTabIdentifier = @"Schema Privileges";

@interface SPUserManager ()

- (void)_initializeTree:(NSArray *)items;
- (void)_initializeUsers;
- (void)_selectParentFromSelection;
- (NSArray *)_fetchUserWithUserName:(NSString *)username;
- (SPUserMO *)_createNewSPUser;
- (BOOL)_grantPrivileges:(NSArray *)thePrivileges onDatabase:(NSString *)aDatabase forUser:(NSString *)aUser host:(NSString *)aHost;
- (BOOL)_revokePrivileges:(NSArray *)thePrivileges onDatabase:(NSString *)aDatabase forUser:(NSString *)aUser host:(NSString *)aHost;
- (BOOL)_checkAndDisplayMySqlError;
- (void)_clearData;
- (void)_initializeChild:(NSManagedObject *)child withItem:(NSDictionary *)item;
- (void)_initializeSchemaPrivsForChild:(SPUserMO *)child fromData:(NSArray *)dataForUser;
- (void)_initializeSchemaPrivs;
- (NSArray *)_fetchPrivsWithUser:(NSString *)username schema:(NSString *)selectedSchema host:(NSString *)host;
- (void)_setSchemaPrivValues:(NSArray *)objects enabled:(BOOL)enabled;
- (void)_initializeAvailablePrivs;
- (BOOL)_renameUserFrom:(NSString *)originalUser host:(NSString *)originalHost to:(NSString *)newUser host:(NSString *)newHost;
- (void)contextWillSave:(NSNotification *)notice;
- (void)_selectFirstChildOfParentNode;

@end

@implementation SPUserManager

@synthesize connection;
@synthesize databaseDocument;
@synthesize privsSupportedByServer;
@synthesize managedObjectContext;
@synthesize managedObjectModel;
@synthesize persistentStoreCoordinator;
@synthesize schemas;
@synthesize grantedSchemaPrivs;
@synthesize availablePrivs;
@synthesize treeSortDescriptors;
@synthesize serverSupport;
@synthesize isInitializing = isInitializing;

#pragma mark -
#pragma mark Initialisation

- (instancetype)init
{
	if ((self = [super initWithWindowNibName:@"UserManagerView"])) {
		
		// When reading privileges from the database, they are converted automatically to a
		// lowercase key used in the user privileges stores, from which a GRANT syntax
		// is derived automatically.  While most keys can be automatically converted without
		// any difficulty, some keys differ slightly in mysql column storage to GRANT syntax;
		// this dictionary provides mappings for those values to ensure consistency.
		
		// key is:   The PostgreSQL privilege name from pg_roles
		// value is: The internal privilege key with "_priv" appended
		privColumnToGrantMap = @{
			@"grant_priv":               @"grant_option_priv",
			@"show_db_priv":             @"show_databases_priv",
			@"create_tmp_table_priv":    @"create_temporary_tables_priv",
			@"repl_slave_priv":          @"replication_slave_priv",
			@"repl_client_priv":         @"replication_client_priv",
			@"truncate_versioning_priv": @"delete_versioning_rows_priv", // MariaDB only, 10.3.4 only
			@"delete_history_priv":      @"delete_versioning_rows_priv", // MariaDB only, since 10.3.5,
			@"show_create_routine_priv": @"show_create_routine_priv", // MariaDB only, since 11.3.1, see more: https://jira.mariadb.org/browse/MDEV-29167
		};
	
        schemas = [[NSMutableArray alloc] init];
        availablePrivs = [[NSMutableArray alloc] init];
        grantedSchemaPrivs = [[NSMutableArray alloc] init];
        isSaving = NO;

        // listen for new/dropped/renamed databases, to refresh the list
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_initializeSchemaPrivs)
                                                     name:SPDatabaseCreatedRemovedRenamedNotification
                                                   object:nil];
	}
	
	return self;
}

/** 
 * UI specific items to set up when the window loads. This is different than awakeFromNib 
 * as it's only called once.
 */
- (void)windowDidLoad
{
	[tabView selectTabViewItemAtIndex:0];

	[splitView setMinSize:120.f ofSubviewAtIndex:0];
	[splitView setMinSize:550.f ofSubviewAtIndex:1];

	NSTableColumn *tableColumn = [outlineView tableColumnWithIdentifier:SPTableViewNameColumnID];
	ImageAndTextCell *imageAndTextCell = [[ImageAndTextCell alloc] init];
	
	[imageAndTextCell setEditable:NO];
	[tableColumn setDataCell:imageAndTextCell];

	// Set schema table double-click actions
	[grantedTableView setDoubleAction:@selector(doubleClickSchemaPriv:)];
	[availableTableView setDoubleAction:@selector(doubleClickSchemaPriv:)];

	[self _initializeSchemaPrivs];
	[self _initializeUsers];
	[self _initializeAvailablePrivs];	

	treeSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"displayName" ascending:YES];
	
	[self setTreeSortDescriptors:@[treeSortDescriptor]];
		
	[super windowDidLoad];
}

/**
 * This method reads in the users from the pg_roles table of the current
 * connection. Then uses this information to initialize the NSOutlineView.
 */
- (void)_initializeUsers
{
	isInitializing = YES; // Don't want to do some of the notifications if initializing

	@autoreleasepool {
		NSMutableArray *usersResultArray = [NSMutableArray array];

		// PostgreSQL: Select users (roles that can login) from pg_roles
		// Map PostgreSQL role attributes to a MySQL-like structure for compatibility
		SPPostgresResult *result = [connection queryString:
			@"SELECT rolname AS \"User\", "
			@"'localhost' AS \"Host\", "
			@"CASE WHEN rolpassword IS NOT NULL THEN '********' ELSE '' END AS \"authentication_string\", "
			@"rolsuper AS \"Super_priv\", "
			@"rolcreaterole AS \"Create_user_priv\", "
			@"rolcreatedb AS \"Create_priv\", "
			@"rolcanlogin AS \"can_login\", "
			@"rolreplication AS \"Repl_slave_priv\" "
			@"FROM pg_roles "
			@"WHERE rolcanlogin = true "
			@"ORDER BY rolname"];
		[result setReturnDataAsStrings:YES];

		if (![result numberOfRows]) {
			SPLog(@"No login roles found in pg_roles");
			isInitializing = NO;
			return;
		}

		// PostgreSQL doesn't use password hashing in the same way as MySQL
		requiresPost576PasswordHandling = YES;
		[usersResultArray addObjectsFromArray:[result getAllRows]];

		[self _initializeTree:usersResultArray];

		// Set up the array of privs supported by PostgreSQL
		// PostgreSQL has different privilege model - set basic privileges
		[[self privsSupportedByServer] removeAllObjects];

		// PostgreSQL privileges that map to MySQL-style privilege names
		[[self privsSupportedByServer] setValue:@YES forKey:@"select_priv"];
		[[self privsSupportedByServer] setValue:@YES forKey:@"insert_priv"];
		[[self privsSupportedByServer] setValue:@YES forKey:@"update_priv"];
		[[self privsSupportedByServer] setValue:@YES forKey:@"delete_priv"];
		[[self privsSupportedByServer] setValue:@YES forKey:@"create_priv"];
		[[self privsSupportedByServer] setValue:@YES forKey:@"drop_priv"];
		[[self privsSupportedByServer] setValue:@YES forKey:@"references_priv"];
		[[self privsSupportedByServer] setValue:@YES forKey:@"trigger_priv"];
		[[self privsSupportedByServer] setValue:@YES forKey:@"execute_priv"];
		// Role-level privileges
		[[self privsSupportedByServer] setValue:@YES forKey:@"super_priv"];
		[[self privsSupportedByServer] setValue:@YES forKey:@"create_user_priv"];
		[[self privsSupportedByServer] setValue:@YES forKey:@"repl_slave_priv"];
	}

	isInitializing = NO;
}

/**
 * Initialize the outline view tree. The NSOutlineView gets it's data from a NSTreeController which gets
 * it's data from the SPUser Entity objects in the current managedObjectContext.
 */
- (void)_initializeTree:(NSArray *)items
{
	// Retrieve all the user data in order to be able to initialise the schema privs for each child,
	// copying into a dictionary keyed by user, each with all the host rows.
	// PostgreSQL: Query information_schema.role_table_grants for database-level privileges
	NSMutableDictionary *schemaPrivilegeData = [NSMutableDictionary dictionary];
	SPPostgresResult *queryResults = [connection queryString:
		@"SELECT grantee AS \"User\", "
		@"table_schema AS \"Db\", "
		@"privilege_type, "
		@"CASE WHEN privilege_type = 'SELECT' THEN 'Y' ELSE 'N' END AS \"Select_priv\", "
		@"CASE WHEN privilege_type = 'INSERT' THEN 'Y' ELSE 'N' END AS \"Insert_priv\", "
		@"CASE WHEN privilege_type = 'UPDATE' THEN 'Y' ELSE 'N' END AS \"Update_priv\", "
		@"CASE WHEN privilege_type = 'DELETE' THEN 'Y' ELSE 'N' END AS \"Delete_priv\" "
		@"FROM information_schema.role_table_grants "
		@"WHERE grantee IN (SELECT rolname FROM pg_roles WHERE rolcanlogin = true) "
		@"GROUP BY grantee, table_schema, privilege_type"];

	[queryResults setReturnDataAsStrings:YES];

	for (NSDictionary *privRow in queryResults)
	{
		if (![schemaPrivilegeData objectForKey:[privRow objectForKey:@"User"]]) {
			[schemaPrivilegeData setObject:[NSMutableArray array] forKey:[privRow objectForKey:@"User"]];
		}

		[[schemaPrivilegeData objectForKey:[privRow objectForKey:@"User"]] addObject:privRow];

		// If "all database" values were found, add them to the schemas list if not already present
		NSString *schemaName = [privRow objectForKey:@"Db"];

		if ([schemaName isEqualToString:@""] || [schemaName isEqualToString:@"%"] || [schemaName isEqualToString:@"public"]) {
			if (![schemas containsObject:schemaName]) {
				[schemas addObject:schemaName];
				[schemasTableView noteNumberOfRowsChanged];
			}
		}
	}

	// Go through each item that contains a dictionary of key-value pairs
	// for each user currently in the database.
	for (NSUInteger i = 0; i < [items count]; i++)
	{
		NSDictionary *item = [items objectAtIndex:i];
		NSString *username = [item objectForKey:@"User"];
		NSArray *parentResults = [self _fetchUserWithUserName:username];
		SPUserMO *parent;
		SPUserMO *child;
		
		// Check to make sure if we already have added the parent
		if (parentResults != nil && [parentResults count] > 0) {
			
			// Add Children
			parent = [parentResults objectAtIndex:0];
			child = [self _createNewSPUser];
		} 
		else {
			// Add Parent
			parent = [self _createNewSPUser];
			child = [self _createNewSPUser];
			
			// We only care about setting the user and password keys on the parent, together with their
			// original values for comparison purposes
			[parent setPrimitiveValue:username forKey:@"user"];
			[parent setPrimitiveValue:username forKey:@"originaluser"];

			if (requiresPost576PasswordHandling) {
				[parent setPrimitiveValue:[item objectForKey:@"plugin"] forKey:@"plugin"];

				NSString *passwordHash = [item objectForKey:@"authentication_string"];

				if (![passwordHash isNSNull]) {
					[parent setPrimitiveValue:passwordHash forKey:@"authentication_string"];

					// for the UI dialog
					if ([passwordHash length]) {
						[parent setPrimitiveValue:@"sequelpro_dummy_password" forKey:@"password"];
					}
				}
			}
			else {
				[parent setPrimitiveValue:[item objectForKey:@"Password"] forKey:@"password"];
				[parent setPrimitiveValue:[item objectForKey:@"Password"] forKey:@"originalpassword"];
			}
		}

		// Setup the NSManagedObject with values from the dictionary
		[self _initializeChild:child withItem:item];
		
		NSMutableSet *children = [parent mutableSetValueForKey:@"children"];
		[children addObject:child];
		
		[self _initializeSchemaPrivsForChild:child fromData:[schemaPrivilegeData objectForKey:username]];
		
		// Save the initialized objects so that any new changes will be tracked.
		NSError *error = nil;
		
		[[self managedObjectContext] save:&error];
		
		if (error != nil) {
			[NSApp presentError:error];
		}
	}
	
	// Reload data of the outline view with the changes.
	[outlineView reloadData];
	[treeController rearrangeObjects];
}

/**
 * Initialize the available user privileges.
 */
- (void)_initializeAvailablePrivs 
{
	// Initialize available privileges
	NSManagedObjectContext *moc = [self managedObjectContext];
	NSEntityDescription *privEntityDescription = [NSEntityDescription entityForName:@"Privileges" inManagedObjectContext:moc];
	NSArray *props = [privEntityDescription attributeKeys];
	
	[availablePrivs removeAllObjects];
	
	for (NSString *prop in props)
	{
		if ([prop hasSuffix:@"_priv"] && [[[self privsSupportedByServer] objectForKey:[prop lowercaseString]] boolValue]) {
			NSString *displayName = [[prop stringByReplacingOccurrencesOfString:@"_priv" withString:@""] replaceUnderscoreWithSpace];
			
			[availablePrivs addObject:[NSDictionary dictionaryWithObjectsAndKeys:displayName, @"displayName", [prop lowercaseString], @"name", nil]];
		}
	}
	
	[availableController rearrangeObjects];
}

/**
 * Initialize the available schema privileges.
 */
- (void)_initializeSchemaPrivs
{
    SPLog(@"_initializeSchemaPrivs called.");
	// Initialize Databases
	[schemas removeAllObjects];
	[schemas addObjectsFromArray:[databaseDocument allDatabaseNames]];

	[schemasTableView reloadData];
}

/**
 * Set NSManagedObject with values from the passed in dictionary.
 */
- (void)_initializeChild:(NSManagedObject *)child withItem:(NSDictionary *)item
{
	for (__strong NSString *key in item)
	{
		// In order to keep the priviledges a little more dynamic, just
		// go through the keys that have the _priv suffix.  If a priviledge is
		// currently not supported in the model, then an exception is thrown.
		// We catch that exception and print to the console for future enhancement.
		NS_DURING		
		if ([key hasSuffix:@"_priv"])
		{
			BOOL value = [[item objectForKey:key] boolValue];
            key = [key lowercaseString];

			// Special case keys
			if ([privColumnToGrantMap objectForKey:key])
			{
				key = [privColumnToGrantMap objectForKey:key];
			}
			
			[child setValue:[NSNumber numberWithBool:value] forKey:key];
		} 
		else if ([[key lowercaseString] hasPrefix:@"max"]) // Resource Management restrictions
		{
			NSNumber *value = [NSNumber numberWithInteger:[[item objectForKey:key] integerValue]];
			[child setValue:value forKey:[key lowercaseString]];
		}
		else if (![[key lowercaseString] isInArray:@[@"user",@"password",@"plugin",@"authentication_string"]])
		{
			NSString *value = [item objectForKey:key];
			[child setValue:value forKey:[key lowercaseString]];
		}
		NS_HANDLER
		NS_ENDHANDLER
	}
}

/**
 * Initialize the schema privileges for the supplied child object.
 *
 * Assumes that the child has already been initialized with values from the
 * global user table.
 */
- (void)_initializeSchemaPrivsForChild:(SPUserMO *)child fromData:(NSArray *)dataForUser
{
	NSMutableSet *privs = [child mutableSetValueForKey:@"schema_privileges"];

	// Set an originalhost key on the child to allow the tracking of edits
	[child setPrimitiveValue:[child valueForKey:@"host"] forKey:@"originalhost"];

	for (NSDictionary *rowDict in dataForUser) 
	{

		// Verify that the host matches, or skip this entry
		if (![[rowDict objectForKey:@"Host"] isEqualToString:[child valueForKey:@"host"]]) {
			continue;
		}

		SPPrivilegesMO *dbPriv = [NSEntityDescription insertNewObjectForEntityForName:@"Privileges" inManagedObjectContext:[self managedObjectContext]];


		for (__strong NSString *key in rowDict)
		{

			if ([key hasSuffix:@"_priv"]) {
				
				BOOL boolValue = [[rowDict objectForKey:key] boolValue];
                key = [key lowercaseString];
				
				// Special case keys
				if ([privColumnToGrantMap objectForKey:key]) {
					key = [privColumnToGrantMap objectForKey:key];
				}
				
				[dbPriv setValue:[NSNumber numberWithBool:boolValue] forKey:key];
			}
			else if ([[key lowercaseString] isEqualToString:@"db"]) {
				NSString *db = [[rowDict objectForKey:key] stringByReplacingOccurrencesOfString:@"\\_" withString:@"_"];
                [dbPriv setValue:db forKey:[key lowercaseString]];
            }
			else if (![[key lowercaseString] isEqualToString:@"host"] && ![[key lowercaseString] isEqualToString:@"user"]) {
				[dbPriv setValue:[rowDict objectForKey:key] forKey:[key lowercaseString]];
			}
		}
		[privs addObject:dbPriv];
	}
}

/**
 * Creates, retains, and returns the managed object model for the application 
 * by merging all of the models found in the application bundle.
 */
- (NSManagedObjectModel *)managedObjectModel 
{	
	if (!managedObjectModel) {
		managedObjectModel = [NSManagedObjectModel mergedModelFromBundles:nil];
	}
    return managedObjectModel;
}

/**
 * Returns the persistent store coordinator for the application.  This 
 * implementation will create and return a coordinator, having added the 
 * store for the application to it.  (The folder for the store is created, 
 * if necessary.)
 */
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator 
{	
    if (persistentStoreCoordinator != nil) return persistentStoreCoordinator;
	
    NSError *error = nil;
    
    persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel: [self managedObjectModel]];
	
    if (![persistentStoreCoordinator addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:&error] && error) {
        [NSApp presentError:error];
    }    
	
    return persistentStoreCoordinator;
}

/**
 * Returns the managed object context for the application (which is already
 * bound to the persistent store coordinator for the application.) 
 */
- (NSManagedObjectContext *)managedObjectContext 
{	
    if (managedObjectContext != nil) return managedObjectContext;
	
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
	
    if (coordinator != nil) {
        managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        [managedObjectContext setPersistentStoreCoordinator:coordinator];
    }
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(contextWillSave:)
												 name:NSManagedObjectContextWillSaveNotification
											   object:managedObjectContext];
    
    return managedObjectContext;
}

- (void)beginSheetModalForWindow:(NSWindow *)docWindow completionHandler:(void (^)(void))callback
{
	[docWindow beginSheet:self.window completionHandler:^(NSModalResponse returnCode) {
		callback();
	}];
}

#pragma mark -
#pragma mark General IBAction methods

/**
 * Closes the user manager and reverts any changes made.
 */
- (IBAction)doCancel:(id)sender
{
	// Discard any pending changes
	[treeController discardEditing];

	// Change the first responder to end editing in any field
	[[self window] makeFirstResponder:self];

	[[self managedObjectContext] rollback];
	
	// Close sheet
	[NSApp endSheet:[self window] returnCode:0];
}

/**
 * Closes the user manager and applies any changes made.
 */
- (IBAction)doApply:(id)sender
{
	// If editing can't be committed, cancel the apply
	if (![treeController commitEditing]) {
		return;
	}

	errorsString = [[NSMutableString alloc] init];
    
	// Change the first responder to end editing in any field
	[[self window] makeFirstResponder:self];

	isSaving = YES;

	NSError *error = nil;
	
	[[self managedObjectContext] save:&error];
	
	isSaving = NO;
	
	if (error) [errorsString appendString:[error localizedDescription]];

	[connection queryString:@"FLUSH PRIVILEGES"];

	// Display any errors
	if ([errorsString length]) {
		[errorsTextView setString:errorsString];

		[self.window beginSheet:errorsSheet completionHandler:nil];
		
		
		
		return;
	}
	
	

	// Otherwise, close the sheet
	[NSApp endSheet:[self window] returnCode:0];
}

/**
 * Enables all privileges.
 */
- (IBAction)checkAllPrivileges:(id)sender
{
	id selectedUser = [[treeController selectedObjects] firstObject];

    if(selectedUser == nil){
        SPLog(@"selectedUser == nil");
        return;
    }

	// Iterate through the supported privs, setting the value of each to YES
	for (NSString *key in [self privsSupportedByServer]) 
	{
		if (![key hasSuffix:@"_priv"]) continue;

		// Perform the change in a try/catch check to avoid exceptions for unhandled privs
		NS_DURING
			[selectedUser setValue:@YES forKey:key];
		NS_HANDLER
		NS_ENDHANDLER
	}
}

/**
 * Disables all privileges.
 */
- (IBAction)uncheckAllPrivileges:(id)sender
{
	id selectedUser = [[treeController selectedObjects] firstObject];

    if(selectedUser == nil){
        SPLog(@"selectedUser == nil");
        return;
    }

	// Iterate through the supported privs, setting the value of each to NO
	for (NSString *key in [self privsSupportedByServer]) 
	{
		if (![key hasSuffix:@"_priv"]) continue;

		// Perform the change in a try/catch check to avoid exceptions for unhandled privs
		NS_DURING
			[selectedUser setValue:@NO forKey:key];
		NS_HANDLER
		NS_ENDHANDLER
	}
}

/**
 * Adds a new user to the current database.
 */
- (IBAction)addUser:(id)sender
{
	// Adds a new SPUser objects to the managedObjectContext and sets default values
	if ([[treeController selectedObjects] count] > 0) {
		if ([[[treeController selectedObjects] objectAtIndex:0] parent] != nil) {
			[self _selectParentFromSelection];
		}
	}	
	
	SPUserMO *newItem = [self _createNewSPUser];
	SPUserMO *newChild = [self _createNewSPUser];
	[newChild setValue:@"localhost" forKey:@"host"];
	[newItem addChildrenObject:newChild];
		
	[treeController addObject:newItem];
	[outlineView expandItem:[outlineView itemAtRow:[outlineView selectedRow]]];
    [[self window] makeFirstResponder:userNameTextField];
}

/**
 * Removes the currently selected user from the current database.
 */
- (IBAction)removeUser:(id)sender
{
    NSString *username = [[[treeController selectedObjects] firstObject] valueForKey:@"originaluser"];
    NSArray *children = [[[treeController selectedObjects] firstObject] valueForKey:@"children"];

	// On all the children - host entries - set the username to be deleted,
	// for later query contruction.
    for (NSManagedObject *child in children)
    {
        [child setPrimitiveValue:username forKey:@"user"];
    }
	
	// Unset the host on the user, so that only the host entries are dropped
	[[[treeController selectedObjects] firstObject] setPrimitiveValue:nil forKey:@"host"];

	[treeController remove:sender];
}

/**
 * Adds a new host to the currently selected user.
 */
- (IBAction)addHost:(id)sender
{
	if ([[treeController selectedObjects] count] > 0)
	{
		if ([[[treeController selectedObjects] firstObject] parent] != nil)
		{
			[self _selectParentFromSelection];
		}
	}
	
	[treeController addChild:sender];

	// The newly added item will be selected as it is added, but only after the next iteration of the
	// run loop - edit it after a tiny delay.
	[self performSelector:@selector(editNewHost) withObject:nil afterDelay:0.1];
}

/**
 * Perform a deferred edit of the currently selected row.
 */ 
- (void)editNewHost
{
	[outlineView editColumn:0 row:[outlineView selectedRow]	withEvent:nil select:YES];		
}

/**
 * Removes the currently selected host from it's parent user.
 */
- (IBAction)removeHost:(id)sender
{
    // Set the username on the child so that it's accessabile when building
    // the drop sql command
    SPUserMO *child = [[treeController selectedObjects] firstObject];
    SPUserMO *parent = [child parent];
	
    [child setPrimitiveValue:[[child valueForKey:@"parent"] valueForKey:@"user"] forKey:@"user"];
	
	[treeController remove:sender];
	
    if ([[parent valueForKey:@"children"] count] == 0)
    {
		[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Unable to remove host", @"error removing host message") message:NSLocalizedString(@"This user doesn't seem to have any associated hosts and will be removed unless a host is added.", @"error removing host informative message") callback:nil];
    }
}

/**
 * Adds a new schema privilege.
 */
- (IBAction)addSchemaPriv:(id)sender
{
	NSArray *selectedObjects = [availableController selectedObjects];
	
	[grantedController addObjects:selectedObjects];
	[grantedTableView noteNumberOfRowsChanged];
	[availableController removeObjects:selectedObjects];
	[availableTableView noteNumberOfRowsChanged];
	[schemasTableView setNeedsDisplay:YES];
	
	[self _setSchemaPrivValues:selectedObjects enabled:YES];
}

/**
 * Removes a schema privilege.
 */
- (IBAction)removeSchemaPriv:(id)sender
{
	NSArray *selectedObjects = [grantedController selectedObjects];
	
	[availableController addObjects:selectedObjects];
	[availableTableView noteNumberOfRowsChanged];
	[grantedController removeObjects:selectedObjects];
	[grantedTableView noteNumberOfRowsChanged];
	[schemasTableView setNeedsDisplay:YES];
	
	[self _setSchemaPrivValues:selectedObjects enabled:NO];
}

/**
 * Move double-clicked rows across to the other table, using the
 * appropriate methods.
 */
- (IBAction)doubleClickSchemaPriv:(id)sender
{
	// Ignore double-clicked header cells
	if ([sender clickedRow] == -1) return;

	if (sender == availableTableView) {
		[self addSchemaPriv:sender];
	} 
	else {
		[self removeSchemaPriv:sender];
	}
}

/**
 * Refreshes the current list of users.
 */
- (IBAction)refresh:(id)sender
{
	if ([[self managedObjectContext] hasChanges]) {

		NSAlert *alert = [[NSAlert alloc] init];
		alert.messageText = NSLocalizedString(@"Unsaved changes", @"unsaved changes message");
		alert.informativeText = NSLocalizedString(@"Changes have been made, which will be lost if this window is closed. Are you sure you want to continue", @"unsaved changes informative message");
		[alert addButtonWithTitle:NSLocalizedString(@"Continue", @"continue button")];
		[alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"cancel button")];
		[alert setAlertStyle:NSAlertStyleWarning];

		// "Continue" is our first button, "Cancel" is our second button. We could also implement setKeyEquivalent but this is easier for now
		NSModalResponse response = [alert runModal];
		if (response == NSAlertSecondButtonReturn) {
			// Cancel button tapped
			return;
		}
	}
    
	[[self managedObjectContext] reset];

    [grantedSchemaPrivs removeAllObjects];
	[grantedTableView reloadData];

	[self _initializeAvailablePrivs];

	[outlineView reloadData];
	[treeController rearrangeObjects];

    // Get all the stores on the current MOC and remove them.
    NSArray *stores = [[[self managedObjectContext] persistentStoreCoordinator] persistentStores];

	for (NSPersistentStore* store in stores)
    {
        [[[self managedObjectContext] persistentStoreCoordinator] removePersistentStore:store error:nil];
    }

    // Add a new store
    [[[self managedObjectContext] persistentStoreCoordinator] addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:nil];

    // Reinitialize the tree with values from the database.
    [self _initializeUsers];

	// After the reset, ensure all original password and user values are up-to-date.
	NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"SPUser" inManagedObjectContext:[self managedObjectContext]];
	NSFetchRequest *request = [[NSFetchRequest alloc] init];

	[request setEntity:entityDescription];

	NSArray *userArray = [[self managedObjectContext] executeFetchRequest:request error:nil];

	for (SPUserMO *user in userArray)
	{
		if (![user parent]) {
			[user setPrimitiveValue:[user valueForKey:@"user"] forKey:@"originaluser"];
			if(!requiresPost576PasswordHandling) [user setPrimitiveValue:[user valueForKey:@"password"] forKey:@"originalpassword"];
		}
	}
}

- (void)_setSchemaPrivValues:(NSArray *)objects enabled:(BOOL)enabled
{
	// The passed in objects should be an array of NSDictionaries with a key
	// of "name".
	NSManagedObject *selectedHost = [[treeController selectedObjects] objectAtIndex:0];
	NSString *selectedDb = [schemas objectAtIndex:[schemasTableView selectedRow]];
	
	NSArray *selectedPrivs = [self _fetchPrivsWithUser:[selectedHost valueForKeyPath:@"parent.user"] 
												schema:[selectedDb stringByReplacingOccurrencesOfString:@"_" withString:@"\\_"]
												  host:[selectedHost valueForKey:@"host"]];
	
	BOOL isNew = NO;
	NSManagedObject *priv = nil;
    
	if ([selectedPrivs count] > 0){
		priv = [selectedPrivs objectAtIndex:0];
	} 
	else {
		priv = [NSEntityDescription insertNewObjectForEntityForName:@"Privileges" inManagedObjectContext:[self managedObjectContext]];
		
		[priv setValue:selectedDb forKey:@"db"];
		isNew = YES;
	}

	// Now setup all the items that are selected to their enabled value
	for (NSDictionary *obj in objects)
	{
		[priv setValue:[NSNumber numberWithBool:enabled] forKey:[obj valueForKey:@"name"]];
	}

	if (isNew) {
		// Set up relationship
		NSMutableSet *privs = [selectedHost mutableSetValueForKey:@"schema_privileges"];
		[privs addObject:priv];		
	}
}

- (void)_clearData
{
	[managedObjectContext reset];
	
}

/**
 * Menu item validation.
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	// Only allow removing hosts of a host node is selected.
	if ([menuItem action] == @selector(removeHost:)) {
		return (([[treeController selectedObjects] count] > 0) && 
				[[[treeController selectedObjects] objectAtIndex:0] parent] != nil);
	} 
	else if ([menuItem action] == @selector(addHost:)) {
		return ([[treeController selectedObjects] count] > 0);
	}
	
	return YES;
}

- (void)_selectParentFromSelection
{
	if ([[treeController selectedObjects] count] > 0)
	{
		NSTreeNode *firstSelectedNode = [[treeController selectedNodes] objectAtIndex:0];
		NSTreeNode *parentNode = [firstSelectedNode parentNode];
	
		if (parentNode) {
			NSIndexPath *parentIndex = [parentNode indexPath];
			[treeController setSelectionIndexPath:parentIndex];
		}
		else {
			NSArray *selectedIndexPaths = [treeController selectionIndexPaths];
			[treeController removeSelectionIndexPaths:selectedIndexPaths];
		}
	}
}

- (void)_selectFirstChildOfParentNode
{
	if ([[treeController selectedObjects] count] > 0)
	{
		[outlineView expandItem:[outlineView itemAtRow:[outlineView selectedRow]]];
		
		id selectedObject = [[treeController selectedObjects] objectAtIndex:0];
		NSTreeNode *firstSelectedNode = [[treeController selectedNodes] objectAtIndex:0];
		id parent = [selectedObject parent];
		
		// If this is already a parent, then parentNode should be null.
		// If a child is already selected, then we want to not change the selection
		if (!parent) {
			NSIndexPath *childIndex = [[[firstSelectedNode childNodes] objectAtIndex:0] indexPath];
			[treeController setSelectionIndexPath:childIndex];
		}
	}
}

/**
 * Closes the supplied sheet, before closing the master window.
 */
- (IBAction)closeErrorsSheet:(id)sender
{
	[NSApp endSheet:[sender window] returnCode:[sender tag]];
	[[sender window] orderOut:self];
}

#pragma mark -
#pragma mark Notifications

/** 
 * This notification is called when the managedObjectContext save happens.
 *
 * This will link this class to any newly created objects, so when they do their
 * -validateFor(Insert|Update|Delete): call later, they can forward it to this class.
 */
- (void)contextWillSave:(NSNotification *)notice
{
	//new objects don't yet know about us (this will also be called the first time an object is loaded from the db)
	for (NSManagedObject *o in [managedObjectContext insertedObjects]) {
		if([o isKindOfClass:[SPUserMO class]] || [o isKindOfClass:[SPPrivilegesMO class]]) {
			[o setValue:self forKey:@"userManager"];
		}
	}
}

- (void)contextDidChange:(NSNotification *)notification
{	
	if (!isInitializing) [outlineView reloadData];
}

#pragma mark -
#pragma mark Core data notifications

- (BOOL)updateUser:(SPUserMO *)user
{
	if (![user parent]) {
		// If the role name has been changed, rename it
		// PostgreSQL doesn't have host-based users, so we only need to rename once
		if (![[user valueForKey:@"user"] isEqualToString:[user valueForKey:@"originaluser"]]) {
			[self _renameUserFrom:[user valueForKey:@"originaluser"]
							 host:nil
							   to:[user valueForKey:@"user"]
							 host:nil];
		}

		// If the password has been changed, update it
		// PostgreSQL uses ALTER ROLE ... WITH PASSWORD
		NSString *newPass = [[user changedValues] objectForKey:@"password"];
		if(newPass && ![newPass isNSNull] && [newPass length]) {
			NSString *alterStmt = [NSString stringWithFormat:@"ALTER ROLE %@ WITH PASSWORD %@",
				[[user valueForKey:@"user"] postgresQuotedIdentifier],
				[[self connection] escapeAndQuoteString:newPass]];
			[connection queryString:alterStmt];
			if(![self _checkAndDisplayMySqlError]) return NO;
		}
	}
	else {
		// PostgreSQL doesn't support per-host role definitions
		// Just update resources and privileges
        if(![self updateResourcesForUser:user]) {
            return NO;
        }

        if(![self grantPrivilegesToUser:user]) {
            return NO;
        }
	}

	return YES;
}

- (BOOL)deleteUser:(SPUserMO *)user
{
	// users without hosts are for display only
    if(isInitializing || ![user valueForKey:@"host"]) {
        return YES;
    }

	// PostgreSQL uses DROP ROLE (no @host)
	NSString *roleName = [[user valueForKey:@"user"] postgresQuotedIdentifier];

	// DROP ROLE
    [connection queryString:[NSString stringWithFormat:@"DROP ROLE %@", roleName]];

	return [self _checkAndDisplayMySqlError];
}

- (BOOL)insertUser:(SPUserMO *)user
{
	// This is also called during the initialize phase. We don't want to write to the db there.
	if(isInitializing) return YES;

	NSString *createStatement = nil;

	// PostgreSQL uses CREATE ROLE ... WITH LOGIN PASSWORD 'password'
	// No @host syntax - host restrictions are managed in pg_hba.conf

	if ([user parent] && [[user parent] valueForKey:@"user"]) {
		NSString *roleName = [[[user parent] valueForKey:@"user"] postgresQuotedIdentifier];
		NSString *password = [[user parent] valueForKey:@"password"];

		if (password && ![password isNSNull] && [password length]) {
			// Create role with password
			createStatement = [NSString stringWithFormat:@"CREATE ROLE %@ WITH LOGIN PASSWORD %@",
				roleName,
				[[self connection] escapeAndQuoteString:password]];
		}
		else {
			// Create role without password
			createStatement = [NSString stringWithFormat:@"CREATE ROLE %@ WITH LOGIN", roleName];
		}
	}

	if (createStatement) {
		// Create role in database
		[connection queryString:createStatement];

		if ([self _checkAndDisplayMySqlError]) {
            if(![self updateResourcesForUser:user]) {
                return NO;
            }

			return [self grantPrivilegesToUser:user skippingRevoke:YES];
		}
	}
	return NO;
}

- (BOOL)grantDbPrivilegesWithPrivilege:(SPPrivilegesMO *)schemaPriv
{
	return [self grantDbPrivilegesWithPrivilege:schemaPriv skippingRevoke:NO];
}

/**
 * Grant or revoke DB privileges for the supplied user.
 */
- (BOOL)grantDbPrivilegesWithPrivilege:(SPPrivilegesMO *)schemaPriv skippingRevoke:(BOOL)skipRevoke
{
	NSMutableArray *grantPrivileges = [NSMutableArray array];
	NSMutableArray *revokePrivileges = [NSMutableArray array];
	
	NSString *dbName = [schemaPriv valueForKey:@"db"];
    dbName = [dbName stringByReplacingOccurrencesOfString:@"_" withString:@"\\_"];
	
	NSArray *changedKeys = [[schemaPriv changedValues] allKeys];
	
	for (NSString *key in [self privsSupportedByServer])
	{
		if (![key hasSuffix:@"_priv"]) continue;
		
		//ignore anything that we didn't change
		if (![changedKeys containsObject:key]) continue;
		
		NSString *privilege = [key stringByReplacingOccurrencesOfString:@"_priv" withString:@""];
		
		NS_DURING
			if ([[schemaPriv valueForKey:key] boolValue] == YES) {
				[grantPrivileges addObject:[privilege replaceUnderscoreWithSpace]];
			}
			else {
				[revokePrivileges addObject:[privilege replaceUnderscoreWithSpace]];
			}
		NS_HANDLER
		NS_ENDHANDLER
	
	}
	
	// Grant privileges
	if(![self _grantPrivileges:grantPrivileges
				onDatabase:dbName 
				   forUser:[schemaPriv valueForKeyPath:@"user.parent.user"] 
					  host:[schemaPriv valueForKeyPath:@"user.host"]]) return NO;
	
	if(!skipRevoke) {
		// Revoke privileges
		if(![self _revokePrivileges:revokePrivileges
					 onDatabase:dbName 
						forUser:[schemaPriv valueForKeyPath:@"user.parent.user"] 
						   host:[schemaPriv valueForKeyPath:@"user.host"]]) return NO;
	}
	
	return YES;
}

/**
 * Update resource limits for given user.
 * Note: PostgreSQL does not support per-role resource limits like MySQL.
 * Connection limits can be set via ALTER ROLE, but query/update limits are not available.
 */
- (BOOL)updateResourcesForUser:(SPUserMO *)user
{
    if ([user valueForKey:@"parent"] != nil) {
        // PostgreSQL only supports connection limits via ALTER ROLE
        NSNumber *maxConnections = [user valueForKey:@"max_connections"];
        if (maxConnections && [maxConnections integerValue] > 0) {
            NSString *alterStmt = [NSString stringWithFormat:@"ALTER ROLE %@ WITH CONNECTION LIMIT %@",
                                   [[[user valueForKey:@"parent"] valueForKey:@"user"] postgresQuotedIdentifier],
                                   maxConnections];
            [connection queryString:alterStmt];

            if ([connection queryErrored]) {
                // Connection limit setting failed, but this is not critical
                SPLog(@"Failed to set connection limit for role: %@", [connection lastErrorMessage]);
            }
        }

        // Check if user tried to set query/update limits (not supported in PostgreSQL)
        NSNumber *maxQuestions = [user valueForKey:@"max_questions"];
        NSNumber *maxUpdates = [user valueForKey:@"max_updates"];
        if ((maxQuestions && [maxQuestions integerValue] > 0) ||
            (maxUpdates && [maxUpdates integerValue] > 0)) {
            SPLog(@"PostgreSQL does not support max_questions or max_updates resource limits");
        }
    }

	return YES;
}

- (BOOL)grantPrivilegesToUser:(SPUserMO *)user
{
	return [self grantPrivilegesToUser:user skippingRevoke:NO];
}

/**
 * Grant or revoke privileges for the supplied user.
 */
- (BOOL)grantPrivilegesToUser:(SPUserMO *)user skippingRevoke:(BOOL)skipRevoke
{
	if ([user valueForKey:@"parent"] != nil)
	{
		NSMutableArray *grantPrivileges = [NSMutableArray array];
		NSMutableArray *revokePrivileges = [NSMutableArray array];
		
		NSArray *changedKeys = [[user changedValues] allKeys];
		
		for (NSString *key in [self privsSupportedByServer])
		{
			if (![key hasSuffix:@"_priv"]) continue;
			
			//ignore anything that we didn't change
			if (![changedKeys containsObject:key]) continue;
			
			NSString *privilege = [key stringByReplacingOccurrencesOfString:@"_priv" withString:@""];
			
			// Check the value of the priv and assign to grant or revoke query as appropriate; do this
			// in a try/catch check to avoid exceptions for unhandled privs
			NS_DURING
				if ([[user valueForKey:key] boolValue] == YES) {
					[grantPrivileges addObject:[privilege replaceUnderscoreWithSpace]];
				} 
				else {
					[revokePrivileges addObject:[privilege replaceUnderscoreWithSpace]];
				}
			NS_HANDLER
			NS_ENDHANDLER
		}
		
		// Grant privileges
		if(![self _grantPrivileges:grantPrivileges
					onDatabase:nil 
					   forUser:[[user parent] valueForKey:@"user"] 
						  host:[user valueForKey:@"host"]]) return NO;

		if(!skipRevoke) {
			// Revoke privileges
			if(![self _revokePrivileges:revokePrivileges
						 onDatabase:nil 
							forUser:[[user parent] valueForKey:@"user"] 
							   host:[user valueForKey:@"host"]]) return NO;
		}
	}
	
	for (SPPrivilegesMO *priv in [user valueForKey:@"schema_privileges"])
	{
		if(![self grantDbPrivilegesWithPrivilege:priv skippingRevoke:skipRevoke]) return NO;
	}
	
	return YES;
}

#pragma mark -
#pragma mark Private API

/** 
 * Gets any NSManagedObject (SPUser) from the managedObjectContext that may
 * already exist with the given username.
 */
- (NSArray *)_fetchUserWithUserName:(NSString *)username
{
	NSManagedObjectContext *moc = [self managedObjectContext];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"user == %@ AND parent == nil", username];
	NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"SPUser" inManagedObjectContext:moc];
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	
	[request setEntity:entityDescription];
	[request setPredicate:predicate];
	
	NSError *error = nil;
	NSArray *array = [moc executeFetchRequest:request error:&error];
	
	if (error != nil) {
		[NSApp presentError:error];
	}
	
	return array;
}

- (NSArray *)_fetchPrivsWithUser:(NSString *)username schema:(NSString *)selectedSchema host:(NSString *)host
{
	NSManagedObjectContext *moc = [self managedObjectContext];
	NSPredicate *predicate;
	NSEntityDescription *privEntity = [NSEntityDescription entityForName:@"Privileges" inManagedObjectContext:moc];
	NSFetchRequest *request = [[NSFetchRequest alloc] init];

	// Construct the predicate depending on whether a user and schema were supplied;
	// blank schemas indicate a default priv value (as per %)
	if ([username length]) {
		if ([selectedSchema length]) {
			predicate = [NSPredicate predicateWithFormat:@"(user.parent.user like[cd] %@) AND (user.host like[cd] %@) AND (db like[cd] %@)", username, host, selectedSchema];
		} else {
			predicate = [NSPredicate predicateWithFormat:@"(user.parent.user like[cd] %@) AND (user.host like[cd] %@) AND (db == '')", username, host];
		}
	} else {
		if ([selectedSchema length]) {
			predicate = [NSPredicate predicateWithFormat:@"(user.parent.user == '') AND (user.host like[cd] %@) AND (db like[cd] %@)", host, selectedSchema];
		} else {
			predicate = [NSPredicate predicateWithFormat:@"(user.parent.user == '') AND (user.host like[cd] %@) AND (db == '')", host];
		}
	}

	[request setEntity:privEntity];
	[request setPredicate:predicate];
	
	NSError *error = nil;
	NSArray *array = [moc executeFetchRequest:request error:&error];
	
	if (error != nil) {
		[NSApp presentError:error];
	}
	
	return array;
}

/**
 * Creates a new NSManagedObject and inserts it into the managedObjectContext.
 */
- (SPUserMO *)_createNewSPUser
{
	return [NSEntityDescription insertNewObjectForEntityForName:@"SPUser" inManagedObjectContext:[self managedObjectContext]];	
}

/**
 * Grant the supplied privileges to the specified user.
 * PostgreSQL uses GRANT privilege ON schema.* TO rolename (no @host)
 */
- (BOOL)_grantPrivileges:(NSArray *)thePrivileges onDatabase:(NSString *)aDatabase forUser:(NSString *)aUser host:(NSString *)aHost
{
	if (![thePrivileges count]) return YES;

	NSString *grantStatement;
	NSString *roleIdentifier = [aUser postgresQuotedIdentifier];

	// PostgreSQL grants on schemas (not database.*)
	// For global privileges, we grant on ALL TABLES IN SCHEMA public
	NSString *targetObject;
	if (aDatabase && [aDatabase length]) {
		targetObject = [NSString stringWithFormat:@"ALL TABLES IN SCHEMA %@", [aDatabase postgresQuotedIdentifier]];
	} else {
		targetObject = @"ALL TABLES IN SCHEMA public";
	}

	// Special case when all items are checked, to allow GRANT OPTION to work
	if ([[self privsSupportedByServer] count] == [thePrivileges count]) {
		grantStatement = [NSString stringWithFormat:@"GRANT ALL PRIVILEGES ON %@ TO %@ WITH GRANT OPTION",
							targetObject, roleIdentifier];
	}
	else {
		grantStatement = [NSString stringWithFormat:@"GRANT %@ ON %@ TO %@",
							[[thePrivileges componentsJoinedByCommas] uppercaseString],
							targetObject, roleIdentifier];
	}

	[connection queryString:grantStatement];
	return [self _checkAndDisplayMySqlError];
}

/**
 * Revoke the supplied privileges from the specified user.
 * PostgreSQL uses REVOKE privilege ON schema.* FROM rolename (no @host)
 */
- (BOOL)_revokePrivileges:(NSArray *)thePrivileges onDatabase:(NSString *)aDatabase forUser:(NSString *)aUser host:(NSString *)aHost
{
	if (![thePrivileges count]) return YES;

	NSString *revokeStatement;
	NSString *roleIdentifier = [aUser postgresQuotedIdentifier];

	// PostgreSQL revokes on schemas (not database.*)
	NSString *targetObject;
	if (aDatabase && [aDatabase length]) {
		targetObject = [NSString stringWithFormat:@"ALL TABLES IN SCHEMA %@", [aDatabase postgresQuotedIdentifier]];
	} else {
		targetObject = @"ALL TABLES IN SCHEMA public";
	}

	// Special case when all items are checked, to also revoke GRANT OPTION
	if ([[self privsSupportedByServer] count] == [thePrivileges count]) {
		revokeStatement = [NSString stringWithFormat:@"REVOKE ALL PRIVILEGES ON %@ FROM %@",
							targetObject, roleIdentifier];

		[connection queryString:revokeStatement];
		if(![self _checkAndDisplayMySqlError]) return NO;

		revokeStatement = [NSString stringWithFormat:@"REVOKE GRANT OPTION FOR ALL PRIVILEGES ON %@ FROM %@",
							targetObject, roleIdentifier];
	}
	else {
		revokeStatement = [NSString stringWithFormat:@"REVOKE %@ ON %@ FROM %@",
							[[thePrivileges componentsJoinedByCommas] uppercaseString],
							targetObject, roleIdentifier];
	}

	[connection queryString:revokeStatement];
	return [self _checkAndDisplayMySqlError];
}

/**
 * Displays an alert panel if there was an error condition on the Postgres connection.
 */
- (BOOL)_checkAndDisplayMySqlError
{
	if ([connection queryErrored]) {
		if (isSaving) {
			[errorsString appendFormat:@"%@\n", [connection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error")];
		}
		else {
			[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"An error occurred", @"postgresql error occurred message") message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred whilst trying to perform the operation.\n\nPostgreSQL said: %@", @"PostgreSQL error occurred informative message"), [connection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error")] callback:nil];
		}

		return NO;
	}
	
	return YES;
}

/**
 * Renames a role using the supplied parameters.
 * PostgreSQL uses ALTER ROLE ... RENAME TO (no host concept).
 *
 * @param originalUser The role's original name
 * @param originalHost Ignored for PostgreSQL
 * @param newUser      The role's new name
 * @param newHost      Ignored for PostgreSQL
 */
- (BOOL)_renameUserFrom:(NSString *)originalUser host:(NSString *)originalHost to:(NSString *)newUser host:(NSString *)newHost
{
	// PostgreSQL doesn't use host-based role names, so we ignore the host parameters
	NSString *renameQuery = [NSString stringWithFormat:@"ALTER ROLE %@ RENAME TO %@",
					   [originalUser postgresQuotedIdentifier],
					   [newUser postgresQuotedIdentifier]];

    [connection queryString:renameQuery];
    return [self _checkAndDisplayMySqlError];
}

#pragma mark - SPUserManagerDelegate

#pragma mark TableView Delegate Methods

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	id object = [notification object];

	if (object == schemasTableView) {
		[grantedSchemaPrivs removeAllObjects];
		[grantedTableView reloadData];

		[self _initializeAvailablePrivs];

		if ([[treeController selectedObjects] count] > 0 && [[schemasTableView selectedRowIndexes] count] > 0) {
			SPUserMO *user = [[treeController selectedObjects] objectAtIndex:0];

			// Check to see if the user host node was selected
			if ([user valueForKey:@"host"]) {
				NSString *selectedSchema = [schemas objectAtIndex:[schemasTableView selectedRow]];

				NSArray *results = [self _fetchPrivsWithUser:[[user parent] valueForKey:@"user"]
													  schema:[selectedSchema stringByReplacingOccurrencesOfString:@"_" withString:@"\\_"]
														host:[user valueForKey:@"host"]];

				if ([results count] > 0) {
					NSManagedObject *priv = [results objectAtIndex:0];

					for (NSPropertyDescription *property in [priv entity])
					{
						if ([[property name] hasSuffix:@"_priv"] && [[priv valueForKey:[property name]] boolValue])
						{
							NSString *displayName = [[[property name] stringByReplacingOccurrencesOfString:@"_priv" withString:@""] replaceUnderscoreWithSpace];
							NSDictionary *newDict = [NSDictionary dictionaryWithObjectsAndKeys:displayName, @"displayName", [[property name] lowercaseString], @"name", nil];
							[grantedController addObject:newDict];

							// Remove items from available so they can't be added twice.
							NSPredicate *predicate = [NSPredicate predicateWithFormat:@"displayName like[cd] %@", displayName];
							NSArray *previousObjects = [[availableController arrangedObjects] filteredArrayUsingPredicate:predicate];

							for (NSDictionary *dict in previousObjects)
							{
								[availableController removeObject:dict];
							}
						}
					}
				}

				[availableTableView setEnabled:YES];
			}
		}
		else {
			[availableTableView setEnabled:NO];
		}
	}
	else if (object == grantedTableView) {
		[removeSchemaPrivButton setEnabled:[[grantedController selectedObjects] count] > 0];
	}
	else if (object == availableTableView) {
		[addSchemaPrivButton setEnabled:[[availableController selectedObjects] count] > 0];
	}
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if (tableView == schemasTableView) {
		NSString *schemaName = [schemas objectAtIndex:rowIndex];

		// Gray out the "all database" entries
		if ([schemaName isEqualToString:@""] || [schemaName isEqualToString:@"%"]) {
			[cell setTextColor:[NSColor lightGrayColor]];
		} else {
			[cell setTextColor:[NSColor controlTextColor]];
		}

        if ([[treeController selectedObjects] count] > 0) {
            // If the schema has permissions set, highlight with a yellow background
            BOOL enabledPermissions = NO;
            SPUserMO *user = [[treeController selectedObjects] objectAtIndex:0];
            NSArray *results = [self _fetchPrivsWithUser:[[user parent] valueForKey:@"user"]
                                                  schema:[schemaName stringByReplacingOccurrencesOfString:@"_" withString:@"\\_"]
                                                    host:[user valueForKey:@"host"]];
            if ([results count]) {
                NSManagedObject *schemaPrivs = [results objectAtIndex:0];
                for (NSString *itemKey in [[[schemaPrivs entity] attributesByName] allKeys]) {
                    if ([itemKey hasSuffix:@"_priv"] && [[schemaPrivs valueForKey:itemKey] boolValue]) {
                        enabledPermissions = YES;
                        break;
                    }
                }
            }

            if (enabledPermissions) {
                [cell setDrawsBackground:YES];
                [cell setBackgroundColor:[NSColor colorWithDeviceRed:1.f green:1.f blue:0.f alpha:0.2]];
            } else {
                [cell setDrawsBackground:NO];
            }
        }
    }
}

#pragma mark -
#pragma mark Tab View Delegate methods

- (BOOL)tabView:(NSTabView *)tabView shouldSelectTabViewItem:(NSTabViewItem *)tabViewItem {
	BOOL retVal = YES;

	if ([[treeController selectedObjects] count] == 0) return NO;

	if (![treeController commitEditing]) {
		return NO;
	}

	// Currently selected object in tree
	id selectedObject = [[treeController selectedObjects] objectAtIndex:0];

	// If we are selecting a tab view that requires there be a child, make sure there is a child to select.  If not, don't allow it.
	if ([[tabViewItem identifier] isEqualToString:SPGlobalPrivilegesTabIdentifier] ||
		[[tabViewItem identifier] isEqualToString:SPResourcesTabIdentifier] ||
		[[tabViewItem identifier] isEqualToString:SPSchemaPrivilegesTabIdentifier]) {

		id parent = [selectedObject parent];

		retVal = parent ? ([[parent children] count] > 0) : ([[selectedObject children] count] > 0);

		if (!retVal) {

			[NSAlert createDefaultAlertWithTitle:NSLocalizedString(@"User has no hosts", @"user has no hosts message") message:NSLocalizedString(@"This user doesn't have any hosts associated with it. It will be deleted unless one is added", @"user has no hosts informative message") primaryButtonTitle:NSLocalizedString(@"Add Host", @"Add Host") primaryButtonHandler:^{
				[self addHost:nil];
			} cancelButtonHandler:nil];
		}

		// If this is the resources tab, enable or disable the controls based on the server's support for them
		if ([[tabViewItem identifier] isEqualToString:SPResourcesTabIdentifier]) {
			[maxUpdatesTextField setEnabled:YES];
			[maxConnectionsTextField setEnabled:YES];
			[maxQuestionsTextField setEnabled:YES];
		}
	}

	return retVal;
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	if ([[treeController selectedObjects] count] == 0) return;

	id selectedObject = [[treeController selectedObjects] objectAtIndex:0];

	// If the selected tab is General and a child is selected, select the
	// parent (user info).
	if ([[tabViewItem identifier] isEqualToString:SPGeneralTabIdentifier]) {
		if ([selectedObject parent]) {
			[self _selectParentFromSelection];
		}
	}
	else if ([[tabViewItem identifier] isEqualToString:SPGlobalPrivilegesTabIdentifier] ||
			 [[tabViewItem identifier] isEqualToString:SPResourcesTabIdentifier] ||
			 [[tabViewItem identifier] isEqualToString:SPSchemaPrivilegesTabIdentifier]) {
		// If the tab is either Global Privs or Resources and we have a user
		// selected, then open tree and select first child node.
		[self _selectFirstChildOfParentNode];
	}
}

#pragma mark -
#pragma mark Outline view Delegate Methods

- (void)outlineView:(NSOutlineView *)olv willDisplayCell:(NSCell *)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	if ([cell isKindOfClass:[ImageAndTextCell class]])
	{
		// Determines which Image to display depending on parent or child object
		NSImage *image = [NSImage imageNamed:[(SPUserMO *)[item  representedObject] parent] ? NSImageNameNetwork : NSImageNameUser];

		[image setSize:(NSSize){16, 16}];
		[(ImageAndTextCell *)cell setImage:image];
	}
}

- (BOOL)outlineView:(NSOutlineView *)olv isGroupItem:(id)item
{
	return NO;
}

- (BOOL)outlineView:(NSOutlineView *)olv shouldSelectItem:(id)item
{
	return YES;
}

- (BOOL)outlineView:(NSOutlineView *)olv shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	return ([[[item representedObject] children] count] == 0);
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	if ([[treeController selectedObjects] count] == 0) return;

	id selectedObject = [[treeController selectedObjects] objectAtIndex:0];

	if ([selectedObject parent] == nil && !([[[tabView selectedTabViewItem] identifier] isEqualToString:@"General"])) {
		[tabView selectTabViewItemWithIdentifier:SPGeneralTabIdentifier];
	}
	else {
		if ([selectedObject parent] != nil && [[[tabView selectedTabViewItem] identifier] isEqualToString:@"General"]) {
			[tabView selectTabViewItemWithIdentifier:SPGlobalPrivilegesTabIdentifier];
		}
	}

	if ([selectedObject parent] != nil && [selectedObject host] == nil)
	{
		[selectedObject setValue:@"%" forKey:@"host"];
		[outlineView reloadItem:selectedObject];
	}

	[schemasTableView deselectAll:nil];
	[schemasTableView setNeedsDisplay:YES];
	[grantedTableView deselectAll:nil];
	[availableTableView deselectAll:nil];
}

- (BOOL)selectionShouldChangeInOutlineView:(NSOutlineView *)olv {
	id selectedObject = [[treeController selectedObjects] firstObject];
	if (selectedObject) {
		// Check parents
		if ([selectedObject valueForKey:@"parent"] == nil) {
			NSString *name = [selectedObject valueForKey:@"user"];
			NSArray *results = [self _fetchUserWithUserName:name];

			if ([results count] > 1) {
				[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Duplicate User", @"duplicate user message") message:[NSString stringWithFormat:NSLocalizedString(@"A user with the name '%@' already exists", @"duplicate user informative message"), name] callback:nil];
				return NO;
			}
		} else {
			NSArray *children = [selectedObject valueForKeyPath:@"parent.children"];
			NSString *host = [selectedObject valueForKey:@"host"];

			for (NSManagedObject *child in children) {
				if (![selectedObject isEqual:child] && [[child valueForKey:@"host"] isEqualToString:host]) {
					[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Duplicate Host", @"duplicate host message") message:[NSString stringWithFormat:NSLocalizedString(@"A user with the host '%@' already exists", @"duplicate host informative message"), host] callback:nil];
					return NO;
				}
			}
		}
	}
	return YES;
}

#pragma mark - SPUserManagerDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
	return [schemas count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
	NSString *databaseName = [schemas objectAtIndex:rowIndex];
	if ([databaseName isEqualToString:@""]) {
		databaseName = NSLocalizedString(@"All Databases", @"All databases placeholder");
	} else if ([databaseName isEqualToString:@"%"]) {
		databaseName = NSLocalizedString(@"All Databases (%)", @"All databases (%) placeholder");
	}
	return databaseName;
}

#pragma mark -

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
