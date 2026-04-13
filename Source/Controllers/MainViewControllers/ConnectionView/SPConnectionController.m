//
//  SPConnectionController.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on November 15, 2010.
//  Copyright (c) 2010 Stuart Connolly. All rights reserved.
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

#import "SPConnectionController.h"
#import "SPDatabaseDocument.h"
#import "SPAppController.h"
#import "SPPreferenceController.h"
#import "ImageAndTextCell.h"
#import "RegexKitLite.h"
#import "SPKeychain.h"
#import "SPSSHTunnel.h"
#import "SPFileHandle.h"
#import "SPTableTextFieldCell.h"
#import "SPFavoritesController.h"
#import "SPFavoriteNode.h"
#import "SPGeneralPreferencePane.h"
#import "SPTreeNode.h"
#import "SPFavoritesExporter.h"
#import "SPFavoritesImporter.h"
#import "SPThreadAdditions.h"
#import "SPFavoriteColorSupport.h"
#import "SPNamedNode.h"
#import "SPFavoritesOutlineView.h"
#import "SPCategoryAdditions.h"
#import "SPFavoriteTextFieldCell.h"
#import "SPGroupNode.h"
#import "SPSplitView.h"
#import "SPColorSelectorView.h"
#import "SPFunctions.h"
#import "SPBundleHTMLOutputController.h"
#import "SPBundleManager.h"
// AWS IAM Authentication is now implemented in Swift
// See: AWSCredentials.swift, RDSIAMAuthentication.swift, AWSSTSClient.swift, AWSMFATokenDialog.swift, AWSIAMAuthManager.swift

#import <SPMySQL/SPMySQL.h>

#import "sequel-ace-Swift.h"

// Constants
static NSString *SPRemoveNode              = @"RemoveNode";
static NSString *SPExportFavoritesFilename = @"SequelAceFavorites.plist";
static NSString *SPLocalhostAddress        = @"127.0.0.1";

static NSString *SPDatabaseImage           = @"database-small";
static NSString *SPQuickConnectImage       = @"quick-connect-icon.pdf";
static NSString *SPQuickConnectImageWhite  = @"quick-connect-icon-white.pdf";

static NSString *SPConnectionViewNibName   = @"ConnectionView";

const static NSInteger SPUseServerTimeZoneTag = -1;
const static NSInteger SPUseSystemTimeZoneTag = -2;

@interface SPConnectionController ()

// Privately redeclare as read/write to get the synthesized setter
@property (readwrite, assign) BOOL isEditingConnection;
@property (readwrite, assign) BOOL allowSplitViewResizing;
@property (readwrite, assign) BOOL errorShowing;
@property (readwrite, assign) BOOL localNetworkPermissionDeniedForCurrentAttempt;

- (void)_saveCurrentDetailsCreatingNewFavorite:(BOOL)createNewFavorite validateDetails:(BOOL)validateDetails;
- (void)_sortFavorites;
- (void)_sortTreeNode:(SPTreeNode *)node usingKey:(NSString *)key;
- (void)_favoriteTypeDidChange;
- (void)_reloadFavoritesViewData;
- (void)_updateFavoriteFirstResponder;
- (void)_restoreConnectionInterface;
- (void)_selectNode:(SPTreeNode *)node;
- (void)_scrollToSelectedNode;
- (void)_removeNode:(SPTreeNode *)node;
- (void)_removeAllPasswordsForNode:(SPTreeNode *)node;
- (void)_refreshBookmarks;


- (NSNumber *)_createNewFavoriteID;
- (SPTreeNode *)_favoriteNodeForFavoriteID:(NSInteger)favoriteID;
- (NSString *)_stripInvalidCharactersFromString:(NSString *)subject;

- (NSString *)_generateNameForConnection;

- (void)_startEditingConnection;
- (BOOL)_isAWSIAMConnection;
- (void)_syncAWSIAMAndSSLInterfaceState;
- (void)_refreshAWSAvailableRegions;

static NSComparisonResult _compareFavoritesUsingKey(id favorite1, id favorite2, void *key);

#pragma mark - SPConnectionControllerDelegate

- (void)_stopEditingConnection;

#pragma mark - SPConnectionHandlerPrivateAPI

- (void)_showConnectionTestResult:(NSString *)resultString;
- (BOOL)_shouldShowLocalNetworkPermissionAlertForErrorMessage:(NSString *)errorMessage detail:(NSString *)errorDetail;
- (BOOL)_isLocalNetworkAccessDeniedForCurrentConnectionAttempt;
- (void)_failConnectionWithTitle:(NSString *)theTitle errorMessage:(NSString *)theErrorMessage detail:(NSString *)errorDetail localNetworkPermissionDenied:(BOOL)localNetworkPermissionDenied;
- (void)_showLocalNetworkPermissionAlert;
- (BOOL)_openLocalNetworkPrivacySettings;

#pragma mark - SPConnectionControllerInitializer_Private_API

- (void)_processFavoritesDataChange:(NSNotification *)aNotification;
- (void)scrollViewFrameChanged:(NSNotification *)aNotification;

@end

@implementation SPConnectionController

@synthesize delegate;
@synthesize type;
@synthesize name;
@synthesize host;
@synthesize user;
@synthesize password;
@synthesize database;
@synthesize socket;
@synthesize port;
@synthesize colorIndex;
@synthesize timeZoneMode;
@synthesize timeZoneIdentifier;
@synthesize allowDataLocalInfile;
@synthesize enableClearTextPlugin;
@synthesize useAWSIAMAuth;
@synthesize awsRegion;
@synthesize awsProfile;
@synthesize useSSL;
@synthesize sslKeyFileLocationEnabled;
@synthesize sslKeyFileLocation;
@synthesize sslCertificateFileLocationEnabled;
@synthesize sslCertificateFileLocation;
@synthesize sslCACertFileLocationEnabled;
@synthesize sslCACertFileLocation;
@synthesize sshHost;
@synthesize sshUser;
@synthesize sshPassword;
@synthesize sshKeyLocationEnabled;
@synthesize sshKeyLocation;
@synthesize sshPort;
@synthesize useCompression;
@synthesize bookmarks;
@synthesize allowSplitViewResizing;

@synthesize connectionKeychainID = connectionKeychainID;
@synthesize connectionKeychainItemName;
@synthesize connectionKeychainItemAccount;
@synthesize connectionSSHKeychainItemName;
@synthesize connectionSSHKeychainItemAccount;
@synthesize socketHelpWindowUUID;
@synthesize isConnecting;
@synthesize isEditingConnection;
@synthesize errorShowing;

+ (void)initialize {


}

- (NSString *)keychainPassword
{
    NSString *kcItemName = [self connectionKeychainItemName];
    // If no keychain item is available, return an empty password
    if (!kcItemName) return nil;

    // Otherwise, pull the password from the keychain using the details from this connection
    NSString *kcPassword = [keychain getPasswordForName:kcItemName account:[self connectionKeychainItemAccount]];

    return kcPassword;
}

- (NSString *)passwordForConnectionRequest
{
    if ([self _isAWSIAMConnection]) {
        return [self generateAWSIAMAuthToken];
    }

    return [self keychainPassword];
}

/**
 * Generates a fresh AWS IAM authentication token.
 * Called both during initial connection and for token refresh on reconnection.
 * Uses the Swift AWSIAMAuthManager for all AWS operations.
 * Note: Only AWS CLI profiles are supported. Manual credentials are not persisted securely.
 */
