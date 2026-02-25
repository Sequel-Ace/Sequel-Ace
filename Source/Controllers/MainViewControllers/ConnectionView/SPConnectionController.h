//
//  SPConnectionController.h
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

#import "SPConnectionControllerDelegateProtocol.h"
#import "SPFavoritesExportProtocol.h"
#import "SPFavoritesImportProtocol.h"
#import "SPReachability.h"

#import <SPMySQL/SPMySQL.h>

@class SPDatabaseDocument, 
	   SPFavoritesController, 
	   SPSSHTunnel,
	   SPTreeNode,
	   SPFavoritesOutlineView,
       SPMySQLConnection,
	   SPSplitView,
	   SPKeychain,
	   SPFavoriteNode,
	   SPFavoriteTextFieldCell,
       SPColorSelectorView
;

typedef NS_ENUM(NSInteger, SPConnectionTimeZoneMode) {
    SPConnectionTimeZoneModeUseServerTZ,
    SPConnectionTimeZoneModeUseSystemTZ,
    SPConnectionTimeZoneModeUseFixedTZ
};

@interface SPConnectionController : NSViewController <SPMySQLConnectionDelegate, NSOpenSavePanelDelegate, SPFavoritesImportProtocol, SPFavoritesExportProtocol, NSSplitViewDelegate>
{	
	__weak SPDatabaseDocument *dbDocument;
	SPMySQLConnection *mySQLConnection;

	SPKeychain *keychain;
	NSSplitView *databaseConnectionView;

	NSOpenPanel *keySelectionPanel;
	NSUserDefaults *prefs;

	BOOL cancellingConnection;
	BOOL isConnecting;
	BOOL isEditingConnection;
	BOOL isTestingConnection;
	
	// Standard details
	NSInteger previousType;
	NSInteger type;
	NSString *name;
	NSString *host;
	NSString *user;
	NSString *password;
	NSString *database;
	NSString *socket;
	NSString *port;
	NSInteger colorIndex;
	BOOL useCompression;

	// Time Zone details
	SPConnectionTimeZoneMode timeZoneMode;
	NSString *timeZoneIdentifier;
	
	//Special settings
	NSInteger allowDataLocalInfile;
	
	// Clear text plugin
	NSInteger enableClearTextPlugin;

	// AWS IAM Authentication (profile-based only)
	NSInteger useAWSIAMAuth;
	NSString *awsRegion;
	NSString *awsProfile;
	NSArray<NSString *> *awsAvailableRegionValues;

	// SSL details
	NSInteger useSSL;
	NSInteger sslKeyFileLocationEnabled;
	NSString *sslKeyFileLocation;
	NSInteger sslCertificateFileLocationEnabled;
	NSString *sslCertificateFileLocation;
	NSInteger sslCACertFileLocationEnabled;
	NSString *sslCACertFileLocation;
	
	// SSH details
	NSString *sshHost;
	NSString *sshUser;
	NSString *sshPassword;
	NSInteger sshKeyLocationEnabled;
	NSString *sshKeyLocation;
	NSString *sshPort;

	NSString *connectionKeychainID;
	NSString *connectionKeychainItemName;
	NSString *connectionKeychainItemAccount;
	NSString *connectionSSHKeychainItemName;
	NSString *connectionSSHKeychainItemAccount;

	IBOutlet NSView *connectionView;
	IBOutlet SPSplitView *connectionSplitView;
	IBOutlet NSScrollView *connectionDetailsScrollView;
	IBOutlet NSTextField *connectionInstructionsTextField;
	IBOutlet SPFavoritesOutlineView *favoritesOutlineView;


	IBOutlet NSView *connectionResizeContainer;
	IBOutlet NSView *standardConnectionFormContainer;
	IBOutlet NSView *standardConnectionSSLDetailsContainer;
	IBOutlet NSView *awsIAMConnectionFormContainer;
	IBOutlet NSView *socketConnectionFormContainer;
	IBOutlet NSView *socketConnectionSSLDetailsContainer;
	IBOutlet NSView *sshConnectionFormContainer;
	IBOutlet NSView *sshConnectionSSLDetailsContainer;
	IBOutlet NSView *sshKeyLocationHelp;
	IBOutlet NSView *sslKeyFileLocationHelp;
	IBOutlet NSView *sslCertificateLocationHelp;
	IBOutlet NSView *sslCACertLocationHelp;

