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
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "SPDatabaseDocument.h"
#import "SPAppController.h"
#import "SPPreferenceController.h"
#import "ImageAndTextCell.h"
#import "RegexKitLite.h"
#import "SPKeychain.h"
#import <objc/runtime.h>
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
- (BOOL)_shouldRequireMySQLHost;
- (void)_syncAWSIAMAndSSLInterfaceState;
- (void)_refreshAWSAvailableRegions;
- (BOOL)_isVaultConnection;

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
- (BOOL)connectionStringComponentsContainDisplaySecrets:(NSURLComponents *)components;
- (NSString *)redactedConnectionStringForDisplayFromComponents:(NSURLComponents *)components fallback:(NSString *)fallback;
- (NSMutableDictionary *)favoriteImportDictionaryByAssigningNewIDs:(NSDictionary *)item;
- (void)collectFavoriteImportLeavesFromItems:(NSArray *)items intoArray:(NSMutableArray *)favorites;
- (NSArray *)favoriteImportItemsByApplyingDuplicateActionsToItems:(NSArray *)items duplicateItems:(NSArray<SPDuplicateImportItem *> *)duplicateItems;
- (void)setUpPasswordRevealButtons;
- (void)addPasswordRevealButtonForField:(NSSecureTextField *)field keyPath:(NSString *)keyPath;
- (void)toggleConnectionPasswordVisibility:(NSButton *)sender;

@end

@interface SPPasswordRevealButton : NSButton
@end

@implementation SPPasswordRevealButton

- (void)resetCursorRects
{
    [super resetCursorRects];
    [self addCursorRect:self.bounds cursor:[NSCursor pointingHandCursor]];
}

@end

@implementation SPConnectionController

// Associated object keys for password visibility toggle (shared between methods)
static void *kOriginalStringKey = &kOriginalStringKey;
static void *kRedactedStringKey = &kRedactedStringKey;
static void *kURLFieldKey = &kURLFieldKey;
static void *kPasswordFieldKey = &kPasswordFieldKey;
static void *kPlainPasswordFieldKey = &kPlainPasswordFieldKey;
static void *kRevealPasswordImageKey = &kRevealPasswordImageKey;
static void *kHidePasswordImageKey = &kHidePasswordImageKey;

#pragma mark - Connection Type Mapping Helpers

/**
 * Converts a connection type string to its numeric tag value.
 * @param typeString The connection type string (e.g., "SPSocketConnection")
 * @return The corresponding numeric tag (0=TCP/IP, 1=Socket, 2=SSH, 3=AWS IAM)
 */
+ (NSInteger)favoriteTypeTagForString:(NSString *)typeString
{
    if ([typeString isEqualToString:@"SPSocketConnection"]) {
        return SPSocketConnection;
    }
    else if ([typeString isEqualToString:@"SPSSHTunnelConnection"]) {
        return SPSSHTunnelConnection;
    }
    else if ([typeString isEqualToString:@"SPAWSIAMConnection"]) {
        return SPAWSIAMConnection;
    }
    return SPTCPIPConnection; // Default
}

/**
 * Converts a connection type tag to its string representation.
 * @param typeTag The connection type tag (0=TCP/IP, 1=Socket, 2=SSH, 3=AWS IAM)
 * @return The corresponding type string
 */
+ (NSString *)stringForFavoriteTypeTag:(NSInteger)typeTag
{
    switch (typeTag) {
        case SPSocketConnection:
            return @"SPSocketConnection";
        case SPSSHTunnelConnection:
            return @"SPSSHTunnelConnection";
        case SPAWSIAMConnection:
            return @"SPAWSIAMConnection";
        case SPTCPIPConnection:
        default:
            return @"SPTCPIPConnection";
    }
}