- (NSString *)generateAWSIAMAuthTokenWithError:(NSError **)errorPointer
{
    NSInteger dbPort = [[self port] length] ? [[self port] integerValue] : 3306;

    // Get profile name (defaults to "default" if empty)
    NSString *trimmedProfileName = [[self awsProfile] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *profileName = [trimmedProfileName length] > 0 ? trimmedProfileName : @"default";

    NSError *awsError = nil;

    // Use the Swift AWSIAMAuthManager for token generation (profile-based only)
    NSString *token = [AWSIAMAuthManager generateAuthTokenWithHostname:[self host]
                                                                  port:dbPort
                                                              username:[self user]
                                                                region:[self awsRegion]
                                                               profile:profileName
                                                             accessKey:nil
                                                             secretKey:nil
                                                          parentWindow:[dbDocument parentWindowControllerWindow]
                                                                 error:&awsError];

    if (errorPointer) {
        *errorPointer = awsError;
    }

    if (awsError) {
        NSLog(@"AWS IAM Authentication token generation failed: %@", awsError.localizedDescription);
        return nil;
    }

    if (![token length]) {
        if (errorPointer && !*errorPointer) {
            *errorPointer = [NSError errorWithDomain:@"AWSIAMAuthErrorDomain"
                                                code:-1
                                            userInfo:@{
                                                NSLocalizedDescriptionKey: NSLocalizedString(@"Empty authentication token returned", @"AWS IAM empty token error")
                                            }];
        }
        NSLog(@"AWS IAM Authentication token generation failed: empty authentication token returned");
        return nil;
    }

    return token;
}

- (NSString *)generateAWSIAMAuthToken
{
    return [self generateAWSIAMAuthTokenWithError:nil];
}

- (NSString *)keychainPasswordForSSH
{
    if (![self connectionKeychainItemName]) return nil;

    // Otherwise, pull the password from the keychain using the details from this connection
    NSString *kcSSHPassword = [keychain getPasswordForName:connectionSSHKeychainItemName account:connectionSSHKeychainItemAccount];

    return kcSSHPassword;
}

#pragma mark -
#pragma mark Connection processes

-(BOOL)connected{

    SPReachability *reachability = [SPReachability reachabilityForInternetConnection];
    NetworkStatus networkStatus = [reachability currentReachabilityStatus];
    return networkStatus != NotReachable;

}

/**
 * Starts the connection process; invoked when user hits the connect button
 * or double-clicks on a favourite.
 * Error-checks fields as required, and triggers connection of MySQL or any
 * connection proxies in use.
 */
- (IBAction)initiateConnection:(id)sender
{
    // If this action was triggered via a double-click on the favorites outline view,
    // ensure that one of the connections was double-clicked, not the area above or below
    if (sender == favoritesOutlineView && [favoritesOutlineView clickedRow] <= 0) return;

    // If triggered via the "Test Connection" button, set the state - otherwise clear it
    isTestingConnection = (sender == testConnectButton);
    self.localNetworkPermissionDeniedForCurrentAttempt = NO;

    NSFileManager *fileManager = [NSFileManager defaultManager];

    // Ensure that host is not empty if this is a TCP/IP, SSH, or AWS IAM connection
    if (([self type] == SPTCPIPConnection || [self type] == SPSSHTunnelConnection || [self type] == SPAWSIAMConnection) && ![[self host] length]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Insufficient connection details", @"insufficient details message") message:NSLocalizedString(@"Insufficient details provided to establish a connection. Please enter at least the hostname.", @"insufficient details informative message") callback:nil];
        return;
    }

    if ([self _isAWSIAMConnection] && ![self isAWSDirectoryAuthorized]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"AWS Authorization Required", @"AWS authorization required title")
                                     message:NSLocalizedString(@"Authorize access to your ~/.aws directory before testing or connecting with an AWS IAM favorite.", @"AWS authorization required message")
                                    callback:nil];
        return;
    }

    // If SSH is enabled, ensure that the SSH host is not nil
    if ([self type] == SPSSHTunnelConnection && ![[self sshHost] length]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Insufficient connection details", @"insufficient details message") message:NSLocalizedString(@"Insufficient details provided to establish a connection. Please enter the hostname for the SSH Tunnel, or disable the SSH Tunnel.", @"insufficient SSH tunnel details informative message") callback:nil];
        return;
    }

    // If an SSH key has been provided, verify it exists
    if ([self type] == SPSSHTunnelConnection && sshKeyLocationEnabled && sshKeyLocation) {
        if (![fileManager fileExistsAtPath:[sshKeyLocation stringByExpandingTildeInPath]]) {
            [self setSshKeyLocationEnabled:NSControlStateValueOff];
            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"SSH Key not found", @"SSH key check error") message:NSLocalizedString(@"A SSH key location was specified, but no file was found in the specified location.  Please re-select the key and try again.", @"SSH key not found message") callback:nil];
            return;
        }
    }

    // If SSL keys have been supplied, verify they exist
    if (([self type] == SPTCPIPConnection || [self type] == SPSocketConnection) && [self useSSL]) {

        if (sslKeyFileLocationEnabled && sslKeyFileLocation &&
            ![fileManager fileExistsAtPath:[sslKeyFileLocation stringByExpandingTildeInPath]])
        {
            [self setSslKeyFileLocationEnabled:NSControlStateValueOff];
            [self setSslKeyFileLocation:nil];

            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"SSL Key File not found", @"SSL key file check error") message:NSLocalizedString(@"A SSL key file location was specified, but no file was found in the specified location.  Please re-select the key file and try again.", @"SSL key file not found message") callback:nil];
            return;
        }

        if (sslCertificateFileLocationEnabled && sslCertificateFileLocation &&
            ![fileManager fileExistsAtPath:[sslCertificateFileLocation stringByExpandingTildeInPath]])
        {
            [self setSslCertificateFileLocationEnabled:NSControlStateValueOff];
            [self setSslCertificateFileLocation:nil];

            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"SSL Certificate File not found", @"SSL certificate file check error") message:NSLocalizedString(@"A SSL certificate location was specified, but no file was found in the specified location.  Please re-select the certificate and try again.", @"SSL certificate file not found message") callback:nil];
            return;
        }

        if (sslCACertFileLocationEnabled && sslCACertFileLocation &&
            ![fileManager fileExistsAtPath:[sslCACertFileLocation stringByExpandingTildeInPath]])
        {
            [self setSslCACertFileLocationEnabled:NSControlStateValueOff];
            [self setSslCACertFileLocation:nil];

            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"SSL Certificate Authority File not found", @"SSL certificate authority file check error") message:NSLocalizedString(@"A SSL Certificate Authority certificate location was specified, but no file was found in the specified location.  Please re-select the Certificate Authority certificate and try again.", @"SSL CA certificate file not found message") callback:nil];
            return;
        }
    }

    // Basic details have validated - start the connection process animating
    isConnecting = YES;
    cancellingConnection = NO;
    errorShowing = NO;

    // Disable the favorites outline view to prevent further connections attempts
    [favoritesOutlineView setEnabled:NO];

    [helpButton setHidden:YES];
    [connectButton setEnabled:NO];
    [testConnectButton setEnabled:NO];
    [progressIndicator startAnimation:self];
    [progressIndicatorText setHidden:NO];

    // Start the current tab's progress indicator
    [dbDocument setIsProcessing:YES];

    // If the password(s) are marked as having been originally sourced from a keychain, check whether they
    // have been changed or not; if not, leave the mark in place and remove the password from the field
    // for increased security.
    if (connectionKeychainItemName && !isTestingConnection) {
        if ([[keychain getPasswordForName:connectionKeychainItemName account:connectionKeychainItemAccount] isEqualToString:[self password]]) {
            [self setPassword:@"SequelAceSecretPassword"];

            [[standardPasswordField undoManager] removeAllActionsWithTarget:standardPasswordField];
            [[socketPasswordField undoManager] removeAllActionsWithTarget:socketPasswordField];
            [[sshPasswordField undoManager] removeAllActionsWithTarget:sshPasswordField];
        }
    }

    if (connectionSSHKeychainItemName && !isTestingConnection) {
        if ([[keychain getPasswordForName:connectionSSHKeychainItemName account:connectionSSHKeychainItemAccount] isEqualToString:[self sshPassword]]) {
            [self setSshPassword:@"SequelAceSecretPassword"];
            [[sshSSHPasswordField undoManager] removeAllActionsWithTarget:sshSSHPasswordField];
        }
    }

    // Inform the delegate that we are starting the connection process
    if (delegate && [delegate respondsToSelector:@selector(connectionControllerInitiatingConnection:)]) {
        [delegate connectionControllerInitiatingConnection:self];
    }

    // Trim whitespace and newlines from the host field before attempting to connect
    [self setHost:[[self host] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];

    // For SSH connections, validate the config file before proceeding
    if ([self type] == SPSSHTunnelConnection) {
        [self setSshHost:[[self sshHost] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
        if (![self _validateSSHConfigFile]) {
            return;
        }
    }

    // Resolve passwords (handles keychain marker and AWS IAM token)
    NSString *resolvedPassword = [self _resolvedMySQLPassword];
    if (!resolvedPassword) return; // AWS IAM error already shown

    NSString *resolvedSSHPassword = [self _resolvedSSHPassword];

    // Build connection info and preferences
    SAConnectionInfoObjC *info = [self _buildConnectionInfo];
    SAConnectionPreferences *preferences = [SAConnectionPreferences fromUserDefaults];

    // Update progress text
    if (isTestingConnection) {
        [progressIndicatorText setStringValue:([self type] == SPSSHTunnelConnection)
            ? NSLocalizedString(@"Testing SSH...", @"testing SSH status message")
            : NSLocalizedString(@"Testing MySQL...", @"testing MySQL status message")];
    } else {
        [progressIndicatorText setStringValue:([self type] == SPSSHTunnelConnection)
            ? NSLocalizedString(@"SSH connecting...", @"SSH connecting status message")
            : NSLocalizedString(@"MySQL connecting...", @"MySQL connecting status message")];
    }

    // Change Connect button to Cancel
    [connectButton setTitle:NSLocalizedString(@"Cancel", @"cancel button")];
    [connectButton setAction:@selector(cancelConnection:)];
    [connectButton setEnabled:YES];
    [connectButton display];

    // Connect via service (async — completion called on main thread)
    __weak __kindof SPConnectionController *weakSelf = self;
    [self.connectionService connectWith:info
                            preferences:preferences
                               password:resolvedPassword
                            sshPassword:resolvedSSHPassword
                           parentWindow:[dbDocument parentWindowControllerWindow]
                             completion:^(SAConnectionResult *result) {
        SPConnectionController *strongSelf = weakSelf;
        if (!strongSelf) return;

        // User cancelled (e.g. SSH password prompt) — silently restore UI
        if (result.userCancelled) {
            [strongSelf _restoreConnectionInterface];
            return;
        }

        // Store connection/tunnel on controller ivars for cancelConnection: etc.
        strongSelf->mySQLConnection = result.connection;
        if (result.sshTunnel) {
            strongSelf->sshTunnel = result.sshTunnel;
        } else if (strongSelf.connectionService.activeTunnel) {
            strongSelf->sshTunnel = strongSelf.connectionService.activeTunnel;
        }

        if (result.databaseSelectionFailed) {
            if (strongSelf->isTestingConnection) {
                [strongSelf cancelConnection:nil];
                [strongSelf _showConnectionTestResult:NSLocalizedString(@"Invalid database", @"Invalid database very short status message")];
            } else {
                [strongSelf failConnectionWithTitle:NSLocalizedString(@"Unable to connect", @"connection failed title")
                                 errorMessage:[NSString stringWithFormat:NSLocalizedString(@"Connected but unable to select database '%@'.", @"message when database selection fails"), info.database]
                                       detail:result.databaseSelectionError];
            }
            return;
        }

        if (!result.isSuccess) {
            BOOL localNetworkDenied = result.isLocalNetworkDenied || [strongSelf _isLocalNetworkAccessDeniedForCurrentConnectionAttempt];
            // Use SSH debug messages as detail when available (for tunnel failures),
            // falling back to the result's errorDetail
            NSString *failDetail = (result.sshDebugMessages.length > 0)
                ? result.sshDebugMessages
                : result.errorDetail;
            [strongSelf _failConnectionWithTitle:result.errorTitle ?: @""
                              errorMessage:result.errorMessage
                                    detail:failDetail
                   localNetworkPermissionDenied:localNetworkDenied];
            return;
        }

        // Success — delegate to existing handler
        [strongSelf mySQLConnectionEstablished];
    }];
}

/**
 * Cancels the current connection - both SSH and MySQL.
 */
- (IBAction)cancelConnection:(id)sender
{
    [connectButton setEnabled:NO];

    [progressIndicatorText setStringValue:NSLocalizedString(@"Cancelling...", @"cancelling task status message")];
    [progressIndicatorText display];

    cancellingConnection = YES;

    // Cancel via connection service (handles both MySQL and SSH tunnel)
    [self.connectionService cancel];

    // Also clean up any locally-held references
    if (mySQLConnection) {
        [mySQLConnection setDelegate:nil];
        mySQLConnection = nil;
    }
    sshTunnel = nil;

    // Restore the connection interface
    [self _restoreConnectionInterface];
}

- (BOOL)isConnectedViaSSL {
    return [mySQLConnection isConnectedViaSSL];
}

#pragma mark -
#pragma mark Interface interaction

/**
 * Registered to be the double click action of the favorites outline view.
 */
- (void)nodeDoubleClicked:(id)sender
{
    SPTreeNode *node = [favoritesOutlineView itemForDoubleAction];

    if (node) {
        if (node == quickConnectItem) {
            return;
        }

        // Only proceed to initiate a connection if a leaf node (i.e. a favorite and not a group) was double clicked.
        if (![node isGroup]) {
            [self initiateConnection:self];
        }

        // Otherwise start editing the group node's name
        else {
            [favoritesOutlineView editColumn:0 row:[favoritesOutlineView selectedRow] withEvent:nil select:YES];
        }
    }
}

/**
 * Opens the SSH/SSL key selection window, ready to select a key file.
 */
- (IBAction)chooseKeyLocation:(NSButton *)sender
{
    NSView *accessoryView = nil;

    // If the button was toggled off, ensure editing is ended
    if ([sender state] == NSControlStateValueOff) {
        [self _startEditingConnection];
    }

    // Switch details by sender.
    // First, SSH keys:
    if (sender == sshSSHKeyButton) {

        // If the custom key location is currently disabled - after the button
        // action - leave it disabled and return without showing the sheet.
        if (!sshKeyLocationEnabled) {
            [self setSshKeyLocation:nil];
            return;
        }

        accessoryView = sshKeyLocationHelp;
    }
    // SSL key file location:
    else if (sender == standardSSLKeyFileButton || sender == socketSSLKeyFileButton || sender == sslOverSSHKeyFileButton) {
        if ([sender state] == NSControlStateValueOff) {
            [self setSslKeyFileLocation:nil];
            return;
        }

        accessoryView = sslKeyFileLocationHelp;
    }
    // SSL certificate file location:
    else if (sender == standardSSLCertificateButton || sender == socketSSLCertificateButton || sender == sslOverSSHCertificateButton) {
        if ([sender state] == NSControlStateValueOff) {
            [self setSslCertificateFileLocation:nil];
            return;
        }

        accessoryView = sslCertificateLocationHelp;
    }
    // SSL CA certificate file location:
    else if (sender == standardSSLCACertButton || sender == socketSSLCACertButton || sender == sslOverSSHCACertButton) {
        if ([sender state] == NSControlStateValueOff) {
            [self setSslCACertFileLocation:nil];
            return;
        }

        accessoryView = sslCACertLocationHelp;
    }

    keySelectionPanel = [NSOpenPanel openPanel]; // retain/release needed on OS X ≤ 10.6 according to Apple doc

    [keySelectionPanel setCanChooseFiles:YES];
    [keySelectionPanel setCanChooseDirectories:YES];
    [keySelectionPanel setCanCreateDirectories:YES];

    [keySelectionPanel setShowsHiddenFiles:[prefs boolForKey:SPHiddenKeyFileVisibilityKey]];
    [keySelectionPanel setAccessoryView:accessoryView];
    //on os x 10.11+ the accessory view will be hidden by default and has to be made visible
    if(accessoryView && [keySelectionPanel respondsToSelector:@selector(setAccessoryViewDisclosed:)]) {
        [keySelectionPanel setAccessoryViewDisclosed:YES];
    }
    [keySelectionPanel setDelegate:self];
    [keySelectionPanel beginSheetModalForWindow:[dbDocument parentWindowControllerWindow] completionHandler:^(NSInteger returnCode){

        NSString *selectedFilePath=[[self->keySelectionPanel URL] path];
        NSError *err=nil;

        NSMutableString *classStr = [NSMutableString string];
        [classStr appendStringOrNil:NSStringFromClass(self->keySelectionPanel.URL.class)];

        SPLog(@"self->keySelectionPanel.URL.class: %@", classStr);

        // check it's really a URL
        if(![self->keySelectionPanel.URL isKindOfClass:[NSURL class]]){

            SPLog(@"self->keySelectionPanel.URL is not a valid URL: %@", classStr);

            NSView __block *helpView;

            SPMainQSync(^{
                // call windowDidLoad to alloc the panes
                [[SPAppDelegate preferenceController] window];
                helpView = [[[SPAppDelegate preferenceController] generalPreferencePane] modifyAndReturnBookmarkHelpView];
            });

            NSString *alertMessage = [NSString stringWithFormat:NSLocalizedString(@"The selected file is not a valid file.\n\nPlease try again.\n\nClass: %@", @"error while selecting file message"),
                                      classStr];

            [NSAlert createAccessoryWarningAlertWithTitle:NSLocalizedString(@"File Selection Error", @"error while selecting file message") message:alertMessage accessoryView:helpView callback:^{

                NSDictionary *userInfo = @{
                    NSLocalizedDescriptionKey: @"self->keySelectionPanel.URL is not a valid URL",
                    @"func": [NSString stringWithFormat:@"%s", __PRETTY_FUNCTION__],
                    @"class": classStr
                };

                SPLog(@"userInfo: %@", userInfo);
            }];
        }
        else{
            SPLog(@"calling addBookmarkForUrl");
            // this needs to be read-only to handle keys with 400 perms so we add the bitwise OR NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess
            if([SecureBookmarkManager.sharedInstance addBookmarkForUrl:self->keySelectionPanel.URL options:(NSURLBookmarkCreationWithSecurityScope|NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess) isForStaleBookmark:NO isForKnownHostsFile:NO] == YES){
                SPLog(@"addBookmarkForUrl success");
            }
            else{
                SPLog(@"addBookmarkForUrl failed");
                // JCS - should we stop here?
                // No just the act of selecting the file in the NSOpenPanel calls startAccessingSecurityScopedResource
                // the only downside of this failing is that we won't have a bookmark,
                // and therefore no access on the next app start
            }
        }

        // SSH key file selection
        if (sender == self->sshSSHKeyButton) {
            if (returnCode == NSModalResponseCancel) {
                [self setSshKeyLocationEnabled:NSControlStateValueOff];
                [self setSshKeyLocation:nil];
                return;
            }

            [self setSshKeyLocation:selectedFilePath];
        }
        // SSL key file selection
        else if (sender == self->standardSSLKeyFileButton || sender == self->socketSSLKeyFileButton || sender == self->sslOverSSHKeyFileButton) {
            if (returnCode == NSModalResponseCancel) {
                [self setSslKeyFileLocationEnabled:NSControlStateValueOff];
                [self setSslKeyFileLocation:nil];
                return;
            }

            if( [self validateKeyFile:self->keySelectionPanel.URL error:&err] == NO ){
                NSLog(@"Problem with key file - %@ : %@",[err localizedDescription], [err localizedRecoverySuggestion]);
                [self showValidationAlertForError:err];
                return; // don't copy the bad key
            }

            [self setSslKeyFileLocation:selectedFilePath];
        }
        // SSL certificate file selection
        else if (sender == self->standardSSLCertificateButton || sender == self->socketSSLCertificateButton || sender == self->sslOverSSHCertificateButton) {
            if (returnCode == NSModalResponseCancel) {
                [self setSslCertificateFileLocationEnabled:NSControlStateValueOff];
                [self setSslCertificateFileLocation:nil];
                return;
            }

            if( [self validateCertFile:self->keySelectionPanel.URL error:&err] == NO ){
                NSLog(@"Problem with cert file - %@ : %@",[err localizedDescription], [err localizedRecoverySuggestion]);
                [self showValidationAlertForError:err];
                return; // don't copy the bad cert
            }

            [self setSslCertificateFileLocation:selectedFilePath];
        }
        // SSL CA certificate file selection
        else if (sender == self->standardSSLCACertButton || sender == self->socketSSLCACertButton || sender == self->sslOverSSHCACertButton) {
            if (returnCode == NSModalResponseCancel) {
                [self setSslCACertFileLocationEnabled:NSControlStateValueOff];
                [self setSslCACertFileLocation:nil];
                return;
            }

            [self setSslCACertFileLocation:selectedFilePath];
        }

        [self _startEditingConnection];
    }];
}

-(void)showValidationAlertForError:(NSError*)err{

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [err localizedDescription];
    alert.informativeText = [err localizedRecoverySuggestion];
    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
    [alert beginSheetModalForWindow:[dbDocument parentWindowControllerWindow] completionHandler:nil];
}

-(BOOL)validateKeyFile:(NSURL *)url error:(NSError **)outError{

    NSError *err = nil;
    NSData *file = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&err];
    if(err) {
        *outError = err;
        return NO;
    }

    NSString *stringFromData = [[NSString alloc] initWithData:file encoding:NSASCIIStringEncoding];

    // SEE: https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Strings/Articles/stringsParagraphBreaks.html#//apple_ref/doc/uid/TP40005016-SW3
    // need to handle \n, \r, \r\n,

    BOOL __block foundValidFirstLine = NO;
    BOOL __block foundValidLastLine = NO;

    if(stringFromData){
        NSRange range = NSMakeRange(0, stringFromData.length);

        [stringFromData enumerateSubstringsInRange:range
                                           options:NSStringEnumerationByParagraphs
                                        usingBlock:^(NSString * _Nullable paragraph, NSRange paragraphRange, NSRange enclosingRange, BOOL * _Nonnull stop) {

            if ([paragraph containsString:@"PRIVATE KEY-----"] && [paragraph containsString:@"-----BEGIN"]) {
                foundValidFirstLine = YES;
            }
            if ([paragraph containsString:@"PRIVATE KEY-----"] && [paragraph containsString:@"-----END"]) {
                foundValidLastLine = YES;
            }
        }];
    }

    if(foundValidFirstLine == YES && foundValidLastLine == YES){
        return YES;
    }
    else{
        *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedString(@"“%@” is not a valid private key file.", @"connection view : ssl : key file picker : wrong format error title"),[url lastPathComponent]],
            NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Make sure the file contains a RSA private key and is using PEM encoding.", @"connection view : ssl : key file picker : wrong format error description"),
            NSURLErrorKey: url
        }];

        return NO;
    }
}

-(BOOL)validateCertFile:(NSURL *)url error:(NSError **)outError{

    NSError *err = nil;
    NSData *file = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&err];
    if(err) {
        *outError = err;
        return NO;
    }

    NSString *stringFromData = [[NSString alloc] initWithData:file encoding:NSASCIIStringEncoding];

    // SEE: https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Strings/Articles/stringsParagraphBreaks.html#//apple_ref/doc/uid/TP40005016-SW3
    // need to handle \n, \r, \r\n,

    BOOL __block foundValidFirstLine = NO;
    BOOL __block foundValidLastLine = NO;

    if(stringFromData){
        NSRange range = NSMakeRange(0, stringFromData.length);

        [stringFromData enumerateSubstringsInRange:range
                                           options:NSStringEnumerationByParagraphs
                                        usingBlock:^(NSString * _Nullable paragraph, NSRange paragraphRange, NSRange enclosingRange, BOOL * _Nonnull stop) {

            if ([paragraph containsString:@"CERTIFICATE-----"] && [paragraph containsString:@"-----BEGIN"]) {
                foundValidFirstLine = YES;
            }
            if ([paragraph containsString:@"CERTIFICATE-----"] && [paragraph containsString:@"-----END"]) {
                foundValidLastLine = YES;
            }
        }];
    }

    if(foundValidFirstLine == YES && foundValidLastLine == YES){
        return YES;
    }
    else{

        *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedString(@"“%@” is not a valid client certificate file.", @"connection view : ssl : client cert file picker : wrong format error title"),[url lastPathComponent]],
            NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Make sure the file contains a X.509 client certificate and is using PEM encoding.", @"connection view : ssl : client cert picker : wrong format error description"),
            NSURLErrorKey: url
        }];

        return NO;
    }
}

// quick check to stop users selecting .pub files
- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url{
    if([url.pathExtension isEqualToString:@"pub"]){
        return NO;
    }
    return YES;
}

- (BOOL)panel:(id)sender validateURL:(NSURL *)url error:(NSError **)outError
{

    // see https://developer.apple.com/documentation/foundation/nsurl/1410597-checkresourceisreachableandretur?language=objc
    // If your app must perform operations on the file, such as opening it or copying resource properties,
    //it is more efficient to attempt the operation and handle any failure that may occur.

    //unknown, accept by default
    return YES;

    /* And now, an intermission from the mysql source code:

  if (!cert_file &&  key_file)
     cert_file= key_file;

  if (!key_file &&  cert_file)
     key_file= cert_file;

     */
}

/**
 * Show connection help webpage.
 */
- (IBAction)showHelp:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:SPLOCALIZEDURL_CONNECTIONHELP]];
}

/**
 * Resize parts of the interface to reflect SSL status.
 */
- (IBAction)updateSSLInterface:(id)sender
{
    [self _startEditingConnection];

    [self _syncAWSIAMAndSSLInterfaceState];
    [self resizeTabViewToConnectionType:[self type] animating:YES];
}

/**
 * Toggle hidden file visiblity in response to accessory view changes
 */
- (IBAction)updateKeyLocationFileVisibility:(id)sender
{
    [keySelectionPanel setShowsHiddenFiles:[prefs boolForKey:SPHiddenKeyFileVisibilityKey]];
}

- (IBAction)updateClearTextPlugin:(id)sender
{
    [self _startEditingConnection];
}

- (BOOL)_isAWSIAMConnection
{
    return [self type] == SPAWSIAMConnection;
}

- (void)_syncAWSIAMAndSSLInterfaceState
{
    BOOL isTCPIPConnection = ([self type] == SPTCPIPConnection);
    BOOL isAWSIAMConnection = [self _isAWSIAMConnection];
    BOOL isAWSDirectoryAuthorized = [self isAWSDirectoryAuthorized];
    BOOL showAWSAuthorizationPrompt = (isAWSIAMConnection && !isAWSDirectoryAuthorized);
    BOOL showAWSProfileRegionSelectors = (isAWSIAMConnection && isAWSDirectoryAuthorized);

    // IAM connections always use TLS internally, so manual SSL settings are disabled for that mode.
    if (isAWSIAMConnection && [self useSSL]) {
        [self setUseSSL:NSControlStateValueOff];
    }

    if (standardConnectionSSLDetailsContainer) {
        [standardConnectionSSLDetailsContainer setHidden:(!isTCPIPConnection || ![self useSSL])];
    }

    if (awsIAMPasswordField) {
        [awsIAMPasswordField setEnabled:NO];
        [awsIAMPasswordField setStringValue:@""];
        [awsIAMPasswordField setPlaceholderString:NSLocalizedString(@"Generated from AWS IAM profile", @"placeholder when AWS IAM auth is enabled")];
    }

    if (standardPasswordField) {
        [standardPasswordField setEnabled:YES];
        [standardPasswordField setPlaceholderString:@""];
    }

    if (awsAuthorizeButton) {
        [awsAuthorizeButton setHidden:!showAWSAuthorizationPrompt];
    }

    if (awsAuthorizeInfoLabel) {
        [awsAuthorizeInfoLabel setHidden:!showAWSAuthorizationPrompt];
    }

    if (awsProfileLabel) {
        [awsProfileLabel setHidden:!isAWSIAMConnection];
    }

    if (awsProfilePopup) {
        [awsProfilePopup setHidden:!showAWSProfileRegionSelectors];
    }

    if (awsRegionLabel) {
        [awsRegionLabel setHidden:!showAWSProfileRegionSelectors];
    }

    if (awsRegionComboBox) {
        [awsRegionComboBox setHidden:!showAWSProfileRegionSelectors];
    }
}

#pragma mark -
#pragma mark AWS IAM Authentication

/**
 * Called when AWS IAM authentication settings are changed
 */
- (IBAction)updateAWSIAMInterface:(id)sender
{
    [self _startEditingConnection];

    [self _syncAWSIAMAndSSLInterfaceState];
    [self resizeTabViewToConnectionType:[self type] animating:YES];
}

/**
 * Returns available AWS profiles from ~/.aws/credentials
 */
- (NSArray<NSString *> *)awsAvailableProfiles
{
    return [AWSIAMAuthManager availableProfiles];
}

/**
 * Check if AWS directory access is authorized (for sandbox support)
 */
- (BOOL)isAWSDirectoryAuthorized
{
    return [AWSDirectoryBookmarkManager.shared isAWSDirectoryAuthorized];
}

/**
 * Opens NSOpenPanel to authorize access to ~/.aws directory
 */
