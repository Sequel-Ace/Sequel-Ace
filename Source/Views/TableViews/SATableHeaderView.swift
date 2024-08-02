//
//  Created by Luis Aguiniga on 2024.07.05.
//  Copyright © 2024 Sequel-Ace. All rights reserved.
//

import Cocoa


@objc protocol SATableHeaderViewDelegate: AnyObject {
    func validate(menu: NSMenu, forTableColumn col: NSTableColumn) -> NSMenu?
}

/// Takes the table header's Menu (same for all columns) and allows
/// delegate to contextualize it for the clicked column.
@objc class SATableHeaderView: NSTableHeaderView {
    @IBOutlet weak var delegate: SATableHeaderViewDelegate?
    
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = self.menu else { return nil }
        guard let delegate = self.delegate  else { return menu }
        
        let idx = self.column(at: self.convert(event.locationInWindow, from: nil))
        guard idx >= 0, let col = self.tableView?.tableColumns[idx] else { return menu }
        
        return delegate.validate(menu: menu, forTableColumn: col)
    }
}
