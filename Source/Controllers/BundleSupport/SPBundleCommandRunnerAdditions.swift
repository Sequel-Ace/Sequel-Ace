//
//  SPBundleCommandRunnerAdditions.swift
//  Sequel Ace
//
//  Created by Christopher Jensen-Reimann on 10/31/21.
//  Copyright © 2021 Christopher Jensen-Reimann.
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

import Foundation
import os.log

public extension SPBundleCommandRunner {
    @objc static func computeAction(error: NSErrorPointer) -> String? {
        guard let error = error,
              let underlyingError = error.pointee,
              let errCode = SPBundleRedirectAction(rawValue: underlyingError.code) else {
            return ""
        }
        
        error.pointee = nil
        
        switch errCode {
        case .none:
            return SPBundleOutputActionNone
            
        case .replaceSection:
            return SPBundleOutputActionReplaceSelection
            
        case .replaceContent:
            return SPBundleOutputActionReplaceContent
            
        case .insertAsText:
            return SPBundleOutputActionInsertAsText
            
        case .insertAsSnippet:
            return SPBundleOutputActionInsertAsSnippet
            
        case .showAsHTML:
            return SPBundleOutputActionShowAsHTML
            
        case .showAsTextTooltip:
            return SPBundleOutputActionShowAsTextTooltip
            
        case .showAsHTMLTooltip:
            return SPBundleOutputActionShowAsHTMLTooltip
            
        @unknown default:
            os_log("Unknown bundle redirect action: %@ from error: %@", log: OSLog.default, type: .error, underlyingError.code, underlyingError)
            error.pointee = underlyingError
            return ""
        }
    }
}