- (IBAction)authorizeAWSDirectory:(id)sender
{
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setCanChooseFiles:NO];
    [openPanel setCanChooseDirectories:YES];
    [openPanel setAllowsMultipleSelection:NO];
    [openPanel setCanCreateDirectories:NO];
    [openPanel setShowsHiddenFiles:YES];
    [openPanel setMessage:NSLocalizedString(@"Select your .aws directory to enable AWS IAM authentication", @"AWS directory selection message")];
    [openPanel setPrompt:NSLocalizedString(@"Authorize", @"AWS directory authorize button")];

    // Start at the home directory
    NSString *homeDirectory = NSHomeDirectory();
    [openPanel setDirectoryURL:[NSURL fileURLWithPath:homeDirectory]];

    [openPanel beginSheetModalForWindow:[dbDocument parentWindowControllerWindow] completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSURL *selectedURL = [openPanel URL];

            // Verify the selected directory is the .aws folder or contains aws files
            NSString *selectedPath = [selectedURL path];
            BOOL isValidAWSDirectory = NO;

            if ([selectedPath hasSuffix:@".aws"]) {
                isValidAWSDirectory = YES;
            } else {
                // Check if it contains credentials or config file
                NSFileManager *fm = [NSFileManager defaultManager];
                if ([fm fileExistsAtPath:[selectedPath stringByAppendingPathComponent:@"credentials"]] ||
                    [fm fileExistsAtPath:[selectedPath stringByAppendingPathComponent:@"config"]]) {
                    isValidAWSDirectory = YES;
                }
            }

            if (!isValidAWSDirectory) {
                NSAlert *alert = [[NSAlert alloc] init];
                [alert setMessageText:NSLocalizedString(@"Invalid AWS Directory", @"Invalid AWS directory alert title")];
                [alert setInformativeText:NSLocalizedString(@"Please select the .aws directory in your home folder (usually ~/.aws). This directory should contain your AWS credentials and/or config files.", @"Invalid AWS directory alert message")];
                [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
                [alert setAlertStyle:NSAlertStyleWarning];
                [alert runModal];
                return;
            }

            // Add the bookmark
            if ([AWSDirectoryBookmarkManager.shared addAWSDirectoryBookmarkFrom:selectedURL]) {
                SPLog(@"Successfully authorized AWS directory access");

                // Trigger KVO updates for bindings
                [self willChangeValueForKey:@"isAWSDirectoryAuthorized"];
                [self didChangeValueForKey:@"isAWSDirectoryAuthorized"];
                [self willChangeValueForKey:@"awsAvailableProfiles"];
                [self didChangeValueForKey:@"awsAvailableProfiles"];

                // Post notification
                [[NSNotificationCenter defaultCenter] postNotificationName:@"AWSDirectoryAuthorizationChanged" object:self];
            } else {
                NSAlert *alert = [[NSAlert alloc] init];
                [alert setMessageText:NSLocalizedString(@"Authorization Failed", @"AWS authorization failed alert title")];
                [alert setInformativeText:NSLocalizedString(@"Failed to create a secure bookmark for the AWS directory. Please try again.", @"AWS authorization failed alert message")];
                [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
                [alert setAlertStyle:NSAlertStyleWarning];
                [alert runModal];
            }
        }
    }];
}

/**
 * Update UI elements based on AWS directory authorization state
 */
- (void)updateAWSAuthorizationUI
{
    // Trigger KVO updates for bindings
    [self willChangeValueForKey:@"isAWSDirectoryAuthorized"];
    [self didChangeValueForKey:@"isAWSDirectoryAuthorized"];

    [self _syncAWSIAMAndSSLInterfaceState];
}

/**
 * Refreshes AWS regions from AWS public metadata with a fallback cache/list.
 * The async callback updates the bound combo box values via KVO.
 */
- (void)_refreshAWSAvailableRegions
{
    [AWSIAMAuthManager refreshAWSRegionsIfNeededWithCompletion:^(NSArray<NSString *> *regions) {
        if (!regions || !regions.count) return;
        if ([awsAvailableRegionValues isEqualToArray:regions]) return;

        NSString *currentRegion = [[self awsRegion] copy];

        [self willChangeValueForKey:@"awsAvailableRegions"];
        awsAvailableRegionValues = [regions copy];
        [self didChangeValueForKey:@"awsAvailableRegions"];

        if (awsRegionComboBox) {
            [awsRegionComboBox reloadData];
        }

        if ([currentRegion length]) {
            [self setAwsRegion:currentRegion];
        }
    }];
}

/**
 * Returns AWS region identifiers for the IAM region picker.
 */
- (NSArray<NSString *> *)awsAvailableRegions
{
    return awsAvailableRegionValues ?: [AWSIAMAuthManager cachedOrFallbackRegions];
}

#pragma mark -
#pragma mark Connection details interaction and display

/**
 * Control tab view resizing based on the supplied connection type,
 * with an option defining whether it should be animated or not.
 */
- (void)resizeTabViewToConnectionType:(NSUInteger)theType animating:(BOOL)animate
{
    NSRect frameRect, targetResizeRect;

    // Use a magic number which needs to be added to the form when calculating resizes -
    // including the height of the button areas below.
    NSInteger additionalFormHeight = 92;

    frameRect = [connectionResizeContainer frame];

    switch (theType) {
        case SPTCPIPConnection:
            targetResizeRect = [standardConnectionFormContainer frame];
            if ([self useSSL]) {
                additionalFormHeight += [standardConnectionSSLDetailsContainer frame].size.height;
            }
            break;
        case SPAWSIAMConnection:
            targetResizeRect = [awsIAMConnectionFormContainer frame];
            // IAM only has one security checkbox and a helper message at the bottom.
            // Use a smaller footer area to keep its vertical density aligned with the other tabs.
            additionalFormHeight = 29;
            break;
        case SPSocketConnection:
            targetResizeRect = [socketConnectionFormContainer frame];
            if ([self useSSL]) additionalFormHeight += [socketConnectionSSLDetailsContainer frame].size.height;
            break;
        case SPSSHTunnelConnection:
            targetResizeRect = [sshConnectionFormContainer frame];
            if ([self useSSL]) additionalFormHeight += [sshConnectionSSLDetailsContainer frame].size.height;
            break;
    }

    frameRect.size.height = targetResizeRect.size.height + additionalFormHeight;

    if (animate && initComplete) {
        [[connectionResizeContainer animator] setFrame:frameRect];
    }
    else {
        [connectionResizeContainer setFrame:frameRect];
    }

    // Re-apply scroll layout after every details resize to avoid clipped top rows in small windows.
    [self scrollViewFrameChanged:nil];
}

#pragma mark -
#pragma mark Favorites interaction

/**
 * Sorts the favorites table view based on the selected sort by item.
 */
- (void)sortFavorites:(id)sender
{
    SPFavoritesSortItem previousSortItem = currentSortItem;
    currentSortItem  = (SPFavoritesSortItem)[[sender menu] indexOfItem:sender];

    [prefs setInteger:currentSortItem forKey:SPFavoritesSortedBy];

    // Perform sorting
    [self _sortFavorites];

    if (previousSortItem > SPFavoritesSortUnsorted) [[[sender menu] itemAtIndex:previousSortItem] setState:NSControlStateValueOff];

    [[[sender menu] itemAtIndex:currentSortItem] setState:NSControlStateValueOn];
}

/**
 * Reverses the favorites table view sorting based on the selected criteria.
 */
- (void)reverseSortFavorites:(NSMenuItem *)sender
{
    reverseFavoritesSort = (![sender state]);

    [prefs setBool:reverseFavoritesSort forKey:SPFavoritesSortedInReverse];

    // Perform re-sorting
    [self _sortFavorites];

    [sender setState:reverseFavoritesSort];
}

/**
 * Sets fields for the chosen favorite.
 */
- (void)updateFavoriteSelection:(id)sender
{

    // Clear the keychain referral items as appropriate
    [self setConnectionKeychainID:nil];

    SPTreeNode *node = [self selectedFavoriteNode];
    if ([node isGroup]) node = nil;

    // Update key-value properties from the selected favourite, using empty strings where not found
    NSDictionary *fav = [[node representedObject] nodeFavorite];

    // Keep a copy of the favorite as it currently stands
    currentFavorite = [fav copy];

    [connectionResizeContainer setHidden:NO];
    [self _stopEditingConnection];

    // Set up the type, also storing it in the previous type store to prevent type "changes" triggering actions
    NSUInteger connectionType = ([fav objectForKey:SPFavoriteTypeKey] ? [[fav objectForKey:SPFavoriteTypeKey] integerValue] : SPTCPIPConnection);
    previousType = connectionType;
    [self setType:connectionType];

    // Standard details
    [self setName:([fav objectForKey:SPFavoriteNameKey] ? [fav objectForKey:SPFavoriteNameKey] : @"")];
    [self setHost:([fav objectForKey:SPFavoriteHostKey] ? [fav objectForKey:SPFavoriteHostKey] : @"")];
    [self setSocket:([fav objectForKey:SPFavoriteSocketKey] ? [fav objectForKey:SPFavoriteSocketKey] : @"")];
    [self setUser:([fav objectForKey:SPFavoriteUserKey] ? [fav objectForKey:SPFavoriteUserKey] : @"")];
    [self setColorIndex:([fav objectForKey:SPFavoriteColorIndexKey]? [[fav objectForKey:SPFavoriteColorIndexKey] integerValue] : -1)];
    [self setPort:([fav objectForKey:SPFavoritePortKey] ? [fav objectForKey:SPFavoritePortKey] : @"")];
    [self setDatabase:([fav objectForKey:SPFavoriteDatabaseKey] ? [fav objectForKey:SPFavoriteDatabaseKey] : @"")];
    [self setUseCompression:([fav objectForKey:SPFavoriteUseCompressionKey] ? [[fav objectForKey:SPFavoriteUseCompressionKey] boolValue] : YES)];

    // Time Zone details
    switch ([fav objectForKey:SPFavoriteTimeZoneModeKey] ? [[fav objectForKey:SPFavoriteTimeZoneModeKey] intValue] : SPConnectionTimeZoneModeUseServerTZ) {
        case SPConnectionTimeZoneModeUseSystemTZ: {
            [standardTimeZoneField selectItemWithTag:SPUseSystemTimeZoneTag];
            [awsIAMTimeZoneField selectItemWithTag:SPUseSystemTimeZoneTag];
            [socketTimeZoneField selectItemWithTag:SPUseSystemTimeZoneTag];
            [sshTimeZoneField selectItemWithTag:SPUseSystemTimeZoneTag];
            [self setTimeZoneMode:SPConnectionTimeZoneModeUseSystemTZ];
            [self setTimeZoneIdentifier:@""];
            break;
        }
        case SPConnectionTimeZoneModeUseFixedTZ: {
            NSString *tzIdentifier = [fav objectForKey:SPFavoriteTimeZoneIdentifierKey];
            [standardTimeZoneField selectItemWithTitle:tzIdentifier];
            [awsIAMTimeZoneField selectItemWithTitle:tzIdentifier];
            [socketTimeZoneField selectItemWithTitle:tzIdentifier];
            [sshTimeZoneField selectItemWithTitle:tzIdentifier];
            [self setTimeZoneMode:SPConnectionTimeZoneModeUseFixedTZ];
            [self setTimeZoneIdentifier:tzIdentifier];
            break;
        }
        default: {
            [standardTimeZoneField selectItemWithTag:SPUseServerTimeZoneTag];
            [awsIAMTimeZoneField selectItemWithTag:SPUseServerTimeZoneTag];
            [socketTimeZoneField selectItemWithTag:SPUseServerTimeZoneTag];
            [sshTimeZoneField selectItemWithTag:SPUseServerTimeZoneTag];
            [self setTimeZoneMode:SPConnectionTimeZoneModeUseServerTZ];
            [self setTimeZoneIdentifier:@""];
            break;
        }
    }

    //Special prefs
    [self setAllowDataLocalInfile:([fav objectForKey:SPFavoriteAllowDataLocalInfileKey] ? [[fav objectForKey:SPFavoriteAllowDataLocalInfileKey] intValue] : NSControlStateValueOff)];

    // Clear text plugin
    [self setEnableClearTextPlugin:([fav objectForKey:SPFavoriteEnableClearTextPluginKey] ? [[fav objectForKey:SPFavoriteEnableClearTextPluginKey] intValue] : NSControlStateValueOff)];

    // AWS IAM Authentication (profile-based only - manual credentials not supported)
    [self setUseAWSIAMAuth:([self type] == SPAWSIAMConnection ? NSControlStateValueOn : NSControlStateValueOff)];
    [self setAwsRegion:([fav objectForKey:SPFavoriteAWSRegionKey] ? [fav objectForKey:SPFavoriteAWSRegionKey] : @"")];
    [self setAwsProfile:([fav objectForKey:SPFavoriteAWSProfileKey] ? [fav objectForKey:SPFavoriteAWSProfileKey] : @"default")];

    // SSL details
    [self setUseSSL:([fav objectForKey:SPFavoriteUseSSLKey] ? [[fav objectForKey:SPFavoriteUseSSLKey] intValue] : NSControlStateValueOff)];
    [self setSslKeyFileLocationEnabled:([fav objectForKey:SPFavoriteSSLKeyFileLocationEnabledKey] ? [[fav objectForKey:SPFavoriteSSLKeyFileLocationEnabledKey] intValue] : NSControlStateValueOff)];
    [self setSslKeyFileLocation:([fav objectForKey:SPFavoriteSSLKeyFileLocationKey] ? [fav objectForKey:SPFavoriteSSLKeyFileLocationKey] : @"")];
    [self setSslCertificateFileLocationEnabled:([fav objectForKey:SPFavoriteSSLCertificateFileLocationEnabledKey] ? [[fav objectForKey:SPFavoriteSSLCertificateFileLocationEnabledKey] intValue] : NSControlStateValueOff)];
    [self setSslCertificateFileLocation:([fav objectForKey:SPFavoriteSSLCertificateFileLocationKey] ? [fav objectForKey:SPFavoriteSSLCertificateFileLocationKey] : @"")];
    [self setSslCACertFileLocationEnabled:([fav objectForKey:SPFavoriteSSLCACertFileLocationEnabledKey] ? [[fav objectForKey:SPFavoriteSSLCACertFileLocationEnabledKey] intValue] : NSControlStateValueOff)];
    [self setSslCACertFileLocation:([fav objectForKey:SPFavoriteSSLCACertFileLocationKey] ? [fav objectForKey:SPFavoriteSSLCACertFileLocationKey] : @"")];

    // SSH details
    [self setSshHost:([fav objectForKey:SPFavoriteSSHHostKey] ? [fav objectForKey:SPFavoriteSSHHostKey] : @"")];
    [self setSshUser:([fav objectForKey:SPFavoriteSSHUserKey] ? [fav objectForKey:SPFavoriteSSHUserKey] : @"")];
    [self setSshKeyLocationEnabled:([fav objectForKey:SPFavoriteSSHKeyLocationEnabledKey] ? [[fav objectForKey:SPFavoriteSSHKeyLocationEnabledKey] intValue] : NSControlStateValueOff)];
    [self setSshKeyLocation:([fav objectForKey:SPFavoriteSSHKeyLocationKey] ? [fav objectForKey:SPFavoriteSSHKeyLocationKey] : @"")];
    [self setSshPort:([fav objectForKey:SPFavoriteSSHPortKey] ? [fav objectForKey:SPFavoriteSSHPortKey] : @"")];

    // Check whether the password exists in the keychain, and if so add it; also record the
    // keychain details so we can pass around only those details if the password doesn't change
    connectionKeychainItemName = !fav ? nil : [keychain nameForFavoriteName:[fav objectForKey:SPFavoriteNameKey] id:[fav objectForKey:SPFavoriteIDKey]];
    connectionKeychainItemAccount = !fav ? nil : [keychain accountForUser:[fav objectForKey:SPFavoriteUserKey] host:(([self type] == SPSocketConnection) ? @"localhost" : [fav objectForKey:SPFavoriteHostKey]) database:[fav objectForKey:SPFavoriteDatabaseKey]];

    if(fav) {
        [self setPassword:[keychain getPasswordForName:connectionKeychainItemName account:connectionKeychainItemAccount]];
    }

    if (!fav || ![[self password] length]) {
        [self setPassword:nil];
    }

    [self _syncAWSIAMAndSSLInterfaceState];

    // Trigger an interface update
    [self resizeTabViewToConnectionType:[self type] animating:(sender == self)];

    // Store the selected favorite ID for use with the document on connection
    if ([fav objectForKey:SPFavoriteIDKey]){
        id obj = [fav safeObjectForKey:SPFavoriteIDKey];
        if([obj respondsToSelector:@selector(stringValue)]){
            [self setConnectionKeychainID:[obj stringValue]];
        }
    }

    // And the same for the SSH password
    connectionSSHKeychainItemName = !fav ? nil : [keychain nameForSSHForFavoriteName:[fav objectForKey:SPFavoriteNameKey] id:[fav objectForKey:SPFavoriteIDKey]];
    connectionSSHKeychainItemAccount = !fav ? nil : [keychain accountForSSHUser:[fav objectForKey:SPFavoriteSSHUserKey] sshHost:[fav objectForKey:SPFavoriteSSHHostKey]];

    if(fav) {
        [self setSshPassword:[keychain getPasswordForName:connectionSSHKeychainItemName account:connectionSSHKeychainItemAccount]];
    }

    if (!fav || ![[self sshPassword] length]) {
        [self setSshPassword:nil];
    }

    [prefs setInteger:[[fav objectForKey:SPFavoriteIDKey] integerValue] forKey:SPLastFavoriteID];

    [self updateFavoriteNextKeyView];
}

/**
 * Set the next KeyView to password field if the password is empty
 */
- (void)updateFavoriteNextKeyView
{
    switch ([self type])
    {
        case SPTCPIPConnection:
        {
            BOOL shouldFocusPassword = ![[standardPasswordField stringValue] length];
            [favoritesOutlineView setNextKeyView:shouldFocusPassword ? standardPasswordField : standardNameField];
            break;
        }
        case SPAWSIAMConnection:
            [favoritesOutlineView setNextKeyView:awsIAMNameField];
            break;
        case SPSocketConnection:
            [favoritesOutlineView setNextKeyView:(![[socketPasswordField stringValue] length]) ? socketPasswordField : socketNameField];
            break;
        case SPSSHTunnelConnection:
            if (![[sshPasswordField stringValue] length]) {
                [favoritesOutlineView setNextKeyView:sshPasswordField];
            }
            else if (![[sshSSHPasswordField stringValue] length]) {
                [favoritesOutlineView setNextKeyView:sshSSHPasswordField];
            }
            else {
                [favoritesOutlineView setNextKeyView:sshNameField];
            }
            break;
    }
}

/**
 * Returns the selected favorite data dictionary or nil if nothing is selected.
 */
