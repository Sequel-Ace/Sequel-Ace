import XCTest

/// The Settings window's number fields: what a typed value becomes (or that it is refused and the old value kept),
/// checked per catalog range against today's Preferences.xib formatters, and how a value is shown with its unit.
final class SAClaudeSettingsValuesTests: XCTestCase {

    private typealias Values = SAClaudeSettingsValues

    /// The catalog's numeric rows: id → (range, step).
    private static let numericRows: [String: (range: ClosedRange<Double>, step: Double)] = {
        var rows: [String: (ClosedRange<Double>, Double)] = [:]
        for row in SAClaudeSettingsCatalog.panes.flatMap({ $0.sections.flatMap(\.rows) }) {
            switch row.control {
            case let .number(_, _, range, step), let .toggleNumber(_, _, _, range, step):
                rows[row.id] = (range, step)
            default:
                break
            }
        }
        return rows
    }()

    private func parse(_ text: String, _ id: String, file: StaticString = #filePath, line: UInt = #line) -> Double? {
        guard let row = Self.numericRows[id] else {
            XCTFail("\(id) is not a numeric row", file: file, line: line)
            return nil
        }
        return Values.parse(text, range: row.range, step: row.step)
    }

    // MARK: - Parsing

    func testNumberFieldClampsAndRejects() throws {
        XCTAssertEqual(Set(Self.numericRows.keys), ["historySize", "tabWidth", "softIndent", "autoHelp", "autoComplete",
                                                    "mcpPort", "pageSize", "longValueSheet", "connectTimeout"])

        // Not numbers: refused in every field (the formatters refuse them; so does the MCP port check).
        for id in Self.numericRows.keys {
            for text in ["abc", "", "  ", "1e2", "3e2", "0x10", "1.2.3", "--1", "+5", "7s", "1 2", "five", "0,5", "1,00", ","] {
                XCTAssertNil(parse(text, id), "\(id): \(text)")
            }
        }

        // Each range's ends are accepted; one step past either end is refused (never clamped into range).
        for (id, row) in Self.numericRows {
            let lower = row.range.lowerBound, upper = row.range.upperBound
            XCTAssertEqual(parse(Values.numberText(lower), id), lower, id)
            XCTAssertEqual(parse(Values.numberText(upper), id), upper, id)
            XCTAssertNil(parse(Values.numberText(upper + row.step), id), "\(id) above")
            XCTAssertNil(parse(Values.numberText(upper * 10), id), "\(id) far above")
            XCTAssertNil(parse("-1", id), "\(id) negative")
            if lower - row.step >= 0 {
                XCTAssertNil(parse(Values.numberText(lower - row.step), id), "\(id) below")
            }
        }

        // History: 0–100 whole queries (formatter 0–100, no fractions).
        XCTAssertEqual(parse("0", "historySize"), 0)
        XCTAssertEqual(parse("100", "historySize"), 100)
        XCTAssertNil(parse("101", "historySize"))
        XCTAssertNil(parse("2.5", "historySize"))
        XCTAssertEqual(parse(" 7 ", "historySize"), 7, "surrounding spaces are ignored, as the formatter does")

        // Tab width 1–20, soft indent 1–32: whole spaces.
        XCTAssertNil(parse("0", "tabWidth"))
        XCTAssertEqual(parse("4", "tabWidth"), 4)
        XCTAssertEqual(parse("20", "tabWidth"), 20)
        XCTAssertNil(parse("21", "tabWidth"))
        XCTAssertNil(parse("4.5", "tabWidth"), "half a space is refused (the reader truncates it today)")
        XCTAssertNil(parse("0", "softIndent"))
        XCTAssertEqual(parse("32", "softIndent"), 32)
        XCTAssertNil(parse("33", "softIndent"))
        XCTAssertEqual(parse("2.0", "softIndent"), 2, "a whole number written with a decimal point is that number")

        // Timeout 0–10000 seconds; 0 waits forever.
        XCTAssertEqual(parse("0", "connectTimeout"), 0)
        XCTAssertEqual(parse("10000", "connectTimeout"), 10_000)
        XCTAssertNil(parse("10001", "connectTimeout"))
        XCTAssertNil(parse("2.5", "connectTimeout"))

        // Page size 1–1,000,000 rows. Thousands separators are refused in every field (only the page-size formatter
        // took them; the MCP port's digits-only check and the other formatters refused "8,765").
        XCTAssertNil(parse("0", "pageSize"), "0 rows per page would load nothing")
        XCTAssertEqual(parse("1000", "pageSize"), 1000)
        XCTAssertEqual(parse("1000000", "pageSize"), 1_000_000)
        for id in Self.numericRows.keys {
            for text in ["1,000", "8,765", "1,000,000", "1,000,001", "10,00"] {
                XCTAssertNil(parse(text, id), "\(id): \(text)")
            }
        }

        // Long-value sheet: 1–1,000,000 characters.
        XCTAssertEqual(parse("15", "longValueSheet"), 15)
        XCTAssertNil(parse("0", "longValueSheet"))

        // MCP port 1024–65535, whole numbers only.
        XCTAssertNil(parse("1023", "mcpPort"))
        XCTAssertEqual(parse("8765", "mcpPort"), 8765)
        XCTAssertEqual(parse("65535", "mcpPort"), 65535)
        XCTAssertNil(parse("65536", "mcpPort"))
        XCTAssertNil(parse("8765.5", "mcpPort"))

        // Delays: tenths of a second. A value inside the range is rounded to the tenth the field shows (today's
        // "#.0" formatter shows 1.55 as "1.6"; the field now also stores what it shows); outside it is refused
        // before rounding, as the formatter refuses 0.05 and 5.04.
        XCTAssertEqual(try XCTUnwrap(parse("1.55", "autoHelp")), 1.6, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(parse("1.54", "autoHelp")), 1.5, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(parse("1.45", "autoHelp")), 1.5, accuracy: 1e-12, "halves round up, decimally")
        XCTAssertEqual(parse("0.1", "autoHelp"), 0.1)
        XCTAssertEqual(parse(".1", "autoHelp"), 0.1)
        XCTAssertEqual(parse("5", "autoHelp"), 5)
        XCTAssertNil(parse("0", "autoHelp"))
        XCTAssertNil(parse("0.05", "autoHelp"))
        XCTAssertNil(parse("0.06", "autoHelp"))
        XCTAssertNil(parse("5.04", "autoHelp"))
        XCTAssertEqual(parse("1.6", "autoHelp"), 1.6, "exactly the Double a literal 1.6 is, so == holds")
        XCTAssertEqual(parse("0", "autoComplete"), 0)
        XCTAssertEqual(parse("0.5", "autoComplete"), 0.5)
        XCTAssertEqual(parse("5", "autoComplete"), 5)
        XCTAssertNil(parse("5.1", "autoComplete"))
    }

