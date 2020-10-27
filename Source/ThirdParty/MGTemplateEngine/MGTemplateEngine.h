//
//  MGTemplateEngine.h
//
//  Created by Matt Gemmell on 11/05/2008.
//  Copyright 2008 Instinctive Code. All rights reserved.
//

// Keys in blockInfo dictionaries passed to delegate methods.
#define	BLOCK_NAME_KEY					@"name"				// NSString containing block name (first word of marker)
#define BLOCK_END_NAMES_KEY				@"endNames"			// NSArray containing names of possible ending-markers for block
#define BLOCK_ARGUMENTS_KEY				@"args"				// NSArray of further arguments in block start marker
#define BLOCK_START_MARKER_RANGE_KEY	@"startMarkerRange"	// NSRange (as NSValue) of block's starting marker
#define BLOCK_VARIABLES_KEY				@"vars"				// NSDictionary of variables

#define TEMPLATE_ENGINE_ERROR_DOMAIN	@"MGTemplateEngineErrorDomain"

@class MGTemplateEngine;
@protocol MGTemplateEngineDelegate <NSObject>
@optional
- (void)templateEngine:(MGTemplateEngine *)engine blockStarted:(NSDictionary *)blockInfo;
- (void)templateEngine:(MGTemplateEngine *)engine blockEnded:(NSDictionary *)blockInfo;
- (void)templateEngineFinishedProcessingTemplate:(MGTemplateEngine *)engine;
- (void)templateEngine:(MGTemplateEngine *)engine encounteredError:(NSError *)error isContinuing:(BOOL)continuing;
@end

// Keys in marker dictionaries returned from Matcher methods.
#define MARKER_NAME_KEY					@"name"				// NSString containing marker name (first word of marker)
#define MARKER_TYPE_KEY					@"type"				// NSString, either MARKER_TYPE_EXPRESSION or MARKER_TYPE_MARKER
#define MARKER_TYPE_MARKER				@"marker"
#define MARKER_TYPE_EXPRESSION			@"expression"
#define MARKER_ARGUMENTS_KEY			@"args"				// NSArray of further arguments in marker, if any
#define MARKER_FILTER_KEY				@"filter"			// NSString containing name of filter attached to marker, if any
#define MARKER_FILTER_ARGUMENTS_KEY		@"filterArgs"		// NSArray of filter arguments, if any
#define MARKER_RANGE_KEY				@"range"			// NSRange (as NSValue) of marker's range

@protocol MGTemplateEngineMatcher <NSObject>
@required
- (id)initWithTemplateEngine:(MGTemplateEngine *)engine;
- (void)engineSettingsChanged; // always called at least once before beginning to process a template.
- (NSDictionary *)firstMarkerWithinRange:(NSRange)range;
@end

#import "MGTemplateMarker.h"
#import "MGTemplateFilter.h"

@interface MGTemplateEngine : NSObject

@property(atomic,retain) NSString *markerStartDelimiter;
@property(atomic,retain) NSString *markerEndDelimiter;
@property(atomic,retain) NSString *expressionStartDelimiter;
@property(atomic,retain) NSString *expressionEndDelimiter;
@property(atomic,retain) NSString *filterDelimiter;
@property(atomic,retain) NSString *literalStartMarker;
@property(atomic,retain) NSString *literalEndMarker;
@property(atomic,readonly) NSRange remainingRange;
@property(atomic,weak) id <MGTemplateEngineDelegate> delegate;	// weak ref
@property(atomic,retain) id <MGTemplateEngineMatcher> matcher;
@property(atomic,readonly) NSString *templateContents;

// Creation.
+ (NSString *)engineVersion;
+ (MGTemplateEngine *)templateEngine;

// Managing persistent values.
- (void)setObject:(id)anObject forKey:(id)aKey;
- (void)addEntriesFromDictionary:(NSDictionary *)dict;
- (id)objectForKey:(id)aKey;

// Configuration and extensibility.
- (void)loadMarker:(id<MGTemplateMarker>)marker;
- (void)loadFilter:(id<MGTemplateFilter>)filter;

// Utilities.
- (NSObject *)resolveVariable:(NSString *)var;
- (NSDictionary *)templateVariables;

// Processing templates.
- (NSString *)processTemplate:(NSString *)templateString withVariables:(NSDictionary *)variables;
- (NSString *)processTemplateInFileAtPath:(NSString *)templatePath withVariables:(NSDictionary *)variables;

@end
