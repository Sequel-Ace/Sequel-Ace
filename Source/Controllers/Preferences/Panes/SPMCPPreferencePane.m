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
@property (nonatomic, strong) NSTextField   *portLabel;
@property (nonatomic, strong) NSTextField   *portField;
@property (nonatomic, strong) NSTextField   *statusLabel;
@property (nonatomic, strong) NSTextField   *exportPathLabel;
@property (nonatomic, strong) NSTextField   *exportPathField;
@property (nonatomic, strong) NSButton      *exportPathButton;
@property (nonatomic, strong) NSTextField   *configSampleLabel;
@property (nonatomic, strong) NSTextView    *configSampleView;

@end

@implementation SPMCPPreferencePane

#pragma mark - View lifecycle

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 564, 420)];
    [root setAutoresizingMask:NSViewWidthSizable];

    CGFloat x        = 20.0;
    CGFloat maxWidth = 524.0;
    CGFloat y        = 380.0;   // Top-down layout; we decrement y as we add rows.

    // ── Section: Enable / Status ──────────────────────────────────────────────

    _enableCheckbox = [NSButton checkboxWithTitle:NSLocalizedString(@"Enable MCP Server (localhost only)",
                                                                    @"MCP pref: enable checkbox")
                                           target:self
                                           action:@selector(toggleMCPServer:)];
    _enableCheckbox.frame = NSMakeRect(x, y, maxWidth, 20);
    _enableCheckbox.state = [prefs boolForKey:SPMCPServerEnabled]
        ? NSControlStateValueOn : NSControlStateValueOff;
    [root addSubview:_enableCheckbox];
    y -= 28;

    _statusLabel = [self makeSmallLabel:@"" x:x y:y width:maxWidth];
    [root addSubview:_statusLabel];
    y -= 30;

    // ── Section: Port ──────────────────────────────────────────────────────────

    NSTextField *portSectionLabel = [self makeBoldLabel:NSLocalizedString(@"Server Port", @"MCP pref: port section")
                                                      x:x y:y width:maxWidth];
    [root addSubview:portSectionLabel];
    y -= 22;

    _portLabel = [self makeLabel:NSLocalizedString(@"Port:", @"MCP pref: port label") x:x y:y width:50];
    [root addSubview:_portLabel];

    _portField = [[NSTextField alloc] initWithFrame:NSMakeRect(x + 56, y - 2, 80, 22)];
    _portField.delegate       = (id<NSTextFieldDelegate>)self;
    _portField.target         = self;
    _portField.action         = @selector(updatePort:);
    _portField.integerValue   = [self currentPort];
    _portField.placeholderString = @"8765";
    [root addSubview:_portField];

    NSTextField *portHint = [self makeSmallLabel:NSLocalizedString(
        @"Default: 8765. Any unprivileged port (1024–65535) may be used.",
        @"MCP pref: port hint")
                                               x:x + 144 y:y + 2 width:maxWidth - 144];
    [root addSubview:portHint];
    y -= 36;

    // ── Section: Export Path ──────────────────────────────────────────────────

    NSTextField *exportSectionLabel = [self makeBoldLabel:NSLocalizedString(@"Default Export Folder",
                                                                            @"MCP pref: export section")
                                                        x:x y:y width:maxWidth];
    [root addSubview:exportSectionLabel];
    y -= 22;

    _exportPathLabel = [self makeLabel:NSLocalizedString(@"Folder:", @"MCP pref: folder label") x:x y:y width:54];
    [root addSubview:_exportPathLabel];

    _exportPathField = [[NSTextField alloc] initWithFrame:NSMakeRect(x + 60, y - 1, 350, 22)];
    _exportPathField.editable    = NO;
    _exportPathField.bezeled     = YES;
    _exportPathField.bezelStyle  = NSTextFieldSquareBezel;
    _exportPathField.stringValue = [self currentExportPath];
    [root addSubview:_exportPathField];

    _exportPathButton = [NSButton buttonWithTitle:NSLocalizedString(@"Choose…", @"MCP pref: choose button")
                                           target:self
                                           action:@selector(chooseExportPath:)];
    _exportPathButton.frame = NSMakeRect(x + 416, y - 1, 108, 22);
    [root addSubview:_exportPathButton];
    y -= 36;

    // ── Section: Claude config sample ─────────────────────────────────────────

    NSTextField *configSectionLabel = [self makeBoldLabel:NSLocalizedString(@"Claude Desktop / Claude Code Config",
                                                                            @"MCP pref: config section")
                                                        x:x y:y width:maxWidth];
    [root addSubview:configSectionLabel];
    y -= 22;

    NSTextField *configHint = [self makeSmallLabel:NSLocalizedString(
        @"Add the following to your claude_desktop_config.json or .claude/mcp.json:",
        @"MCP pref: config hint")
                                                 x:x y:y width:maxWidth];
    [root addSubview:configHint];
    y -= 20;

    // Scrollable text area for config sample.
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(x, y - 100, maxWidth, 100)];
    scrollView.hasVerticalScroller   = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.autohidesScrollers    = YES;
    scrollView.borderType            = NSBezelBorder;

    _configSampleView = [[NSTextView alloc] initWithFrame:scrollView.contentView.bounds];
    _configSampleView.editable      = NO;
    _configSampleView.font          = [NSFont userFixedPitchFontOfSize:11.0];
    _configSampleView.string        = [self configSampleText];
    _configSampleView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scrollView.documentView = _configSampleView;

    [root addSubview:scrollView];
    y -= 110;

    NSTextField *mcpJsonHint = [self makeSmallLabel:NSLocalizedString(
        @"For Claude Code, run: claude mcp add sequel-ace http://127.0.0.1:8765/sse",
        @"MCP pref: claude code hint")
                                                  x:x y:y width:maxWidth];
    [root addSubview:mcpJsonHint];

    self.view = root;
}

