//
//  SPMCPPreferencePane.m
//  Sequel Ace
//
//  Created for Sequel Ace by contributors.
//  See https://github.com/Sequel-Ace/Sequel-Ace/issues/2314
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

#import "SPMCPPreferencePane.h"
#import "SPConstants.h"
#import "sequel-ace-Swift.h"

static const NSInteger kMCPDefaultPort     = 8765;
static const NSInteger kMCPMinPort         = 1024;
static const NSInteger kMCPMaxPort         = 65535;

@interface SPMCPPreferencePane ()

@property (nonatomic, strong) NSButton      *enableCheckbox;
@property (nonatomic, strong) NSButton      *readOnlyCheckbox;
@property (nonatomic, strong) NSTextField   *portLabel;
@property (nonatomic, strong) NSTextField   *portField;
@property (nonatomic, strong) NSTextField   *statusLabel;
@property (nonatomic, strong) NSTextField   *exportPathLabel;
@property (nonatomic, strong) NSTextField   *exportPathField;
@property (nonatomic, strong) NSButton      *exportPathButton;
@property (nonatomic, strong) NSTextField   *endpointField;

@end

@implementation SPMCPPreferencePane

#pragma mark - View lifecycle

- (void)loadView
{
    CGFloat viewW = 564.0;
    CGFloat viewH = 254.0;
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, viewW, viewH)];
    [root setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    // Frame-based panes report a fittingSize of 0, which makes the preferences
    // window fall back to its minimum height. Give the view an explicit height
    // so the window sizes to this pane's content, like the Auto Layout panes do.
    NSLayoutConstraint *heightC = [NSLayoutConstraint constraintWithItem:root
                                                              attribute:NSLayoutAttributeHeight
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:nil
                                                              attribute:NSLayoutAttributeNotAnAttribute
                                                             multiplier:1.0
                                                               constant:viewH];
    heightC.priority = NSLayoutPriorityDefaultHigh;
    [root addConstraint:heightC];

    // Two-column layout (matching the other preference panes): right-aligned
    // labels in a left column, controls in a right column, all pinned to the top.
    NSAutoresizingMaskOptions ctrlMask  = NSViewWidthSizable | NSViewMinYMargin;
    NSAutoresizingMaskOptions labelMask = NSViewMinYMargin;

    CGFloat labelX   = 20.0;
    CGFloat labelW   = 130.0;
    CGFloat controlX = labelX + labelW + 12.0;
    CGFloat controlW = viewW - 20.0 - controlX;
    CGFloat chooseW  = 100.0;
    CGFloat y        = 218.0;

    // Server: enable, status, read-only
    NSTextField *serverLabel = [self makeLabel:NSLocalizedString(@"Server:", @"MCP pref: server row label")
                                             x:labelX y:y width:labelW];
    serverLabel.autoresizingMask = labelMask;
    [root addSubview:serverLabel];

    _enableCheckbox = [NSButton checkboxWithTitle:NSLocalizedString(@"Enable MCP Server (localhost only)",
                                                                    @"MCP pref: enable checkbox")
                                           target:self action:@selector(toggleMCPServer:)];
    _enableCheckbox.frame = NSMakeRect(controlX, y, controlW, 20);
    _enableCheckbox.autoresizingMask = ctrlMask;
    _enableCheckbox.state = [prefs boolForKey:SPMCPServerEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    [root addSubview:_enableCheckbox];
    y -= 20;

    _statusLabel = [self makeSmallLabel:@"" x:controlX y:y width:controlW];
    _statusLabel.autoresizingMask = ctrlMask;
    [root addSubview:_statusLabel];
    y -= 24;

    _readOnlyCheckbox = [NSButton checkboxWithTitle:NSLocalizedString(@"Read-only mode (reject queries that modify data)",
                                                                      @"MCP pref: read-only checkbox")
                                             target:self action:@selector(toggleReadOnly:)];
    _readOnlyCheckbox.frame = NSMakeRect(controlX, y, controlW, 20);
    _readOnlyCheckbox.autoresizingMask = ctrlMask;
    _readOnlyCheckbox.state = [prefs boolForKey:SPMCPReadOnly] ? NSControlStateValueOn : NSControlStateValueOff;
    [root addSubview:_readOnlyCheckbox];
    y -= 34;

    // Port
    NSTextField *portLabel = [self makeLabel:NSLocalizedString(@"Port:", @"MCP pref: port label")
                                           x:labelX y:y + 2 width:labelW];
    portLabel.autoresizingMask = labelMask;
    [root addSubview:portLabel];
    _portLabel = portLabel;

    _portField = [[NSTextField alloc] initWithFrame:NSMakeRect(controlX, y, 80, 22)];
    _portField.delegate       = (id<NSTextFieldDelegate>)self;
    _portField.target         = self;
    _portField.action         = @selector(updatePort:);
    _portField.stringValue    = [NSString stringWithFormat:@"%ld", (long)[self currentPort]];
    _portField.placeholderString = @"8765";
    _portField.autoresizingMask = labelMask;
    [root addSubview:_portField];
    y -= 22;

    NSTextField *portHint = [self makeSmallLabel:NSLocalizedString(
        @"Default: 8765. Any unprivileged port (1024–65535) may be used.",
        @"MCP pref: port hint")
                                               x:controlX y:y width:controlW];
    portHint.autoresizingMask = ctrlMask;
    [root addSubview:portHint];
    y -= 30;

    // Export folder
    NSTextField *exportLabel = [self makeLabel:NSLocalizedString(@"Export folder:", @"MCP pref: export row label")
                                             x:labelX y:y + 2 width:labelW];
    exportLabel.autoresizingMask = labelMask;
    [root addSubview:exportLabel];
    _exportPathLabel = exportLabel;

    _exportPathField = [[NSTextField alloc] initWithFrame:NSMakeRect(controlX, y, controlW - chooseW - 8, 22)];
    _exportPathField.editable    = NO;
    _exportPathField.bezeled     = YES;
    _exportPathField.bezelStyle  = NSTextFieldSquareBezel;
    _exportPathField.stringValue = [self currentExportPath];
    _exportPathField.autoresizingMask = ctrlMask;
    [root addSubview:_exportPathField];

    _exportPathButton = [NSButton buttonWithTitle:NSLocalizedString(@"Choose…", @"MCP pref: choose button")
                                           target:self action:@selector(chooseExportPath:)];
    _exportPathButton.frame = NSMakeRect(controlX + controlW - chooseW, y - 1, chooseW, 24);
    _exportPathButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [root addSubview:_exportPathButton];
    y -= 34;

    // Endpoint (the one value every MCP client needs)
    NSTextField *endpointLabel = [self makeLabel:NSLocalizedString(@"Endpoint:", @"MCP pref: endpoint row label")
                                               x:labelX y:y + 2 width:labelW];
    endpointLabel.autoresizingMask = labelMask;
    [root addSubview:endpointLabel];

    _endpointField = [[NSTextField alloc] initWithFrame:NSMakeRect(controlX, y, controlW - chooseW - 8, 22)];
    _endpointField.editable    = NO;
    _endpointField.selectable  = YES;
    _endpointField.bezeled     = YES;
    _endpointField.bezelStyle  = NSTextFieldSquareBezel;
    _endpointField.font        = [NSFont userFixedPitchFontOfSize:NSFont.smallSystemFontSize];
    _endpointField.stringValue = [self endpointURLString];
    _endpointField.autoresizingMask = ctrlMask;
    [root addSubview:_endpointField];

    NSButton *copyButton = [NSButton buttonWithTitle:NSLocalizedString(@"Copy", @"MCP pref: copy endpoint button")
                                              target:self action:@selector(copyEndpoint:)];
    copyButton.frame = NSMakeRect(controlX + controlW - chooseW, y - 1, chooseW, 24);
    copyButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [root addSubview:copyButton];
    y -= 24;

    NSTextField *endpointHint = [self makeSmallLabel:NSLocalizedString(
        @"Add this URL to any MCP-compatible client (Claude, Cursor, Cline, VS Code, and others).",
        @"MCP pref: endpoint hint")
                                                   x:controlX y:y - 14 width:controlW];
    endpointHint.frame = NSMakeRect(controlX, y - 14, controlW, 32);
    endpointHint.autoresizingMask = ctrlMask;
    [root addSubview:endpointHint];

    [self refreshStatus];
    self.view = root;
}

#pragma mark - SPPreferencePaneProtocol

- (NSView *)preferencePaneView
{
    return self.view;
}

- (NSImage *)preferencePaneIcon
{
    if (@available(macOS 11.0, *)) {
        NSImage *icon = [NSImage imageWithSystemSymbolName:@"point.3.connected.trianglepath.dotted"
                                 accessibilityDescription:nil];
        if (icon) return icon;
    }
    return [NSImage imageNamed:NSImageNameNetwork];
}

- (NSString *)preferencePaneName
{
    return NSLocalizedString(@"MCP Server", @"MCP preference pane name");
}

- (NSString *)preferencePaneIdentifier
{
    return SPPreferenceToolbarMCP;
}

- (NSString *)preferencePaneToolTip
{
    return NSLocalizedString(@"MCP Server Preferences", @"MCP preference pane tooltip");
}

- (void)preferencePaneWillBeShown
{
    [self refreshStatus];
    [self refreshEndpoint];
}

#pragma mark - IBActions

- (IBAction)toggleMCPServer:(id)sender
{
    BOOL enabled = _enableCheckbox.state == NSControlStateValueOn;
    [prefs setBool:enabled forKey:SPMCPServerEnabled];

    // SPAppController observes NSUserDefaultsDidChangeNotification and will start/stop
    // the server in response. We just update the status label after a short delay so
    // the server has time to start.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self refreshStatus];
    });
}

