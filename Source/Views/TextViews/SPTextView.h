//
//  SPTextView.h
//  sequel-pro
//
//  Created by Carsten Blüm.
//  Copyright (c) 2012 Sequel Pro Team. All rights reserved.
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

#define SP_TEXT_SIZE_TRIGGER_FOR_PARTLY_PARSING 10000
#define SP_TEXT_SIZE_MAX_PASTE_LENGTH 15000

@class SPNarrowDownCompletion;
@class SPDatabaseDocument;
@class SPTablesList;
@class SPCustomQuery;
@class SPMySQLConnection;
@class SPCopyTable;
@class NoodleLineNumberView;

typedef struct {
	NSInteger location; // snippet location
	NSInteger length;   // snippet length
	NSInteger task;     // snippet task : -1 not valid, 0 select snippet
} SnippetControlInfo;

typedef struct {
	NSInteger snippet;  // mirrored snippet index
	NSInteger location; // mirrored snippet location
	NSInteger length;   // mirrored snippet length
} MirrorControlInfo;

@interface SPTextView : NSTextView <NSTextStorageDelegate>
{
	IBOutlet SPDatabaseDocument *tableDocumentInstance;
	IBOutlet SPTablesList *tablesListInstance;
	IBOutlet SPCustomQuery *customQueryInstance;

    BOOL autoindentEnabled;
    BOOL autocompleteEnabled;
	BOOL autopairEnabled;
	BOOL autoindentIgnoresEnter;
	BOOL autouppercaseKeywordsEnabled;
	BOOL delBackwardsWasPressed;
	BOOL autohelpEnabled;
	NoodleLineNumberView *lineNumberView;
	
	BOOL textBufferSizeIncreased;

	NSString *showMySQLHelpFor;
	
	IBOutlet NSScrollView *scrollView;
	SPNarrowDownCompletion *completionPopup;

	NSUserDefaults *prefs;

	SPMySQLConnection *mySQLConnection;
	NSInteger mySQLmajorVersion;

	SnippetControlInfo snippetControlArray[20];
	MirrorControlInfo snippetMirroredControlArray[20];
	NSInteger snippetControlCounter;
	NSInteger snippetControlMax;
	NSInteger currentSnippetIndex;
	NSInteger mirroredCounter;
	BOOL snippetWasJustInserted;
	BOOL isProcessingMirroredSnippets;

	BOOL completionIsOpen;
	BOOL completionWasReinvokedAutomatically;
	BOOL completionWasRefreshed;
	NSUInteger completionParseRangeLocation;

	NSColor *queryHiliteColor;
	NSColor *queryEditorBackgroundColor;
	NSColor *commentColor;
	NSColor *quoteColor;
	NSColor *keywordColor;
	NSColor *backtickColor;
	NSColor *numericColor;
	NSColor *variableColor;
	NSColor *otherTextColor;
	NSRange queryRange;
	BOOL shouldHiliteQuery;
	BOOL enableSyntaxHighlighting;

	BOOL syntaxHighlightingApplied;
}

@property (strong) NSColor* queryHiliteColor;
@property (strong) NSColor* queryEditorBackgroundColor;
@property (strong) NSColor* commentColor;
@property (strong) NSColor* quoteColor;
@property (strong) NSColor* keywordColor;
@property (strong) NSColor* backtickColor;
@property (strong) NSColor* numericColor;
@property (strong) NSColor* variableColor;
@property (strong) NSColor* otherTextColor;
@property (assign) NSRange queryRange;
@property (assign) BOOL shouldHiliteQuery;
@property (assign) BOOL enableSyntaxHighlighting;
@property (assign) BOOL syntaxHighlightingApplied;
@property (assign) BOOL completionIsOpen;
@property (assign) BOOL completionWasReinvokedAutomatically;
@property (assign) BOOL completionFuzzyMode;

- (IBAction)showMySQLHelpForCurrentWord:(id)sender;

- (BOOL) isNextCharMarkedBy:(id)attribute withValue:(id)aValue;
- (BOOL) areAdjacentCharsLinked;
- (BOOL) isCaretAdjacentToAlphanumCharWithInsertionOf:(unichar)aChar;
- (BOOL) isCaretAtIndentPositionIgnoreLineStart:(BOOL)ignoreLineStart;
- (BOOL) wrapSelectionWithPrefix:(NSString *)prefix suffix:(NSString *)suffix;
- (BOOL) shiftSelectionRight;
- (BOOL) shiftSelectionLeft;
- (void) setAutoindent:(BOOL)enableAutoindent;
- (void) setAutoComplete:(BOOL)enableAutocomplete;
- (BOOL) autoindent;
- (void) setAutoindentIgnoresEnter:(BOOL)enableAutoindentIgnoresEnter;
- (BOOL) autoindentIgnoresEnter;
- (void) setAutopair:(BOOL)enableAutopair;
- (BOOL) autopair;
- (void) setAutouppercaseKeywords:(BOOL)enableAutouppercaseKeywords;
- (BOOL) autouppercaseKeywords;
- (void) setAutohelp:(BOOL)enableAutohelp;
- (BOOL) autohelp;
- (void) setTabStops;
- (void) selectLineNumber:(NSUInteger)lineNumber ignoreLeadingNewLines:(BOOL)ignLeadingNewLines;
- (NSUInteger) getLineNumberForCharacterIndex:(NSUInteger)anIndex;
- (void) autoHelp;
- (NSBezierPath*)roundedBezierPathAroundRange:(NSRange)aRange;
- (void) setConnection:(SPMySQLConnection *)theConnection withVersion:(NSInteger)majorVersion;
- (void) doCompletionByUsingSpellChecker:(BOOL)isDictMode fuzzyMode:(BOOL)fuzzySearch autoCompleteMode:(BOOL)autoCompleteMode;
- (void) doAutoCompletion;
- (void) refreshCompletion;
- (NSArray *)suggestionsForSQLCompletionWith:(NSString *)currentWord dictMode:(BOOL)isDictMode browseMode:(BOOL)dbBrowseMode withTableName:(NSString*)aTableName withDbName:(NSString*)aDbName;
- (IBAction) selectCurrentQuery:(id)sender;
- (void) processMirroredSnippets;
- (void)doSyntaxHighlightingWithForceWrapper:(NSString*)keyPath;

- (BOOL)checkForCaretInsideSnippet;
- (void)insertAsSnippet:(NSString*)theSnippet atRange:(NSRange)targetRange;

- (void)showCompletionListFor:(NSString*)kind atRange:(NSRange)aRange fuzzySearch:(BOOL)fuzzySearchMode;

- (NSUInteger)characterIndexOfPoint:(NSPoint)aPoint;
- (void)insertFileContentOfFile:(NSString *)aPath;

- (BOOL)isSnippetMode;

- (void)doSyntaxHighlightingWithForce:(BOOL)forced;
- (void)appendString:(NSString *)string;
- (void)insertString:(NSString *)string atIndex:(NSUInteger)loc;
- (void)insertString:(NSString *)string intoRange:(NSRange)range;

@end
