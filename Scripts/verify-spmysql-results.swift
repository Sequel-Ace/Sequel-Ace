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

struct SAEnumerationNode: Decodable {
    let name: String
    let kind: String
    let children: [SAEnumerationNode]?
}

struct SATestEnumeration: Decodable {
    let errors: [String]
    let values: [SAEnumerationNode]
}

func testIdentifier(suite: String, test: String) -> String {
    "\(suite)/\(test.hasSuffix("()") ? String(test.dropLast(2)) : test)"
}

func suiteName(_ name: String?) -> String? {
    name?.split(separator: ".").last.map(String.init)
}

func requiredCoverage(in enumeration: SATestEnumeration) throws -> [String: Set<String>] {
    guard enumeration.errors.isEmpty else {
        throw NSError(domain: "SACoverage", code: 1, userInfo: [NSLocalizedDescriptionKey: enumeration.errors.joined(separator: "\n")])
    }
    // The two existing suites are unconditional coverage contracts. Additional
    // compiled integration classes (including #2775's) come from Xcode, not source text.
    var required: [String: Set<String>] = ["SAEscapingBoundaryIntegrationTests": [], "SADatabaseAssertionIntegrationTests": []]
    func visit(_ node: SAEnumerationNode, suite: String? = nil) {
        // These policy suites mean #2775's foundation is compiled. Its live
        // identity contract must not disappear through accidental target unregistration.
        if node.kind == "class", ["SAConnectionCancellationTests", "SASessionGateTests", "SAStatementBytesTests"].contains(suiteName(node.name) ?? "") {
            if required["SASessionIdentityIntegrationTests"] == nil { required["SASessionIdentityIntegrationTests"] = [] }
        }
        let suite = node.kind == "class" ? (node.name.hasSuffix("IntegrationTests") ? suiteName(node.name) : nil) : suite
        if let suite {
            if required[suite] == nil { required[suite] = [] }
            if node.kind == "test" { required[suite, default: []].insert(testIdentifier(suite: suite, test: node.name)) }
        }
        for child in node.children ?? [] { visit(child, suite: suite) }
    }
    for node in enumeration.values { visit(node) }
    return required
}

func coverageErrors(in nodes: [SATestNode], requiredSuites: [String], expectedTests: Set<String> = []) -> [String] {
    // Sphinx is a separate product, not provided by this MySQL job. No other
    // live integration skip is allowed, including privilege/setup-related skips.
    let optionalTest = "SADatabaseAssertionIntegrationTests/testSphinxQueryCanAssertEmptyDatabaseContext"
    var seen: Set<String> = []
    var seenTests: Set<String> = []
    var errors: [String] = []

    func visit(_ node: SATestNode, suite: String? = nil) {
        let suite = node.nodeType == "Test Suite" ? suiteName(node.name) : suite
        if node.nodeType == "Test Case", let suite, requiredSuites.contains(suite) {
            let identifier = testIdentifier(suite: suite, test: node.name ?? "<unnamed>")
            if node.name != nil { seenTests.insert(identifier) }
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
    for test in expectedTests.subtracting(seenTests) {
        errors.append("\(test): enumerated test missing from result bundle")
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
    let enumerated = Data(#"{"errors":[],"values":[{"kind":"class","name":"SASessionIdentityIntegrationTests","children":[{"kind":"test","name":"testDatabase"}]}]}"#.utf8)
    let discovery = try JSONDecoder().decode(SATestEnumeration.self, from: enumerated)
    let required = try requiredCoverage(in: discovery)
    try check(required["SASessionIdentityIntegrationTests"] == ["SASessionIdentityIntegrationTests/testDatabase"],
              "lost an enumerated integration test")
    try check(required["CommentedIntegrationTests"] == nil && required["InactiveIntegrationTests"] == nil,
              "invented a suite absent from compiler enumeration")
    let foundation = SATestEnumeration(errors: [], values: [SAEnumerationNode(name: "SASessionGateTests", kind: "class", children: nil)])
    let foundationCoverage = try requiredCoverage(in: foundation)
    try check(foundationCoverage["SASessionIdentityIntegrationTests"] != nil,
              "accepted foundation tests without their live identity contract")
    try check(!coverageErrors(in: fixture("Passed"), requiredSuites: ["LiveTests"], expectedTests: ["LiveTests/testMissing"]).isEmpty,
              "accepted an enumerated test absent from results")
    print("Live-coverage verifier self-tests passed")
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--self-test"] {
        try selfTest()
    } else {
        guard arguments.count == 2 else {
            throw NSError(domain: "SACoverage", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Usage: swift verify-spmysql-results.swift tests.json enumeration.json"])
        }
        let results = try JSONDecoder().decode(SATestResults.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[0])))
        let enumeration = try JSONDecoder().decode(SATestEnumeration.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
        let required = try requiredCoverage(in: enumeration)
        let suites = required.keys.sorted()
        let errors = coverageErrors(in: results.testNodes, requiredSuites: suites, expectedTests: Set(required.values.flatMap { $0 }))
        guard errors.isEmpty else {
            throw NSError(domain: "SACoverage", code: 1, userInfo: [NSLocalizedDescriptionKey: errors.joined(separator: "\n")])
        }
        print("Required live suites executed without skips: \(suites.joined(separator: ", ")) (Sphinx excluded)")
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
