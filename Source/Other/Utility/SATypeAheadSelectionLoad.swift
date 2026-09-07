import Foundation

/// Remembers the load started by a type-ahead selection, including a selection
/// committed by the settle timer before the next keyboard command arrives.
final class SATypeAheadSelectionLoad<Document: AnyObject> {
    private weak var document: Document?

    func resolve(committingSelection: () -> Document?, isWorking: (Document) -> Bool) -> Document? {
        if let startedDocument = committingSelection() {
            document = startedDocument
        }

        guard let document, isWorking(document) else {
            self.document = nil
            return nil
        }
        return document
    }

    func didFinish(_ finishedDocument: Document) {
        if document === finishedDocument {
            document = nil
        }
    }

    func cancel() {
        document = nil
    }
}