+ (NSString *)normalizedPortForDuplicateComparison:(id)port type:(NSString *)type
{
    NSInteger typeTag = [SPConnectionController favoriteTypeTagForString:type];
    NSString *portString = @"";

    if ([port isKindOfClass:[NSNumber class]]) {
        portString = [(NSNumber *)port stringValue];
    }
    else if ([port isKindOfClass:[NSString class]]) {
        portString = [(NSString *)port stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }

    if (typeTag == SPSocketConnection) {
        return portString;
    }

    if (portString.length == 0) {
        return @"3306";
    }

    return portString;
}

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
@synthesize requestServerPublicKey;
@synthesize useAWSIAMAuth;
@synthesize awsRegion;
@synthesize awsProfile;
@synthesize vaultMount;
@synthesize vaultAvailableRoles;
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
@synthesize sshRemoteSocketPath;
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

    // Pre-connection validation runs through SAConnectionDetailsValidator
    // FIRST so the user-facing "first error" ordering matches the
    // pre-refactor behavior (host non-empty beats every later check,
    // including AWS-directory authorization). On failure the controller
    // still owns the alert + per-failure side effects (clearing the
    // matching enabled toggles / paths) so the user can correct the input.
    SAConnectionValidationFailure *failure = [SAConnectionDetailsValidator
        validateWithType:(SAConnectionType)[self type]
                    host:[self host] ?: @""
                 sshHost:[self sshHost] ?: @""
     sshRemoteSocketPath:[self sshRemoteSocketPath] ?: @""
                  useSSL:[self useSSL]
   sshKeyLocationEnabled:(sshKeyLocationEnabled != NSControlStateValueOff)
         sshKeyLocation:sshKeyLocation
sslKeyFileLocationEnabled:(sslKeyFileLocationEnabled != NSControlStateValueOff)
     sslKeyFileLocation:sslKeyFileLocation
sslCertificateFileLocationEnabled:(sslCertificateFileLocationEnabled != NSControlStateValueOff)
sslCertificateFileLocation:sslCertificateFileLocation
sslCACertFileLocationEnabled:(sslCACertFileLocationEnabled != NSControlStateValueOff)
  sslCACertFileLocation:sslCACertFileLocation];

    if (failure) {
        switch (failure.kind) {
            case SAConnectionValidationFailureKindSshKeyFileMissing:
                [self setSshKeyLocationEnabled:NSControlStateValueOff];
                break;
            case SAConnectionValidationFailureKindSslKeyFileMissing:
                [self setSslKeyFileLocationEnabled:NSControlStateValueOff];
                [self setSslKeyFileLocation:nil];
                break;
            case SAConnectionValidationFailureKindSslCertificateFileMissing:
                [self setSslCertificateFileLocationEnabled:NSControlStateValueOff];
                [self setSslCertificateFileLocation:nil];
                break;
            case SAConnectionValidationFailureKindSslCACertFileMissing:
                [self setSslCACertFileLocationEnabled:NSControlStateValueOff];
                [self setSslCACertFileLocation:nil];
                break;
            case SAConnectionValidationFailureKindHostMissing:
            case SAConnectionValidationFailureKindSshHostMissing:
                break;
        }
        [NSAlert createWarningAlertWithTitle:failure.alertTitle message:failure.alertMessage callback:nil];
        return;
    }

    // AWS-directory authorization stays inline — it depends on the
    // Security framework bookmark state, which the pure validator
    // can't represent. Ordered AFTER the validator so the
    // host-missing alert still beats this one for AWS IAM favorites
    // with an empty host (matches pre-refactor behavior).
    if ([self _isAWSIAMConnection] && ![self isAWSDirectoryAuthorized]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"AWS Authorization Required", @"AWS authorization required title")
                                     message:NSLocalizedString(@"Authorize access to your ~/.aws directory before testing or connecting with an AWS IAM favorite.", @"AWS authorization required message")
                                    callback:nil];
        return;
    }

    if ([self _isVaultConnection] && ![[self vaultHost] length]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Insufficient connection details", @"insufficient details message")
                                     message:NSLocalizedString(@"A Vault host is required to connect.", @"vault host required connect message")
                                    callback:nil];
        return;
    }
    if ([self _isVaultConnection] && ![[self vaultCredentialsPath] length]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Insufficient connection details", @"insufficient details message")
                                     message:NSLocalizedString(@"A Vault credentials path is required to connect. Fill in the mount and role, or paste a full path into the Role field.", @"vault creds path required connect message")
                                    callback:nil];
        return;
    }
    if ([self _isVaultConnection] && ![[self host] length]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Insufficient connection details", @"insufficient details message")
                                     message:NSLocalizedString(@"A database host is required to connect.", @"vault db host required connect message")
                                    callback:nil];
        return;
    }

    // Basic details have validated - start the connection process animating
    isConnecting = YES;
    cancellingConnection = NO;
    connectionAttemptID++;
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

    // Shared completion handler — used by both the Vault and non-Vault paths.
    __weak __kindof SPConnectionController *weakSelf = self;
    void (^connectCompletion)(SAConnectionResult *) = ^(SAConnectionResult *result) {
        SPConnectionController *strongSelf = weakSelf;
        if (!strongSelf) return;

        // User cancelled (e.g. SSH password prompt) — silently restore UI
        if (result.userCancelled) {
            [strongSelf _restoreConnectionInterface];
            return;
        }

        // Store tunnel on controller ivar for failConnectionWithTitle: cleanup.
        if (result.sshTunnel) {
            strongSelf->sshTunnel = result.sshTunnel;
        } else if (strongSelf.connectionService.activeTunnel) {
            strongSelf->sshTunnel = strongSelf.connectionService.activeTunnel;
        }

        // Database selection failure
        if (result.databaseSelectionFailed) {
            strongSelf->mySQLConnection = result.connection;
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

        // Connection failure — format case-specific error messages
        if (!result.isSuccess) {
            // Check local network denial before clearing mySQLConnection
            BOOL localNetworkDenied = result.isLocalNetworkDenied || [strongSelf _isLocalNetworkAccessDeniedForCurrentConnectionAttempt];
            strongSelf->mySQLConnection = nil;

            NSString *failTitle = result.errorTitle ?: NSLocalizedString(@"Unable to connect", @"connection failed title");
            // rawErrorMessage is populated for MySQL errors; errorMessage for SSH tunnel errors
            NSString *failMessage = (result.rawErrorMessage.length > 0) ? result.rawErrorMessage : (result.errorMessage ?: @"");
            NSString *failDetail = nil;

            // Format detailed error based on connection type and error code
            if (result.sshDebugMessages.length > 0 && strongSelf->sshTunnel) {
                // SSH tunnel failure — show debug messages
                failTitle = NSLocalizedString(@"SSH port forwarding failed", @"title when ssh tunnel port forwarding failed");
                failDetail = result.sshDebugMessages;
            } else if (result.lastErrorID == 1045) {
                // Access denied
                failTitle = NSLocalizedString(@"Access denied!", @"connection failed due to access denied title");
                failDetail = NSLocalizedString(@"Please check your username and password and try again.", @"");
            } else if (result.connectionType == SAConnectionTypeSocket) {
                if ([result.rawErrorMessage rangeOfString:@"No such file"].location != NSNotFound) {
                    failTitle = NSLocalizedString(@"Socket not found!", @"socket not found title");
                } else {
                    failTitle = NSLocalizedString(@"Socket connection failed!", @"socket connection failed title");
                }
            }

            [strongSelf _failConnectionWithTitle:failTitle
                              errorMessage:failMessage
                                    detail:failDetail
                   localNetworkPermissionDenied:localNetworkDenied];
            return;
        }

        // Success — store connection and delegate to existing handler
        strongSelf->mySQLConnection = result.connection;
        [strongSelf mySQLConnectionEstablished];
    };

    // Vault: fetch ephemeral credentials on a background thread so that a
    // browser-based OIDC flow (up to 120 s) does not block the main thread.
    // The service call is then dispatched back to the main thread.
    if ([self _isVaultConnection]) {
        NSString *credHost = [[self vaultHost] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *credPort  = [[self vaultPort] length] ? [self vaultPort] : @"443";
        NSString *credMount = [[self vaultOIDCMount] length] ? [self vaultOIDCMount] : @"oidc";
        NSString *credPath  = [self vaultCredentialsPath];
        NSUInteger vaultConnectionAttemptID = connectionAttemptID;
        NSString *vaultLoginIdentifierForAttempt = [VaultOIDCHandler prepareActiveLogin];
        vaultLoginIdentifier = vaultLoginIdentifierForAttempt;

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *vaultError = nil;
            NSString *outUsername = nil;
            NSString *outPassword = nil;

            SPConnectionController *strongSelf = weakSelf;
            if (!strongSelf || strongSelf->cancellingConnection || strongSelf->connectionAttemptID != vaultConnectionAttemptID) {
                [VaultOIDCHandler clearPreparedActiveLoginWithIdentifier:vaultLoginIdentifierForAttempt];
                return;
            }

            BOOL success = [VaultAuthManager generateCredentialsWithHost:credHost
                                                                    port:credPort
                                                              oidcMount:credMount
                                                               credPath:credPath
                                                        loginIdentifier:vaultLoginIdentifierForAttempt
                                                               username:&outUsername
                                                               password:&outPassword
                                                                  error:&vaultError];
            [VaultOIDCHandler clearPreparedActiveLoginWithIdentifier:vaultLoginIdentifierForAttempt];

            // User may cancel while the OIDC browser is open; bail without showing an error.
            strongSelf = weakSelf;
            if (!strongSelf || strongSelf->cancellingConnection || strongSelf->connectionAttemptID != vaultConnectionAttemptID) {
                [VaultAuthManager clearCachedCredentialsForHost:credHost
                                                           port:credPort
                                                     oidcMount:credMount
                                                       credPath:credPath];
                return;
            }

            if (!success || ![outUsername length] || ![outPassword length]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    SPConnectionController *strongSelf = weakSelf;
                    if (!strongSelf || strongSelf->connectionAttemptID != vaultConnectionAttemptID) return;
                    if ([strongSelf->vaultLoginIdentifier isEqualToString:vaultLoginIdentifierForAttempt]) {
                        strongSelf->vaultLoginIdentifier = nil;
                    }
                    [strongSelf failConnectionWithTitle:NSLocalizedString(@"Vault Authentication Failed", @"Vault auth failed title")
                                          errorMessage:vaultError ? vaultError.localizedDescription : NSLocalizedString(@"Vault returned empty credentials.", @"Vault auth empty creds error")
                                                detail:nil];
                });
                return;
            }

            NSString *capturedUsername = outUsername;
            NSString *capturedPassword = outPassword;
            dispatch_async(dispatch_get_main_queue(), ^{
                SPConnectionController *strongSelf = weakSelf;
                if (!strongSelf) return;
                // Second cancel check: user may have hit Cancel while we were on the background queue.
                if (strongSelf->cancellingConnection || strongSelf->connectionAttemptID != vaultConnectionAttemptID) {
                    [VaultAuthManager clearCachedCredentialsForHost:credHost
                                                               port:credPort
                                                         oidcMount:credMount
                                                           credPath:credPath];
                    return;
                }
                if ([strongSelf->vaultLoginIdentifier isEqualToString:vaultLoginIdentifierForAttempt]) {
                    strongSelf->vaultLoginIdentifier = nil;
                }
                info.user = capturedUsername;
                [strongSelf.connectionService connectWith:info
                                             preferences:preferences
                                                password:capturedPassword
                                             sshPassword:@""
                                            parentWindow:[strongSelf->dbDocument parentWindowControllerWindow]
                                              completion:connectCompletion];
            });
        });
        return;
    }

    // Non-Vault: connect via service directly (async — completion on main thread)
    [self.connectionService connectWith:info
                            preferences:preferences
                               password:resolvedPassword
                            sshPassword:resolvedSSHPassword
                           parentWindow:[dbDocument parentWindowControllerWindow]
                             completion:connectCompletion];
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
    connectionAttemptID++;

    // Abort any in-progress Vault OIDC browser login so the background thread
    // unblocks immediately rather than waiting up to 120 s for a callback.
    if ([vaultLoginIdentifier length]) {
        [VaultOIDCHandler cancelActiveLoginWithIdentifier:vaultLoginIdentifier];
    }

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
    else if (sender == standardSSLKeyFileButton || sender == socketSSLKeyFileButton || sender == sslOverSSHKeyFileButton || sender == vaultSSLKeyFileButton) {
        if ([sender state] == NSControlStateValueOff) {
            [self setSslKeyFileLocation:nil];
            return;
        }

        accessoryView = sslKeyFileLocationHelp;
    }
    // SSL certificate file location:
    else if (sender == standardSSLCertificateButton || sender == socketSSLCertificateButton || sender == sslOverSSHCertificateButton || sender == vaultSSLCertificateButton) {
        if ([sender state] == NSControlStateValueOff) {
            [self setSslCertificateFileLocation:nil];
            return;
        }

        accessoryView = sslCertificateLocationHelp;
    }
    // SSL CA certificate file location:
    else if (sender == standardSSLCACertButton || sender == socketSSLCACertButton || sender == sslOverSSHCACertButton || sender == vaultSSLCACertButton) {
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
        else if (sender == self->standardSSLKeyFileButton || sender == self->socketSSLKeyFileButton || sender == self->sslOverSSHKeyFileButton || sender == self->vaultSSLKeyFileButton) {
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
        else if (sender == self->standardSSLCertificateButton || sender == self->socketSSLCertificateButton || sender == self->sslOverSSHCertificateButton || sender == self->vaultSSLCertificateButton) {
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
        else if (sender == self->standardSSLCACertButton || sender == self->socketSSLCACertButton || sender == self->sslOverSSHCACertButton || sender == self->vaultSSLCACertButton) {
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

- (IBAction)requestServerPublicKeyChanged:(id)sender
{
    [self _startEditingConnection];
}

- (BOOL)_isAWSIAMConnection
{
    return [self type] == SPAWSIAMConnection;
}

- (BOOL)_shouldRequireMySQLHost
{
    NSString *trimmedRemoteSocketPath = [[self sshRemoteSocketPath] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([self type] == SPSSHTunnelConnection && [trimmedRemoteSocketPath length]) {
        return NO;
    }

    return [self type] == SPTCPIPConnection || [self type] == SPSSHTunnelConnection || [self type] == SPAWSIAMConnection;
}

- (BOOL)_isVaultConnection
{
    return [self type] == SPVaultConnection;
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
#pragma mark Vault Authentication

/**
 * KVO: vaultCredentialsPath is affected by vaultMount and vaultCredentialsRole.
 */
+ (NSSet *)keyPathsForValuesAffectingVaultCredentialsPath
{
    return [NSSet setWithObjects:@"vaultMount", @"vaultCredentialsRole", nil];
}

/**
 * Computed getter: joins mount + role into the full credentials path.
 * Existing persistence (SPFavoriteVaultCredentialsPathKey) and the connect
 * path read this value, so they remain unchanged.
 */
- (NSString *)vaultCredentialsPath
{
    return [VaultCredentialsPath credPathWithMount:(vaultMount ?: @"") role:(vaultCredentialsRole ?: @"")];
}

/**
 * Computed setter: called when loading a favorite — splits the stored path
 * back into the mount and role fields.
 */
- (void)setVaultCredentialsPath:(NSString *)path
{
    NSString *value = path ?: @"";
    // Set both backing ivars before emitting KVO so observers of the dependent
    // vaultCredentialsPath key never see a half-updated mount/role pair.
    [self willChangeValueForKey:@"vaultMount"];
    [self willChangeValueForKey:@"vaultCredentialsRole"];
    vaultMount = [[VaultCredentialsPath mountFromCredPath:value] copy];
    vaultCredentialsRole = [[VaultCredentialsPath roleFromCredPath:value] copy];
    [self didChangeValueForKey:@"vaultCredentialsRole"];
    [self didChangeValueForKey:@"vaultMount"];

    // The fetched role list belongs to the previous mount; drop it so the
    // dropdown isn't stale after switching favorites (the user can re-Refresh).
    [self willChangeValueForKey:@"vaultAvailableRoles"];
    vaultAvailableRoles = nil;
    [self didChangeValueForKey:@"vaultAvailableRoles"];
    [self _reloadVaultRoleComboItems];
}

- (NSString *)vaultCredentialsRole
{
    return vaultCredentialsRole;
}

- (void)setVaultCredentialsRole:(NSString *)role
{
    // Ignore selection of the dropdown separator pseudo-row.
    if ([role isEqualToString:[VaultRoleFilter separator]]) {
        return;
    }
    [self willChangeValueForKey:@"vaultCredentialsRole"];
    vaultCredentialsRole = [role copy];
    [self didChangeValueForKey:@"vaultCredentialsRole"];
}

- (void)_reloadVaultRoleComboItems
{
    // While the field is being edited, the committed -stringValue can lag behind
    // what the user has typed; the live text lives in the field editor.
    NSString *query = [[vaultCredentialsRoleComboBox currentEditor] string] ?: ([vaultCredentialsRoleComboBox stringValue] ?: @"");
    NSArray<NSString *> *ordered = [VaultRoleFilter orderedRoles:(vaultAvailableRoles ?: @[])
                                                            query:query];
    [vaultCredentialsRoleComboBox removeAllItems];
    [vaultCredentialsRoleComboBox addItemsWithObjectValues:ordered];
}

/**
 * Reorder the role list every time the dropdown is about to open, so it always
 * reflects what is currently typed (NSComboBox does not live-refresh an already
 * open popup, so ordering it just before it appears is the reliable hook).
 */
- (void)comboBoxWillPopUp:(NSNotification *)notification
{
    if ([notification object] == vaultCredentialsRoleComboBox) {
        [self _reloadVaultRoleComboItems];
    }
}

/**
 * Fetches the list of Vault database roles for the current mount on a
 * background thread (the call may open a browser for OIDC login), then
 * updates vaultAvailableRoles on the main thread via KVO.
 */
- (IBAction)refreshVaultRoles:(id)sender
{
    NSString *mount = [self vaultMount] ?: @"";
    if (![[mount stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(@"Enter a Vault mount first", @"Vault roles refresh – missing mount");
        alert.informativeText = NSLocalizedString(@"The list of roles is read from <mount>/roles. Fill in the Vault mount field, then refresh.", @"Vault roles refresh – missing mount detail");
        NSWindow *parentWindow = [dbDocument parentWindowControllerWindow];
        if (parentWindow) {
            [alert beginSheetModalForWindow:parentWindow completionHandler:nil];
        } else {
            [alert runModal];
        }
        return;
    }

    NSString *host      = [self vaultHost] ?: @"";
    NSString *port      = [self vaultPort] ?: @"";
    NSString *oidcMount = [self vaultOIDCMount] ?: @"";

    // Listing roles needs a Vault token; if none is cached, refreshing will open
    // the browser for OIDC login. Confirm first so it isn't a surprise.
    if (![VaultAuthManager hasCachedTokenWithHost:host port:port oidcMount:oidcMount]) {
        NSAlert *confirm = [[NSAlert alloc] init];
        confirm.messageText = NSLocalizedString(@"Sign in to Vault?", @"Vault roles refresh – login confirm");
        confirm.informativeText = NSLocalizedString(@"Listing roles requires authenticating to Vault, which will open your web browser.", @"Vault roles refresh – login confirm detail");
        [confirm addButtonWithTitle:NSLocalizedString(@"Continue", @"continue button")];
        [confirm addButtonWithTitle:NSLocalizedString(@"Cancel", @"cancel button")];
        if ([confirm runModal] != NSAlertFirstButtonReturn) {
            return;
        }
    }

    [vaultRefreshRolesButton setEnabled:NO];
    [vaultRolesProgressIndicator setHidden:NO];
    [vaultRolesProgressIndicator startAnimation:self];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSArray<NSString *> *roles = [VaultAuthManager listRolesWithHost:host
                                                                    port:port
                                                               oidcMount:oidcMount
                                                                   mount:mount
                                                                   error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->vaultRolesProgressIndicator stopAnimation:self];
            [self->vaultRolesProgressIndicator setHidden:YES];
            [self->vaultRefreshRolesButton setEnabled:YES];

            if (roles) {
                [self willChangeValueForKey:@"vaultAvailableRoles"];
                self->vaultAvailableRoles = [roles copy];
                [self didChangeValueForKey:@"vaultAvailableRoles"];
                [self _reloadVaultRoleComboItems];
                if (roles.count == 0) {
                    NSAlert *empty = [[NSAlert alloc] init];
                    empty.messageText = NSLocalizedString(@"No Vault roles found", @"Vault roles refresh – empty");
                    empty.informativeText = NSLocalizedString(@"No database roles were returned for this mount. Check the Vault mount path and that your token may list roles, or type the role manually.", @"Vault roles refresh – empty detail");
                    NSWindow *emptyParentWindow = [self->dbDocument parentWindowControllerWindow];
                    if (emptyParentWindow) {
                        [empty beginSheetModalForWindow:emptyParentWindow completionHandler:nil];
                    } else {
                        [empty runModal];
                    }
                }
            } else {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = NSLocalizedString(@"Could not load Vault roles", @"Vault roles refresh – failure");
                alert.informativeText = error.localizedDescription ?: NSLocalizedString(@"Unknown error. You can still type the role manually.", @"Vault roles refresh – failure detail");
                NSWindow *parentWindow = [self->dbDocument parentWindowControllerWindow];
                if (parentWindow) {
                    [alert beginSheetModalForWindow:parentWindow completionHandler:nil];
                } else {
                    [alert runModal];
                }
            }
        });
    });
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
        case SPVaultConnection:
            targetResizeRect = [vaultConnectionFormContainer frame];
            additionalFormHeight = 49;
            if ([self useSSL]) additionalFormHeight += [vaultConnectionSSLDetailsContainer frame].size.height;
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
 * Filters the favorites list by the search field's current text.
 * An empty query restores the full list.
 */
- (void)searchFavorites:(id)sender
{
    NSString *query = [sender respondsToSelector:@selector(stringValue)] ? [sender stringValue] : @"";
    self.favoritesListDataSource.searchQuery = query ?: @"";
    [self.favoritesListDataSource reloadDataIn:favoritesOutlineView];
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

    // Decode the favorite into typed values. The defaulting rules (missing
    // name → @"", colorIndex → -1, useCompression → YES, awsProfile →
    // @"default", …) live in SAConnectionInfo+Favorite.swift and are pinned
    // by SAConnectionInfoFavoriteTests.
    SAConnectionInfoObjC *details = [SAConnectionInfoObjC infoFromFavoriteDictionary:fav];

    // Set up the type, also storing it in the previous type store to prevent type "changes" triggering actions
    NSUInteger connectionType = (NSUInteger)[details type];
    previousType = connectionType;
    [self setType:connectionType];

    // Standard details
    [self setName:[details name]];
    [self setHost:[details host]];
    [self setSocket:[details socket]];
    [self setUser:[details user]];
    [self setColorIndex:[details colorIndex]];
    [self setPort:[details port]];
    [self setDatabase:[details database]];
    [self setUseCompression:[details useCompression]];

    // Time Zone details: sync the per-type popups, then store mode + identifier
    switch ([details timeZoneMode]) {
        case SAConnectionTimeZoneModeUseSystemTZ: {
            [standardTimeZoneField selectItemWithTag:SPUseSystemTimeZoneTag];
            [awsIAMTimeZoneField selectItemWithTag:SPUseSystemTimeZoneTag];
            [vaultTimeZoneField selectItemWithTag:SPUseSystemTimeZoneTag];
            [socketTimeZoneField selectItemWithTag:SPUseSystemTimeZoneTag];
            [sshTimeZoneField selectItemWithTag:SPUseSystemTimeZoneTag];
            break;
        }
        case SAConnectionTimeZoneModeUseFixedTZ: {
            NSString *tzIdentifier = [details timeZoneIdentifier];
            [standardTimeZoneField selectItemWithTitle:tzIdentifier];
            [awsIAMTimeZoneField selectItemWithTitle:tzIdentifier];
            [vaultTimeZoneField selectItemWithTitle:tzIdentifier];
            [socketTimeZoneField selectItemWithTitle:tzIdentifier];
            [sshTimeZoneField selectItemWithTitle:tzIdentifier];
            break;
        }
        default: {
            [standardTimeZoneField selectItemWithTag:SPUseServerTimeZoneTag];
            [awsIAMTimeZoneField selectItemWithTag:SPUseServerTimeZoneTag];
            [vaultTimeZoneField selectItemWithTag:SPUseServerTimeZoneTag];
            [socketTimeZoneField selectItemWithTag:SPUseServerTimeZoneTag];
            [sshTimeZoneField selectItemWithTag:SPUseServerTimeZoneTag];
            break;
        }
    }
    [self setTimeZoneMode:(SPConnectionTimeZoneMode)[details timeZoneMode]];
    [self setTimeZoneIdentifier:[details timeZoneIdentifier]];

    //Special prefs
    [self setAllowDataLocalInfile:[details allowDataLocalInfile]];

    // Clear text plugin
    [self setEnableClearTextPlugin:[details enableClearTextPlugin]];
    [self setRequestServerPublicKey:[details requestServerPublicKey]];

    // AWS IAM Authentication (profile-based only - manual credentials not supported)
    [self setUseAWSIAMAuth:[details useAWSIAMAuth]];
    [self setAwsRegion:[details awsRegion]];
    [self setAwsProfile:[details awsProfile]];

    // Vault Authentication
    [self setVaultHost:[details vaultHost]];
    // nil is intentional here — the KVO binding shows NSNullPlaceholder ("443"/"oidc")
    // when the property is nil. The runtime fallback to "443"/"oidc" is applied at
    // connect time. These two stay as raw dictionary reads because the decoded
    // info cannot represent the nil-vs-empty distinction the placeholder needs;
    // rawFavoriteString: coerces NSNumber/NSNull from imported favorites so the
    // properties are always NSString or nil.
    [self setVaultPort:[SAConnectionInfoObjC rawFavoriteString:[fav objectForKey:SPFavoriteVaultPortKey]]];
    [self setVaultOIDCMount:[SAConnectionInfoObjC rawFavoriteString:[fav objectForKey:SPFavoriteVaultOIDCMountKey]]];
    [self setVaultCredentialsPath:[details vaultCredentialsPath]];

    // SSL details
    [self setUseSSL:[details useSSL]];
    [self setSslKeyFileLocationEnabled:[details sslKeyFileLocationEnabled]];
    [self setSslKeyFileLocation:[details sslKeyFileLocation]];
    [self setSslCertificateFileLocationEnabled:[details sslCertificateFileLocationEnabled]];
    [self setSslCertificateFileLocation:[details sslCertificateFileLocation]];
    [self setSslCACertFileLocationEnabled:[details sslCACertFileLocationEnabled]];
    [self setSslCACertFileLocation:[details sslCACertFileLocation]];

    // SSH details
    [self setSshHost:[details sshHost]];
    [self setSshUser:[details sshUser]];
    [self setSshKeyLocationEnabled:[details sshKeyLocationEnabled]];
    [self setSshKeyLocation:[details sshKeyLocation]];
    [self setSshPort:[details sshPort]];
    [self setSshRemoteSocketPath:[details sshRemoteSocketPath]];

    // Check whether the password exists in the keychain, and if so add it; also record the
    // keychain details so we can pass around only those details if the password doesn't change
    if ([self type] == SPVaultConnection) {
        connectionKeychainItemName = nil;
        connectionKeychainItemAccount = nil;
        [self setPassword:nil];
    } else {
        connectionKeychainItemName = !fav ? nil : [keychain nameForFavoriteName:[fav objectForKey:SPFavoriteNameKey] id:[fav objectForKey:SPFavoriteIDKey]];
        connectionKeychainItemAccount = !fav ? nil : [keychain accountForUser:[fav objectForKey:SPFavoriteUserKey] host:(([self type] == SPSocketConnection) ? @"localhost" : [fav objectForKey:SPFavoriteHostKey]) database:[fav objectForKey:SPFavoriteDatabaseKey]];

        if(fav) {
            [self setPassword:[keychain getPasswordForName:connectionKeychainItemName account:connectionKeychainItemAccount]];
        }

        if (!fav || ![[self password] length]) {
            [self setPassword:nil];
        }
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

    // And the same for the SSH password. Vault connections do not use SSH
    // tunnels, so do not hydrate stale SSH keychain entries from old favorites.
    if ([self type] == SPVaultConnection) {
        connectionSSHKeychainItemName = nil;
        connectionSSHKeychainItemAccount = nil;
        [self setSshPassword:nil];
    } else {
        connectionSSHKeychainItemName = !fav ? nil : [keychain nameForSSHForFavoriteName:[fav objectForKey:SPFavoriteNameKey] id:[fav objectForKey:SPFavoriteIDKey]];
        connectionSSHKeychainItemAccount = !fav ? nil : [keychain accountForSSHUser:[fav objectForKey:SPFavoriteSSHUserKey] sshHost:[fav objectForKey:SPFavoriteSSHHostKey]];

        if(fav) {
            [self setSshPassword:[keychain getPasswordForName:connectionSSHKeychainItemName account:connectionSSHKeychainItemAccount]];
        }

        if (!fav || ![[self sshPassword] length]) {
            [self setSshPassword:nil];
        }
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
        case SPVaultConnection:
            [favoritesOutlineView setNextKeyView:vaultNameField];
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

    // Create default favorite (template + wire-format quirks live in
    // SAConnectionInfo+Favorite.swift, pinned by SAConnectionInfoFavoriteTests)
    NSMutableDictionary *favorite = [SAConnectionInfoObjC defaultNewFavoriteDictionaryWithID:favoriteID];

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

        SPTreeNode *node = [self selectedFavoriteNode];

        // The favorite/group/empty-group wording (and whether to ask at all)
        // lives in SAFavoriteDeletionPrompt, pinned by unit tests.
        NSString *nodeDisplayName = [node isGroup]
            ? [[node representedObject] nodeName]
            : [[[node representedObject] nodeFavorite] objectForKey:SPFavoriteNameKey];
        SAFavoriteDeletionPrompt *prompt = [SAFavoriteDeletionPrompt promptForGroup:[node isGroup]
                                                                               name:nodeDisplayName
                                                                         childCount:[[node childNodes] count]];

        if (prompt.needsConfirmation) {
            [NSAlert createDefaultAlertWithTitle:prompt.title message:prompt.informativeText primaryButtonTitle:NSLocalizedString(@"Delete", @"delete button") primaryButtonHandler:^{
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

        // Fresh unique ID + "<name> Copy" (rules in SAConnectionInfo+Favorite.swift)
        NSNumber *favoriteID = [self _createNewFavoriteID];
        NSMutableDictionary *favorite = [SAConnectionInfoObjC duplicatedFavoriteDictionaryFromFavorite:[self selectedFavorite] withID:favoriteID];

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

- (BOOL)connectionStringComponentsContainDisplaySecrets:(NSURLComponents *)components
{
    if (components.password != nil) {
        return YES;
    }

    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        NSString *lowercaseName = [item.name lowercaseString];
        if ([lowercaseName isEqualToString:@"ssh_password"] || [lowercaseName isEqualToString:@"password"]) {
            return YES;
        }
    }

    return NO;
}

- (NSString *)redactedConnectionStringForDisplayFromComponents:(NSURLComponents *)components fallback:(NSString *)fallback
{
    NSURLComponents *displayComponents = [components copy];
    displayComponents.user = nil;
    displayComponents.password = nil;

    if (displayComponents.queryItems.count > 0) {
        NSMutableArray<NSURLQueryItem *> *redactedQueryItems = [NSMutableArray arrayWithCapacity:displayComponents.queryItems.count];
        for (NSURLQueryItem *item in displayComponents.queryItems) {
            NSString *lowercaseName = [item.name lowercaseString];
            if ([lowercaseName isEqualToString:@"ssh_password"] || [lowercaseName isEqualToString:@"password"]) {
                [redactedQueryItems addObject:[NSURLQueryItem queryItemWithName:item.name value:@"•••"]];
            }
            else {
                [redactedQueryItems addObject:item];
            }
        }
        displayComponents.queryItems = redactedQueryItems;
    }

    NSMutableString *displayString = [NSMutableString string];

    if (components.scheme.length) {
        [displayString appendFormat:@"%@://", components.scheme];
    }

    if (components.user != nil || components.password != nil) {
        if (components.percentEncodedUser.length) {
            [displayString appendString:components.percentEncodedUser];
        }
        [displayString appendString:@":•••@"];
    }

    NSString *urlWithoutUserInfo = [displayComponents string];
    if (urlWithoutUserInfo.length) {
        NSString *schemePrefix = components.scheme.length ? [NSString stringWithFormat:@"%@://", components.scheme] : nil;
        NSString *schemeSeparator = components.scheme.length ? [NSString stringWithFormat:@"%@:", components.scheme] : nil;
        if (schemePrefix && [urlWithoutUserInfo hasPrefix:schemePrefix]) {
            [displayString appendString:[urlWithoutUserInfo substringFromIndex:schemePrefix.length]];
        }
        else if (schemeSeparator && [urlWithoutUserInfo hasPrefix:schemeSeparator]) {
            [displayString appendString:[urlWithoutUserInfo substringFromIndex:schemeSeparator.length]];
        }
        else {
            [displayString appendString:urlWithoutUserInfo];
        }
    }

    return displayString.length ? displayString : fallback;
}

#pragma mark -
#pragma mark Import/export favorites

/**
 * Displays an open panel, allowing the user to import their favorites.
 */
- (IBAction)importFavorites:(id)sender
{
    // Check user preference for automatic clipboard checking
    BOOL autoCheckClipboard = [[NSUserDefaults standardUserDefaults] boolForKey:SPAutoCheckClipboardForConnectionStrings];

    // Check if clipboard contains a MySQL connection string (if preference enabled)
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    NSString *clipboardString = [pasteboard stringForType:NSPasteboardTypeString];

    if (autoCheckClipboard && clipboardString && [[clipboardString lowercaseString] hasPrefix:@"mysql://"]) {
        // Found a connection string in clipboard - offer to import it

        // Validate URL
        NSURL *url = [NSURL URLWithString:clipboardString];
        if (!url) {
            NSLog(@"Invalid connection string URL in clipboard");
            [self showImportFilePanel];
            return;
        }

        // Use NSURLComponents for proper password handling (handles percent-encoding)
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        BOOL hasPassword = [self connectionStringComponentsContainDisplaySecrets:components];

        // Create redacted version for display by rebuilding URL from components
        NSString *displayString = clipboardString;
        if (hasPassword) {
            displayString = [self redactedConnectionStringForDisplayFromComponents:components
                                                                          fallback:NSLocalizedString(@"mysql://[connection string with password hidden]", @"Redacted connection string fallback")];
        }

        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:NSLocalizedString(@"Import from Clipboard or File?", @"Import from clipboard or file")];

        if (hasPassword) {
            // Create accessory view with checkbox to reveal password
            NSView *accessoryView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 80)];

            NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 55, 400, 20)];
            [label setStringValue:NSLocalizedString(@"Found connection string in clipboard:", @"Found connection string label")];
            [label setBezeled:NO];
            [label setDrawsBackground:NO];
            [label setEditable:NO];
            [label setSelectable:NO];
            [accessoryView addSubview:label];

            NSTextField *urlField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 30, 400, 20)];
            [urlField setStringValue:displayString];
            [urlField setBezeled:NO];
            [urlField setDrawsBackground:NO];
            [urlField setEditable:NO];
            [urlField setSelectable:YES];
            [urlField setFont:[NSFont systemFontOfSize:11]];
            [accessoryView addSubview:urlField];

            // Use checkbox instead of eye button - simpler and more reliable
            NSButton *revealCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(0, 5, 200, 20)];
            [revealCheckbox setButtonType:NSButtonTypeSwitch];
            [revealCheckbox setTitle:NSLocalizedString(@"Show password", @"Show password checkbox")];
            [revealCheckbox setState:NSControlStateValueOff];

            // Use target-action with stored context via associated objects
            objc_setAssociatedObject(revealCheckbox, kOriginalStringKey, clipboardString, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(revealCheckbox, kRedactedStringKey, displayString, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(revealCheckbox, kURLFieldKey, urlField, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            [revealCheckbox setTarget:self];
            [revealCheckbox setAction:@selector(togglePasswordVisibility:)];

            [accessoryView addSubview:revealCheckbox];

            [alert setAccessoryView:accessoryView];
            [alert setInformativeText:NSLocalizedString(@"\nWould you like to import from clipboard or choose a file?", @"Import prompt")];
        }
        else {
            // Use redacted string even when no password to avoid exposing any sensitive data
            [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Found connection string in clipboard:\n\n%@\n\nWould you like to import from clipboard or choose a file?", @"Import connection string prompt"), displayString]];
        }

        [alert addButtonWithTitle:NSLocalizedString(@"Import from Clipboard", @"Import from clipboard button")];
        [alert addButtonWithTitle:NSLocalizedString(@"Choose File...", @"Choose file button")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button")];

        [alert beginSheetModalForWindow:[dbDocument parentWindowControllerWindow] completionHandler:^(NSModalResponse returnCode) {
            if (returnCode == NSAlertFirstButtonReturn) {
                // Import from clipboard
                [self importFavoritesFromConnectionString:clipboardString];
            }
            else if (returnCode == NSAlertSecondButtonReturn) {
                // Choose file
                [self showImportFilePanel];
            }
        }];
    }
    else {
        // No connection string in clipboard - show file picker
        [self showImportFilePanel];
    }
}

/**
 * Toggles password visibility in the clipboard import alert.
 */
- (void)togglePasswordVisibility:(NSButton *)sender
{
    NSString *originalString = objc_getAssociatedObject(sender, kOriginalStringKey);
    NSString *redactedString = objc_getAssociatedObject(sender, kRedactedStringKey);
    NSTextField *urlField = objc_getAssociatedObject(sender, kURLFieldKey);

    if (sender.state == NSControlStateValueOn) {
        // Show password
        [urlField setStringValue:originalString];
    } else {
        // Hide password
        [urlField setStringValue:redactedString];
    }
}

/**
 * Saves a password to the keychain for a favorite using proper keychain helper methods.
 */
- (void)savePassword:(NSString *)password forFavorite:(NSDictionary *)favorite
{
    if (!password || password.length == 0) {
        return;
    }

    NSString *favoriteName = [favorite objectForKey:SPFavoriteNameKey] ?: @"";
    NSNumber *favoriteID = [favorite objectForKey:SPFavoriteIDKey] ?: @(-1);
    NSString *user = [favorite objectForKey:SPFavoriteUserKey] ?: @"";
    NSString *host = [favorite objectForKey:SPFavoriteHostKey] ?: @"";
    NSString *database = [favorite objectForKey:SPFavoriteDatabaseKey] ?: @"";
    NSInteger typeTag = [[favorite objectForKey:SPFavoriteTypeKey] integerValue];

    // Normalize host for keychain (socket connections use "localhost")
    NSString *hostForKeychain = (typeTag == SPSocketConnection) ? @"localhost" : host;

    // Use keychain helper methods for consistent format
    NSString *keychainName = [keychain nameForFavoriteName:favoriteName id:[NSString stringWithFormat:@"%@", favoriteID]];
    NSString *keychainAccount = [keychain accountForUser:user host:hostForKeychain database:database];

    [keychain addPassword:password forName:keychainName account:keychainAccount];
}

/**
 * Helper method to save SSH password to keychain for a favorite.
 * Uses consistent keychain naming format via SPKeychain helper methods.
 */
- (void)saveSSHPassword:(NSString *)sshPassword forFavorite:(NSDictionary *)favorite
{
    if (!sshPassword || sshPassword.length == 0) {
        return;
    }

    NSString *favoriteName = [favorite objectForKey:SPFavoriteNameKey] ?: @"";
    NSNumber *favoriteID = [favorite objectForKey:SPFavoriteIDKey] ?: @(-1);
    NSString *sshUser = [favorite objectForKey:SPFavoriteSSHUserKey] ?: @"";
    NSString *sshHost = [favorite objectForKey:SPFavoriteSSHHostKey] ?: @"";

    // Use keychain helper methods for consistent SSH password format
    NSString *keychainName = [keychain nameForSSHForFavoriteName:favoriteName id:[NSString stringWithFormat:@"%@", favoriteID]];
    NSString *keychainAccount = [keychain accountForSSHUser:sshUser sshHost:sshHost];

    [keychain addPassword:sshPassword forName:keychainName account:keychainAccount];
}

- (void)showImportFilePanel
{
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];

    [openPanel setAllowedContentTypes:@[[UTType typeWithFilenameExtension:@"plist"]]];

    [openPanel beginSheetModalForWindow:[dbDocument parentWindowControllerWindow] completionHandler:^(NSInteger returnCode)
    {
        if (returnCode == NSModalResponseOK) {
            SPFavoritesImporter *importer = [[SPFavoritesImporter alloc] init];

            [importer setDelegate:(NSObject<SPFavoritesImportProtocol> *)self];

            [importer importFavoritesFromFileAtPath:[[openPanel URL] path]];
        }
    }];
}

- (void)importFavoritesFromConnectionString:(NSString *)connectionString
{
    // Validate connection string using Swift helper
    NSURL *url = [ConnectionStringParser validateConnectionString:connectionString];
    if (!url) {
        NSBeep();
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Invalid Connection String", @"Invalid connection string")
                                     message:NSLocalizedString(@"The connection string is not valid.", @"The connection string is not valid")
                                    callback:nil];
        return;
    }

    // Parse connection string using Swift helper
    ConnectionStringParseResult *result = [ConnectionStringParser parse:url];
    NSMutableDictionary *details = [result.details mutableCopy];
    NSArray<NSString *> *invalidParameters = result.invalidParameters;
    BOOL parsed = result.success;

    if (!parsed) {
        NSBeep();
        if ([invalidParameters count] > 0) {
            NSArray<NSString *> *validParameters = [ConnectionStringParser validQueryParameters];
            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Invalid Connection String", @"Invalid connection string")
                                         message:[NSString stringWithFormat:@"%@:\n\n%@: %@\n\n%@: %@",
                                                  NSLocalizedString(@"Error parsing connection string", @"Error parsing connection string"),
                                                  NSLocalizedString(@"Invalid query parameters given", @"Invalid query parameters given"),
                                                  [invalidParameters componentsJoinedByString:@", "],
                                                  NSLocalizedString(@"Allowed query parameters are", @"Allowed query parameters are"),
                                                  [validParameters componentsJoinedByString:@", "]]
                                        callback:nil];
        }
        return;
    }

    // Create a favorite from the connection details
    NSMutableDictionary *favorite = [NSMutableDictionary dictionary];

    // Set a default name based on host
    NSString *host = [details objectForKey:@"host"] ?: @"localhost";
    NSString *user = [details objectForKey:@"user"] ?: @"";
    NSString *database = [details objectForKey:@"database"] ?: @"";
    NSString *favoriteName = [NSString stringWithFormat:@"%@@%@%@",
                              user.length ? user : @"",
                              host,
                              database.length ? [NSString stringWithFormat:@"/%@", database] : @""];
    [favorite setObject:favoriteName forKey:SPFavoriteNameKey];

    // Map the connection details to favorite keys
    if ([details objectForKey:@"host"]) [favorite setObject:[details objectForKey:@"host"] forKey:SPFavoriteHostKey];
    if ([details objectForKey:@"user"]) [favorite setObject:[details objectForKey:@"user"] forKey:SPFavoriteUserKey];
    if ([details objectForKey:@"database"]) [favorite setObject:[details objectForKey:@"database"] forKey:SPFavoriteDatabaseKey];
    // Handle port - can be NSString (from parser) or NSNumber (from other sources)
    if ([details objectForKey:@"port"]) {
        id portValue = [details objectForKey:@"port"];
        if ([portValue isKindOfClass:[NSNumber class]]) {
            [favorite setObject:[portValue stringValue] forKey:SPFavoritePortKey];
        } else if ([portValue isKindOfClass:[NSString class]]) {
            [favorite setObject:portValue forKey:SPFavoritePortKey];
        }
    }
    if ([details objectForKey:@"socket"]) [favorite setObject:[details objectForKey:@"socket"] forKey:SPFavoriteSocketKey];

    // Map connection type using centralized helper
    NSString *typeString = [details objectForKey:@"type"];
    NSInteger typeTag = [SPConnectionController favoriteTypeTagForString:typeString];
    [favorite setObject:@(typeTag) forKey:SPFavoriteTypeKey];

    // Add type-specific parameters
    if (typeTag == SPSSHTunnelConnection) {
        if ([details objectForKey:@"ssh_host"]) [favorite setObject:[details objectForKey:@"ssh_host"] forKey:SPFavoriteSSHHostKey];
        if ([details objectForKey:@"ssh_port"]) [favorite setObject:[details objectForKey:@"ssh_port"] forKey:SPFavoriteSSHPortKey];
        if ([details objectForKey:@"ssh_user"]) [favorite setObject:[details objectForKey:@"ssh_user"] forKey:SPFavoriteSSHUserKey];
        if ([details objectForKey:@"ssh_keyLocationEnabled"]) [favorite setObject:[details objectForKey:@"ssh_keyLocationEnabled"] forKey:SPFavoriteSSHKeyLocationEnabledKey];
        if ([details objectForKey:@"ssh_keyLocation"]) [favorite setObject:[details objectForKey:@"ssh_keyLocation"] forKey:SPFavoriteSSHKeyLocationKey];
        id sshRemoteSocketPath = [details objectForKey:SPFavoriteSSHRemoteSocketPathKey] ?: [details objectForKey:@"ssh_remote_socket_path"];
        if (sshRemoteSocketPath) [favorite setObject:sshRemoteSocketPath forKey:SPFavoriteSSHRemoteSocketPathKey];
    }
    else if (typeTag == SPAWSIAMConnection) {
        if ([details objectForKey:@"aws_region"]) [favorite setObject:[details objectForKey:@"aws_region"] forKey:@"awsRegion"];
        if ([details objectForKey:@"aws_profile"]) [favorite setObject:[details objectForKey:@"aws_profile"] forKey:@"awsProfile"];
    }

    // Add cleartext plugin flag if present (for LDAP/cleartext auth)
    // Check normalized key first (from ConnectionStringParser), then raw key for compatibility
    id clearTextValue = [details objectForKey:@"enableClearTextPlugin"] ?: [details objectForKey:@"enable_cleartext_plugin"];
    if (clearTextValue) {
        BOOL enableClearText = NO;
        if ([clearTextValue isKindOfClass:[NSNumber class]]) {
            enableClearText = [clearTextValue boolValue];
        } else if ([clearTextValue isKindOfClass:[NSString class]]) {
            enableClearText = ([clearTextValue isEqualToString:@"1"] ||
                              [[clearTextValue lowercaseString] isEqualToString:@"true"]);
        }
        [favorite setObject:@(enableClearText) forKey:SPFavoriteEnableClearTextPluginKey];
    }

    id publicKeyValue = [details objectForKey:@"requestServerPublicKey"] ?: [details objectForKey:@"get_server_public_key"] ?: [details objectForKey:@"request_server_public_key"];
    if (publicKeyValue) {
        BOOL requestPublicKey = NO;
        if ([publicKeyValue isKindOfClass:[NSNumber class]]) {
            requestPublicKey = [publicKeyValue boolValue];
        } else if ([publicKeyValue isKindOfClass:[NSString class]]) {
            requestPublicKey = ([publicKeyValue isEqualToString:@"1"] ||
                                [[publicKeyValue lowercaseString] isEqualToString:@"true"]);
        }
        [favorite setObject:@(requestPublicKey) forKey:SPFavoriteRequestServerPublicKeyKey];
    }

    // Generate unique ID for this favorite
    NSNumber *favoriteID = [self _createNewFavoriteID];
    [favorite setObject:favoriteID forKey:SPFavoriteIDKey];

    // Store passwords for later (will be saved to keychain after user confirms action)
    NSString *passwordFromURL = [details objectForKey:@"password"];
    NSString *sshPasswordFromURL = [details objectForKey:@"ssh_password"];

    // Check for duplicates (including mode-specific fields for accurate matching)
    NSString *port = [favorite objectForKey:SPFavoritePortKey] ?: @"";
    SPTreeNode *duplicateNode = [self findDuplicateFavoriteForHost:host
                                                              user:user
                                                          database:database
                                                              port:port
                                                              type:typeString
                                                modeSpecificFields:details];

    if (duplicateNode) {
        // Found a duplicate - create item and show UI
        SPDuplicateImportItem *item = [[SPDuplicateImportItem alloc] initWithFavoriteName:favoriteName
                                                                                      host:host
                                                                                  favorite:favorite
                                                                             duplicateNode:duplicateNode];

        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:NSLocalizedString(@"Duplicate Connection Found", @"Duplicate connection found")];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"A connection with the same details already exists:\n\n%@\n\nChoose an action:", @"Duplicate connection prompt"), favoriteName]];

        // Add custom accessory view
        NSView *accessoryView = [SPDuplicateImportHelper createAccessoryViewWithDuplicateItems:@[item]];
        [alert setAccessoryView:accessoryView];

        [alert addButtonWithTitle:NSLocalizedString(@"Import", @"Import button")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button")];

        [alert beginSheetModalForWindow:[dbDocument parentWindowControllerWindow] completionHandler:^(NSModalResponse returnCode) {
            if (returnCode != NSAlertFirstButtonReturn) {
                // Cancel
                SPDuplicateActionHandler.shared.items = @[];
                return;
            }

            SPTreeNode *selectedNode = nil;

            if (item.action == SPDuplicateActionUpdate) {
                // Update existing
                [self updateFavoriteNode:duplicateNode withData:favorite password:passwordFromURL sshPassword:sshPasswordFromURL];
                selectedNode = duplicateNode;
            }
            else if (item.action == SPDuplicateActionCreateNew) {
                // Create new
                selectedNode = [self->favoritesController addFavoriteNodeWithData:favorite asChildOfNode:nil];
                // Save passwords to keychain for new favorite
                [self savePassword:passwordFromURL forFavorite:favorite];
                [self saveSSHPassword:sshPasswordFromURL forFavorite:favorite];
            }
            // If Skip - do nothing

            if (selectedNode) {
                if (self->currentSortItem > SPFavoritesSortUnsorted) {
                    [self _sortFavorites];
                }
                [self _reloadFavoritesViewData];

                NSInteger row = [self->favoritesOutlineView rowForItem:selectedNode];
                if (row >= 0) {
                    [self->favoritesOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
                    [self _scrollToSelectedNode];
                }
            }

            // Clear singleton items to prevent memory leak
            SPDuplicateActionHandler.shared.items = @[];
        }];
    }
    else {
        // No duplicate - add normally
        SPTreeNode *newNode = [favoritesController addFavoriteNodeWithData:favorite asChildOfNode:nil];

        // Save passwords to keychain
        [self savePassword:passwordFromURL forFavorite:favorite];
        [self saveSSHPassword:sshPasswordFromURL forFavorite:favorite];

        if (currentSortItem > SPFavoritesSortUnsorted) {
            [self _sortFavorites];
        }

        [self _reloadFavoritesViewData];

        // Select and scroll to the new favorite
        NSInteger row = [favoritesOutlineView rowForItem:newNode];
        if (row >= 0) {
            [favoritesOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
            [self _scrollToSelectedNode];
        }
    }
}

- (SPTreeNode *)findDuplicateFavoriteForHost:(NSString *)host
                                         user:(NSString *)user
                                     database:(NSString *)database
                                         port:(NSString *)port
                                         type:(NSString *)type
{
    return [self findDuplicateFavoriteForHost:host user:user database:database port:port type:type modeSpecificFields:nil];
}

- (SPTreeNode *)findDuplicateFavoriteForHost:(NSString *)host
                                         user:(NSString *)user
                                     database:(NSString *)database
                                         port:(NSString *)port
                                         type:(NSString *)type
                              modeSpecificFields:(NSDictionary *)modeFields
{
    // Get all favorite leaves
    NSArray *allFavorites = [favoritesRoot allChildLeafs];

    for (SPTreeNode *node in allFavorites) {
        if ([node isGroup]) continue;

        NSDictionary *favoriteDict = [[node representedObject] nodeFavorite];
        if (!favoriteDict) continue;

        // Compare key fields
        NSString *existingHost = [favoriteDict objectForKey:SPFavoriteHostKey] ?: @"";
        NSString *existingUser = [favoriteDict objectForKey:SPFavoriteUserKey] ?: @"";
        NSString *existingDatabase = [favoriteDict objectForKey:SPFavoriteDatabaseKey] ?: @"";
        NSString *existingPort = [favoriteDict objectForKey:SPFavoritePortKey] ?: @"";

        // Get type string using centralized helper
        NSInteger existingTypeInt = [[favoriteDict objectForKey:SPFavoriteTypeKey] integerValue];
        NSString *existingType = [SPConnectionController stringForFavoriteTypeTag:existingTypeInt];
        NSString *normalizedExistingPort = [SPConnectionController normalizedPortForDuplicateComparison:existingPort type:existingType];
        NSString *normalizedNewPort = [SPConnectionController normalizedPortForDuplicateComparison:port type:type];

        // Check if basic fields match
        if (![existingHost isEqualToString:host] ||
            ![existingUser isEqualToString:user] ||
            ![existingDatabase isEqualToString:database] ||
            ![normalizedExistingPort isEqualToString:normalizedNewPort] ||
            ![existingType isEqualToString:type]) {
            continue;
        }

        // If mode-specific fields were provided, compare them too
        if (modeFields) {
            NSInteger typeTag = [SPConnectionController favoriteTypeTagForString:type];

            if (typeTag == SPSSHTunnelConnection) {
                // Compare SSH-specific fields
                NSString *existingSSHHost = [favoriteDict objectForKey:SPFavoriteSSHHostKey] ?: @"";
                NSString *existingSSHUser = [favoriteDict objectForKey:SPFavoriteSSHUserKey] ?: @"";
                NSString *existingSSHPort = [favoriteDict objectForKey:SPFavoriteSSHPortKey] ?: @"";
                NSString *existingSSHRemoteSocketPath = [favoriteDict objectForKey:SPFavoriteSSHRemoteSocketPathKey] ?: @"";

                // Check both URL keys (from connection string) and favorite keys (from plist import)
                NSString *newSSHHost = [modeFields objectForKey:@"ssh_host"] ?: [modeFields objectForKey:SPFavoriteSSHHostKey] ?: @"";
                NSString *newSSHUser = [modeFields objectForKey:@"ssh_user"] ?: [modeFields objectForKey:SPFavoriteSSHUserKey] ?: @"";
                NSString *newSSHPort = [modeFields objectForKey:@"ssh_port"] ?: [modeFields objectForKey:SPFavoriteSSHPortKey] ?: @"";
                NSString *newSSHRemoteSocketPath = [modeFields objectForKey:@"ssh_remote_socket_path"] ?: [modeFields objectForKey:SPFavoriteSSHRemoteSocketPathKey] ?: @"";

                if (![existingSSHHost isEqualToString:newSSHHost] ||
                    ![existingSSHUser isEqualToString:newSSHUser] ||
                    ![existingSSHPort isEqualToString:newSSHPort] ||
                    ![existingSSHRemoteSocketPath isEqualToString:newSSHRemoteSocketPath]) {
                    continue;
                }
            }
            else if (typeTag == SPSocketConnection) {
                // Compare socket path
                NSString *existingSocket = [favoriteDict objectForKey:SPFavoriteSocketKey] ?: @"";
                // Check both URL key (from connection string) and favorite key (from plist import)
                NSString *newSocket = [modeFields objectForKey:@"socket"] ?: [modeFields objectForKey:SPFavoriteSocketKey] ?: @"";

                if (![existingSocket isEqualToString:newSocket]) {
                    continue;
                }
            }
            else if (typeTag == SPAWSIAMConnection) {
                // Compare AWS-specific fields
                NSString *existingRegion = [favoriteDict objectForKey:@"awsRegion"] ?: @"";
                NSString *existingProfile = [favoriteDict objectForKey:@"awsProfile"] ?: @"";

                // Check both URL keys (from connection string) and favorite keys (from plist import)
                NSString *newRegion = [modeFields objectForKey:@"aws_region"] ?: [modeFields objectForKey:@"awsRegion"] ?: @"";
                NSString *newProfile = [modeFields objectForKey:@"aws_profile"] ?: [modeFields objectForKey:@"awsProfile"] ?: @"";

                if (![existingRegion isEqualToString:newRegion] ||
                    ![existingProfile isEqualToString:newProfile]) {
                    continue;
                }
            }
        }

        // All fields match - this is a duplicate
        return node;
    }

    return nil;
}

- (void)updateFavoriteNode:(SPTreeNode *)node withData:(NSDictionary *)newData password:(NSString *)password
{
    [self updateFavoriteNode:node withData:newData password:password sshPassword:nil];
}

- (void)updateFavoriteNode:(SPTreeNode *)node withData:(NSDictionary *)newData password:(NSString *)password sshPassword:(NSString *)sshPassword
{
    id representedObject = [node representedObject];
    if (![representedObject respondsToSelector:@selector(nodeFavorite)]) return;

    NSMutableDictionary *favoriteDict = [[representedObject nodeFavorite] mutableCopy];
    if (!favoriteDict) return;

    // Get old values for keychain update
    NSString *oldHost = [favoriteDict objectForKey:SPFavoriteHostKey] ?: @"";
    NSString *oldUser = [favoriteDict objectForKey:SPFavoriteUserKey] ?: @"";
    NSString *oldDatabase = [favoriteDict objectForKey:SPFavoriteDatabaseKey] ?: @"";
    NSString *oldName = [favoriteDict objectForKey:SPFavoriteNameKey] ?: @"";
    NSNumber *favoriteID = [favoriteDict objectForKey:SPFavoriteIDKey] ?: @(-1);
    NSInteger oldTypeTag = [[favoriteDict objectForKey:SPFavoriteTypeKey] integerValue];
    NSString *oldSSHUser = [favoriteDict objectForKey:SPFavoriteSSHUserKey] ?: @"";
    NSString *oldSSHHost = [favoriteDict objectForKey:SPFavoriteSSHHostKey] ?: @"";

    // Update all fields from newData (except name and ID - keep existing name and ID)
    for (NSString *key in newData) {
        if (![key isEqualToString:SPFavoriteNameKey] && ![key isEqualToString:SPFavoriteIDKey]) {
            [favoriteDict setObject:[newData objectForKey:key] forKey:key];
        }
    }

    // Get new values
    NSString *newHost = [favoriteDict objectForKey:SPFavoriteHostKey] ?: @"";
    NSString *newUser = [favoriteDict objectForKey:SPFavoriteUserKey] ?: @"";
    NSString *newDatabase = [favoriteDict objectForKey:SPFavoriteDatabaseKey] ?: @"";
    NSString *newName = [favoriteDict objectForKey:SPFavoriteNameKey] ?: @"";
    NSInteger newTypeTag = [[favoriteDict objectForKey:SPFavoriteTypeKey] integerValue];

    // Normalize host for keychain (socket connections use "localhost")
    NSString *oldHostForKeychain = (oldTypeTag == SPSocketConnection) ? @"localhost" : oldHost;
    NSString *newHostForKeychain = (newTypeTag == SPSocketConnection) ? @"localhost" : newHost;

    // Use keychain helper methods for consistent format
    NSString *oldKeychainName = [keychain nameForFavoriteName:oldName id:[NSString stringWithFormat:@"%@", favoriteID]];
    NSString *oldKeychainAccount = [keychain accountForUser:oldUser host:oldHostForKeychain database:oldDatabase];
    NSString *newKeychainName = [keychain nameForFavoriteName:newName id:[NSString stringWithFormat:@"%@", favoriteID]];
    NSString *newKeychainAccount = [keychain accountForUser:newUser host:newHostForKeychain database:newDatabase];

    // Update keychain if account changed or new password provided
    BOOL accountChanged = ![oldKeychainAccount isEqualToString:newKeychainAccount];
    BOOL hasNewPassword = (password && password.length > 0);

    if (accountChanged || hasNewPassword) {
        // Try to get existing password
        NSString *existingPassword = [keychain getPasswordForName:oldKeychainName account:oldKeychainAccount];

        // Determine which password to save
        NSString *passwordToSave = hasNewPassword ? password : existingPassword;

        if (passwordToSave && passwordToSave.length > 0) {
            if ([keychain passwordExistsForName:oldKeychainName account:oldKeychainAccount]) {
                // Update existing keychain entry
                [keychain updateItemWithName:oldKeychainName
                                     account:oldKeychainAccount
                                      toName:newKeychainName
                                     account:newKeychainAccount
                                    password:passwordToSave];
            } else {
                // Create new keychain entry
                [keychain addPassword:passwordToSave
                              forName:newKeychainName
                              account:newKeychainAccount];
            }
        } else if (accountChanged && existingPassword) {
            // No password to save but account changed - delete old entry
            [keychain deletePasswordForName:oldKeychainName account:oldKeychainAccount];
        }
    }

    // Update SSH password if this is an SSH connection
    if (newTypeTag == SPSSHTunnelConnection) {
        NSString *newSSHUser = [favoriteDict objectForKey:SPFavoriteSSHUserKey] ?: @"";
        NSString *newSSHHost = [favoriteDict objectForKey:SPFavoriteSSHHostKey] ?: @"";

        NSString *oldSSHKeychainName = [keychain nameForSSHForFavoriteName:oldName id:[NSString stringWithFormat:@"%@", favoriteID]];
        NSString *oldSSHKeychainAccount = [keychain accountForSSHUser:oldSSHUser sshHost:oldSSHHost];
        NSString *newSSHKeychainName = [keychain nameForSSHForFavoriteName:newName id:[NSString stringWithFormat:@"%@", favoriteID]];
        NSString *newSSHKeychainAccount = [keychain accountForSSHUser:newSSHUser sshHost:newSSHHost];

        BOOL sshAccountChanged = ![oldSSHKeychainAccount isEqualToString:newSSHKeychainAccount];
        BOOL hasNewSSHPassword = (sshPassword && sshPassword.length > 0);

        if (sshAccountChanged || hasNewSSHPassword) {
            NSString *existingSSHPassword = [keychain getPasswordForName:oldSSHKeychainName account:oldSSHKeychainAccount];
            NSString *sshPasswordToSave = hasNewSSHPassword ? sshPassword : existingSSHPassword;

            if (sshPasswordToSave && sshPasswordToSave.length > 0) {
                if ([keychain passwordExistsForName:oldSSHKeychainName account:oldSSHKeychainAccount]) {
                    [keychain updateItemWithName:oldSSHKeychainName
                                         account:oldSSHKeychainAccount
                                          toName:newSSHKeychainName
                                         account:newSSHKeychainAccount
                                        password:sshPasswordToSave];
                } else {
                    [keychain addPassword:sshPasswordToSave
                                  forName:newSSHKeychainName
                                  account:newSSHKeychainAccount];
                }
            } else if (sshAccountChanged && existingSSHPassword) {
                [keychain deletePasswordForName:oldSSHKeychainName account:oldSSHKeychainAccount];
            }
        }
    }

    // Update the node's data
    if ([representedObject respondsToSelector:@selector(setNodeFavorite:)]) {
        [representedObject setNodeFavorite:favoriteDict];
    }

    // Save favorites
    [favoritesController saveFavorites];
    [[NSNotificationCenter defaultCenter] postNotificationName:SPConnectionFavoritesChangedNotification object:self];
}

/**
 * Copies the connection string of the selected favorite to the clipboard.
 */
- (IBAction)copyConnectionString:(id)sender
{
    SPTreeNode *node = [self selectedFavoriteNode];

    if (!node || [node isGroup]) {
        NSBeep();
        return;
    }

    // Show dialog with password option
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:NSLocalizedString(@"Copy Connection String", @"Copy connection string")];
    [alert setInformativeText:NSLocalizedString(@"Would you like to include the password in the connection string?\n\n⚠️ WARNING: Sharing passwords in plaintext (Slack, email, etc.) is a security risk!\n\nOnly include the password if you're sharing through a secure channel.", @"Copy connection string password warning")];
    [alert addButtonWithTitle:NSLocalizedString(@"Copy Without Password", @"Copy without password button")];
    [alert addButtonWithTitle:NSLocalizedString(@"Copy With Password", @"Copy with password button")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button")];
    [alert setAlertStyle:NSAlertStyleWarning];

    [alert beginSheetModalForWindow:[dbDocument parentWindowControllerWindow] completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertThirdButtonReturn) {
            // Cancel
            return;
        }

        BOOL includePassword = (returnCode == NSAlertSecondButtonReturn);
        id nodeObject = [node representedObject];
        NSString *connectionString = nil;

        if ([nodeObject respondsToSelector:@selector(toConnectionString:)]) {
            connectionString = [nodeObject toConnectionString:includePassword];
        }

        if (connectionString && [connectionString length] > 0) {
            NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
            [pasteboard clearContents];
            [pasteboard setString:connectionString forType:NSPasteboardTypeString];

            // Show brief success message
            NSString *message = includePassword ?
                NSLocalizedString(@"Connection string with password copied to clipboard", @"Connection string with password copied") :
                NSLocalizedString(@"Connection string copied to clipboard (password not included)", @"Connection string copied without password");

            // You could add a toast notification here if available
            SPLog(@"%@", message);
        } else {
            NSBeep();
            NSLog(@"Failed to generate connection string for favorite");
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
    [vaultTimeZoneField selectItemAtIndex:sender.indexOfSelectedItem];

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

    // Ensure that host is not empty for connection types that require a MySQL host.
    if (validateDetails && [self _shouldRequireMySQLHost] && ![[self host] length]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Insufficient connection details", @"insufficient details message") message:NSLocalizedString(@"Insufficient details provided to establish a connection. Please provide at least a host.", @"insufficient details informative message") callback:nil];
        return;
    }

    if (validateDetails && [self _isAWSIAMConnection] && ![self isAWSDirectoryAuthorized]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"AWS Authorization Required", @"AWS authorization required title")
                                     message:NSLocalizedString(@"Authorize access to your ~/.aws directory before saving an AWS IAM favorite.", @"AWS authorization required save message")
                                    callback:nil];
        return;
    }

    if (validateDetails && [self type] == SPVaultConnection && ![[self host] length]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Insufficient connection details", @"insufficient details message")
                                     message:NSLocalizedString(@"Please provide a database host to save a Vault favorite.", @"vault db host required save message")
                                    callback:nil];
        return;
    }
    if (validateDetails && [self type] == SPVaultConnection && ![[self vaultHost] length]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Insufficient connection details", @"insufficient details message")
                                     message:NSLocalizedString(@"A Vault host is required to save a Vault favorite.", @"vault host required save message")
                                    callback:nil];
        return;
    }
    if (validateDetails && [self type] == SPVaultConnection && ![[self vaultCredentialsPath] length]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Insufficient connection details", @"insufficient details message")
                                     message:NSLocalizedString(@"A Vault credentials path is required to save a Vault favorite. Fill in the mount and role, or paste a full path into the Role field.", @"vault creds path required save message")
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
    [theFavorite setObject:[NSNumber numberWithInteger:[self requestServerPublicKey]] forKey:SPFavoriteRequestServerPublicKeyKey];
    // AWS IAM Authentication (profile-based only)
    NSInteger awsIAMEnabled = ([self type] == SPAWSIAMConnection) ? NSControlStateValueOn : NSControlStateValueOff;
    [theFavorite setObject:[NSNumber numberWithInteger:awsIAMEnabled] forKey:SPFavoriteUseAWSIAMAuthKey];
    _setOrRemoveKey(SPFavoriteAWSRegionKey, [self awsRegion]);
    _setOrRemoveKey(SPFavoriteAWSProfileKey, [self awsProfile]);
    // Vault Authentication
    _setOrRemoveKey(SPFavoriteVaultHostKey, [self vaultHost]);
    _setOrRemoveKey(SPFavoriteVaultPortKey, [self vaultPort]);
    _setOrRemoveKey(SPFavoriteVaultOIDCMountKey, [self vaultOIDCMount]);
    _setOrRemoveKey(SPFavoriteVaultCredentialsPathKey, [self vaultCredentialsPath]);
    // SSL details
    [theFavorite setObject:[NSNumber numberWithInteger:[self useSSL]] forKey:SPFavoriteUseSSLKey];
    [theFavorite setObject:[NSNumber numberWithInteger:[self sslKeyFileLocationEnabled]] forKey:SPFavoriteSSLKeyFileLocationEnabledKey];
    _setOrRemoveKey(SPFavoriteSSLKeyFileLocationKey, [self sslKeyFileLocation]);
    [theFavorite setObject:[NSNumber numberWithInteger:[self sslCertificateFileLocationEnabled]] forKey:SPFavoriteSSLCertificateFileLocationEnabledKey];
    _setOrRemoveKey(SPFavoriteSSLCertificateFileLocationKey, [self sslCertificateFileLocation]);
    [theFavorite setObject:[NSNumber numberWithInteger:[self sslCACertFileLocationEnabled]] forKey:SPFavoriteSSLCACertFileLocationEnabledKey];
    _setOrRemoveKey(SPFavoriteSSLCACertFileLocationKey, [self sslCACertFileLocation]);

    // SSH details. Vault credentials are generated directly from Vault and
    // cannot be combined with an SSH tunnel; remove stale SSH favorite fields.
    if ([self type] == SPVaultConnection) {
        [theFavorite removeObjectForKey:SPFavoriteSSHHostKey];
        [theFavorite removeObjectForKey:SPFavoriteSSHUserKey];
        [theFavorite removeObjectForKey:SPFavoriteSSHPortKey];
        [theFavorite removeObjectForKey:SPFavoriteSSHKeyLocationEnabledKey];
        [theFavorite removeObjectForKey:SPFavoriteSSHKeyLocationKey];
        [theFavorite removeObjectForKey:SPFavoriteSSHRemoteSocketPathKey];
    } else {
        _setOrRemoveKey(SPFavoriteSSHHostKey, [self sshHost]);
        _setOrRemoveKey(SPFavoriteSSHUserKey, [self sshUser]);
        _setOrRemoveKey(SPFavoriteSSHPortKey, [self sshPort]);
        [theFavorite setObject:[NSNumber numberWithInteger:[self sshKeyLocationEnabled]] forKey:SPFavoriteSSHKeyLocationEnabledKey];
        _setOrRemoveKey(SPFavoriteSSHKeyLocationKey, [self sshKeyLocation]);
        _setOrRemoveKey(SPFavoriteSSHRemoteSocketPathKey, [self sshRemoteSocketPath]);
    }


    /*
     * Password handling for the SQL connection
     */
    NSString *oldKeychainName, *oldKeychainAccount, *newKeychainName, *newKeychainAccount;;
    NSString *oldHostnameForPassword = ([[currentFavorite objectForKey:SPFavoriteTypeKey] integerValue] == SPSocketConnection) ? @"localhost" : [currentFavorite objectForKey:SPFavoriteHostKey];
    NSString *newHostnameForPassword = ([self type] == SPSocketConnection) ? @"localhost" : [self host];

    if ([self type] == SPVaultConnection) {
        // Vault credentials are generated at connect time; remove any static SQL password from the previous favorite type.
        if (!createNewFavorite) {
            oldKeychainName = [keychain nameForFavoriteName:[currentFavorite objectForKey:SPFavoriteNameKey] id:[currentFavorite objectForKey:SPFavoriteIDKey]];
            oldKeychainAccount = [keychain accountForUser:[currentFavorite objectForKey:SPFavoriteUserKey] host:oldHostnameForPassword database:[currentFavorite objectForKey:SPFavoriteDatabaseKey]];
            [keychain deletePasswordForName:oldKeychainName account:oldKeychainAccount];
        }
    } else {
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
    }

    /*
     * Password handling for the SSH connection
     */
    if ([self type] == SPVaultConnection) {
        // Remove any SSH password left behind when converting an SSH favorite to Vault.
        if (!createNewFavorite) {
            oldKeychainName = [keychain nameForSSHForFavoriteName:[currentFavorite objectForKey:SPFavoriteNameKey] id:[currentFavorite objectForKey:SPFavoriteIDKey]];
            oldKeychainAccount = [keychain accountForSSHUser:[currentFavorite objectForKey:SPFavoriteSSHUserKey] sshHost:[currentFavorite objectForKey:SPFavoriteSSHHostKey]];
            [keychain deletePasswordForName:oldKeychainName account:oldKeychainAccount];
        }
    } else {
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
    }

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
        case SPVaultConnection:
            if (vaultNameField) {
                [[dbDocument parentWindowControllerWindow] makeFirstResponder:vaultNameField];
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

    isConnecting = NO;

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
    return [SAConnectionFormHelpers newFavoriteID];
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
    return [SAConnectionFormHelpers stripInvalidCharacters:subject ?: @""];
}

/**
 * Generate a name for the current connection based on any other populated details.
 * Currently uses the host and database fields.
 * If a name cannot be generated because there are insufficient other details, returns nil.
 */
- (NSString *)_generateNameForConnection
{
    if ([self type] == SPVaultConnection) {
        NSString *credPath = [[self vaultCredentialsPath] lastPathComponent];
        NSString *vHost = [[self vaultHost] length] ? [self vaultHost] : @"vault";
        return [credPath length] ? [NSString stringWithFormat:@"%@/%@", vHost, credPath] : vHost;
    }

    return [SAConnectionFormHelpers generateNameWithType:(SAConnectionType)[self type]
                                                    host:[self host] ?: @""
                                                database:[self database] ?: @""];
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
            connectionAttemptID++;
            dbDocument = nil;

            if (mySQLConnection) {
                [mySQLConnection setDelegate:nil];
                [NSThread detachNewThreadWithName:SPCtxt(@"SPConnectionController close background disconnect", dbDocument) target:mySQLConnection selector:@selector(disconnect) object:nil];
            }

            if ([self _isVaultConnection]) {
                if ([vaultLoginIdentifier length]) {
                    [VaultOIDCHandler cancelActiveLoginWithIdentifier:vaultLoginIdentifier];
                }
                [VaultAuthManager clearCachedCredentialsForHost:[self vaultHost] ?: @""
                                                           port:[self vaultPort] ?: @""
                                                      oidcMount:[self vaultOIDCMount] ?: @""
                                                       credPath:[self vaultCredentialsPath] ?: @""];
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
    if (requiresSSL && ([self type] == SPTCPIPConnection || [self type] == SPSocketConnection || [self type] == SPAWSIAMConnection || [self type] == SPVaultConnection)) {
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
    info.sshRemoteSocketPath = self.sshRemoteSocketPath ?: @"";
    info.connectionKeychainID = connectionKeychainID ?: @"";
    info.connectionKeychainItemName = connectionKeychainItemName ?: @"";
    info.connectionKeychainItemAccount = connectionKeychainItemAccount ?: @"";
    info.connectionSSHKeychainItemName = connectionSSHKeychainItemName ?: @"";
    info.connectionSSHKeychainItemAccount = connectionSSHKeychainItemAccount ?: @"";
    info.timeZoneMode = (SAConnectionTimeZoneMode)timeZoneMode;
    info.timeZoneIdentifier = timeZoneIdentifier ?: @"";
    info.allowDataLocalInfile = self.allowDataLocalInfile;
    info.enableClearTextPlugin = self.enableClearTextPlugin;
    info.requestServerPublicKey = self.requestServerPublicKey;
    info.useAWSIAMAuth = self.useAWSIAMAuth;
    info.awsRegion = self.awsRegion ?: @"";
    info.awsProfile = self.awsProfile ?: @"";
    info.vaultHost = self.vaultHost ?: @"";
    info.vaultPort = self.vaultPort ?: @"";
    info.vaultOIDCMount = self.vaultOIDCMount ?: @"";
    info.vaultCredentialsPath = self.vaultCredentialsPath ?: @"";
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
    if (((field == standardNameField) || (field == awsIAMNameField) || (field == socketNameField) || (field == sshNameField) || (field == vaultNameField)) && [self selectedFavoriteNode]) {
        if (![[self _stripInvalidCharactersFromString:[field stringValue]] length]) {
            [self controlTextDidEndEditing:notification];
        }
    }

    [self _startEditingConnection];

    if ([notification object] == vaultCredentialsRoleComboBox) {
        // Debounce the dropdown reorder so rapid typing doesn't reshuffle (and
        // flicker) the popup on every keystroke. Use a GCD timer rather than
        // -performSelector:afterDelay: because the latter only fires in the
        // default run-loop mode and would be starved while the field/popup is in
        // event-tracking mode (i.e. exactly while the user is typing).
        NSUInteger token = ++vaultRoleReloadToken;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self->vaultRoleReloadToken == token) {
                [self _reloadVaultRoleComboItems];
            }
        });
    }

    if (favoriteNameFieldWasAutogenerated && (field != standardNameField && field != awsIAMNameField && field != socketNameField && field != sshNameField && field != vaultNameField)) {
        [self setName:[self _generateNameForConnection]];
    }

    if (field == standardSQLHostField || field == standardUserField || field == sshSQLHostField || field == sshUserField) {
        standardPasswordField.stringValue = @"";
        sshPasswordField.stringValue = @"";
    }
}

/**
 * Selecting a Vault role from the combo box dropdown does not emit
 * controlTextDidChange:, so mark the connection as edited here to mirror the
 * behaviour of editing any other field (the value binding updates on selection).
 */
- (void)comboBoxSelectionDidChange:(NSNotification *)notification
{
    if ([notification object] != vaultCredentialsRoleComboBox) {
        return;
    }
    NSInteger idx = [vaultCredentialsRoleComboBox indexOfSelectedItem];
    if (idx >= 0 && [[vaultCredentialsRoleComboBox itemObjectValueAtIndex:idx] isEqual:[VaultRoleFilter separator]]) {
        // Separator is not a real role; restore the field to the current value.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->vaultCredentialsRoleComboBox setStringValue:(self->vaultCredentialsRole ?: @"")];
        });
        return;
    }
    [self _startEditingConnection];
    if (favoriteNameFieldWasAutogenerated) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->favoriteNameFieldWasAutogenerated) {
                [self setName:[self _generateNameForConnection]];
            }
        });
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
    if (((field == standardNameField) || (field == awsIAMNameField) || (field == socketNameField) || (field == sshNameField) || (field == vaultNameField)) && [self selectedFavoriteNode]) {

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
            if([[win delegate] isKindOfClass:[SABundleHTMLOutputWindowController class]]) {
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
                SABundleHTMLOutputWindowController *bundleController = [[SABundleHTMLOutputWindowController alloc] init];
                [bundleController setWindowUUID:socketHelpWindowUUID];

                // Remember that the socket help has been shown once the user closes its window.
                bundleController.windowWillCloseHandler = ^{
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:SPConnectionShownSocketHelp];
                };

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

    // Copy connection string requires a single non-group favorite
    if (action == @selector(copyConnectionString:)) {
        return (selectedRows == 1) && (![node isGroup]);
    }

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
    if ([data count] == 0) return;

    NSMutableArray *preparedImportData = [NSMutableArray arrayWithCapacity:[data count]];
    for (NSDictionary *item in data) {
        [preparedImportData addObject:[self favoriteImportDictionaryByAssigningNewIDs:item]];
    }

    NSMutableArray *importFavorites = [NSMutableArray array];
    [self collectFavoriteImportLeavesFromItems:preparedImportData intoArray:importFavorites];

    // Check for duplicates in imported favorites, including favorites nested in groups.
    NSMutableArray *duplicates = [NSMutableArray array];

    for (NSDictionary *favorite in importFavorites) {
        NSString *host = [favorite objectForKey:SPFavoriteHostKey] ?: @"";
        NSString *user = [favorite objectForKey:SPFavoriteUserKey] ?: @"";
        NSString *database = [favorite objectForKey:SPFavoriteDatabaseKey] ?: @"";
        NSString *port = [favorite objectForKey:SPFavoritePortKey] ?: @"";
        NSInteger typeInt = [[favorite objectForKey:SPFavoriteTypeKey] integerValue];

        // Use centralized helper for type mapping
        NSString *typeString = [SPConnectionController stringForFavoriteTypeTag:typeInt];

        SPTreeNode *duplicateNode = [self findDuplicateFavoriteForHost:host
                                                                  user:user
                                                              database:database
                                                                  port:port
                                                                  type:typeString
                                                    modeSpecificFields:favorite];

        if (duplicateNode) {
            [duplicates addObject:@{@"favorite": favorite, @"node": duplicateNode}];
        }
    }

    // Handle duplicates
    if ([duplicates count] > 0) {
        // Create duplicate items for the UI
        NSMutableArray<SPDuplicateImportItem *> *duplicateItems = [NSMutableArray array];

        for (NSDictionary *dupInfo in duplicates) {
            NSDictionary *favorite = [dupInfo objectForKey:@"favorite"];
            SPTreeNode *node = [dupInfo objectForKey:@"node"];

            NSString *favoriteName = [favorite objectForKey:SPFavoriteNameKey] ?: @"Unnamed";
            NSString *host = [favorite objectForKey:SPFavoriteHostKey] ?: @"";

            SPDuplicateImportItem *item = [[SPDuplicateImportItem alloc] initWithFavoriteName:favoriteName
                                                                                          host:host
                                                                                      favorite:favorite
                                                                                 duplicateNode:node];
            [duplicateItems addObject:item];
        }

        NSString *message;
        if ([duplicates count] == 1) {
            message = NSLocalizedString(@"1 duplicate connection found. Choose an action for each:", @"1 duplicate found");
        } else {
            message = [NSString stringWithFormat:NSLocalizedString(@"%ld duplicate connections found. Choose an action for each:", @"Multiple duplicates found"), (long)[duplicates count]];
        }

        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:NSLocalizedString(@"Duplicate Connections Found", @"Duplicate connections found")];
        [alert setInformativeText:message];

        // Add custom accessory view
        NSView *accessoryView = [SPDuplicateImportHelper createAccessoryViewWithDuplicateItems:duplicateItems];
        [alert setAccessoryView:accessoryView];

        [alert addButtonWithTitle:NSLocalizedString(@"Import", @"Import button")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button")];

        [alert beginSheetModalForWindow:[dbDocument parentWindowControllerWindow] completionHandler:^(NSModalResponse returnCode) {
            if (returnCode != NSAlertFirstButtonReturn) {
                // Cancel
                SPDuplicateActionHandler.shared.items = @[];
                return;
            }

            NSMutableArray *importedNodes = [NSMutableArray array];
            NSMutableIndexSet *importedIndexSet = [NSMutableIndexSet indexSet];

            // Process each duplicate based on selected action
            for (SPDuplicateImportItem *item in duplicateItems) {
                if (item.action == SPDuplicateActionUpdate) {
                    // Update existing (no password from plist imports)
                    [self updateFavoriteNode:item.duplicateNode withData:item.favorite password:nil];
                    [importedNodes addObject:item.duplicateNode];
                }
                // Create New entries stay in itemsToImport so grouped imports keep their structure.
                // If Skip - the duplicate leaf is filtered out below.
            }

            NSArray *itemsToImport = [self favoriteImportItemsByApplyingDuplicateActionsToItems:preparedImportData duplicateItems:duplicateItems];

            // Add remaining imported items. This preserves imported groups while removing skipped or updated duplicate leaves.
            for (NSMutableDictionary *favorite in itemsToImport) {
                SPTreeNode *newNode = [self->favoritesController addFavoriteNodeWithData:favorite asChildOfNode:nil];
                [importedNodes addObject:newNode];
            }

            if (self->currentSortItem > SPFavoritesSortUnsorted) {
                [self _sortFavorites];
            }

            [self _reloadFavoritesViewData];

            // Select the imported nodes and scroll into view
            for (SPTreeNode *eachNode in importedNodes) {
                NSInteger row = [self->favoritesOutlineView rowForItem:eachNode];
                // Guard against -1 before adding to index set
                if (row != -1) {
                    [importedIndexSet addIndex:(NSUInteger)row];
                }
            }

            if ([importedIndexSet count] > 0) {
                [self->favoritesOutlineView selectRowIndexes:importedIndexSet byExtendingSelection:NO];
                [self _scrollToSelectedNode];
            }

            // Clear singleton items to prevent memory leak
            SPDuplicateActionHandler.shared.items = @[];
        }];
    }
    else {
        // No duplicates - import all normally
        NSMutableArray *importedNodes = [NSMutableArray array];
        NSMutableIndexSet *importedIndexSet = [NSMutableIndexSet indexSet];

        for (NSMutableDictionary *favorite in preparedImportData) {
            SPTreeNode *newNode = [favoritesController addFavoriteNodeWithData:favorite asChildOfNode:nil];
            [importedNodes addObject:newNode];
        }

        if (currentSortItem > SPFavoritesSortUnsorted) {
            [self _sortFavorites];
        }

        [self _reloadFavoritesViewData];

        // Select the new nodes and scroll into view
        for (SPTreeNode *eachNode in importedNodes) {
            NSInteger row = [favoritesOutlineView rowForItem:eachNode];
            if (row != -1) {
                [importedIndexSet addIndex:(NSUInteger)row];
            }
        }

        if ([importedIndexSet count] > 0) {
            [favoritesOutlineView selectRowIndexes:importedIndexSet byExtendingSelection:NO];
            [self _scrollToSelectedNode];
        }
    }
}