#pragma mark - SPPreferencePaneProtocol

- (NSView *)preferencePaneView
{
    return self.view;
}

- (NSImage *)preferencePaneIcon
{
    return [NSImage imageWithSystemSymbolName:@"square.and.arrow.up.on.square"
                        accessibilityDescription:nil];
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
    [self refreshConfigSample];
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

- (IBAction)updatePort:(NSTextField *)sender
{
    NSInteger port = sender.integerValue;
    if (port < kMCPMinPort || port > kMCPMaxPort) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(@"Invalid Port", @"MCP pref: invalid port alert");
        alert.informativeText = [NSString stringWithFormat:
            NSLocalizedString(@"Port must be between %ld and %ld.", @"MCP pref: port range"),
            (long)kMCPMinPort, (long)kMCPMaxPort];
        [alert runModal];
        sender.integerValue = [self currentPort];
        return;
    }

    [prefs setInteger:port forKey:SPMCPServerPort];
    [self refreshConfigSample];

    // Restart server with new port if it is running.
    if ([prefs boolForKey:SPMCPServerEnabled]) {
        [prefs setBool:NO  forKey:SPMCPServerEnabled];
        [prefs setBool:YES forKey:SPMCPServerEnabled];
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
            [self->prefs setString:path forKey:SPMCPExportPath];
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
            NSLocalizedString(@"MCP server is running on http://127.0.0.1:%ld/sse", @"MCP pref: status running"),
            (long)port];
        _statusLabel.textColor = [NSColor systemGreenColor];
    } else {
        _statusLabel.stringValue = NSLocalizedString(@"MCP server is not running.", @"MCP pref: status stopped");
        _statusLabel.textColor   = [NSColor systemOrangeColor];
    }
}

- (void)refreshConfigSample
{
    _configSampleView.string = [self configSampleText];
}

- (NSString *)configSampleText
{
    NSInteger port = [self currentPort];
    return [NSString stringWithFormat:
        @"{\n"
        @"  \"mcpServers\": {\n"
        @"    \"sequel-ace\": {\n"
        @"      \"url\": \"http://127.0.0.1:%ld/sse\"\n"
        @"    }\n"
        @"  }\n"
        @"}",
        (long)port];
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

- (NSTextField *)makeBoldLabel:(NSString *)text x:(CGFloat)x y:(CGFloat)y width:(CGFloat)w
{
    NSTextField *tf = [NSTextField labelWithString:text];
    tf.frame = NSMakeRect(x, y, w, 18);
    tf.font  = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
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