- (IBAction)toggleReadOnly:(id)sender
{
    BOOL readOnly = _readOnlyCheckbox.state == NSControlStateValueOn;
    [prefs setBool:readOnly forKey:SPMCPReadOnly];
}

- (IBAction)updatePort:(NSTextField *)sender
{
    NSString *digits = [sender.stringValue stringByReplacingOccurrencesOfString:@" " withString:@""];
    // Reject non-numeric input (integerValue would silently accept e.g. "8765abc").
    BOOL allDigits = digits.length > 0 &&
        [digits rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound;
    NSInteger port = digits.integerValue;
    if (!allDigits || port < kMCPMinPort || port > kMCPMaxPort) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(@"Invalid Port", @"MCP pref: invalid port alert");
        alert.informativeText = [NSString stringWithFormat:
            NSLocalizedString(@"Port must be between %ld and %ld.", @"MCP pref: port range"),
            (long)kMCPMinPort, (long)kMCPMaxPort];
        [alert runModal];
        sender.stringValue = [NSString stringWithFormat:@"%ld", (long)[self currentPort]];
        return;
    }

    [prefs setInteger:port forKey:SPMCPServerPort];
    [self refreshEndpoint];

    // Persisting the new port posts NSUserDefaultsDidChangeNotification, which
    // SPAppController observes and uses to restart the server on the new port if
    // it is running. We just refresh the status label after it has had time to
    // rebind.
    if ([prefs boolForKey:SPMCPServerEnabled]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self refreshStatus];
        });
    }
}