- (NSMutableDictionary *)favoriteImportDictionaryByAssigningNewIDs:(NSDictionary *)item
{
    NSMutableDictionary *mutableItem = [item mutableCopy];
    NSArray *children = [item objectForKey:SPFavoriteChildrenKey];

    if (children) {
        NSMutableArray *preparedChildren = [NSMutableArray arrayWithCapacity:[children count]];
        for (NSDictionary *child in children) {
            [preparedChildren addObject:[self favoriteImportDictionaryByAssigningNewIDs:child]];
        }
        [mutableItem setObject:preparedChildren forKey:SPFavoriteChildrenKey];
    }
    else {
        [mutableItem setObject:[self _createNewFavoriteID] forKey:SPFavoriteIDKey];
    }

    return mutableItem;
}

- (void)collectFavoriteImportLeavesFromItems:(NSArray *)items intoArray:(NSMutableArray *)favorites
{
    for (NSDictionary *item in items) {
        NSArray *children = [item objectForKey:SPFavoriteChildrenKey];

        if (children) {
            [self collectFavoriteImportLeavesFromItems:children intoArray:favorites];
        }
        else {
            [favorites addObject:item];
        }
    }
}

- (NSArray *)favoriteImportItemsByApplyingDuplicateActionsToItems:(NSArray *)items duplicateItems:(NSArray<SPDuplicateImportItem *> *)duplicateItems
{
    NSMutableArray *filteredItems = [NSMutableArray array];

    for (NSMutableDictionary *item in items) {
        NSArray *children = [item objectForKey:SPFavoriteChildrenKey];

        if (children) {
            NSArray *filteredChildren = [self favoriteImportItemsByApplyingDuplicateActionsToItems:children duplicateItems:duplicateItems];
            if ([filteredChildren count] > 0 || [children count] == 0) {
                NSMutableDictionary *groupCopy = [item mutableCopy];
                [groupCopy setObject:filteredChildren forKey:SPFavoriteChildrenKey];
                [filteredItems addObject:groupCopy];
            }
            continue;
        }

        BOOL shouldImport = YES;
        for (SPDuplicateImportItem *duplicateItem in duplicateItems) {
            if (duplicateItem.favorite == item) {
                shouldImport = (duplicateItem.action == SPDuplicateActionCreateNew);
                break;
            }
        }

        if (shouldImport) {
            [filteredItems addObject:item];
        }
    }

    return filteredItems;
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
        [vaultColorField setColorList:colorList];
        [vaultColorField bind:@"selectedTag" toObject:self withKeyPath:@"colorIndex" options:nil];
        [socketColorField setColorList:colorList];
        [socketColorField   bind:@"selectedTag" toObject:self withKeyPath:@"colorIndex" options:nil];

        // An instance of NSMenuItem can not be assigned to more than one menu so we have to clone items.
        // Cannot bulk set items on macOS < 10.14, must removeAllItems and addItem https://github.com/Sequel-Ace/Sequel-Ace/issues/403
        [standardTimeZoneField.menu removeAllItems];
        [awsIAMTimeZoneField.menu removeAllItems];
        [vaultTimeZoneField.menu removeAllItems];
        [sshTimeZoneField.menu removeAllItems];
        [socketTimeZoneField.menu removeAllItems];
        for (NSMenuItem *menuItem in [self generateTimeZoneMenuItems]) {
            [standardTimeZoneField.menu addItem:[menuItem copy]];
            [awsIAMTimeZoneField.menu addItem:[menuItem copy]];
            [vaultTimeZoneField.menu addItem:[menuItem copy]];
            [sshTimeZoneField.menu addItem:[menuItem copy]];
            [socketTimeZoneField.menu addItem:[menuItem copy]];
        }

        [connectionDetailsScrollView setPostsFrameChangedNotifications:YES];
        [[connectionDetailsScrollView contentView] setPostsFrameChangedNotifications:YES];
        [self setUpPasswordRevealButtons];

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

        // Localize the Vault role refresh button title (static XIB titles are not localized in this app).
        [vaultRefreshRolesButton setTitle:NSLocalizedString(@"Refresh", @"Vault roles refresh button title")];

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

- (void)setUpPasswordRevealButtons
{
    [self addPasswordRevealButtonForField:standardPasswordField keyPath:@"password"];
    [self addPasswordRevealButtonForField:socketPasswordField keyPath:@"password"];
    [self addPasswordRevealButtonForField:sshPasswordField keyPath:@"password"];
    [self addPasswordRevealButtonForField:sshSSHPasswordField keyPath:@"sshPassword"];
}

- (void)addPasswordRevealButtonForField:(NSSecureTextField *)field keyPath:(NSString *)keyPath
{
    if (!field || !field.superview) {
        return;
    }

    NSRect fieldFrame = field.frame;
    CGFloat buttonSize = 18.f;

    NSTextField *plainField = [[NSTextField alloc] initWithFrame:fieldFrame];
    plainField.hidden = YES;
    plainField.autoresizingMask = field.autoresizingMask;
    plainField.toolTip = field.toolTip;
    plainField.font = field.font;
    plainField.delegate = field.delegate;
    plainField.editable = field.editable;
    plainField.selectable = field.selectable;
    plainField.enabled = field.enabled;
    plainField.bezelStyle = field.bezelStyle;
    plainField.drawsBackground = field.drawsBackground;
    plainField.lineBreakMode = field.lineBreakMode;
    plainField.usesSingleLineMode = field.cell.usesSingleLineMode;
    [plainField bind:@"value" toObject:self withKeyPath:keyPath options:@{NSContinuouslyUpdatesValueBindingOption: @YES}];
    [field.superview addSubview:plainField positioned:NSWindowAbove relativeTo:field];

    NSButton *button = [[SPPasswordRevealButton alloc] initWithFrame:NSMakeRect(NSMaxX(fieldFrame) - buttonSize - 6.f,
                                                                                fieldFrame.origin.y + floor((fieldFrame.size.height - buttonSize) / 2.f),
                                                                                buttonSize,
                                                                                buttonSize)];
    button.buttonType = NSButtonTypeToggle;
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.bordered = NO;
    button.autoresizingMask = NSViewMinXMargin;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = NSLocalizedString(@"Show password", @"Show password tooltip");

    NSImage *image = nil;
    NSImage *alternateImage = nil;
    if ([NSImage respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)]) {
        image = [NSImage imageWithSystemSymbolName:@"eye" accessibilityDescription:NSLocalizedString(@"Show password", @"Show password tooltip")];
        alternateImage = [NSImage imageWithSystemSymbolName:@"eye.slash" accessibilityDescription:NSLocalizedString(@"Hide password", @"Hide password tooltip")];
    }

    if (image) {
        image.template = YES;
        if (alternateImage) {
            alternateImage.template = YES;
        }
        button.image = image;
    }
    else {
        button.title = NSLocalizedString(@"Show", @"Fallback password reveal button title");
    }

    objc_setAssociatedObject(button, kPasswordFieldKey, field, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(button, kPlainPasswordFieldKey, plainField, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(button, kRevealPasswordImageKey, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, kHidePasswordImageKey, alternateImage, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    button.target = self;
    button.action = @selector(toggleConnectionPasswordVisibility:);

    [field.superview addSubview:button positioned:NSWindowAbove relativeTo:plainField];
}

- (void)toggleConnectionPasswordVisibility:(NSButton *)sender
{
    NSSecureTextField *secureField = objc_getAssociatedObject(sender, kPasswordFieldKey);
    NSTextField *plainField = objc_getAssociatedObject(sender, kPlainPasswordFieldKey);

    if (!secureField || !plainField) {
        return;
    }

    BOOL shouldReveal = (sender.state == NSControlStateValueOn);
    plainField.stringValue = secureField.stringValue ?: @"";
    secureField.hidden = shouldReveal;
    plainField.hidden = !shouldReveal;

    NSImage *revealImage = objc_getAssociatedObject(sender, kRevealPasswordImageKey);
    NSImage *hideImage = objc_getAssociatedObject(sender, kHidePasswordImageKey);

    if (revealImage && hideImage) {
        sender.image = shouldReveal ? hideImage : revealImage;
    }
    else {
        sender.title = shouldReveal ?
            NSLocalizedString(@"Hide", @"Fallback password hide button title") :
            NSLocalizedString(@"Show", @"Fallback password reveal button title");
    }

    sender.toolTip = shouldReveal ?
        NSLocalizedString(@"Hide password", @"Hide password tooltip") :
        NSLocalizedString(@"Show password", @"Show password tooltip");

    [sender.superview addSubview:sender positioned:NSWindowAbove relativeTo:nil];

    if (shouldReveal && [[secureField window] firstResponder] == secureField) {
        [[secureField window] makeFirstResponder:plainField];
    }
    else if (!shouldReveal && [[plainField window] firstResponder] == plainField) {
        secureField.stringValue = plainField.stringValue ?: @"";
        [[plainField window] makeFirstResponder:secureField];
    }
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
           forKeyPath:SPFavoriteRequestServerPublicKeyKey
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
           forKeyPath:SPFavoriteSSHRemoteSocketPathKey
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

    [self setUpFavoritesSearchField];

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
 * Configures the favorites search field: sets self as text delegate (so Down arrow can
 * forward focus into the outline view), and installs a local key-event monitor so that
 * ⌘F focuses the search field whenever the connection window is key.
 */
- (void)setUpFavoritesSearchField
{
    favoritesSearchField.delegate = self;

    if (favoritesSearchKeyMonitor) return;

    __weak SPConnectionController *weakSelf = self;
    favoritesSearchKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                                     handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
        SPConnectionController *strongSelf = weakSelf;
        if (!strongSelf) return event;
        NSSearchField *field = strongSelf->favoritesSearchField;
        NSView *connView = strongSelf->connectionView;
        if (!field || !connView) return event;

        BOOL cmdPressed = ([event modifierFlags] & NSEventModifierFlagCommand) != 0;
        BOOL isCmdF = cmdPressed && [[event charactersIgnoringModifiers] isEqualToString:@"f"];
        if (!isCmdF) return event;

        NSWindow *window = [connView window];
        if (!window || [NSApp keyWindow] != window) return event;
        if ([connView isHiddenOrHasHiddenAncestor]) return event;

        [window makeFirstResponder:field];
        return nil; // consume
    }];
}

#pragma mark - NSTextFieldDelegate (favorites search field)

/**
 * Handles arrow-down in the search field: moves keyboard focus into the
 * favorites outline view and selects the first favorite if nothing is selected.
 */
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    if (control != favoritesSearchField) return NO;
    if (commandSelector != @selector(moveDown:)) return NO;

    NSWindow *window = [favoritesOutlineView window];
    if (!window) return NO;
    [window makeFirstResponder:favoritesOutlineView];

    if ([favoritesOutlineView selectedRow] < 0) {
        // Row 0 is Quick Connect; pick the first selectable row after it.
        for (NSInteger row = 1; row < [favoritesOutlineView numberOfRows]; row++) {
            id item = [favoritesOutlineView itemAtRow:row];
            if ([favoritesOutlineView.delegate respondsToSelector:@selector(outlineView:shouldSelectItem:)]
                && ![favoritesOutlineView.delegate outlineView:favoritesOutlineView shouldSelectItem:item]) {
                continue;
            }
            [favoritesOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
            [favoritesOutlineView scrollRowToVisible:row];
            break;
        }
    }
    return YES;
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
    if (favoritesSearchKeyMonitor) {
        [NSEvent removeMonitor:favoritesSearchKeyMonitor];
        favoritesSearchKeyMonitor = nil;
    }

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
    [self removeObserver:self forKeyPath:SPFavoriteRequestServerPublicKeyKey];
    [self removeObserver:self forKeyPath:SPFavoriteUseSSLKey];
    [self removeObserver:self forKeyPath:SPFavoriteSSHHostKey];
    [self removeObserver:self forKeyPath:SPFavoriteSSHUserKey];
    [self removeObserver:self forKeyPath:SPFavoriteSSHPortKey];
    [self removeObserver:self forKeyPath:SPFavoriteSSHKeyLocationEnabledKey];
    [self removeObserver:self forKeyPath:SPFavoriteSSHKeyLocationKey];
    [self removeObserver:self forKeyPath:SPFavoriteSSHRemoteSocketPathKey];
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