- (NSMutableDictionary *)selectedFavorite
{
    SPTreeNode *node = [self selectedFavoriteNode];

    return (![node isGroup]) ? [(SPFavoriteNode *)[node representedObject] nodeFavorite] : nil;
}

/**
 * Returns the selected favorite node or nil if nothing is selected.
 */
- (SPTreeNode *)selectedFavoriteNode
{
    NSArray *nodes = [self selectedFavoriteNodes];

    return (SPTreeNode *)[nodes firstObject];
}

/**
 * Returns an array of selected favorite nodes.
 */
- (NSArray *)selectedFavoriteNodes
{
    NSMutableArray *nodes = [NSMutableArray array];
    NSIndexSet *indexes = [favoritesOutlineView selectedRowIndexes];

    [indexes enumerateIndexesUsingBlock:^(NSUInteger currentIndex, BOOL * _Nonnull stop) {
        [nodes addObject:[favoritesOutlineView itemAtRow:currentIndex]];
    }];

    return nodes;
}

/**
 * Saves the current connection favorite.
 */
- (IBAction)saveFavorite:(id)sender
{
    [self _saveCurrentDetailsCreatingNewFavorite:NO validateDetails:YES];
}

/**
 * Adds a new connection favorite.
 */
- (IBAction)addFavorite:(id)sender
{
    NSNumber *favoriteID = [self _createNewFavoriteID];

    NSArray *objects = @[
        NSLocalizedString(@"New Favorite", @"new favorite name"),
        @0,
        @"",
        @"",
        @"",
        @(-1),
        @"",
        @0,
        @"",
        @(NSControlStateValueOff),
        @(NSControlStateValueOff),
        @(NSControlStateValueOff),
        @"",
        @"default",
        @(NSControlStateValueOff),
        @(NSControlStateValueOff),
        @(NSControlStateValueOff),
        @(NSControlStateValueOff),
        @"",
        @"",
        @"",
        @(NSControlStateValueOff),
        @"",
        @"",
        favoriteID
    ];

    NSArray *keys = @[
        SPFavoriteNameKey,
        SPFavoriteTypeKey,
        SPFavoriteHostKey,
        SPFavoriteSocketKey,
        SPFavoriteUserKey,
        SPFavoriteColorIndexKey,
        SPFavoritePortKey,
        SPFavoriteTimeZoneModeKey,
        SPFavoriteTimeZoneIdentifierKey,
        SPFavoriteAllowDataLocalInfileKey,
        SPFavoriteEnableClearTextPluginKey,
        SPFavoriteUseAWSIAMAuthKey,
        SPFavoriteAWSRegionKey,
        SPFavoriteAWSProfileKey,
        SPFavoriteUseSSLKey,
        SPFavoriteSSLKeyFileLocationEnabledKey,
        SPFavoriteSSLCertificateFileLocationEnabledKey,
        SPFavoriteSSLCACertFileLocationEnabledKey,
        SPFavoriteDatabaseKey,
        SPFavoriteSSHHostKey,
        SPFavoriteSSHUserKey,
        SPFavoriteSSHKeyLocationEnabledKey,
        SPFavoriteSSHKeyLocationKey,
        SPFavoriteSSHPortKey,
        SPFavoriteIDKey
    ];

    // Create default favorite
    NSMutableDictionary *favorite = [NSMutableDictionary dictionaryWithObjects:objects forKeys:keys];

    SPTreeNode *selectedNode = [self selectedFavoriteNode];

    SPTreeNode *parent = ([selectedNode isGroup] && selectedNode != quickConnectItem) ? selectedNode : (SPTreeNode *)[selectedNode parentNode];

    SPTreeNode *node = [favoritesController addFavoriteNodeWithData:favorite asChildOfNode:parent];

    // Ensure the parent is expanded
    [favoritesOutlineView expandItem:parent];

    [self _sortFavorites];
    [self _selectNode:node];

    [[[SPAppDelegate preferenceController] generalPreferencePane] updateDefaultFavoritePopup];

    favoriteNameFieldWasAutogenerated = YES;

    [favoritesOutlineView editColumn:0 row:[favoritesOutlineView selectedRow] withEvent:nil select:YES];
}

/**
 * Adds the current details as a new connection favorite, selects it, and scrolls the selected
 * row to be visible.
 */
- (IBAction)addFavoriteUsingCurrentDetails:(id)sender
{
    [self _saveCurrentDetailsCreatingNewFavorite:YES validateDetails:YES];
}

/**
 * Adds a new group node to the favorites tree with a default name. Once added it is selected for editing.
 */
- (IBAction)addGroup:(id)sender
{
    SPTreeNode *selectedNode = [self selectedFavoriteNode];

    SPTreeNode *parent = ([selectedNode isGroup] && selectedNode != quickConnectItem) ? selectedNode : (SPTreeNode *)[selectedNode parentNode];

    // Ensure the parent is expanded
    [favoritesOutlineView expandItem:parent];

    SPTreeNode *node = [favoritesController addGroupNodeWithName:NSLocalizedString(@"New Folder", @"new folder placeholder name") asChildOfNode:parent];

    [self _reloadFavoritesViewData];
    [self _selectNode:node];

    [favoritesOutlineView editColumn:0 row:[favoritesOutlineView selectedRow] withEvent:nil select:YES];
}

/**
 * Removes the selected node.
 */
- (IBAction)removeNode:(id)sender
{
    if ([favoritesOutlineView numberOfSelectedRows] == 1) {

        BOOL suppressWarning = NO;
        SPTreeNode *node = [self selectedFavoriteNode];

        NSString *message = @"";
        NSString *informativeMessage = @"";

        if (![node isGroup]) {
            message = [NSString stringWithFormat:NSLocalizedString(@"Delete favorite '%@'?", @"delete database message"), [[[node representedObject] nodeFavorite] objectForKey:SPFavoriteNameKey]];
            informativeMessage = [NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to delete the favorite '%@'? This operation cannot be undone.", @"delete database informative message"), [[[node representedObject] nodeFavorite] objectForKey:SPFavoriteNameKey]];
        } else if ([[node childNodes] count] > 0) {
            message = [NSString stringWithFormat:NSLocalizedString(@"Delete group '%@'?", @"delete database message"), [[node representedObject] nodeName]];
            informativeMessage = [NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to delete the group '%@'? All groups and favorites within this group will also be deleted. This operation cannot be undone.", @"delete database informative message"), [[node representedObject] nodeName]];
        } else {
            suppressWarning = YES;
        }

        if (!suppressWarning) {
            [NSAlert createDefaultAlertWithTitle:message message:informativeMessage primaryButtonTitle:NSLocalizedString(@"Delete", @"delete button") primaryButtonHandler:^{
                [self _removeNode:[self selectedFavoriteNode]];
            } cancelButtonHandler:nil];
        } else {
            [self _removeNode:node];
        }
    }
}

/**
 * Duplicates the selected connection favorite.
 */
- (IBAction)duplicateFavorite:(id)sender
{
    if ([favoritesOutlineView numberOfSelectedRows] == 1) {

        NSMutableDictionary *favorite = [NSMutableDictionary dictionaryWithDictionary:[self selectedFavorite]];

        NSNumber *favoriteID = [self _createNewFavoriteID];

        // Update the unique ID
        [favorite setObject:favoriteID forKey:SPFavoriteIDKey];

        // Alter the name for clarity
        [favorite setObject:[NSString stringWithFormat:NSLocalizedString(@"%@ Copy", @"Initial favourite name after duplicating a previous favourite"), [favorite objectForKey:SPFavoriteNameKey]] forKey:SPFavoriteNameKey];

        SPTreeNode *selectedNode = [self selectedFavoriteNode];

        SPTreeNode *parent = ([selectedNode isGroup]) ? selectedNode : (SPTreeNode *)[selectedNode parentNode];

        SPTreeNode *node = [favoritesController addFavoriteNodeWithData:favorite asChildOfNode:parent];

        [self _reloadFavoritesViewData];
        [self _selectNode:node];

        [[[SPAppDelegate preferenceController] generalPreferencePane] updateDefaultFavoritePopup];
    }
}

/**
 * Switches the selected favorite/group to editing mode so it can be renamed.
 */
- (IBAction)renameNode:(id)sender
{
    if ([favoritesOutlineView numberOfSelectedRows] == 1) {
        [favoritesOutlineView editColumn:0 row:[favoritesOutlineView selectedRow] withEvent:nil select:YES];
    }
}

/**
 * Marks the selected favorite as the default.
 */
- (IBAction)makeSelectedFavoriteDefault:(id)sender
{
    NSInteger favoriteID = [[[self selectedFavorite] objectForKey:SPFavoriteIDKey] integerValue];

    [prefs setInteger:favoriteID forKey:SPDefaultFavorite];
}

- (void)selectQuickConnectItem
{
    return [self _selectNode:quickConnectItem];
}

#pragma mark -
#pragma mark Import/export favorites

/**
 * Displays an open panel, allowing the user to import their favorites.
 */
- (IBAction)importFavorites:(id)sender
{
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];

    [openPanel setAllowedFileTypes:@[@"plist"]];

    [openPanel beginSheetModalForWindow:[dbDocument parentWindowControllerWindow] completionHandler:^(NSInteger returnCode)
    {
        if (returnCode == NSModalResponseOK) {
            SPFavoritesImporter *importer = [[SPFavoritesImporter alloc] init];

            [importer setDelegate:(NSObject<SPFavoritesImportProtocol> *)self];

            [importer importFavoritesFromFileAtPath:[[openPanel URL] path]];
        }
    }];
}

/**
 * Displays a save panel, allowing the user to export their favorites.
 */
- (IBAction)exportFavorites:(id)sender
{
    // additional empty selection check
    if(![[self selectedFavoriteNodes] count]) return;

    NSSavePanel *savePanel = [NSSavePanel savePanel];

    // suggest the name of the favorite or a default name for multiple selection
    NSString *fileName = ([[self selectedFavoriteNodes] count] == 1)? [[(id<SPNamedNode>)[[self selectedFavoriteNode] representedObject] nodeName] stringByAppendingPathExtension:@"plist"] : nil;
    // This if() is so we can also catch nil due to favorite corruption (NSSavePanel will @throw if nil is passed in)
    if(!fileName) fileName = SPExportFavoritesFilename;

    [savePanel setAccessoryView:exportPanelAccessoryView];
    [savePanel setNameFieldStringValue:fileName];

    [savePanel beginSheetModalForWindow:[dbDocument parentWindowControllerWindow] completionHandler:^(NSInteger returnCode)
    {
        if (returnCode == NSModalResponseOK) {
            SPFavoritesExporter *exporter = [[SPFavoritesExporter alloc] init];

            [exporter setDelegate:self];

            [exporter writeFavorites:[self selectedFavoriteNodes] toFile:[[savePanel URL] path]];
         }
     }];
}

- (IBAction)allowLocalDataInfileChanged:(id)sender {
    [self _startEditingConnection];
}

#pragma mark -
#pragma mark Time Zone changes

- (IBAction)didChangeSelectedTimeZone:(NSPopUpButton *)sender
{
    NSMenuItem *selectedItem = [sender selectedItem];
    switch (selectedItem.tag) {
        case SPUseServerTimeZoneTag:
            [self setTimeZoneMode:SPConnectionTimeZoneModeUseServerTZ];
            [self setTimeZoneIdentifier:@""];
            break;
        case SPUseSystemTimeZoneTag:
            [self setTimeZoneMode:SPConnectionTimeZoneModeUseSystemTZ];
            [self setTimeZoneIdentifier:@""];
            break;
        default:
            [self setTimeZoneMode:SPConnectionTimeZoneModeUseFixedTZ];
            [self setTimeZoneIdentifier:selectedItem.title];
            break;
    }

    [standardTimeZoneField selectItemAtIndex:sender.indexOfSelectedItem];
    [awsIAMTimeZoneField selectItemAtIndex:sender.indexOfSelectedItem];
    [sshTimeZoneField selectItemAtIndex:sender.indexOfSelectedItem];
    [socketTimeZoneField selectItemAtIndex:sender.indexOfSelectedItem];

    [self _startEditingConnection];
}

#pragma mark -
#pragma mark Accessors

/**
 * Returns the main outline view instance.
 */
- (SPFavoritesOutlineView *)favoritesOutlineView
{
    return favoritesOutlineView;
}

#pragma mark -
#pragma mark Key Value Observing

/**
 * This method is called as part of Key Value Observing.
 */
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    // reload the bookmarks, when the observer detected a change in them
    //
    // thanks a lot to @jamesstout for pointing this out!
    // no longer needed
    // but for some reson there are other KVO registered, so need to keep the method...
}

#pragma mark -
#pragma mark Private API

/**
 * Take the current details and either save them to the currently selected
 * favourite, or create a new connection favourite using them.
 * If creating a new favourite, also select it and ensure the selected
 * favourite is visible.
 */