- (IBAction)chooseExportPath:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles        = NO;
    panel.canChooseDirectories  = YES;
    panel.canCreateDirectories  = YES;
    panel.prompt                = NSLocalizedString(@"Choose", @"MCP pref: open panel prompt");
    panel.message               = NSLocalizedString(@"Choose the default folder for MCP query exports.",
                                                    @"MCP pref: open panel message");

    NSString *current = [prefs stringForKey:SPMCPExportPath];
    if (current.length) {
        panel.directoryURL = [NSURL fileURLWithPath:current];
    }

    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSString *path = panel.URL.path;
            [self->prefs setObject:path forKey:SPMCPExportPath];
            self->_exportPathField.stringValue = path;
        }
    }];
}

#pragma mark - Private helpers

- (void)refreshStatus
{
    BOOL running = [SPMCPServer.shared isRunning];
    BOOL enabled = [prefs boolForKey:SPMCPServerEnabled];

    if (!enabled) {
        _statusLabel.stringValue = NSLocalizedString(@"MCP server is disabled.", @"MCP pref: status disabled");
        _statusLabel.textColor   = [NSColor secondaryLabelColor];
    } else if (running) {
        NSInteger port = [self currentPort];
        _statusLabel.stringValue = [NSString stringWithFormat:
            NSLocalizedString(@"MCP server is running on http://127.0.0.1:%ld/mcp", @"MCP pref: status running"),
            (long)port];
        _statusLabel.textColor = [NSColor systemGreenColor];
    } else {
        _statusLabel.stringValue = NSLocalizedString(@"MCP server is not running.", @"MCP pref: status stopped");
        _statusLabel.textColor   = [NSColor systemOrangeColor];
    }
}

- (void)refreshEndpoint
{
    _endpointField.stringValue = [self endpointURLString];
}

- (NSString *)endpointURLString
{
    return [NSString stringWithFormat:@"http://127.0.0.1:%ld/mcp", (long)[self currentPort]];
}

- (IBAction)copyEndpoint:(id)sender
{
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:[self endpointURLString] forType:NSPasteboardTypeString];
}

- (NSInteger)currentPort
{
    NSInteger p = [prefs integerForKey:SPMCPServerPort];
    return (p >= kMCPMinPort && p <= kMCPMaxPort) ? p : kMCPDefaultPort;
}

- (NSString *)currentExportPath
{
    NSString *path = [prefs stringForKey:SPMCPExportPath];
    if (path.length) return path;
    return NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory, NSUserDomainMask, YES).firstObject
        ?: NSTemporaryDirectory();
}

// MARK: - Label factory helpers

- (NSTextField *)makeLabel:(NSString *)text x:(CGFloat)x y:(CGFloat)y width:(CGFloat)w
{
    NSTextField *tf = [NSTextField labelWithString:text];
    tf.frame = NSMakeRect(x, y, w, 18);
    tf.alignment = NSTextAlignmentRight;
    return tf;
}

- (NSTextField *)makeSmallLabel:(NSString *)text x:(CGFloat)x y:(CGFloat)y width:(CGFloat)w
{
    NSTextField *tf = [NSTextField wrappingLabelWithString:text];
    tf.frame     = NSMakeRect(x, y, w, 16);
    tf.font      = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    tf.textColor = [NSColor secondaryLabelColor];
    return tf;
}

@end
