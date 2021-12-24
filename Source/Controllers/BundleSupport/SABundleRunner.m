//
//  SABundleRunner.m
//  Sequel Ace
//
//  Created by Christopher Jensen-Reimann on 11/4/21.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
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

#import "SABundleRunner.h"

@implementation SABundleRunner

+ (NSString*) computeActionFor:(NSError **)error {
    if (error == nil) {
        return @"";
    }
    
    NSError *old = *error;
    *error = nil;
    SPBundleRedirectAction action = [*error code];
    switch (action) {
        case SPBundleRedirectActionNone:
            return SPBundleOutputActionNone;
            
        case SPBundleRedirectActionReplaceSection:
            return SPBundleOutputActionReplaceSelection;
            
        case SPBundleRedirectActionReplaceContent:
            return SPBundleOutputActionReplaceContent;
            
        case SPBundleRedirectActionInsertAsText:
            return SPBundleOutputActionInsertAsText;
            
        case SPBundleRedirectActionInsertAsSnippet:
            return SPBundleOutputActionInsertAsSnippet;
            
        case SPBundleRedirectActionShowAsHTML:
            return SPBundleOutputActionShowAsHTML;
            
        case SPBundleRedirectActionShowAsTextTooltip:
            return SPBundleOutputActionShowAsTextTooltip;
            
        case SPBundleRedirectActionShowAsHTMLTooltip:
            return SPBundleOutputActionShowAsHTMLTooltip;

        default:
            *error = old;
            return @"";
    }
}

@end
