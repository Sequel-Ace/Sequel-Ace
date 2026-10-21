import AppKit
import Combine
import SwiftUI
import XCTest

/// The Settings window's defaults store: each type round-trips through the bindings the views derive from it
/// (`$store[bool: key]` and friends), a never-set key reads its registered default, every write goes through the
/// controller so a `values.<key>` observer fires exactly once, and the store republishes only for its own keys.
/// Runs against a scratch suite and its own controller — never the app's defaults.
@MainActor
final class SAClaudeSettingsStoreTests: XCTestCase {

    private var suiteName = ""
    private var suite: UserDefaults!
    private var controller: NSUserDefaultsController!
    private var store: SAClaudeSettingsStore!
    private let observer = Observer()

    private static let keys = ["SAStoreTests_bool", "SAStoreTests_int", "SAStoreTests_double", "SAStoreTests_string",
                               "SAStoreTests_whole", "SAStoreTests_tenths", "SAStoreTests_registeredBool",
                               "SAStoreTests_registeredInt", "SAStoreTests_registeredString"]

    /// Counts KVO notifications per key path.
    final class Observer: NSObject {
        var counts: [String: Int] = [:]
        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
                                   context: UnsafeMutableRawPointer?) {
            counts[keyPath ?? "?", default: 0] += 1
        }
    }

    override func setUp() async throws {
        suiteName = "SAClaudeSettingsStoreTests.\(UUID().uuidString)"
        suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        suite.register(defaults: ["SAStoreTests_registeredBool": true, "SAStoreTests_registeredInt": 15,
                                  "SAStoreTests_registeredString": "NULL"])
        controller = NSUserDefaultsController(defaults: suite, initialValues: nil)
        store = SAClaudeSettingsStore(controller: controller, keys: Self.keys)
        for key in Self.keys { controller.addObserver(observer, forKeyPath: "values.\(key)", options: [.new], context: nil) }
    }

    override func tearDown() async throws {
        for key in Self.keys { controller.removeObserver(observer, forKeyPath: "values.\(key)") }
        store = nil
        suite.removePersistentDomain(forName: suiteName)
    }

    private func firedOnce(_ key: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(observer.counts, ["values.\(key)": 1], "one values.\(key) notification, no other", file: file, line: line)
        observer.counts = [:]
    }

    private var bindings: ObservedObject<SAClaudeSettingsStore>.Wrapper { ObservedObject(wrappedValue: store).projectedValue }

    // MARK: - Round trips

    func testEachTypeRoundTripsThroughItsBinding() {
        XCTAssertTrue(store.defaults === suite, "the store reads the controller's own defaults")

        let bool = bindings[bool: "SAStoreTests_bool"]
        XCTAssertFalse(bool.wrappedValue)
        bool.wrappedValue = true
        firedOnce("SAStoreTests_bool")
        XCTAssertTrue(bool.wrappedValue)
        XCTAssertEqual(suite.object(forKey: "SAStoreTests_bool") as? Bool, true)
        bool.wrappedValue = false
        firedOnce("SAStoreTests_bool")
        XCTAssertFalse(store[bool: "SAStoreTests_bool"])

        let int = bindings[int: "SAStoreTests_int"]
        int.wrappedValue = 42
        firedOnce("SAStoreTests_int")
        XCTAssertEqual(int.wrappedValue, 42)
        XCTAssertEqual(suite.integer(forKey: "SAStoreTests_int"), 42)

        let double = bindings[double: "SAStoreTests_double"]
        double.wrappedValue = 1.6
        firedOnce("SAStoreTests_double")
        XCTAssertEqual(double.wrappedValue, 1.6)
        XCTAssertEqual(suite.double(forKey: "SAStoreTests_double"), 1.6)

        let string = bindings[string: "SAStoreTests_string"]
        XCTAssertEqual(string.wrappedValue, "", "a missing string reads as empty")
        string.wrappedValue = "(null)"
        firedOnce("SAStoreTests_string")
        XCTAssertEqual(string.wrappedValue, "(null)")
        XCTAssertEqual(suite.string(forKey: "SAStoreTests_string"), "(null)")
    }

    func testNumberBindingStoresIntegersForWholeStepsAndDoublesForTenths() {
        let whole = bindings[number: "SAStoreTests_whole", step: 1]
        whole.wrappedValue = 20
        firedOnce("SAStoreTests_whole")
        let wholeStored = suite.object(forKey: "SAStoreTests_whole") as? NSNumber
        XCTAssertEqual(wholeStored?.intValue, 20)
        XCTAssertEqual(wholeStored.map { String(cString: $0.objCType) }, String(cString: NSNumber(value: 20).objCType))
        XCTAssertEqual(whole.wrappedValue, 20)

        let tenths = bindings[number: "SAStoreTests_tenths", step: 0.1]
        tenths.wrappedValue = 1.6
        firedOnce("SAStoreTests_tenths")
        let tenthsStored = suite.object(forKey: "SAStoreTests_tenths") as? NSNumber
        XCTAssertEqual(tenthsStored?.doubleValue, 1.6)
        XCTAssertEqual(tenthsStored.map { String(cString: $0.objCType) }, "d")
        XCTAssertEqual(tenths.wrappedValue, 1.6)
    }

    func testNeverSetKeysReadTheirRegisteredDefaults() {
        XCTAssertNil(suite.persistentDomain(forName: suiteName)?["SAStoreTests_registeredBool"], "never set")
        XCTAssertTrue(bindings[bool: "SAStoreTests_registeredBool"].wrappedValue)
        XCTAssertEqual(bindings[int: "SAStoreTests_registeredInt"].wrappedValue, 15)
        XCTAssertEqual(bindings[number: "SAStoreTests_registeredInt", step: 1].wrappedValue, 15)
        XCTAssertEqual(bindings[string: "SAStoreTests_registeredString"].wrappedValue, "NULL")
        XCTAssertTrue(observer.counts.isEmpty, "reading writes nothing")

        // Writing over a registered default, then removing the value, reads the default again.
        bindings[bool: "SAStoreTests_registeredBool"].wrappedValue = false
        firedOnce("SAStoreTests_registeredBool")
        XCTAssertFalse(store[bool: "SAStoreTests_registeredBool"])
        suite.removeObject(forKey: "SAStoreTests_registeredBool")
        XCTAssertTrue(store[bool: "SAStoreTests_registeredBool"])
    }

    func testBindingsDerivedFromKeyPathsAreStable() {
        // Two derivations of the same key compare equal as key paths, so a child view taking one sees no change.
        XCTAssertEqual(\SAClaudeSettingsStore.[bool: "SAStoreTests_bool"], \SAClaudeSettingsStore.[bool: "SAStoreTests_bool"])
        XCTAssertNotEqual(\SAClaudeSettingsStore.[bool: "SAStoreTests_bool"], \SAClaudeSettingsStore.[bool: "SAStoreTests_int"])
        XCTAssertEqual(\SAClaudeSettingsStore.[number: "SAStoreTests_whole", step: 1],
                       \SAClaudeSettingsStore.[number: "SAStoreTests_whole", step: 1])
    }

    // MARK: - Publishing

    func testPublishesOnlyForItsOwnKeys() {
        var published = 0
        let subscription = store.objectWillChange.sink { published += 1 }
        defer { subscription.cancel() }

        suite.set(true, forKey: "SAStoreTests_unwatched")
        XCTAssertEqual(published, 0, "a key no row shows doesn't re-render the window")

        suite.set(true, forKey: "SAStoreTests_bool")    // written elsewhere, not through the store
        XCTAssertEqual(published, 1)
        observer.counts = [:]
        store[int: "SAStoreTests_int"] = 7
        XCTAssertEqual(published, 2, "one publish per write")
        firedOnce("SAStoreTests_int")
        observer.counts = [:]
        suite.removeObject(forKey: "SAStoreTests_unwatched")
    }

    func testStandardStoreUsesTheSharedControllerAndCatalogKeys() {
        let standard = SAClaudeSettingsStore()
        XCTAssertTrue(standard.controller === NSUserDefaultsController.shared)
        XCTAssertTrue(standard.defaults === NSUserDefaultsController.shared.defaults)
        XCTAssertEqual(standard.keys, Set(SAClaudeSettingsCatalog.allKeys))
        // The store observes each key by KVO, where a "." would make it a key path.
        XCTAssertTrue(standard.keys.allSatisfy { !$0.contains(".") }, "catalog keys are KVO-safe")
    }

    func testIsEnabledFollowsTheParentSwitch() throws {
        let catalogStore = SAClaudeSettingsStore(controller: controller)
        let row = try XCTUnwrap(SAClaudeSettingsCatalog.row("logInterface"))
        catalogStore[bool: "ConsoleEnableLogging"] = false
        XCTAssertFalse(catalogStore.isEnabled(row))
        catalogStore[bool: "ConsoleEnableLogging"] = true
        XCTAssertTrue(catalogStore.isEnabled(row))
        // "Ask twice before deleting rows" no longer hangs off "Confirm before running changes".
        let askTwice = try XCTUnwrap(SAClaudeSettingsCatalog.row("askTwiceDelete"))
        catalogStore[bool: "ShowWarningBeforeExecuteQuery"] = false
        XCTAssertTrue(catalogStore.isEnabled(askTwice))
    }
}
