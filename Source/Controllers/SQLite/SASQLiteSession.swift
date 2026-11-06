import Foundation

/// Retain sandbox access for as long as SQLite might open adjacent journal files.
final class SASQLiteFileAccess: @unchecked Sendable {
    private let activeURLs: [URL]

    init(_ urls: [URL]) {
        activeURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
    }

    deinit {
        for url in activeURLs { url.stopAccessingSecurityScopedResource() }
    }
}

final class SASQLiteSession: @unchecked Sendable {
    let url: URL
    let readOnly: Bool
    private let create: Bool
    private let access: SASQLiteFileAccess
    private let queue = DispatchQueue(label: "com.sequel-ace.sqlite-session", qos: .userInitiated)
    private var connection: SASQLiteConnection?

    init(url: URL, readOnly: Bool, create: Bool, access: SASQLiteFileAccess) {
        self.url = url
        self.readOnly = readOnly
        self.create = create
        self.access = access
    }

    deinit {
        // SQLite may checkpoint its WAL during close.
        connection = nil
    }

    func perform<T: Sendable>(_ cancellation: SASQLiteCancellation,
                             _ operation: @escaping @Sendable (SASQLiteConnection) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result {
                    try cancellation.check()
                    let database = try self.open()
                    return try database.withCancellation(cancellation) { try operation(database) }
                })
            }
        }
    }

    private func open() throws -> SASQLiteConnection {
        if let connection { return connection }
        let connection = try SASQLiteConnection(url: url, readOnly: readOnly, create: create)
        self.connection = connection
        return connection
    }
}
