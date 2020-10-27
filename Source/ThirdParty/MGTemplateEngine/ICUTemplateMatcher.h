//
//  ICUTemplateMatcher.h
//
//  Created by Matt Gemmell on 19/05/2008.
//  Copyright 2008 Instinctive Code. All rights reserved.

#import "MGTemplateEngine.h"

/*
 This is an example Matcher for MGTemplateEngine, implemented using libicucore on Leopard,
 via the RegexKitLite library: http://regexkit.sourceforge.net/#RegexKitLite

 This project includes everything you need, as long as you're building on Mac OS X 10.5 or later.

 Other matchers can easily be implemented using the MGTemplateEngineMatcher protocol,
 if you prefer to use another regex framework, or use another matching method entirely.
 */

@interface ICUTemplateMatcher : NSObject <MGTemplateEngineMatcher>

@property(atomic,assign) MGTemplateEngine *engine; // weak ref
@property(atomic,retain) NSString *markerStart;
@property(atomic,retain) NSString *markerEnd;
@property(atomic,retain) NSString *exprStart;
@property(atomic,retain) NSString *exprEnd;
@property(atomic,retain) NSString *filterDelimiter;
@property(atomic,retain) NSString *templateString;
@property(atomic,retain) NSString *regex;

+ (ICUTemplateMatcher *)matcherWithTemplateEngine:(MGTemplateEngine *)theEngine;

- (NSArray *)argumentsFromString:(NSString *)argString;

@end