    // MARK: - Showing

    func testFormatWithUnits() {
        XCTAssertEqual(Values.format(1.5, unit: .seconds), "1.5 s")
        XCTAssertEqual(Values.format(1000, unit: .rows), "1000")
        XCTAssertEqual(Values.format(20, unit: .queries), "20")
        XCTAssertEqual(Values.format(60, unit: .seconds), "60 s")
        XCTAssertEqual(Values.format(0.1, unit: .seconds), "0.1 s")
        XCTAssertEqual(Values.format(0.1 + 0.2, unit: .seconds), "0.3 s", "binary noise is not shown")
        XCTAssertEqual(Values.format(2, unit: .spaces), "2")
        XCTAssertEqual(Values.format(15, unit: .characters), "15")
        XCTAssertEqual(Values.format(1_000_000, unit: .rows), "1000000", "no grouping, so the text parses back as typed")
        XCTAssertEqual(Values.format(8765, unit: .none), "8765")

        XCTAssertEqual(Values.suffix(for: .seconds), "s")
        for unit in [SAClaudeSettingUnit.none, .rows, .characters, .spaces, .queries] {
            XCTAssertNil(Values.suffix(for: unit), "\(unit) is said in the row's description, not in the field")
        }
        XCTAssertEqual(Values.numberText(1.5), "1.5")
        XCTAssertEqual(Values.numberText(2.5), "2.5", "a legacy fractional value is shown, not hidden")
        XCTAssertEqual(Values.numberText(1.55), "1.55")
    }

    func testStoredValueKeepsWholeNumbersWhole() {
        // Whole-step fields write integers, as the integer formatters' NSNumbers did; tenths write doubles.
        let whole = Values.storedValue(20, step: 1)
        XCTAssertEqual(whole as? Int, 20)
        XCTAssertEqual(String(cString: whole.objCType), String(cString: NSNumber(value: 20).objCType))
        let tenth = Values.storedValue(1.6, step: 0.1)
        XCTAssertEqual(tenth.doubleValue, 1.6)
        XCTAssertEqual(String(cString: tenth.objCType), "d")
    }

    func testRoundTripForEveryRow() {
        for (id, row) in Self.numericRows {
            var value = row.range.lowerBound
            var count = 0
            while value <= row.range.upperBound, count < 60 {
                XCTAssertEqual(parse(Values.numberText(value), id), value, "\(id) \(value)")
                value = (value + row.step * Double(max(1, Int(row.range.upperBound - row.range.lowerBound) / 50)))
                value = (value * 10).rounded() / 10
                count += 1
            }
        }
    }
}