- (void)_saveCurrentDetailsCreatingNewFavorite:(BOOL)createNewFavorite validateDetails:(BOOL)validateDetails
{
    // Complete any active editing
    if ([[connectionView window] firstResponder]) {
        [[connectionView window] endEditingFor:[[connectionView window] firstResponder]];
    }

    // Ensure that host is not empty if this is a TCP/IP, SSH, or AWS IAM connection
    if (validateDetails && ([self type] == SPTCPIPConnection || [self type] == SPSSHTunnelConnection || [self type] == SPAWSIAMConnection) && ![[self host] length]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Insufficient connection details", @"insufficient details message") message:NSLocalizedString(@"Insufficient details provided to establish a connection. Please provide at least a host.", @"insufficient details informative message") callback:nil];
        return;
    }

    if (validateDetails && [self _isAWSIAMConnection] && ![self isAWSDirectoryAuthorized]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"AWS Authorization Required", @"AWS authorization required title")
                                     message:NSLocalizedString(@"Authorize access to your ~/.aws directory before saving an AWS IAM favorite.", @"AWS authorization required save message")
                                    callback:nil];
        return;
    }

    // If SSH is enabled, ensure that the SSH host is not nil
    if (validateDetails && [self type] == SPSSHTunnelConnection && ![[self sshHost] length]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Insufficient connection details", @"insufficient details message") message:NSLocalizedString(@"Please enter the hostname for the SSH Tunnel, or disable the SSH Tunnel.", @"message of panel when ssh details are incomplete") callback:nil];
        return;
    }

    // Set up the favourite, or get the mutable dictionary for the current favourite.
    NSMutableDictionary *theFavorite;
    if (createNewFavorite) {
        theFavorite = [NSMutableDictionary dictionary];
        [theFavorite setObject:[self _createNewFavoriteID] forKey:SPFavoriteIDKey];
    } else {
        if (!currentFavorite) {
            [NSException raise:NSInternalInconsistencyException format:@"Tried to save a current favourite with no currentFavorite"];
        }
        theFavorite = [self selectedFavorite];
    }

    void (^_setOrRemoveKey)(NSString *, id) = ^(NSString *key, id value) {
        if (value) {
            [theFavorite setObject:value forKey:key];
        } else {
            [theFavorite removeObjectForKey:key];
        }
    };

    // Set the name - either taking the provided name, or generating one.
    if ([[self name] length]) {
        [theFavorite setObject:[self name] forKey:SPFavoriteNameKey];
    } else {
        NSString *favoriteName = [self _generateNameForConnection];
        if (!favoriteName) {
            favoriteName = NSLocalizedString(@"Untitled", @"Name for an untitled connection");
        }
        [theFavorite setObject:favoriteName forKey:SPFavoriteNameKey];
    }

    // Set standard details for the connection
    [theFavorite setObject:[NSNumber numberWithInteger:[self type]] forKey:SPFavoriteTypeKey];
    _setOrRemoveKey(SPFavoriteHostKey, [self host]);
    _setOrRemoveKey(SPFavoriteSocketKey, [self socket]);
    _setOrRemoveKey(SPFavoriteUserKey, [self user]);
    _setOrRemoveKey(SPFavoritePortKey, [self port]);
    _setOrRemoveKey(SPFavoriteDatabaseKey, [self database]);
    [theFavorite setObject:[NSNumber numberWithInteger:[self colorIndex]] forKey:SPFavoriteColorIndexKey];
    [theFavorite setObject:[NSNumber numberWithInteger:[self timeZoneMode]] forKey:SPFavoriteTimeZoneModeKey];
    _setOrRemoveKey(SPFavoriteTimeZoneIdentifierKey, [self timeZoneIdentifier]);
    //Special prefs
    [theFavorite setObject:[NSNumber numberWithInteger:[self allowDataLocalInfile]] forKey:SPFavoriteAllowDataLocalInfileKey];
    // Clear text plugin
    [theFavorite setObject:[NSNumber numberWithInteger:[self enableClearTextPlugin]] forKey:SPFavoriteEnableClearTextPluginKey];
    // AWS IAM Authentication (profile-based only)
    NSInteger awsIAMEnabled = ([self type] == SPAWSIAMConnection) ? NSControlStateValueOn : NSControlStateValueOff;
    [theFavorite setObject:[NSNumber numberWithInteger:awsIAMEnabled] forKey:SPFavoriteUseAWSIAMAuthKey];
    _setOrRemoveKey(SPFavoriteAWSRegionKey, [self awsRegion]);
    _setOrRemoveKey(SPFavoriteAWSProfileKey, [self awsProfile]);
    // SSL details
    [theFavorite setObject:[NSNumber numberWithInteger:[self useSSL]] forKey:SPFavoriteUseSSLKey];
    [theFavorite setObject:[NSNumber numberWithInteger:[self sslKeyFileLocationEnabled]] forKey:SPFavoriteSSLKeyFileLocationEnabledKey];
    _setOrRemoveKey(SPFavoriteSSLKeyFileLocationKey, [self sslKeyFileLocation]);
    [theFavorite setObject:[NSNumber numberWithInteger:[self sslCertificateFileLocationEnabled]] forKey:SPFavoriteSSLCertificateFileLocationEnabledKey];
    _setOrRemoveKey(SPFavoriteSSLCertificateFileLocationKey, [self sslCertificateFileLocation]);
    [theFavorite setObject:[NSNumber numberWithInteger:[self sslCACertFileLocationEnabled]] forKey:SPFavoriteSSLCACertFileLocationEnabledKey];
    _setOrRemoveKey(SPFavoriteSSLCACertFileLocationKey, [self sslCACertFileLocation]);

    // SSH details
    _setOrRemoveKey(SPFavoriteSSHHostKey, [self sshHost]);
    _setOrRemoveKey(SPFavoriteSSHUserKey, [self sshUser]);
    _setOrRemoveKey(SPFavoriteSSHPortKey, [self sshPort]);
    [theFavorite setObject:[NSNumber numberWithInteger:[self sshKeyLocationEnabled]] forKey:SPFavoriteSSHKeyLocationEnabledKey];
    _setOrRemoveKey(SPFavoriteSSHKeyLocationKey, [self sshKeyLocation]);


    /*
     * Password handling for the SQL connection
     */
    NSString *oldKeychainName, *oldKeychainAccount, *newKeychainName, *newKeychainAccount;;
    NSString *oldHostnameForPassword = ([[currentFavorite objectForKey:SPFavoriteTypeKey] integerValue] == SPSocketConnection) ? @"localhost" : [currentFavorite objectForKey:SPFavoriteHostKey];
    NSString *newHostnameForPassword = ([self type] == SPSocketConnection) ? @"localhost" : [self host];

    // Grab the password for this connection
    // Add the password to keychain as appropriate
    NSString *sqlPassword = [self password];
    if (![sqlPassword length] && mySQLConnection && connectionKeychainItemName) {
        sqlPassword = [keychain getPasswordForName:connectionKeychainItemName account:connectionKeychainItemAccount];
    }

    // If creating a new favourite, always add the password to the keychain if it's set
    if (createNewFavorite && [sqlPassword length]) {
        [keychain addPassword:sqlPassword
                      forName:[keychain nameForFavoriteName:[theFavorite objectForKey:SPFavoriteNameKey] id:[theFavorite objectForKey:SPFavoriteIDKey]]
                      account:[keychain accountForUser:[self user] host:newHostnameForPassword database:[self database]]];
    }

    // If not creating a new favourite...
    if (!createNewFavorite) {

        // Get the old keychain name and account strings
        oldKeychainName = [keychain nameForFavoriteName:[currentFavorite objectForKey:SPFavoriteNameKey] id:[currentFavorite objectForKey:SPFavoriteIDKey]];
        oldKeychainAccount = [keychain accountForUser:[currentFavorite objectForKey:SPFavoriteUserKey] host:oldHostnameForPassword database:[currentFavorite objectForKey:SPFavoriteDatabaseKey]];

        // If there's no new password, remove the old item from the keychain
        if (![sqlPassword length]) {
            [keychain deletePasswordForName:oldKeychainName account:oldKeychainAccount];

        // Otherwise, set up the new keychain name and account strings and create or edit the item
        } else {
            newKeychainName = [keychain nameForFavoriteName:[theFavorite objectForKey:SPFavoriteNameKey] id:[theFavorite objectForKey:SPFavoriteIDKey]];
            newKeychainAccount = [keychain accountForUser:[self user] host:newHostnameForPassword database:[self database]];
            if ([keychain passwordExistsForName:oldKeychainName account:oldKeychainAccount]) {
                [keychain updateItemWithName:oldKeychainName account:oldKeychainAccount toName:newKeychainName account:newKeychainAccount password:sqlPassword];
            } else {
                [keychain addPassword:sqlPassword forName:newKeychainName account:newKeychainAccount];
            }
        }
    }
    sqlPassword = nil;

    /*
     * Password handling for the SSH connection
     */
    NSString *theSSHPassword = [self sshPassword];
    if (mySQLConnection && connectionSSHKeychainItemName) {
        theSSHPassword = [keychain getPasswordForName:connectionSSHKeychainItemName account:connectionSSHKeychainItemAccount];
    }

    // If creating a new favourite, always add the password if it's set
    if (createNewFavorite && [theSSHPassword length]) {
        [keychain addPassword:theSSHPassword
                      forName:[keychain nameForSSHForFavoriteName:[theFavorite objectForKey:SPFavoriteNameKey] id:[theFavorite objectForKey:SPFavoriteIDKey]]
                      account:[keychain accountForSSHUser:[self sshUser] sshHost:[self sshHost]]];
    }

    // If not creating a new favourite...
    if (!createNewFavorite) {

        // Get the old keychain name and account strings
        oldKeychainName = [keychain nameForSSHForFavoriteName:[currentFavorite objectForKey:SPFavoriteNameKey] id:[currentFavorite objectForKey:SPFavoriteIDKey]];
        oldKeychainAccount = [keychain accountForSSHUser:[currentFavorite objectForKey:SPFavoriteSSHUserKey] sshHost:[currentFavorite objectForKey:SPFavoriteSSHHostKey]];

        // If there's no new password, remove the old item from the keychain
        if (![theSSHPassword length]) {
            [keychain deletePasswordForName:oldKeychainName account:oldKeychainAccount];

        // Otherwise, set up the new keychain name and account strings and create or edit the item
        } else {
            newKeychainName = [keychain nameForSSHForFavoriteName:[theFavorite objectForKey:SPFavoriteNameKey] id:[theFavorite objectForKey:SPFavoriteIDKey]];
            newKeychainAccount = [keychain accountForSSHUser:[self sshUser] sshHost:[self sshHost]];
            if ([keychain passwordExistsForName:oldKeychainName account:oldKeychainAccount]) {
                [keychain updateItemWithName:oldKeychainName account:oldKeychainAccount toName:newKeychainName account:newKeychainAccount password:theSSHPassword];
            } else {
                [keychain addPassword:theSSHPassword forName:newKeychainName account:newKeychainAccount];
            }
        }
    }
    theSSHPassword = nil;

    /*
     * Saving the connection
     */

    // If creating the connection, add to the favourites tree.
    if (createNewFavorite) {
        SPTreeNode *selectedNode = [self selectedFavoriteNode];
        SPTreeNode *parentNode = nil;

        // If the current node is a group node, create the favorite as a child of it
        if ([selectedNode isGroup] && selectedNode != quickConnectItem) {
            parentNode = selectedNode;

        // Otherwise, create the new node as a sibling of the selected node if possible
        } else if ([selectedNode parentNode] && [selectedNode parentNode] != favoritesRoot) {
            parentNode = (SPTreeNode *)[selectedNode parentNode];
        }

        // Ensure the parent is expanded
        [favoritesOutlineView expandItem:parentNode];

        // Add the new node and select it
        SPTreeNode *newNode = [favoritesController addFavoriteNodeWithData:theFavorite asChildOfNode:parentNode];

        [self _sortFavorites];

        [self _selectNode:newNode];

        // Update the favorites popup button in the preferences
        [[[SPAppDelegate preferenceController] generalPreferencePane] updateDefaultFavoritePopup];

    // Otherwise, if editing the favourite, update it
    } else {
        [[[self selectedFavoriteNode] representedObject] setNodeFavorite:theFavorite];

        // Save the new data to disk
        [favoritesController saveFavorites];

        [self _stopEditingConnection];


        currentFavorite = [theFavorite copy];

        [self _sortFavorites];
        [self _scrollToSelectedNode];
    }

    // after saving the favorite, the name is never autogenerated (ie. overridable), regardless of the value (#3015)
    favoriteNameFieldWasAutogenerated = NO;

    [[NSNotificationCenter defaultCenter] postNotificationName:SPConnectionFavoritesChangedNotification object:self];
}


/**
 * Sorts the connection favorites based on the selected criteria.
 */

- (void)_sortFavorites {
    NSString *sortKey = SPFavoriteNameKey;
    switch (currentSortItem) {
        case SPFavoritesSortNameItem:
            sortKey = SPFavoriteNameKey;
            break;
        case SPFavoritesSortHostItem:
            sortKey = SPFavoriteHostKey;
            break;
        case SPFavoritesSortTypeItem:
            sortKey = SPFavoriteTypeKey;
            break;
        case SPFavoritesSortColorItem:
            sortKey = SPFavoriteColorIndexKey;
            break;
        case SPFavoritesSortUnsorted:
            // When unsorted, just save the current order without sorting
            [favoritesController saveFavorites];
            [self _reloadFavoritesViewData];
            return;
    }

    // Store a copy of the selected nodes for re-selection
    NSArray *preSortSelection = [self selectedFavoriteNodes];

    [self _sortTreeNode:[[favoritesRoot childNodes] objectAtIndex:0] usingKey:sortKey];
    [favoritesController saveFavorites];
    [self _reloadFavoritesViewData];

    // Update the selection to account for sorted favourites
    NSMutableIndexSet *restoredSelection = [NSMutableIndexSet indexSet];
    for (SPTreeNode *eachNode in preSortSelection) {
        [restoredSelection addIndex:[favoritesOutlineView rowForItem:eachNode]];
    }
    [favoritesOutlineView selectRowIndexes:restoredSelection byExtendingSelection:NO];
    [[NSNotificationCenter defaultCenter] postNotificationName:SPConnectionFavoritesChangedNotification object:self];
}

/**
 * Sorts the supplied tree node using the supplied sort key.
 *
 * @param node The tree node to sort
 * @param key  The sort key to sort by
 */
- (void)_sortTreeNode:(SPTreeNode *)node usingKey:(NSString *)key {
    NSMutableArray *nodes = [[node mutableChildNodes] mutableCopy];

    // If this node only has one child and it's not another group node, don't bother proceeding
    if (([nodes count] == 1) && (![[nodes objectAtIndex:0] isGroup])) {
        return;
    }

    for (SPTreeNode *treeNode in nodes)
    {
        if ([treeNode isGroup]) {
            [self _sortTreeNode:treeNode usingKey:key];
        }
    }

    [nodes sortUsingFunction:_compareFavoritesUsingKey context:(__bridge void * _Nullable)(key)];

    if (reverseFavoritesSort) [nodes reverse];

    [[node mutableChildNodes] setArray:nodes];
}

/**
 * Sort function used by NSMutableArray's sortUsingFunction:
 *
 * @param favorite1 The first of the favorites to compare (and determine sort order)
 * @param favorite2 The second of the favorites to compare
 * @param key       The sort key to perform the comparison by
 *
 * @return An integer (NSComparisonResult) indicating the order of the comparison
 */
static NSComparisonResult _compareFavoritesUsingKey(id favorite1, id favorite2, void *key)
{
    NSString *dictKey = (__bridge NSString *)key;
    id value1, value2;

    BOOL isNamedComparison = [dictKey isEqualToString:SPFavoriteNameKey];
    // Group nodes can only be compared using their names.
    // If this is a named comparison or both nodes are group nodes use their
    // names. Otherwise let the group nodes win (ie. they will be placed at the
    // top ordered alphabetically for all other comparison keys)

    if ([favorite1 isGroup]) {
        if (isNamedComparison || [favorite2 isGroup]) {
            value1 = [[favorite1 representedObject] nodeName];
        } else {
            return NSOrderedAscending; // the left object is a group, the right is not -> left wins
        }
    } else {
        value1 = [[(SPFavoriteNode *)[(SPTreeNode *)favorite1 representedObject] nodeFavorite] objectForKey:dictKey];
    }

    if ([favorite2 isGroup]) {
        if (isNamedComparison || [favorite1 isGroup]) {
            value2 = [[favorite2 representedObject] nodeName];
        } else {
            return NSOrderedDescending; // the left object is not a group, the right is -> left loses
        }
    } else {
        value2 = [[(SPFavoriteNode *)[(SPTreeNode *)favorite2 representedObject] nodeFavorite] objectForKey:dictKey];
    }

    //if a value is undefined count it as "loser"
    if(!value1 && value2) return NSOrderedDescending;
    if(value1 && !value2) return NSOrderedAscending;
    if(!value1 && !value2) return NSOrderedSame;

    if ([value1 isKindOfClass:[NSString class]]) {
        return [value1 caseInsensitiveCompare:value2];
    }
    return [value1 compare:value2];
}

/**
 * Updates the favorite's host when the type changes.
 */

- (void)_favoriteTypeDidChange {

    [self setUseAWSIAMAuth:([self type] == SPAWSIAMConnection ? NSControlStateValueOn : NSControlStateValueOff)];

    // Update the name for newly added favorites if not already touched by the user, by triggering a KVO update
    if (![[self name] length] || favoriteNameFieldWasAutogenerated) {
        NSString *favoriteName = [self _generateNameForConnection];
        if (favoriteName) {
            [self setName:favoriteName];
        }
    }

    [self _syncAWSIAMAndSSLInterfaceState];
}

/**
 * Convenience method for reloading the outline view, expanding the root item and scrolling to the selected item.
 */
- (void)_reloadFavoritesViewData
{
    [self.favoritesListDataSource reloadDataIn:favoritesOutlineView];
    [self _scrollToSelectedNode];
}

/**
 * Update the first responder status on password fields if they are empty and
 * some host details are set, usually as a response to favourite selection changes.
 */
- (void)_updateFavoriteFirstResponder
{
    // Skip auto-selection changes if there is no user set
    if (![[self user] length]) return;

    switch ([self type])
    {
        case SPTCPIPConnection:
            if (![[standardPasswordField stringValue] length]) {
                [[dbDocument parentWindowControllerWindow] makeFirstResponder:standardPasswordField];
            }
            break;
        case SPAWSIAMConnection:
            if (awsIAMNameField) {
                [[dbDocument parentWindowControllerWindow] makeFirstResponder:awsIAMNameField];
            }
            break;
        case SPSocketConnection:
            if (![[socketPasswordField stringValue] length]) {
                [[dbDocument parentWindowControllerWindow] makeFirstResponder:socketPasswordField];
            }
            break;
        case SPSSHTunnelConnection:
            if (![[sshPasswordField stringValue] length]) {
                [[dbDocument parentWindowControllerWindow] makeFirstResponder:sshPasswordField];
            }
            break;
    }
}

/**
 * Restores the connection interface to its original state.
 */
- (void)_restoreConnectionInterface
{
    // Must be performed on the main thread
    if (![NSThread isMainThread]) return [[self onMainThread] _restoreConnectionInterface];

    // Reset the window title
    [dbDocument updateWindowTitle:self];

    // Stop the current tab's progress indicator
    [dbDocument setIsProcessing:NO];

    // Reset the UI
    [helpButton setHidden:NO];
    [helpButton display];
    [connectButton setTitle:NSLocalizedString(@"Connect", @"connect button")];
    [connectButton setEnabled:YES];
    [connectButton display];
    [testConnectButton setEnabled:YES];
    [progressIndicator stopAnimation:self];
    [progressIndicator display];
    [progressIndicatorText setHidden:YES];
    [progressIndicatorText display];

    // If not testing a connection, Update the password fields, restoring passwords that may have
    // been bulleted out during connection
    if (!isTestingConnection) {
        if (connectionKeychainItemName) {
            [self setPassword:[keychain getPasswordForName:connectionKeychainItemName account:connectionKeychainItemAccount]];
        }
        if (connectionSSHKeychainItemName) {
            [self setSshPassword:[keychain getPasswordForName:connectionSSHKeychainItemName account:connectionSSHKeychainItemAccount]];
        }
    }

    // Re-enable favorites table view
    [favoritesOutlineView setEnabled:YES];
    [favoritesOutlineView display];

    // Revert the connect button back to its original selector
    [connectButton setAction:@selector(initiateConnection:)];
}

/**
 * Selected the supplied node in the favorites outline view.
 *
 * @param node The node to select
 */
- (void)_selectNode:(SPTreeNode *)node
{
    [favoritesOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:[favoritesOutlineView rowForItem:node]] byExtendingSelection:NO];
    [self _scrollToSelectedNode];
}

/**
 * Scroll to the currently selected node.
 */
- (void)_scrollToSelectedNode
{
    // Don't scroll if no node is currently selected
    if ([favoritesOutlineView selectedRow] == -1) return;

    [favoritesOutlineView scrollRowToVisible:[favoritesOutlineView selectedRow]];
}

/**
 * Removes the supplied tree node.
 *
 * @param node The node to remove
 */
- (void)_removeNode:(SPTreeNode *)node
{
    [self _removeAllPasswordsForNode:node];

    [favoritesController removeFavoriteNode:node];

    [self _reloadFavoritesViewData];

    // Select Quick Connect item to prevent empty selection
    [self selectQuickConnectItem];

    [connectionResizeContainer setHidden:NO];
    [connectionInstructionsTextField setStringValue:NSLocalizedString(@"Enter connection details below, or choose a favorite", @"enter connection details label")];

    [[[SPAppDelegate preferenceController] generalPreferencePane] updateDefaultFavoritePopup];
}

/**
 * Removes all passwords for the supplied tree node and any child nodes.
 *
 * @param node The node to remove all passwords within and for.
 */
- (void)_removeAllPasswordsForNode:(SPTreeNode *)node
{

    // If the supplied node is a group node, remove all passwords for any children
    if ([node isGroup]) {
        for (SPTreeNode *childNode in [node childNodes]) {
            [self _removeAllPasswordsForNode:childNode];
        }
        return;
    }

    // Otherwise, remove details for the supplied node.

        NSDictionary *favorite = [[node representedObject] nodeFavorite];

        // Get selected favorite's details
        NSString *favoriteName     = [favorite objectForKey:SPFavoriteNameKey];
        NSString *favoriteUser     = [favorite objectForKey:SPFavoriteUserKey];
        NSString *favoriteHost     = [favorite objectForKey:SPFavoriteHostKey];
        NSString *favoriteDatabase = [favorite objectForKey:SPFavoriteDatabaseKey];
        NSString *favoriteSSHUser  = [favorite objectForKey:SPFavoriteSSHUserKey];
        NSString *favoriteSSHHost  = [favorite objectForKey:SPFavoriteSSHHostKey];
        NSString *favoriteID       = [favorite objectForKey:SPFavoriteIDKey];

        // Remove passwords from the Keychain
        [keychain deletePasswordForName:[keychain nameForFavoriteName:favoriteName id:favoriteID]
                                account:[keychain accountForUser:favoriteUser host:((type == SPSocketConnection) ? @"localhost" : favoriteHost) database:favoriteDatabase]];
        [keychain deletePasswordForName:[keychain nameForSSHForFavoriteName:favoriteName id:favoriteID]
                                account:[keychain accountForSSHUser:favoriteSSHUser sshHost:favoriteSSHHost]];

        // Reset last used favorite
        if ([[favorite objectForKey:SPFavoriteIDKey] integerValue] == [prefs integerForKey:SPLastFavoriteID]) {
            [prefs setInteger:0 forKey:SPLastFavoriteID];
        }

        // If required, reset the default favorite
        if ([[favorite objectForKey:SPFavoriteIDKey] integerValue] == [prefs integerForKey:SPDefaultFavorite]) {
            [prefs setInteger:[prefs integerForKey:SPLastFavoriteID] forKey:SPDefaultFavorite];
        }
    }

/**
 * Creates a new favorite ID based on the UNIX epoch time.
 */
- (NSNumber *)_createNewFavoriteID
{
    return [NSNumber numberWithInteger:[[NSString stringWithFormat:@"%f", [[NSDate date] timeIntervalSince1970]] hash]];
}