	// AWS IAM Authentication UI (profile-based only)
	IBOutlet NSPopUpButton *awsProfilePopup;
	IBOutlet NSComboBox *awsRegionComboBox;
	IBOutlet NSButton *awsAuthorizeButton;
	IBOutlet NSTextField *awsAuthorizeInfoLabel;
	IBOutlet NSTextField *awsProfileLabel;
	IBOutlet NSTextField *awsRegionLabel;
	IBOutlet NSTextField *awsIAMNameField;
	IBOutlet NSTextField *awsIAMSQLHostField;
	IBOutlet NSTextField *awsIAMUserField;
	IBOutlet NSSecureTextField *awsIAMPasswordField;
	IBOutlet SPColorSelectorView *awsIAMColorField;
	IBOutlet NSPopUpButton *awsIAMTimeZoneField;

	IBOutlet NSTextField *standardNameField;
	IBOutlet NSTextField *sshNameField;
	IBOutlet NSTextField *socketNameField;
	IBOutlet NSTextField *standardSQLHostField;
	IBOutlet NSTextField *sshSQLHostField;
	IBOutlet NSTextField *standardUserField;
	IBOutlet NSTextField *socketUserField;
	IBOutlet NSTextField *sshUserField;
	IBOutlet SPColorSelectorView *standardColorField;
	IBOutlet SPColorSelectorView *sshColorField;
	IBOutlet SPColorSelectorView *socketColorField;
	IBOutlet NSSecureTextField *standardPasswordField;
	IBOutlet NSSecureTextField *socketPasswordField;
	IBOutlet NSSecureTextField *sshPasswordField;
	IBOutlet NSSecureTextField *sshSSHPasswordField;
	IBOutlet NSButton *sshSSHKeyButton;
	IBOutlet NSPopUpButton *standardTimeZoneField;
	IBOutlet NSPopUpButton *sshTimeZoneField;
	IBOutlet NSPopUpButton *socketTimeZoneField;
	IBOutlet NSButton *standardSSLKeyFileButton;
	IBOutlet NSButton *standardSSLCertificateButton;
	IBOutlet NSButton *standardSSLCACertButton;
	IBOutlet NSButton *socketSSLKeyFileButton;
	IBOutlet NSButton *socketSSLCertificateButton;
	IBOutlet NSButton *socketSSLCACertButton;
	IBOutlet NSButton *sslOverSSHKeyFileButton;
	IBOutlet NSButton *sslOverSSHCertificateButton;
	IBOutlet NSButton *sslOverSSHCACertButton;

	IBOutlet NSButton *connectButton;
	IBOutlet NSButton *testConnectButton;
	IBOutlet NSButton *helpButton;
	IBOutlet NSButton *saveFavoriteButton;
	IBOutlet NSMenuItem *favoritesSortByMenuItem;
	IBOutlet NSView *exportPanelAccessoryView;
	IBOutlet NSView *editButtonsView;
	
	BOOL isEditingItemName;
    BOOL reverseFavoritesSort;
	BOOL initComplete;
	BOOL allowSplitViewResizing;
	BOOL favoriteNameFieldWasAutogenerated;

	NSArray *draggedNodes;
	NSImage *folderImage;
	
	SPTreeNode *favoritesRoot;
	SPTreeNode *quickConnectItem;

	SPFavoriteTextFieldCell *quickConnectCell;

	NSDictionary *currentFavorite;
	SPFavoritesController *favoritesController;
	SPFavoritesSortItem currentSortItem;

    @package
    SPSSHTunnel *sshTunnel;
    IBOutlet NSWindow *errorDetailWindow;
    IBOutlet NSTextView *errorDetailText;
    IBOutlet NSProgressIndicator *progressIndicator;
    IBOutlet NSTextField *progressIndicatorText;

}

@property (readwrite, weak) id <SPConnectionControllerDelegateProtocol> delegate;
@property (readwrite) NSInteger type;
@property (readwrite, copy) NSString *name;
@property (readwrite, copy) NSString *host;
@property (readwrite, copy) NSString *user;
@property (readwrite, copy) NSString *password;
@property (readwrite, copy) NSString *database;
@property (readwrite, copy) NSString *socket;
@property (readwrite, copy) NSString *port;
@property (readwrite) SPConnectionTimeZoneMode timeZoneMode;
@property (readwrite, copy) NSString *timeZoneIdentifier;
@property (readwrite) NSInteger allowDataLocalInfile;
@property (readwrite) NSInteger enableClearTextPlugin;
// AWS IAM Authentication (profile-based only)
@property (readwrite) NSInteger useAWSIAMAuth;
@property (readwrite, copy) NSString *awsRegion;
@property (readwrite, copy) NSString *awsProfile;
@property (readwrite) NSInteger useSSL;
@property (readwrite) NSInteger colorIndex;
@property (readwrite) NSInteger sslKeyFileLocationEnabled;
@property (readwrite, copy) NSString *sslKeyFileLocation;
@property (readwrite) NSInteger sslCertificateFileLocationEnabled;
@property (readwrite, copy) NSString *sslCertificateFileLocation;
@property (readwrite) NSInteger sslCACertFileLocationEnabled;
@property (readwrite, copy) NSString *sslCACertFileLocation;
@property (readwrite, copy) NSString *sshHost;
@property (readwrite, copy) NSString *sshUser;
@property (readwrite, copy) NSString *sshPassword;
@property (readwrite) NSInteger sshKeyLocationEnabled;
@property (readwrite, copy) NSString *sshKeyLocation;
@property (readwrite, copy) NSString *sshPort;
@property (readwrite, copy) NSString *socketHelpWindowUUID;
@property (readwrite, copy) NSString *connectionKeychainID;
@property (readwrite, copy) NSString *connectionKeychainItemName;
@property (readwrite, copy) NSString *connectionKeychainItemAccount;
@property (readwrite, copy) NSString *connectionSSHKeychainItemName;
@property (readwrite, copy) NSString *connectionSSHKeychainItemAccount;
@property (readwrite) BOOL useCompression;
@property (readwrite, strong) NSMutableArray<NSDictionary<NSString *, id> *> *bookmarks;

