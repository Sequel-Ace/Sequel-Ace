import XCTest

final class SATypeAheadSelectionLoadTests: XCTestCase {
    private final class SADocument {
        var isWorking = true
    }

    func testCommandAfterSettleTimerWaitsForTheSelectedTableToLoad() {
        let load = SATypeAheadSelectionLoad<SADocument>()
        let document = SADocument()

        // The timer commits the match and ignores its return value. The next
        // command has no pending match, but must still wait for that load.
        _ = load.resolve(committingSelection: { document }, isWorking: { $0.isWorking })
        XCTAssertTrue(load.resolve(committingSelection: { nil }, isWorking: { $0.isWorking }) === document)
    }

    func testSynchronousCompletionDoesNotStrandTheNextCommand() {
        let load = SATypeAheadSelectionLoad<SADocument>()
        let document = SADocument()

        XCTAssertNil(load.resolve(committingSelection: {
            document.isWorking = false
            return document
        }, isWorking: { $0.isWorking }))
        XCTAssertNil(load.resolve(committingSelection: { nil }, isWorking: { $0.isWorking }))
    }

    func testCompletedSelectionDoesNotWaitForALaterUnrelatedTask() {
        let load = SATypeAheadSelectionLoad<SADocument>()
        let document = SADocument()
        _ = load.resolve(committingSelection: { document }, isWorking: { $0.isWorking })

        load.didFinish(document)

        // The same document is busy again, but its type-ahead load has ended.
        XCTAssertNil(load.resolve(committingSelection: { nil }, isWorking: { $0.isWorking }))
    }

    func testAnotherDocumentsCompletionDoesNotReleaseTheSelectionLoad() {
        let load = SATypeAheadSelectionLoad<SADocument>()
        let document = SADocument()
        _ = load.resolve(committingSelection: { document }, isWorking: { $0.isWorking })

        load.didFinish(SADocument())

        XCTAssertTrue(load.resolve(committingSelection: { nil }, isWorking: { $0.isWorking }) === document)
    }

    func testCancellationForgetsTheSelectionLoad() {
        let load = SATypeAheadSelectionLoad<SADocument>()
        let document = SADocument()
        _ = load.resolve(committingSelection: { document }, isWorking: { $0.isWorking })

        load.cancel()

        XCTAssertNil(load.resolve(committingSelection: { nil }, isWorking: { $0.isWorking }))
    }

    func testSelectionLoadDoesNotKeepAClosedDocumentAlive() {
        let load = SATypeAheadSelectionLoad<SADocument>()
        var document: SADocument? = SADocument()
        weak var observedDocument = document
        _ = load.resolve(committingSelection: { document }, isWorking: { $0.isWorking })

        document = nil

        XCTAssertNil(observedDocument)
        XCTAssertNil(load.resolve(committingSelection: { nil }, isWorking: { $0.isWorking }))
    }
}