/**
 * Returns the favorite node for the conection favorite with the supplied ID.
 */
- (SPTreeNode *)_favoriteNodeForFavoriteID:(NSInteger)favoriteID
{
    SPTreeNode *favoriteNode = nil;

    if (!favoritesRoot) return favoriteNode;

    if (!favoriteID) return quickConnectItem;

    for (SPTreeNode *node in [favoritesRoot allChildLeafs])
    {
        if ([[[[node representedObject] nodeFavorite] objectForKey:SPFavoriteIDKey] integerValue] == favoriteID) {
            favoriteNode = node;
        }
    }

    return favoriteNode;
}

/**
 * Strips any invalid characters form the supplied string. Invalid is defined as any characters that should
 * not be allowed to be enetered on the connection screen.
 */
- (NSString *)_stripInvalidCharactersFromString:(NSString *)subject
{
    NSString *result = [subject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    return [result stringByReplacingOccurrencesOfString:@"\n" withString:@""];
}

/**
 * Generate a name for the current connection based on any other populated details.
 * Currently uses the host and database fields.
 * If a name cannot be generated because there are insufficient other details, returns nil.
 */
- (NSString *)_generateNameForConnection
{
    NSString *aName;

    if ([self type] != SPSocketConnection && ![[self host] length]) {
        return nil;
    }

    aName = ([self type] == SPSocketConnection) ? @"localhost" : [self host];

    if ([[self database] length]) {
        aName = [NSString stringWithFormat:@"%@/%@", aName, [self database]];
    }

    return aName;
}


/**
 * If editing is not already active, mark editing as starting, triggering UI updates
 * to match.
 */
- (void)_startEditingConnection
{
    // If not connecting, hide the connection status text to reflect changes
    if (!isConnecting) {
        [progressIndicatorText setHidden:YES];
    }

    if (isEditingConnection) return;

    // Fade and move the edit button area in
    [editButtonsView setAlphaValue:0.0f];
    [editButtonsView setHidden:NO];
    [editButtonsView setFrameOrigin:NSMakePoint([editButtonsView frame].origin.x, [editButtonsView frame].origin.y - 30)];
    // The animation is started async because there is a bug/oddity with layer-backed views and animating frameOrigin (at least in 10.13):
    // If both calls to -setFrameOrigin: are in the same method, CA would only animate the difference between those calls (which is 0 here).
    // This works fine when not using layers, but then there is another issue with the progress indicator (#2903)
    SPMainLoopAsync(^{
        [NSAnimationContext beginGrouping];
        [[self->editButtonsView animator] setFrameOrigin:NSMakePoint([self->editButtonsView frame].origin.x, [self->editButtonsView frame].origin.y + 30)];
        [[self->editButtonsView animator] setAlphaValue:1.0f];
        [NSAnimationContext endGrouping];
    });

    // Update the "Save" button state as appropriate
    [saveFavoriteButton setEnabled:([self selectedFavorite] != nil)];

    // Show the area to allow saving the changes
    [self setIsEditingConnection:YES];
    [favoritesOutlineView setNeedsDisplayInRect:[favoritesOutlineView rectOfRow:[favoritesOutlineView selectedRow]]];
}

/**
 * If editing is active, mark editing as complete, triggering UI updates to match.
 */
- (void)_stopEditingConnection
{
    if (!isEditingConnection) return;

    [self setIsEditingConnection:NO];

    [editButtonsView setHidden:YES];
    [progressIndicatorText setHidden:YES];
    [favoritesOutlineView display];
}

- (void)_documentWillClose:(NSNotification *)notification {
    if ([notification.object isKindOfClass:[SPDatabaseDocument class]]) {
        SPDatabaseDocument *document = (SPDatabaseDocument *)[notification object];
        if (dbDocument == document) {

            cancellingConnection = YES;
            dbDocument = nil;

            if (mySQLConnection) {
                [mySQLConnection setDelegate:nil];
                [NSThread detachNewThreadWithName:SPCtxt(@"SPConnectionController close background disconnect", dbDocument) target:mySQLConnection selector:@selector(disconnect) object:nil];
            }

            if (sshTunnel) {
                [sshTunnel setConnectionStateChangeSelector:nil delegate:nil];
            }
        }
    }
}


/**
 * Called on the main thread once the MySQL connection is established on the background thread. Either the
 * connection was cancelled or it was successful.
 */
- (void)mySQLConnectionEstablished
{
    SPLog(@"mySQLConnectionEstablished");
    isConnecting = NO;
    self.localNetworkPermissionDeniedForCurrentAttempt = NO;

    // If the user is only testing the connection, kill the connection
    // once established and reset the UI.  Also catch connection cancels.
    if (isTestingConnection || cancellingConnection) {

        // Clean up any connections remaining, and reset the UI
        [self cancelConnection:self];

        if (isTestingConnection) {
            [self _showConnectionTestResult:NSLocalizedString(@"Connection succeeded", @"Connection success very short status message")];
        }

        return;
    }

    [progressIndicatorText setStringValue:NSLocalizedString(@"Connected", @"connection established message")];
    [progressIndicatorText display];

    // Stop the current tab's progress indicator
    [dbDocument setIsProcessing:NO];

    // Successful connection!
    [connectButton setEnabled:NO];
    [connectButton display];
    [progressIndicator stopAnimation:self];
    [progressIndicatorText setHidden:YES];

    // If SSL was enabled (manually or implicitly via IAM), check it was established correctly
    BOOL requiresSSL = (useSSL || [self _isAWSIAMConnection]);
    if (requiresSSL && ([self type] == SPTCPIPConnection || [self type] == SPSocketConnection || [self type] == SPAWSIAMConnection)) {
        if (![mySQLConnection isConnectedViaSSL]) {
            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"SSL connection not established", @"SSL requested but not used title") message:NSLocalizedString(@"You requested that the connection should be established using SSL, but MySQL made the connection without SSL.\n\nThis may be because the server does not support SSL connections, or has SSL disabled; or insufficient details were supplied to establish an SSL connection.\n\nThis connection is not encrypted.", @"SSL connection requested but not established error detail") callback:nil];
        }
    }

    // Re-enable favorites table view
    [favoritesOutlineView setEnabled:YES];
    [favoritesOutlineView display];

    // Pass the connection to the document and clean up the interface
    [self addConnectionToDocument];
}


/**
 * Add the connection to the parent document and restore the
 * interface, allowing the application to run as normal.
 */
- (void)addConnectionToDocument
{
    SPLog(@"addConnectionToDocument");
    // Restore the database content view via coordinator
    [self.viewCoordinator restoreDatabaseViewRemovingConnectionView:connectionView];

    // Restore the toolbar icons
    NSArray *toolbarItems = [[[dbDocument parentWindowControllerWindow] toolbar] items];

    for (NSUInteger i = 0; i < [toolbarItems count]; i++) [[toolbarItems objectAtIndex:i] setEnabled:YES];

    // Notify the connection delegate if set; otherwise fall back to the legacy
    // direct document call. This allows a standalone connection window to receive
    // the connection without being a document.
    if (self.connectionDelegate) {
        [self.connectionDelegate connectionDidEstablish:mySQLConnection info:[self _buildConnectionInfo]];
    } else {
        // Legacy path: pass the connection directly to the document.
        [dbDocument setConnection:mySQLConnection];
    }
}

/**
 * Builds an SAConnectionInfoObjC from the current controller state.
 * Used by the connection service and addConnectionToDocument.
 */
- (SAConnectionInfoObjC *)_buildConnectionInfo
{
    SAConnectionInfoObjC *info = [[SAConnectionInfoObjC alloc] init];
    info.type = (SAConnectionType)self.type;
    info.name = self.name ?: @"";
    info.host = self.host ?: @"";
    info.user = self.user ?: @"";
    info.password = self.password ?: @"";
    info.database = self.database ?: @"";
    info.socket = self.socket ?: @"";
    info.port = self.port ?: @"";
    info.colorIndex = self.colorIndex;
    info.useCompression = self.useCompression;
    info.useSSL = self.useSSL;
    info.sslKeyFileLocationEnabled = self.sslKeyFileLocationEnabled;
    info.sslKeyFileLocation = self.sslKeyFileLocation ?: @"";
    info.sslCertificateFileLocationEnabled = self.sslCertificateFileLocationEnabled;
    info.sslCertificateFileLocation = self.sslCertificateFileLocation ?: @"";
    info.sslCACertFileLocationEnabled = self.sslCACertFileLocationEnabled;
    info.sslCACertFileLocation = self.sslCACertFileLocation ?: @"";
    info.sshHost = self.sshHost ?: @"";
    info.sshUser = self.sshUser ?: @"";
    info.sshPassword = self.sshPassword ?: @"";
    info.sshKeyLocationEnabled = self.sshKeyLocationEnabled;
    info.sshKeyLocation = self.sshKeyLocation ?: @"";
    info.sshPort = self.sshPort ?: @"";
    info.connectionKeychainID = connectionKeychainID ?: @"";
    info.connectionKeychainItemName = connectionKeychainItemName ?: @"";
    info.connectionKeychainItemAccount = connectionKeychainItemAccount ?: @"";
    info.connectionSSHKeychainItemName = connectionSSHKeychainItemName ?: @"";
    info.connectionSSHKeychainItemAccount = connectionSSHKeychainItemAccount ?: @"";
    info.timeZoneMode = (SAConnectionTimeZoneMode)timeZoneMode;
    info.timeZoneIdentifier = timeZoneIdentifier ?: @"";
    info.allowDataLocalInfile = self.allowDataLocalInfile;
    info.enableClearTextPlugin = self.enableClearTextPlugin;
    info.useAWSIAMAuth = self.useAWSIAMAuth;
    info.awsRegion = self.awsRegion ?: @"";
    info.awsProfile = self.awsProfile ?: @"";
    return info;
}

/**
 * Resolves the MySQL password for use with SAConnectionService.
 * Handles: AWS IAM token generation, keychain marker detection, plaintext.
 * Returns nil and calls failConnectionWithTitle: on AWS IAM error.
 */
- (NSString *)_resolvedMySQLPassword
{
    // AWS IAM: generate auth token
    if ([self _isAWSIAMConnection]) {
        NSError *awsError = nil;
        NSString *token = [self generateAWSIAMAuthTokenWithError:&awsError];
        if (awsError || ![token length]) {
            [self failConnectionWithTitle:NSLocalizedString(@"AWS IAM Authentication Failed", @"AWS IAM auth failed title")
                             errorMessage:awsError ? awsError.localizedDescription : NSLocalizedString(@"Empty authentication token returned", @"AWS IAM empty token error")
                                   detail:nil];
            return nil;
        }
        return token;
    }

    // Keychain marker: if password matches the marker, fetch from keychain
    if (connectionKeychainItemName && [[self password] isEqualToString:@"SequelAceSecretPassword"]) {
        NSString *keychainPassword = [keychain getPasswordForName:connectionKeychainItemName account:connectionKeychainItemAccount];
        return keychainPassword ?: @"";
    }

    return [self password] ?: @"";
}

/**
 * Resolves the SSH password for use with SAConnectionService.
 * If keychain item is set and password is the marker, returns empty string
 * (the service passes keychain names through to the tunnel).
 */
- (NSString *)_resolvedSSHPassword
{
    if (connectionSSHKeychainItemName && [[self sshPassword] isEqualToString:@"SequelAceSecretPassword"]) {
        return @""; // Tunnel will use keychain names from SAConnectionInfoObjC
    }
    return [self sshPassword] ?: @"";
}

/**
 * Validates the SSH config file is accessible. Shows alert if not.
 * Returns YES if connection should proceed, NO to abort.
 */
- (BOOL)_validateSSHConfigFile
{
    NSString *sshConfigFile = [[NSUserDefaults standardUserDefaults] stringForKey:SPSSHConfigFile];
    if (sshConfigFile == nil) {
        sshConfigFile = [[NSBundle mainBundle] pathForResource:SPSSHConfigFile ofType:@""];
    }

    if ([SPFileHandle fileHandleForReadingAtPath:sshConfigFile]) {
        return YES; // Config file is accessible
    }

    SPLog(@"Cannot read sshConfigFile: %@", sshConfigFile);

    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:NSLocalizedString(@"Go to Network Settings", @"SSH config file error alert - Go to network settings button")];
    [alert addButtonWithTitle:NSLocalizedString(@"Reset to Default & Continue", @"SSH config file error alert - Reset to default button")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"SSH config file error alert - Cancel button")];
    [alert setMessageText:NSLocalizedString(@"Cannot Access SSH Config File", @"SSH config file error alert title")];
    [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Sequel Ace does not have permission to read the configured SSH config file at '%@'.\n\nThis might be due to Sandbox restrictions. You can configure a different SSH Config File in the Network tab of Preferences or correct access to the exiting file in the Files tab of Preferences, or you can reset the path to the Sequel Ace default.", @"SSH config file error alert message"), sshConfigFile]];
    [alert setAlertStyle:NSAlertStyleWarning];

    NSInteger response = [alert runModal];

    if (response == NSAlertFirstButtonReturn) { // Go to Settings
        SPPreferenceController *prefCon = [((SPAppController *)[NSApp delegate]) preferenceController];
        [prefCon showWindow:nil];
        id filePaneItem = prefCon->networkItem;
        [prefCon displayPreferencePane:filePaneItem];
        [self _restoreConnectionInterface];
        return NO;
    } else if (response == NSAlertSecondButtonReturn) { // Reset to Default
        NSString *defaultSSHConfigPath = [[NSBundle mainBundle] pathForResource:SPSSHConfigFile ofType:@""];
        [[NSUserDefaults standardUserDefaults] setObject:defaultSSHConfigPath forKey:SPSSHConfigFile];
        [[NSUserDefaults standardUserDefaults] synchronize];
        return YES; // Continue with default config
    } else { // Cancel
        [self _restoreConnectionInterface];
        return NO;
    }
}

- (void)_failConnectionWithTitle:(NSString *)theTitle errorMessage:(NSString *)theErrorMessage detail:(NSString *)errorDetail localNetworkPermissionDenied:(BOOL)localNetworkPermissionDenied
{
    void (^presentFailure)(void) = ^{
        self.localNetworkPermissionDeniedForCurrentAttempt = localNetworkPermissionDenied;
        [self failConnectionWithTitle:theTitle errorMessage:theErrorMessage detail:errorDetail];
    };

    if ([NSThread isMainThread]) {
        presentFailure();
    } else {
        dispatch_async(dispatch_get_main_queue(), presentFailure);
    }
}

/**
 * Ends a connection attempt by stopping the connection animation and
 * displaying a specified error message.
 */
- (void)failConnectionWithTitle:(NSString *)theTitle errorMessage:(NSString *)theErrorMessage detail:(NSString *)errorDetail
{
    if(errorShowing == YES){
        SPLog(@"errorShowing already, returning.");
        return;
    }

    BOOL isSSHTunnelBindError = NO;

    [self _restoreConnectionInterface];

    // Release as appropriate
    if (sshTunnel) {
        [sshTunnel disconnect];

        // If the SSH tunnel connection failed because the port it was trying to bind to was already in use take note
        // of it so we can give the user the option of connecting via standard connection and use the existing tunnel.
        if ([theErrorMessage rangeOfString:@"bind"].location != NSNotFound) {
            isSSHTunnelBindError = YES;
        }
    }

    if (errorDetail && [errorDetail length] > 0) [errorDetailText setString:errorDetail];

    // Inform the delegate that the connection attempt failed
    if (delegate && [delegate respondsToSelector:@selector(connectionControllerConnectAttemptFailed:)]) {
        [[(id)delegate onMainThread] connectionControllerConnectAttemptFailed:self];
    }

    // Notify the new-style connection delegate about the failure
    if (self.connectionDelegate) {
        [self.connectionDelegate connectionDidFailWithError:theTitle ?: @"Connection failed"
                                                     detail:errorDetail];
    }

    NSString *errorMessage = errorDetail ? : @"";
    if (theErrorMessage) {
        errorMessage = [errorMessage stringByAppendingString:@"\n"];
        errorMessage = [errorMessage stringByAppendingString:theErrorMessage];
    }

    BOOL shouldShowLocalNetworkPermissionAlert = self.localNetworkPermissionDeniedForCurrentAttempt || [self _shouldShowLocalNetworkPermissionAlertForErrorMessage:theErrorMessage detail:errorDetail];
    self.localNetworkPermissionDeniedForCurrentAttempt = NO;

    // Only display the connection error message if there is a window visible
    if ([[dbDocument parentWindowControllerWindow] isVisible]) {
        if (shouldShowLocalNetworkPermissionAlert) {
            errorShowing = YES;
            [self _showLocalNetworkPermissionAlert];
            errorShowing = NO;

            // we're not connecting anymore, it failed.
            isConnecting = NO;
            // update tab and window title
            [dbDocument updateWindowTitle:self];

            return;
        }

        NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,488,140)];
        [scrollView setDrawsBackground:NO];
        [scrollView setHasVerticalScroller:YES];
        
        NSScroller *verticalScroller = [scrollView verticalScroller];
        CGFloat scrollbarWidth = NSWidth([verticalScroller frame]);
        NSRect textViewFrame = scrollView.bounds;
        textViewFrame.size.width = scrollView.frame.size.width - scrollbarWidth;

        NSText *errorMessageTextView = [[NSText alloc] initWithFrame:textViewFrame];
        [errorMessageTextView setString:errorMessage];
        [errorMessageTextView setEditable:NO];
        [errorMessageTextView setDrawsBackground:NO];

        [scrollView setDocumentView:errorMessageTextView];

        errorShowing = YES;
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:theTitle];
        [alert setAccessoryView:scrollView];
        [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
        if (isSSHTunnelBindError) {
            [alert addButtonWithTitle:NSLocalizedString(@"Use Standard Connection", @"use standard connection button")];
        }
        NSModalResponse returnCode = [alert runModal];
        if (returnCode == NSAlertSecondButtonReturn) {
            // Extract the local port number that SSH attempted to bind to from the debug output
            NSString *tunnelPort = [[[errorDetailText string] componentsMatchedByRegex:@"LOCALHOST:([0-9]+)" capture:1L] lastObject];

            // Change the connection type to standard TCP/IP
            [self setType:SPTCPIPConnection];

            // Change connection details
            [self setPort:tunnelPort];
            [self setHost:SPLocalhostAddress];

            // Change to standard TCP/IP connection view
            [self resizeTabViewToConnectionType:SPTCPIPConnection animating:YES];

            // Initiate the connection after a half second delay to give the connection view a chance to resize
            [self performSelector:@selector(initiateConnection:) withObject:self afterDelay:0.5];
        }

        errorShowing = NO;

        // we're not connecting anymore, it failed.
        isConnecting = NO;
        // update tab and window title
        [dbDocument updateWindowTitle:self];
    }
}