@property (readonly) BOOL isConnecting;
@property (readonly) BOOL isEditingConnection;

- (NSString *)keychainPassword;
- (NSString *)keychainPasswordForSSH;
/**
 * Returns the password to use for an actual MySQL connect/reconnect request.
 * For AWS IAM connections this generates a fresh token.
 */
- (NSString *)passwordForConnectionRequest;

// Connection processes
- (IBAction)initiateConnection:(id)sender;
- (IBAction)cancelConnection:(id)sender;

// Interface interaction
- (void)nodeDoubleClicked:(id)sender;
- (IBAction)chooseKeyLocation:(id)sender;
- (IBAction)showHelp:(id)sender;
- (IBAction)updateSSLInterface:(id)sender;
- (IBAction)updateKeyLocationFileVisibility:(id)sender;

// AWS IAM Authentication
- (IBAction)updateAWSIAMInterface:(id)sender;
- (IBAction)authorizeAWSDirectory:(id)sender;
- (NSArray<NSString *> *)awsAvailableProfiles;
- (NSArray<NSString *> *)awsAvailableRegions;
- (BOOL)isAWSDirectoryAuthorized;

- (void)resizeTabViewToConnectionType:(NSUInteger)theType animating:(BOOL)animate;

- (IBAction)sortFavorites:(id)sender;
- (IBAction)reverseSortFavorites:(NSMenuItem *)sender;

-(BOOL)validateCertFile:(NSURL *)url error:(NSError **)outError;
-(BOOL)validateKeyFile:(NSURL *)url error:(NSError **)outError;
-(void)showValidationAlertForError:(NSError*)err;
-(BOOL)connected;
- (BOOL)isConnectedViaSSL;

// Favorites interaction
- (void)updateFavoriteSelection:(id)sender;
- (void)updateFavoriteNextKeyView;
- (NSMutableDictionary *)selectedFavorite;
- (SPTreeNode *)selectedFavoriteNode;
- (NSArray *)selectedFavoriteNodes;

- (IBAction)saveFavorite:(id)sender;
- (IBAction)addFavorite:(id)sender;
- (IBAction)addFavoriteUsingCurrentDetails:(id)sender;
- (IBAction)addGroup:(id)sender;
- (IBAction)removeNode:(id)sender;
- (IBAction)duplicateFavorite:(id)sender;
- (IBAction)renameNode:(id)sender;
- (IBAction)makeSelectedFavoriteDefault:(id)sender;
- (void)selectQuickConnectItem;

// Import/export favorites
- (IBAction)importFavorites:(id)sender;
- (IBAction)exportFavorites:(id)sender;

// Accessors
- (SPFavoritesOutlineView *)favoritesOutlineView;

#pragma mark - SPConnectionHandler

- (void)initiateMySQLConnection;
- (void)initiateMySQLConnectionInBackground;
- (void)initiateSSHTunnelConnection;

- (void)mySQLConnectionEstablished;
- (void)sshTunnelCallback:(SPSSHTunnel *)theTunnel;

- (void)addConnectionToDocument;

- (void)failConnectionWithTitle:(NSString *)theTitle errorMessage:(NSString *)theErrorMessage detail:(NSString *)errorDetail;

#pragma mark - SPConnectionControllerInitializer

- (instancetype)initWithDocument:(SPDatabaseDocument *)document;

- (void)loadNib;
- (void)registerForNotifications;
- (void)setUpFavoritesOutlineView;
- (void)setUpSelectedConnectionFavorite;

@end
