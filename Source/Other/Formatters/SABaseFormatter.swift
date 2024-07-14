//
//  Created by Luis Aguiniga on 2024.07.07
//  Copyright © 2024 Sequel-Ace. All rights reserved.
//

import Foundation


@objc open class SABaseFormatter: Formatter {

    /// Max length to use for Field Editor
    @objc var maxLengthOverride: UInt { 0 }

    // Short label to append to field description in Popup Field Editor
    @objc var label: String { "" }

}

/// Helper class for MenuItem to keep track of both the formatter and contet Table Column
@objc final class FormatterWithReference: NSObject {
    @objc var formatter: SABaseFormatter
    @objc var reference: AnyObject?

    @objc static func newWith(formatter: SABaseFormatter) -> FormatterWithReference {
        FormatterWithReference(formatter: formatter)
    }

    init(formatter: SABaseFormatter, reference: AnyObject? = nil) {
        self.formatter = formatter
        self.reference = reference
    }
}
