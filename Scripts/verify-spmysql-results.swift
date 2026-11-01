import Foundation

// Input is `xcresulttool get test-results tests` JSON (Xcode 16+).
struct SATestNode: Decodable {
    let name: String?
    let nodeType: String
    let result: String?
    let children: [SATestNode]?
}

struct SATestResults: Decodable {
    let testNodes: [SATestNode]
}

func requiredSuites(in directory: URL) throws -> [String] {
    var isDirectory: ObjCBool = false
    var scanError: Error?
    guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue,
          let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil,
              errorHandler: { _, error in scanError = error; return false }) else {
        throw NSError(domain: "SACoverage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read framework sources: \(directory.path)"])
    }
    // These existing live suites are unconditional. Discover additional integration
    // classes from declarations, so moving/renaming #2775's source cannot omit it.
    var suites: Set<String> = ["SAEscapingBoundaryIntegrationTests", "SADatabaseAssertionIntegrationTests"]
    let declaration = try NSRegularExpression(pattern: #"\bclass\s+([A-Za-z_]\w*IntegrationTests)\s*:\s*XCTestCase\b"#)
    for case let file as URL in files where file.pathExtension == "swift" {
        let source = try String(contentsOf: file, encoding: .utf8)
        for match in declaration.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            if let range = Range(match.range(at: 1), in: source) { suites.insert(String(source[range])) }
        }
    }
    if let scanError { throw scanError }
    return suites.sorted()
}

func coverageErrors(in nodes: [SATestNode], requiredSuites: [String]) -> [String] {
    // Sphinx is a separate product, not provided by this MySQL job. No other
    // live integration skip is allowed, including privilege/setup-related skips.
    let optionalTest = "SADatabaseAssertionIntegrationTests/testSphinxQueryCanAssertEmptyDatabaseContext()"
    var seen: Set<String> = []
    var errors: [String] = []

    func visit(_ node: SATestNode, suite: String? = nil) {
        let suite = node.nodeType == "Test Suite" ? node.name : suite
        if node.nodeType == "Test Case", let suite, requiredSuites.contains(suite) {
            let identifier = "\(suite)/\(node.name ?? "<unnamed>")"
            if identifier != optionalTest && node.name != nil { seen.insert(suite) }
            if node.result != "Passed" && !(identifier == optionalTest && node.result == "Skipped") {
                errors.append("\(identifier): \(node.result ?? "missing result")")
            }
        }
        for child in node.children ?? [] { visit(child, suite: suite) }
    }
    for node in nodes { visit(node) }
    for suite in requiredSuites where !seen.contains(suite) {
        errors.append("\(suite): no test cases in result bundle")
    }
    return errors
}

func selfTest() throws {
    func fixture(_ result: String, suite: String = "LiveTests", test: String = "testDatabase()") -> [SATestNode] {
        [SATestNode(name: "Framework tests", nodeType: "Test Plan", result: nil, children: [
            SATestNode(name: suite, nodeType: "Test Suite", result: nil, children: [
                SATestNode(name: test, nodeType: "Test Case", result: result, children: nil)
            ])
        ])]
    }
    func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "SACoverageSelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    for result in ["Skipped", "Failed", "Expected Failure", "Unknown"] {
        try check(!coverageErrors(in: fixture(result), requiredSuites: ["LiveTests"]).isEmpty,
                  "accepted \(result) live coverage")
    }
    try check(coverageErrors(in: fixture("Passed"), requiredSuites: ["LiveTests"]).isEmpty, "rejected passed coverage")
    try check(!coverageErrors(in: [], requiredSuites: ["LiveTests"]).isEmpty, "accepted an absent suite")
    try check(!coverageErrors(in: fixture("Passed", suite: "OtherTests"), requiredSuites: ["LiveTests"]).isEmpty,
              "accepted coverage from a different suite")
    let optional = fixture("Skipped", suite: "SADatabaseAssertionIntegrationTests",
                           test: "testSphinxQueryCanAssertEmptyDatabaseContext()")
    let databasePass = fixture("Passed", suite: "SADatabaseAssertionIntegrationTests")
    try check(coverageErrors(in: optional + databasePass, requiredSuites: ["SADatabaseAssertionIntegrationTests"]).isEmpty,
              "rejected the documented Sphinx skip")
    try check(!coverageErrors(in: optional, requiredSuites: ["SADatabaseAssertionIntegrationTests"]).isEmpty,
              "counted the Sphinx skip as executed live coverage")
    let encoded = Data(#"{"testNodes":[{"nodeType":"Test Suite","name":"LiveTests","children":[{"nodeType":"Test Case","name":"testDatabase()","result":"Passed"}]}]}"#.utf8)
    let decoded = try JSONDecoder().decode(SATestResults.self, from: encoded)
    try check(coverageErrors(in: decoded.testNodes, requiredSuites: ["LiveTests"]).isEmpty, "JSON decoding lost coverage")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory.appendingPathComponent("moved"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try "final class SASessionIdentityIntegrationTests: XCTestCase {}".write(
        to: directory.appendingPathComponent("moved/RenamedTests.swift"), atomically: true, encoding: .utf8)
    let discovered = try requiredSuites(in: directory)
    try check(discovered.contains("SASessionIdentityIntegrationTests"), "moving a source omitted its live suite")
    try check(!coverageErrors(in: decoded.testNodes, requiredSuites: discovered).isEmpty,
              "accepted missing discovered live suites")
    print("Live-coverage verifier self-tests passed")
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--self-test"] {
        try selfTest()
    } else {
        guard arguments.count == 2 else {
            throw NSError(domain: "SACoverage", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Usage: swift verify-spmysql-results.swift tests.json framework-source-directory"])
        }
        let results = try JSONDecoder().decode(SATestResults.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[0])))
        let suites = try requiredSuites(in: URL(fileURLWithPath: arguments[1], isDirectory: true))
        let errors = coverageErrors(in: results.testNodes, requiredSuites: suites)
        guard errors.isEmpty else {
            throw NSError(domain: "SACoverage", code: 1, userInfo: [NSLocalizedDescriptionKey: errors.joined(separator: "\n")])
        }
        print("Required live suites executed without skips: \(suites.joined(separator: ", ")) (Sphinx excluded)")
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