- (BOOL)_shouldShowLocalNetworkPermissionAlertForErrorMessage:(NSString *)errorMessage detail:(NSString *)errorDetail
{
    if ([self type] != SPSSHTunnelConnection) return NO;

    // Local Network privacy restrictions for sandboxed macOS apps started with macOS 15 (Sequoia).
    if (@available(macOS 15.0, *)) {
        return SPSSHNoRouteToHostLikelyLocalNetworkPrivacyIssue(errorMessage, errorDetail, [self sshHost]);
    }

    return NO;
}

- (BOOL)_isLocalNetworkAccessDeniedForCurrentConnectionAttempt
{
    if (@available(macOS 15.0, *)) {
        BOOL shouldProbeForLocalNetworkDenial = NO;

        if ([self type] == SPSSHTunnelConnection && sshTunnel) {
            if ([sshTunnel state] == SPMySQLProxyIdle) {
                // SSH setup failed before MySQL had a chance to emit a network error.
                shouldProbeForLocalNetworkDenial = YES;
            } else if ([sshTunnel state] == SPMySQLProxyConnected) {
                // SSH is already connected; probing the SSH host cannot indicate local-network denial.
                return NO;
            }
        } else {
            NSUInteger lastErrorID = [mySQLConnection lastErrorID];
            if (lastErrorID == 1045) return NO; // Access denied credentials error.

            NSString *lastErrorMessage = [[mySQLConnection lastErrorMessage] lowercaseString] ?: @"";
            BOOL looksLikeNetworkFailure = ([lastErrorMessage rangeOfString:@"can't connect"].location != NSNotFound
                                            || [lastErrorMessage rangeOfString:@"timed out"].location != NSNotFound
                                            || [lastErrorMessage rangeOfString:@"no route to host"].location != NSNotFound
                                            || [lastErrorMessage rangeOfString:@"network is unreachable"].location != NSNotFound);

            shouldProbeForLocalNetworkDenial = (looksLikeNetworkFailure || lastErrorID == 2002 || lastErrorID == 2003);
        }

        if (!shouldProbeForLocalNetworkDenial) return NO;

        NSString *probeHost = nil;
        NSInteger probePort = 0;

        if ([self type] == SPTCPIPConnection) {
            probeHost = [self host];
            probePort = ([[self port] length] ? [[self port] integerValue] : 3306);
        } else if ([self type] == SPSSHTunnelConnection) {
            probeHost = [self sshHost];
            probePort = ([[self sshPort] length] ? [[self sshPort] integerValue] : 22);
        } else {
            return NO;
        }

        probeHost = [probeHost stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (![probeHost length]) return NO;
        if (probePort <= 0) return NO;
        if ([[probeHost lowercaseString] isEqualToString:@"localhost"] || [probeHost isEqualToString:@"127.0.0.1"] || [probeHost isEqualToString:@"::1"]) return NO;

        return [SALocalNetworkPermissionChecker isLocalNetworkAccessDeniedForHost:probeHost port:probePort timeout:0.75];
    }

    return NO;
}

- (void)_showLocalNetworkPermissionAlert
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:NSLocalizedString(@"Local Network Access is Required", @"title for local network privacy alert")];
    NSString *informativeText = nil;
    if ([self type] == SPSSHTunnelConnection) {
        informativeText = NSLocalizedString(@"Sequel Ace could not reach the SSH host on your local network. On macOS 15 (Sequoia) and later, this often means Local Network access is disabled for Sequel Ace.\n\nOpen System Settings > Privacy & Security > Local Network and enable Sequel Ace, then try connecting again.", @"informative text for local network privacy alert (ssh)");
    } else {
        informativeText = NSLocalizedString(@"Sequel Ace could not reach the database host on your local network. On macOS 15 (Sequoia) and later, this often means Local Network access is disabled for Sequel Ace.\n\nOpen System Settings > Privacy & Security > Local Network and enable Sequel Ace, then try connecting again.", @"informative text for local network privacy alert (direct)");
    }
    [alert setInformativeText:informativeText];
    [alert addButtonWithTitle:NSLocalizedString(@"Open Local Network Settings", @"button title to open local network privacy settings")];
    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];

    NSModalResponse alertResponse = [alert runModal];
    if (alertResponse != NSAlertFirstButtonReturn) return;

    if ([self _openLocalNetworkPrivacySettings]) return;

    [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Unable to Open System Settings", @"title when local network privacy settings deep link fails")
                                 message:NSLocalizedString(@"Couldn't open the Local Network privacy settings automatically.\n\nIn macOS, open System Settings > Privacy & Security > Local Network and enable Sequel Ace.", @"message shown when local network privacy settings deep link fails")
                                callback:nil];
}

- (BOOL)_openLocalNetworkPrivacySettings
{
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];

    NSArray<NSString *> *settingsURLs = @[
        @"x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocalNetwork",
        @"x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork",
        @"x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        @"x-apple.systempreferences:com.apple.preference.security"
    ];

    for (NSString *settingsURL in settingsURLs) {
        NSURL *url = [NSURL URLWithString:settingsURL];
        if (url && [workspace openURL:url]) return YES;
    }

    return NO;
}

#pragma mark - SPConnectionHandlerPrivateAPI

/**
 * Display a connection test error or success message
 */
- (void)_showConnectionTestResult:(NSString *)resultString
{
    if (![NSThread isMainThread]) {
        [[self onMainThread] _showConnectionTestResult:resultString];
    }

    [helpButton setHidden:NO];
    [progressIndicator stopAnimation:self];
    [progressIndicatorText setStringValue:resultString];
    [progressIndicatorText setHidden:NO];
}

#pragma mark - SPConnectionControllerDelegate

#pragma mark SplitView delegate methods

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)dividerIndex
{
    return 145.f;
}

#pragma mark -
#pragma mark SAFavoritesListDelegate

- (void)favoritesListSelectionDidChange:(SPTreeNode *)selectedNode
{
    if (isEditingConnection) {
        [self _stopEditingConnection];
        [favoritesOutlineView setNeedsDisplay:YES];
    }

    NSInteger selected = [favoritesOutlineView numberOfSelectedRows];

    if (selected == 1) {
        [self updateFavoriteSelection:self];
        favoriteNameFieldWasAutogenerated = NO;
        [connectionResizeContainer setHidden:NO];
        [connectionInstructionsTextField setStringValue:NSLocalizedString(@"Enter connection details below, or choose a favorite", @"enter connection details label")];
    }
    else if (selected > 1) {
        [connectionResizeContainer setHidden:YES];
        [connectionInstructionsTextField setStringValue:NSLocalizedString(@"Please choose a favorite", @"please choose a favorite connection view label")];
    }
}

- (void)favoritesListNodeDoubleClicked:(SPTreeNode *)node
{
    [self nodeDoubleClicked:self];
}

- (void)favoritesListDidRenameNode:(SPTreeNode *)node to:(NSString *)newName
{
    if (![node isGroup]) {
        // Note: this saves the full form state, matching the original outlineView:setObjectValue:
        // behavior. A future improvement could save only the name field.
        [self setName:newName];
        [self _saveCurrentDetailsCreatingNewFavorite:NO validateDetails:NO];
    }
    else {
        [[node representedObject] setNodeName:newName];
        [favoritesController saveFavorites];
        [self _reloadFavoritesViewData];
    }
}

- (void)favoritesListDidReorderNodes
{
    currentSortItem = SPFavoritesSortUnsorted;
    reverseFavoritesSort = NO;

    [prefs setInteger:currentSortItem forKey:SPFavoritesSortedBy];
    [prefs setBool:NO forKey:SPFavoritesSortedInReverse];

    for (NSMenuItem *menuItem in [[favoritesSortByMenuItem submenu] itemArray]) {
        [menuItem setState:NSControlStateValueOff];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:SPConnectionFavoritesChangedNotification object:self];
    [[[SPAppDelegate preferenceController] generalPreferencePane] updateDefaultFavoritePopup];
}

- (void)favoritesListEditingStateChangedWithIsEditing:(BOOL)isEditing
{
    if (!isEditing && isEditingConnection) {
        [self _stopEditingConnection];
        [favoritesOutlineView setNeedsDisplay:YES];
    }
}

- (BOOL)favoritesListShouldBeginDrag
{
    if (isEditingItemName) {
        [favoritesController saveFavorites];
        [self _reloadFavoritesViewData];
        isEditingItemName = NO;
        return NO;
    }
    return YES;
}

#pragma mark -
#pragma mark Textfield delegate methods

/**
 * React to control text changes in the connection interface
 */
- (void)controlTextDidChange:(NSNotification *)notification
{
    id field = [notification object];

    // Ignore changes in the outline view edit fields
    if ([field isKindOfClass:[NSOutlineView class]]) {
        return;
    }

    // If a 'name' field was edited, and is now of zero length, trigger a replacement
    // with a standard suggestion
    if (((field == standardNameField) || (field == awsIAMNameField) || (field == socketNameField) || (field == sshNameField)) && [self selectedFavoriteNode]) {
        if (![[self _stripInvalidCharactersFromString:[field stringValue]] length]) {
            [self controlTextDidEndEditing:notification];
        }
    }

    [self _startEditingConnection];

    if (favoriteNameFieldWasAutogenerated && (field != standardNameField && field != awsIAMNameField && field != socketNameField && field != sshNameField)) {
        [self setName:[self _generateNameForConnection]];
    }

    if (field == standardSQLHostField || field == standardUserField || field == sshSQLHostField || field == sshUserField) {
        standardPasswordField.stringValue = @"";
        sshPasswordField.stringValue = @"";
    }
}

/**
 * React to the end of control text changes in the connection interface.
 */
- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    id field = [notification object];

    // Handle updates to the 'name' field of the selected favourite.  The favourite name should
    // have leading or trailing spaces removed at the end of editing, and if it's left empty,
    // should have a default name set.
    if (((field == standardNameField) || (field == awsIAMNameField) || (field == socketNameField) || (field == sshNameField)) && [self selectedFavoriteNode]) {

        NSString *favoriteName = [self _stripInvalidCharactersFromString:[field stringValue]];

        if (![favoriteName length]) {
            favoriteName = [self _generateNameForConnection];

            if (favoriteName) {
                [self setName:favoriteName];
            }

            // Enable user@host update in reaction to other UI changes
            favoriteNameFieldWasAutogenerated = YES;
        }
        else if (![[field stringValue] isEqualToString:[self _generateNameForConnection]]) {
            favoriteNameFieldWasAutogenerated = NO;
            [self setName:favoriteName];
        }
    }
}

#pragma mark -
#pragma mark Tab bar delegate methods

/**
 * Trigger a resize action whenever the tab view changes. The connection
 * detail forms are held within container views, which are of a fixed width;
 * the tabview and buttons are contained within a resizable view which
 * is set to dimensions based on the container views, allowing the view
 * to be sized according to the detail type.
 */
- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    NSInteger selectedTabView = [tabView indexOfTabViewItem:tabViewItem];


    if (selectedTabView == previousType) return;

    [self _startEditingConnection];

    [self resizeTabViewToConnectionType:selectedTabView animating:YES];


    if (selectedTabView == SPSocketConnection) {

        // check we don't already have this window open
        BOOL correspondingWindowFound = NO;
        for(id win in [NSApp windows]) {
            if([[win delegate] isKindOfClass:[SPBundleHTMLOutputController class]]) {
                if([[[win delegate] windowUUID] isEqualToString:socketHelpWindowUUID]) {
                    correspondingWindowFound = YES;
                    SPLog(@"correspondingWindowFound: %hhd", correspondingWindowFound);
                    break;
                }
            }
        }

        if(correspondingWindowFound == NO){
            if([prefs boolForKey:SPConnectionShownSocketHelp] == NO){
                SPLog(@"SPSocketConnection chosen, no current window open, and not show before");

                NSError *error = nil;

                // show socket help
                self.socketHelpWindowUUID = [NSString stringWithNewUUID];
                SPBundleHTMLOutputController *bundleController = [[SPBundleHTMLOutputController alloc] init];
                [bundleController setWindowUUID:socketHelpWindowUUID];

                NSDictionary *tmpDic2 = @{@"x" : @225, @"y" : @536, @"w" : @768, @"h" : @425};
                NSDictionary *tmpDict = @{SPConnectionShownSocketHelp : @YES, @"frame" : tmpDic2};

                if ([self connected]) {
                    SPLog(@"Connected, loading remote URL");
                    [bundleController displayURLString:SPDocsSocketConnection withOptions:tmpDict];
                }
                else{
                    SPLog(@"Not connected, loading local file");
                    NSString *path = [[NSBundle mainBundle] pathForResource:@"local-connection" ofType:@"html"];
                    SPLog(@"path: %@", path);

                    NSString *html = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];

                    if(error == nil){
                        // slightly larger
                        NSMutableDictionary *mutDict = [tmpDict mutableCopy];
                        mutDict[@"frame"] = @{@"x" : @225, @"y" : @536, @"w" : @768, @"h" : @600};

                        [bundleController displayHTMLContent:html withOptions:mutDict];
                    }
                }
                if(error == nil){
                    [SPBundleManager.shared addHTMLOutputController:bundleController];
                }
                // set straight away, or wait for them to close the window?
                //[prefs setBool:YES forKey:SPConnectionShownSocketHelp];
            }
        }
    }


    previousType = selectedTabView;

    [self _favoriteTypeDidChange];
}

#pragma mark -
#pragma mark Color Selector delegate

- (void)colorSelectorDidChange:(SPColorSelectorView *)sel
{
    [self _startEditingConnection];
}

#pragma mark -
#pragma mark Scroll view notifications

/**
 * As the scrollview resizes, keep the details centered within it if
 * the detail frame is larger than the scrollview size; otherwise, pin
 * the detail frame to the top of the scrollview.
 */
- (void)scrollViewFrameChanged:(NSNotification *)aNotification
{
    NSRect scrollViewFrame = [connectionDetailsScrollView frame];
    NSRect scrollDocumentFrame = [[connectionDetailsScrollView documentView] frame];
    NSRect connectionDetailsFrame = [connectionResizeContainer frame];

    // Scroll view is smaller than contents - keep positioned at top.
    if (scrollViewFrame.size.height < connectionDetailsFrame.size.height + 10) {
        connectionDetailsFrame.origin.y = 0;
        [connectionResizeContainer setFrame:connectionDetailsFrame];
        scrollDocumentFrame.size.height = connectionDetailsFrame.size.height + 10;
        [[connectionDetailsScrollView documentView] setFrame:scrollDocumentFrame];

        // Keep the visible area pinned to the top of the connection form.
        NSClipView *clipView = [connectionDetailsScrollView contentView];
        BOOL documentIsFlipped = [[connectionDetailsScrollView documentView] isFlipped];
        CGFloat topY = documentIsFlipped ? 0.f : MAX(0.f, NSMaxY(scrollDocumentFrame) - NSHeight([clipView bounds]));
        [clipView scrollToPoint:NSMakePoint(0.f, topY)];
        [connectionDetailsScrollView reflectScrolledClipView:clipView];
    }
    // Otherwise, center
    else {
        // Keep near-centered placement, with a slight upward bias so the details don't appear too low.
        CGFloat availableVerticalSpace = scrollViewFrame.size.height - connectionDetailsFrame.size.height;
        connectionDetailsFrame.origin.y = availableVerticalSpace * 0.58f;
        // the division may lead to values that are not valid for the current screen size (e.g. non-integer values on a
        // @1x non-retina screen). The OS works something out when not using layer-backed views, but in the latter
        // case the result will look like garbage if we don't fix this.
        connectionDetailsFrame = [connectionDetailsScrollView backingAlignedRect:connectionDetailsFrame options:NSAlignAllEdgesNearest];
        [connectionResizeContainer setFrame:connectionDetailsFrame];
        scrollDocumentFrame.size.height = scrollViewFrame.size.height;
        [[connectionDetailsScrollView documentView] setFrame:scrollDocumentFrame];
    }
}

#pragma mark -
#pragma mark Menu Validation

/**
 * Menu item validation.
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    SEL action = [menuItem action];

    SPTreeNode *node = [self selectedFavoriteNode];
    NSInteger selectedRows = [favoritesOutlineView numberOfSelectedRows];

    if ((action == @selector(sortFavorites:)) || (action == @selector(reverseSortFavorites:))) {

        if ([[favoritesRoot allChildLeafs] count] < 2) return NO;

        // Loop all the items in the sort by menu only checking the currently selected one
        for (NSMenuItem *item in [[menuItem menu] itemArray])
        {
            [item setState:([[menuItem menu] indexOfItem:item] == currentSortItem)];
        }

        // Check or uncheck the reverse sort item
        if (action == @selector(reverseSortFavorites:)) {
            [menuItem setState:reverseFavoritesSort];
        }

        return YES;
    }

    // import does not depend on a selection
    if(action == @selector(importFavorites:)) return YES;

    if (node == quickConnectItem) return NO;

    // Remove/rename the selected node
    if (action == @selector(removeNode:) || action == @selector(renameNode:)) {
        return selectedRows == 1;
    }

    // Duplicate and make the selected favorite the default
    if (action == @selector(duplicateFavorite:)) {
        return ((selectedRows == 1) && (![node isGroup]));
    }

    // Make selected favorite the default
    if (action == @selector(makeSelectedFavoriteDefault:)) {
        NSInteger favoriteID = [[[self selectedFavorite] objectForKey:SPFavoriteIDKey] integerValue];

        return ((selectedRows == 1) && (![node isGroup]) && (favoriteID != [prefs integerForKey:SPDefaultFavorite]));
    }

    // Favorites export
    if (action == @selector(exportFavorites:)) {

        if ([[favoritesRoot allChildLeafs] count] == 0 || selectedRows == 0) {
            return NO;
        }
        else if (selectedRows > 1) {
            [menuItem setTitle:NSLocalizedString(@"Export Selected...", @"export selected favorites menu item")];
        }
    }

    return YES;
}

#pragma mark -
#pragma mark Favorites import/export delegate methods

/**
 * Called by the favorites importer when the imported data is available.
 */
