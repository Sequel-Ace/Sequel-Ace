//
//  Created by Codex on 2026-02-25.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

@objcMembers final class SABundleVersionUpdater: NSObject {
    /// Returns true when a bundled default should replace an installed default bundle.
    /// Missing versions are treated as 0 to allow forward migrations.
    class func shouldUpdateDefaultBundle(installedVersion: NSNumber?, bundledVersion: NSNumber?) -> Bool {
        let installed = installedVersion?.intValue ?? 0
        let bundled = bundledVersion?.intValue ?? 0
        return bundled > installed
    }
}
