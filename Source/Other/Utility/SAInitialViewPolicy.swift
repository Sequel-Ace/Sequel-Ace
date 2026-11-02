//
//  SAInitialViewPolicy.swift
//  Sequel Ace
//
//  Which tab a connection opens on while no table is selected, and when the
//  first table or view picked afterwards switches to the user's usual tab.
//  Pure decisions, shared with the unit tests.
//

import Foundation

@objc final class SAInitialViewPolicy: NSObject {

    // Raw values of SPTableTypeTable and SPTableTypeView in SPConstants.h (this file has no ObjC dependency);
    // keep in sync with SPTableType.
    private static let tableType = 0
    private static let viewType = 1

    /// The tab the user's preferences ask for: the Default View preference when set, else the last-used tab.
    @objc static func preferredMode(forPreferencesValue value: Int) -> SAViewMode {
        SAViewMode.fromPreferences(value)
    }

    /// Where a new connection opens: Query while no table is selected (the only tab that works then),
    /// the preferred tab otherwise.
    @objc static func initialMode(preferred: SAViewMode, hasTable: Bool) -> SAViewMode {
        hasTable ? preferred : .query
    }

    /// Whether picking an item should move from the opening Query tab to the preferred tab: only for a
    /// table or a view, only while the jump is pending and the Query tab is still showing.
    @objc static func shouldJump(pending: Bool, selectedType: Int, currentIsQuery: Bool) -> Bool {
        pending && currentIsQuery && (selectedType == tableType || selectedType == viewType)
    }
}