- (void)favoritesImportData:(NSArray *)data
{
    SPTreeNode *newNode;
    NSMutableArray *importedNodes = [NSMutableArray array];
    NSMutableIndexSet *importedIndexSet = [NSMutableIndexSet indexSet];

    // Add each of the imported favorites to the root node
    for (NSMutableDictionary *favorite in data)
    {
        newNode = [favoritesController addFavoriteNodeWithData:favorite asChildOfNode:nil];
        [importedNodes addObject:newNode];
    }

    if (currentSortItem > SPFavoritesSortUnsorted) {
        [self _sortFavorites];
    }

    [self _reloadFavoritesViewData];

    // Select the new nodes and scroll into view
    for (SPTreeNode *eachNode in importedNodes)
    {
        [importedIndexSet addIndex:[favoritesOutlineView rowForItem:eachNode]];
    }

    [favoritesOutlineView selectRowIndexes:importedIndexSet byExtendingSelection:NO];

    [self _scrollToSelectedNode];
}

/**
 * Called by the favorites importer when the import completes.
 */
- (void)favoritesImportCompletedWithError:(NSError *)error
{
    if (error) {

        NSAlert *alert = [[NSAlert alloc] init];

        // jamesstout notes
        // Alerts should be created with the -init method and setting properties. - NSAlert.h L132
        alert.messageText = NSLocalizedString(@"Favorites import error", @"favorites import error message");
        alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"The following error occurred during the import process:\n\n%@", @"favorites import error informative message"), [error localizedDescription]];
        [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];

        // jamesstout notes
        // API_DEPRECATED("Use -beginSheetModalForWindow:completionHandler: instead" - - NSAlert.h L136
        [alert beginSheetModalForWindow:[dbDocument parentWindowControllerWindow] completionHandler:nil];
    }
}

#pragma mark -
#pragma mark Private API

#pragma mark - SPConnectionControllerInitializer

/**
 * Initialise the connection controller, linking it to the parent document and setting up the parent window.
 */
- (instancetype)initWithDocument:(id<SADatabaseDocumentProviding>)document
{

    SPLog(@"initWithDocument");

    if ((self = [super init])) {

        // Weak reference
        dbDocument = document;

        databaseConnectionView = [dbDocument contentViewSplitter];


        // Keychain references
        connectionKeychainItemName = nil;
        connectionKeychainItemAccount = nil;
        connectionSSHKeychainItemName = nil;
        connectionSSHKeychainItemAccount = nil;

        initComplete = NO;
        isEditingItemName = NO;
        isConnecting = NO;
        isTestingConnection = NO;
        sshTunnel = nil;
        mySQLConnection = nil;
        cancellingConnection = NO;
        favoriteNameFieldWasAutogenerated = NO;
        allowSplitViewResizing = NO;

        [self loadNib];

        NSArray *colorList = SPFavoriteColorSupport.sharedInstance.userColorList;
        [sshColorField setColorList:colorList];
        [sshColorField      bind:@"selectedTag" toObject:self withKeyPath:@"colorIndex" options:nil];
        [standardColorField setColorList:colorList];
        [standardColorField bind:@"selectedTag" toObject:self withKeyPath:@"colorIndex" options:nil];
        [awsIAMColorField setColorList:colorList];
        [awsIAMColorField bind:@"selectedTag" toObject:self withKeyPath:@"colorIndex" options:nil];
        [socketColorField setColorList:colorList];
        [socketColorField   bind:@"selectedTag" toObject:self withKeyPath:@"colorIndex" options:nil];

        // An instance of NSMenuItem can not be assigned to more than one menu so we have to clone items.
        // Cannot bulk set items on macOS < 10.14, must removeAllItems and addItem https://github.com/Sequel-Ace/Sequel-Ace/issues/403
        [standardTimeZoneField.menu removeAllItems];
        [awsIAMTimeZoneField.menu removeAllItems];
        [sshTimeZoneField.menu removeAllItems];
        [socketTimeZoneField.menu removeAllItems];
        for (NSMenuItem *menuItem in [self generateTimeZoneMenuItems]) {
            [standardTimeZoneField.menu addItem:[menuItem copy]];
            [awsIAMTimeZoneField.menu addItem:[menuItem copy]];
            [sshTimeZoneField.menu addItem:[menuItem copy]];
            [socketTimeZoneField.menu addItem:[menuItem copy]];
        }

        [connectionDetailsScrollView setPostsFrameChangedNotifications:YES];
        [[connectionDetailsScrollView contentView] setPostsFrameChangedNotifications:YES];

        [self registerForNotifications];

        // Create the view coordinator and show the connection view
        self.viewCoordinator = [[SAConnectionViewCoordinator alloc]
            initWithDatabaseContentView:databaseConnectionView
            containerView:[dbDocument databaseView]];
        [self.viewCoordinator showConnectionView:connectionView];

        // Set up the splitview
        [connectionSplitView setMinSize:150.f ofSubviewAtIndex:0];
        [connectionSplitView setMinSize:445.f ofSubviewAtIndex:1];

        // Set up a keychain instance and preferences reference, and create the initial favorites list
        keychain = [[SPKeychain alloc] init];
        prefs = [NSUserDefaults standardUserDefaults];

        bookmarks = [NSMutableArray arrayWithArray:SecureBookmarkManager.sharedInstance.bookmarks];
        awsAvailableRegionValues = [AWSIAMAuthManager cachedOrFallbackRegions];

        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_refreshBookmarks) name:SPBookmarksChangedNotification object:SecureBookmarkManager.sharedInstance];

        // Create a reference to the favorites controller, forcing the data to be loaded from disk
        // and the tree to be constructed.
        favoritesController = [SPFavoritesController sharedFavoritesController];

        // Set up the favorites list data source (owns tree data, Quick Connect item, outline view delegate)
        favoritesRoot = [favoritesController favoritesTree];
        currentFavorite = nil;

        self.favoritesListDataSource = [[SAFavoritesListDataSource alloc]
            initWithFavoritesRoot:favoritesRoot
            favoritesController:favoritesController];
        self.favoritesListDataSource.delegate = (id<SAFavoritesListDelegate>)self;

        // Keep local references in sync with the data source
        quickConnectItem = self.favoritesListDataSource.quickConnectItem;
        quickConnectCell = self.favoritesListDataSource.quickConnectCell;
        folderImage = self.favoritesListDataSource.folderImage;

        // Attach the data source to the outline view and set up remaining outline view config
        [self.favoritesListDataSource attachTo:favoritesOutlineView];
        [self setUpFavoritesOutlineView];
        [self.favoritesListDataSource reloadDataIn:favoritesOutlineView];
        [self.favoritesListDataSource restoreOutlineViewState:favoritesRoot in:favoritesOutlineView];

        // Set up the selected favourite, and scroll after a small delay to fix animation delay on Lion
        [self setUpSelectedConnectionFavorite];
        if ([favoritesOutlineView selectedRow] != -1) {
            [self performSelector:@selector(_scrollToSelectedNode) withObject:nil afterDelay:0.0];
        }

        // Set sort items
        currentSortItem = (SPFavoritesSortItem)[prefs integerForKey:SPFavoritesSortedBy];
        reverseFavoritesSort = [prefs boolForKey:SPFavoritesSortedInReverse];

        // Update AWS authorization UI state and kick off async region refresh.
        [self updateAWSAuthorizationUI];
        [self _refreshAWSAvailableRegions];

        // Track profile/region edits the same way as the IAM toggle.
        [awsProfilePopup setTarget:self];
        [awsProfilePopup setAction:@selector(updateAWSIAMInterface:)];
        [awsRegionComboBox setTarget:self];
        [awsRegionComboBox setAction:@selector(updateAWSIAMInterface:)];

        // Initialize the connection service
        self.connectionService = [[SAConnectionService alloc] init];
        if ([dbDocument conformsToProtocol:@protocol(SPMySQLConnectionDelegate)]) {
            self.connectionService.mySQLDelegate = (id<SPMySQLConnectionDelegate>)dbDocument;
        }

        initComplete = YES;

        // Force a resize after a tiny delay to ensure view is fully loaded
        [self performSelector:@selector(_forceInitialResize) withObject:nil afterDelay:0.0];
    }

    return self;
}

- (void)_forceInitialResize {
    [self resizeTabViewToConnectionType:[self type] animating:NO];
}

- (void)_refreshBookmarks{
    SPLog(@"Got SPBookmarksChangedNotification, refreshing bookmarks");

    [bookmarks setArray:SecureBookmarkManager.sharedInstance.bookmarks];

    // Also refresh AWS authorization UI in case AWS directory bookmark changed
    [self updateAWSAuthorizationUI];

    // Notify that profiles may have changed
    [self willChangeValueForKey:@"awsAvailableProfiles"];
    [self didChangeValueForKey:@"awsAvailableProfiles"];
}

// TODO: this is called once per connection screen - but the timezones don't change right? Should be static/class method?
- (NSArray<NSMenuItem *> *)generateTimeZoneMenuItems
{
    NSArray<NSString *> *timeZoneIdentifiers = [NSTimeZone.knownTimeZoneNames sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    // timeZoneIdentifiers.count + (fixed entries and separators) + (separators for time zone prefixes)
    NSMutableArray<NSMenuItem *> *timeZoneMenuItems = [NSMutableArray arrayWithCapacity:timeZoneIdentifiers.count + 4 + 11];

    // Use Server Time Zone
    NSMenuItem *useServerTimeZoneMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Use Server Time Zone", @"Leave the server time zone in place when connecting") action:nil keyEquivalent:@""];
    useServerTimeZoneMenuItem.tag = SPUseServerTimeZoneTag;
    [timeZoneMenuItems addObject:useServerTimeZoneMenuItem];

    [timeZoneMenuItems addObject:NSMenuItem.separatorItem];

    // Use System Time Zone
    NSMenuItem *useSystemTimeZoneMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Use System Time Zone", @"Set the time zone currently used by the user when connecting") action:nil keyEquivalent:@""];
    useSystemTimeZoneMenuItem.tag = SPUseSystemTimeZoneTag;
    [timeZoneMenuItems addObject:useSystemTimeZoneMenuItem];

    // Add all identifier entries and insert a separator every time the prefix changes
    NSString *previousPrefix = @"";
    for (NSString *tzIdentifier in timeZoneIdentifiers) {
        NSString *currentPrefix = [tzIdentifier componentsSeparatedByString:@"/"].firstObject;
        if (![currentPrefix isEqualToString:previousPrefix]) {
            previousPrefix = currentPrefix;
            [timeZoneMenuItems addObject:NSMenuItem.separatorItem];
        }
        NSMenuItem *entry = [[NSMenuItem alloc] initWithTitle:tzIdentifier action:nil keyEquivalent:@""];
        [timeZoneMenuItems addObject:entry]; // adding to an array retains the object // so we can release here. otherwise we leak.
    }

    return timeZoneMenuItems;
}

/**
 * Loads the connection controllers UI nib.
 */
- (void)loadNib
{

    NSArray *connectionViewTopLevelObjects = nil;
    NSNib *nibLoader = [[NSNib alloc] initWithNibNamed:SPConnectionViewNibName bundle:[NSBundle mainBundle]];
    [nibLoader instantiateWithOwner:self topLevelObjects:&connectionViewTopLevelObjects];
}

/**
 * Registers for various notifications.
 */
- (void)registerForNotifications
{
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;

    [nc addObserver:self
           selector:@selector(_documentWillClose:)
               name:SPDocumentWillCloseNotification
             object:nil];

    [nc addObserver:self
           selector:@selector(scrollViewFrameChanged:)
               name:NSViewFrameDidChangeNotification
             object:connectionDetailsScrollView];
    [nc addObserver:self
           selector:@selector(scrollViewFrameChanged:)
               name:NSViewFrameDidChangeNotification
             object:[connectionDetailsScrollView contentView]];
    [nc addObserver:self
           selector:@selector(_processFavoritesDataChange:)
               name:SPConnectionFavoritesChangedNotification
             object:nil];

    // Registered to be notified of changes to connection information
    [self addObserver:self
           forKeyPath:SPFavoriteTypeKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteNameKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteHostKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteUserKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteColorIndexKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteDatabaseKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteSocketKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoritePortKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteAllowDataLocalInfileKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteEnableClearTextPluginKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteUseSSLKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteSSHHostKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteSSHUserKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteSSHPortKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteSSHKeyLocationEnabledKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteSSHKeyLocationKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteSSLKeyFileLocationEnabledKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteSSLKeyFileLocationKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteSSLCertificateFileLocationEnabledKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteSSLCertificateFileLocationKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteSSLCACertFileLocationEnabledKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];

    [self addObserver:self
           forKeyPath:SPFavoriteSSLCACertFileLocationKey
              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
              context:NULL];
}

/**
 * Performs any set up necessary for the favorities outline view.
 */
- (void)setUpFavoritesOutlineView
{
    // Register double click action for the favorites outline view (double click favorite to connect)
    [favoritesOutlineView setTarget:self];
    [favoritesOutlineView setDoubleAction:@selector(nodeDoubleClicked:)];

    // Drag types and data source/delegate are handled by favoritesListDataSource via -attachTo:

    NSFont *tableFont = [NSUserDefaults getFont];
    [favoritesOutlineView setRowHeight:4.0f + NSSizeToCGSize([@"{ǞṶḹÜ∑zgyf" sizeWithAttributes:@{NSFontAttributeName : tableFont}]).height];

    [favoritesOutlineView setFont:tableFont];
    for (NSTableColumn *col in [favoritesOutlineView tableColumns]) {
        [[col dataCell] setFont:tableFont];
    }

    // Register for font change notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(fontChanged:)
                                                 name:@"SPFontChangedNotification"
                                               object:nil];
}

/**
 * Sets up the selected connection favorite according to the user's preferences.
 */
- (void)setUpSelectedConnectionFavorite
{
    SPTreeNode *favorite = [self _favoriteNodeForFavoriteID:[prefs integerForKey:[prefs boolForKey:SPSelectLastFavoriteUsed] ? SPLastFavoriteID : SPDefaultFavorite]];

    if (favorite) {

        if (favorite == quickConnectItem) {
            [self _selectNode:favorite];
        }
        else {
            NSNumber *typeNumber = [[[favorite representedObject] nodeFavorite] objectForKey:SPFavoriteTypeKey];
            previousType = typeNumber ? [typeNumber integerValue] : SPTCPIPConnection;

            [self _selectNode:favorite];
            [self resizeTabViewToConnectionType:[[[[favorite representedObject] nodeFavorite] objectForKey:SPFavoriteTypeKey] integerValue] animating:NO];
        }

        [self _scrollToSelectedNode];
    }
    else {
        previousType = SPTCPIPConnection;

        [self resizeTabViewToConnectionType:SPTCPIPConnection animating:NO];
    }
}

#pragma mark -
#pragma mark Private API

/**
 * Responds to notifications that the favorites root has changed,
 * and updates the interface to match.
 */
- (void)_processFavoritesDataChange:(NSNotification *)aNotification
{
    // Check the supplied notification for the sender; if the sender
    // was this object, ignore it
    if ([aNotification object] == self) return;

    NSArray *selectedFavoriteNodes = [self selectedFavoriteNodes];

    [self _reloadFavoritesViewData];

    NSMutableIndexSet *selectionIndexes = [NSMutableIndexSet indexSet];

    for (SPTreeNode *eachNode in selectedFavoriteNodes)
    {
        NSInteger anIndex = [favoritesOutlineView rowForItem:eachNode];

        if (anIndex == -1) continue;

        [selectionIndexes addIndex:anIndex];
    }

    [favoritesOutlineView selectRowIndexes:selectionIndexes byExtendingSelection:NO];
}

#pragma mark -

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];

    // Unregister observers
    [self removeObserver:self forKeyPath:SPFavoriteTypeKey];
    [self removeObserver:self forKeyPath:SPFavoriteNameKey];
    [self removeObserver:self forKeyPath:SPFavoriteHostKey];
    [self removeObserver:self forKeyPath:SPFavoriteUserKey];
    [self removeObserver:self forKeyPath:SPFavoriteColorIndexKey];
    [self removeObserver:self forKeyPath:SPFavoriteDatabaseKey];
    [self removeObserver:self forKeyPath:SPFavoriteSocketKey];
    [self removeObserver:self forKeyPath:SPFavoritePortKey];
    [self removeObserver:self forKeyPath:SPFavoriteAllowDataLocalInfileKey];
    [self removeObserver:self forKeyPath:SPFavoriteEnableClearTextPluginKey];
    [self removeObserver:self forKeyPath:SPFavoriteUseSSLKey];
    [self removeObserver:self forKeyPath:SPFavoriteSSHHostKey];
    [self removeObserver:self forKeyPath:SPFavoriteSSHUserKey];
    [self removeObserver:self forKeyPath:SPFavoriteSSHPortKey];
    [self removeObserver:self forKeyPath:SPFavoriteSSHKeyLocationEnabledKey];
    [self removeObserver:self forKeyPath:SPFavoriteSSHKeyLocationKey];
    [self removeObserver:self forKeyPath:SPFavoriteSSLKeyFileLocationEnabledKey];
    [self removeObserver:self forKeyPath:SPFavoriteSSLKeyFileLocationKey];
    [self removeObserver:self forKeyPath:SPFavoriteSSLCertificateFileLocationEnabledKey];
    [self removeObserver:self forKeyPath:SPFavoriteSSLCertificateFileLocationKey];
    [self removeObserver:self forKeyPath:SPFavoriteSSLCACertFileLocationEnabledKey];
    [self removeObserver:self forKeyPath:SPFavoriteSSLCACertFileLocationKey];
    [self removeObserver:self forKeyPath:SPBookmarksChangedNotification];


    [self setConnectionKeychainID:nil];
    
    // Remove font change observer
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"SPFontChangedNotification" object:nil];
}

/**
 * Called by the favorites exporter when the export completes.
 */
- (void)favoritesExportCompletedWithError:(NSError *)error {
    if (error) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Favorites export error", @"favorites export error message") message:[NSString stringWithFormat:NSLocalizedString(@"The following error occurred during the export process:\n\n%@", @"favorites export error informative message"), [error localizedDescription]] callback:nil];
    }
}

// Add this method to handle font change notifications
- (void)fontChanged:(NSNotification *)notification
{
    // Update font in favorites outline view
    NSFont *tableFont = [NSUserDefaults getFont];
    [favoritesOutlineView setRowHeight:4.0f + NSSizeToCGSize([@"{ǞṶḹÜ∑zgyf" sizeWithAttributes:@{NSFontAttributeName : tableFont}]).height];
    [favoritesOutlineView setFont:tableFont];
    
    for (NSTableColumn *col in [favoritesOutlineView tableColumns]) {
        [[col dataCell] setFont:tableFont];
    }
    
    // Force reload to update the display
    [favoritesOutlineView reloadData];
    [favoritesOutlineView setNeedsDisplay:YES];
}

@end
