//
//  SAPHPSerializedValue.swift
//  sequel-ace
//
//  Created by Codex on 2026-06-15.
//

import Foundation

private let phpSerializedParserMaximumDepth = 512

private enum PHPSerializedASCII {
    static let colon: UInt8 = 58
    static let semicolon: UInt8 = 59
    static let quote: UInt8 = 34
    static let openBrace: UInt8 = 123
    static let closeBrace: UInt8 = 125
    static let null: UInt8 = 78
    static let boolean: UInt8 = 98
    static let integer: UInt8 = 105
    static let double: UInt8 = 100
    static let string: UInt8 = 115
    static let array: UInt8 = 97
    static let object: UInt8 = 79
    static let customSerialized: UInt8 = 67
    static let `enum`: UInt8 = 69
    static let reference: UInt8 = 114
    static let objectReference: UInt8 = 82
}

private func phpSerializedIntegerValue(from string: String) -> Int? {
    guard SAPHPSerializedValue.isValidPHPIntegerString(string),
          let parsedValue = Int64(string),
          parsedValue >= Int64(Int.min),
          parsedValue <= Int64(Int.max)
    else {
        return nil
    }

    return Int(parsedValue)
}

@objc enum SAPHPSerializedValueType: Int {
    case null = 0
    case boolean
    case integer
    case double
    case string
    case array
    case object
    case customSerialized
    case `enum`
    case reference
}

@objcMembers
final class SAPHPSerializedEntry: NSObject {
    dynamic var key: Any?
    dynamic var keyIsInteger = false
    dynamic var value: SAPHPSerializedValue!
    dynamic weak var parent: SAPHPSerializedEntry?
}

@objcMembers
final class SAPHPSerializedValue: NSObject {
    dynamic var type: SAPHPSerializedValueType = .null
    dynamic var scalarValue = ""
    dynamic var serializedClassName: String?
    dynamic var referenceType: String?
    dynamic var children = NSMutableArray()

    private var stringEncoding = String.Encoding.utf8.rawValue

    @objc(valueWithType:)
    static func value(with type: SAPHPSerializedValueType) -> SAPHPSerializedValue {
        let value = SAPHPSerializedValue()
        value.type = type
        value.scalarValue = ""
        value.children = NSMutableArray()
        value.stringEncoding = String.Encoding.utf8.rawValue
        return value
    }

    @objc(normalizedIntegerStringFromEditedString:)
    static func normalizedIntegerString(fromEditedString string: String?) -> String? {
        let trimmedString = (string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidPHPIntegerString(trimmedString) ? trimmedString : nil
    }

    static func isValidPHPIntegerString(_ string: String?) -> Bool {
        guard let string, !string.isEmpty else {
            return false
        }

        let scalars = Array(string.unicodeScalars)
        var startIndex = 0
        if scalars[0].value == 45 {
            guard scalars.count > 1 else {
                return false
            }
            startIndex = 1
        }

        for scalar in scalars[startIndex..<scalars.count] {
            if scalar.value < 48 || scalar.value > 57 {
                return false
            }
        }

        return true
    }

    static func isValidPHPFloatString(_ string: String?) -> Bool {
        guard let string, !string.isEmpty else {
            return false
        }

        if string == "INF" || string == "-INF" || string == "NAN" {
            return true
        }

        let uppercaseValue = string.uppercased()
        if uppercaseValue == "INF" || uppercaseValue == "-INF" || uppercaseValue == "NAN" {
            return false
        }

        return isValidPHPDecimalFloatString(string) && Double(string) != nil
    }

    private static func isValidPHPDecimalFloatString(_ string: String) -> Bool {
        let scalars = Array(string.unicodeScalars)
        var index = 0

        if scalars[index].value == 43 || scalars[index].value == 45 {
            index += 1
            guard index < scalars.count else {
                return false
            }
        }

        var integerDigitCount = 0
        while index < scalars.count && scalars[index].value >= 48 && scalars[index].value <= 57 {
            integerDigitCount += 1
            index += 1
        }

        var fractionalDigitCount = 0
        if index < scalars.count && scalars[index].value == 46 {
            index += 1
            while index < scalars.count && scalars[index].value >= 48 && scalars[index].value <= 57 {
                fractionalDigitCount += 1
                index += 1
            }
        }

        guard integerDigitCount > 0 || fractionalDigitCount > 0 else {
            return false
        }

        if index < scalars.count && (scalars[index].value == 69 || scalars[index].value == 101) {
            index += 1
            if index < scalars.count && (scalars[index].value == 43 || scalars[index].value == 45) {
                index += 1
            }

            let exponentStartIndex = index
            while index < scalars.count && scalars[index].value >= 48 && scalars[index].value <= 57 {
                index += 1
            }

            guard index > exponentStartIndex else {
                return false
            }
        }

        return index == scalars.count
    }

    @objc(isContainer)
    func isContainer() -> Bool {
        return type == .array || type == .object
    }

    @objc(isScalarEditable)
    func isScalarEditable() -> Bool {
        return type == .null
            || type == .boolean
            || type == .integer
            || type == .double
            || type == .string
    }

    @objc(typeLabel)
    func typeLabel() -> String {
        switch type {
        case .null:
            return "null"
        case .boolean:
            return "bool"
        case .integer:
            return "int"
        case .double:
            return "float"
        case .string:
            return "string"
        case .array:
            return "array (\(children.count))"
        case .object:
            return "object \(serializedClassName ?? "") (\(children.count))"
        case .customSerialized:
            return "custom \(serializedClassName ?? "")"
        case .enum:
            return "enum"
        case .reference:
            return "\(referenceType ?? "r") reference"
        }
    }

    @objc(displayValue)
    func displayValue() -> String {
        switch type {
        case .null:
            return "NULL"
        case .boolean:
            return scalarValue == "1" ? "true" : "false"
        case .integer, .double, .string, .customSerialized, .enum, .reference:
            return scalarValue
        case .array, .object:
            return ""
        }
    }

    @objc(nextAvailableArrayKey)
    func nextAvailableArrayKey() -> NSNumber {
        var maxIntegerKey = -1
        var usedNonNegativeKeys = Set<Int>()

        for case let entry as SAPHPSerializedEntry in children {
            guard entry.keyIsInteger else {
                continue
            }

            let keyString = String(describing: entry.key ?? "")
            guard let integerKey = phpSerializedIntegerValue(from: keyString) else {
                continue
            }

            if integerKey > maxIntegerKey {
                maxIntegerKey = integerKey
            }
            if integerKey >= 0 {
                usedNonNegativeKeys.insert(integerKey)
            }
        }

        if maxIntegerKey >= 0 && maxIntegerKey < Int.max {
            return NSNumber(value: maxIntegerKey + 1)
        }

        var candidateKey = 0
        while usedNonNegativeKeys.contains(candidateKey) && candidateKey < Int.max {
            candidateKey += 1
        }

        return NSNumber(value: candidateKey)
    }

    @objc(uniqueObjectPropertyName)
    func uniqueObjectPropertyName() -> String {
        let basePropertyName = "new_property"
        var usedNames = Set<String>()

        for case let entry as SAPHPSerializedEntry in children {
            guard !entry.keyIsInteger else {
                continue
            }
            if let key = entry.key {
                usedNames.insert(String(describing: key))
            }
        }

        if !usedNames.contains(basePropertyName) {
            return basePropertyName
        }

        var suffix = 2
        while suffix < Int.max {
            let candidate = "\(basePropertyName)_\(suffix)"
            if !usedNames.contains(candidate) {
                return candidate
            }
            suffix += 1
        }

        return "\(basePropertyName)_\(UUID().uuidString)"
    }

    @objc(containsReference)
    func containsReference() -> Bool {
        if type == .reference {
            return true
        }

        for case let entry as SAPHPSerializedEntry in children {
            if entry.value.containsReference() {
                return true
            }
        }

        return false
    }

    fileprivate func setStringEncodingRecursively(_ encoding: UInt) {
        stringEncoding = encoding

        for case let entry as SAPHPSerializedEntry in children {
            entry.value.setStringEncodingRecursively(encoding)
        }
    }

    private func data(forSerializedString string: String, encoding: UInt, errorMessage: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Data? {
        guard let data = string.data(using: String.Encoding(rawValue: encoding), allowLossyConversion: false) else {
            errorMessage?.pointee = NSLocalizedString("Serialized data contains characters that cannot be encoded using the field encoding.", comment: "PHP serialized editor output encoding error") as NSString
            return nil
        }

        return data
    }

    private func serializedString(forKey entry: SAPHPSerializedEntry, encoding: UInt, errorMessage: AutoreleasingUnsafeMutablePointer<NSString?>?) -> String? {
        if entry.keyIsInteger {
            return "i:\(String(describing: entry.key ?? ""));"
        }

        let key = (entry.key as? String) ?? entry.key.map { String(describing: $0) } ?? ""
        guard let keyData = data(forSerializedString: key, encoding: encoding, errorMessage: errorMessage) else {
            return nil
        }

        return "s:\(keyData.count):\"\(key)\";"
    }

    @objc(serializedString)
    func serializedString() -> String? {
        return serializedString(errorMessage: nil)
    }

    @objc(serializedStringWithError:)
    func serializedString(errorMessage: AutoreleasingUnsafeMutablePointer<NSString?>?) -> String? {
        let outputEncoding = stringEncoding == 0 ? String.Encoding.utf8.rawValue : stringEncoding
        return serializedString(using: outputEncoding, errorMessage: errorMessage)
    }

    private func serializedString(using encoding: UInt, errorMessage: AutoreleasingUnsafeMutablePointer<NSString?>?) -> String? {
        switch type {
        case .null:
            return "N;"
        case .boolean:
            return "b:\(scalarValue == "1" ? "1" : "0");"
        case .integer:
            return "i:\(!scalarValue.isEmpty ? scalarValue : "0");"
        case .double:
            return "d:\(!scalarValue.isEmpty ? scalarValue : "0");"
        case .string:
            let string = scalarValue
            guard let stringData = data(forSerializedString: string, encoding: encoding, errorMessage: errorMessage) else {
                return nil
            }
            return "s:\(stringData.count):\"\(string)\";"
        case .array:
            var output = "a:\(children.count):{"
            for case let entry as SAPHPSerializedEntry in children {
                guard let keyString = serializedString(forKey: entry, encoding: encoding, errorMessage: errorMessage),
                      let valueString = entry.value.serializedString(using: encoding, errorMessage: errorMessage)
                else {
                    return nil
                }
                output += keyString
                output += valueString
            }
            output += "}"
            return output
        case .object:
            let className = serializedClassName ?? "stdClass"
            guard let classData = data(forSerializedString: className, encoding: encoding, errorMessage: errorMessage) else {
                return nil
            }
            var output = "O:\(classData.count):\"\(className)\":\(children.count):{"
            for case let entry as SAPHPSerializedEntry in children {
                guard let keyString = serializedString(forKey: entry, encoding: encoding, errorMessage: errorMessage),
                      let valueString = entry.value.serializedString(using: encoding, errorMessage: errorMessage)
                else {
                    return nil
                }
                output += keyString
                output += valueString
            }
            output += "}"
            return output
        case .customSerialized:
            let className = serializedClassName ?? ""
            let payload = scalarValue
            guard let classData = data(forSerializedString: className, encoding: encoding, errorMessage: errorMessage),
                  let payloadData = data(forSerializedString: payload, encoding: encoding, errorMessage: errorMessage)
            else {
                return nil
            }
            return "C:\(classData.count):\"\(className)\":\(payloadData.count):{\(payload)}"
        case .enum:
            let caseName = scalarValue
            guard let caseData = data(forSerializedString: caseName, encoding: encoding, errorMessage: errorMessage) else {
                return nil
            }
            return "E:\(caseData.count):\"\(caseName)\";"
        case .reference:
            return "\(referenceType ?? "r"):\(!scalarValue.isEmpty ? scalarValue : "1");"
        }
    }
}

@objcMembers
final class SAPHPSerializedParser: NSObject {
    private var bytes: [UInt8] = []
    private var position = 0
    private var recursionDepth = 0
    private var stringEncoding = String.Encoding.utf8.rawValue
    private var errorMessage: String?

    @objc(parseString:error:)
    static func parseString(_ input: String?, errorMessage: AutoreleasingUnsafeMutablePointer<NSString?>?) -> SAPHPSerializedValue? {
        return parseString(input, encoding: String.Encoding.utf8.rawValue, errorMessage: errorMessage)
    }

    @objc(parseString:encoding:error:)
    static func parseString(_ input: String?, encoding: UInt, errorMessage: AutoreleasingUnsafeMutablePointer<NSString?>?) -> SAPHPSerializedValue? {
        let inputString = input ?? ""
        guard !inputString.isEmpty else {
            errorMessage?.pointee = NSLocalizedString("No serialized data was provided.", comment: "PHP serialized editor empty input error") as NSString
            return nil
        }

        guard let inputData = inputString.data(using: String.Encoding(rawValue: encoding), allowLossyConversion: false) else {
            errorMessage?.pointee = NSLocalizedString("Serialized data cannot be encoded using the field encoding.", comment: "PHP serialized editor input encoding error") as NSString
            return nil
        }

        let parser = SAPHPSerializedParser()
        parser.bytes = Array(inputData)
        parser.position = 0
        parser.stringEncoding = encoding

        guard let value = parser.parseValue() else {
            errorMessage?.pointee = (parser.errorMessage ?? NSLocalizedString("Unable to parse PHP serialized data.", comment: "PHP serialized editor parse error")) as NSString
            return nil
        }

        guard parser.position == parser.bytes.count else {
            errorMessage?.pointee = NSLocalizedString("Unexpected trailing characters after serialized value.", comment: "PHP serialized editor trailing input error") as NSString
            return nil
        }

        value.setStringEncodingRecursively(encoding)
        return value
    }

    private func currentByte() -> UInt8 {
        if position >= bytes.count {
            return 0
        }

        return bytes[position]
    }

    private func consumeByte(_ byte: UInt8) -> Bool {
        guard currentByte() == byte else {
            errorMessage = String(format: NSLocalizedString("Expected '%c'.", comment: "PHP serialized editor expected byte error"), Int(byte))
            return false
        }

        position += 1
        return true
    }

    private func readUntilByte(_ delimiter: UInt8) -> String? {
        let start = position
        while position < bytes.count && bytes[position] != delimiter {
            position += 1
        }

        guard position < bytes.count else {
            errorMessage = String(format: NSLocalizedString("Expected delimiter '%c'.", comment: "PHP serialized editor expected delimiter error"), Int(delimiter))
            return nil
        }

        let subdata = Data(bytes[start..<position])
        position += 1
        return String(data: subdata, encoding: .ascii)
    }

    private func readBytesAsString(_ byteLength: UInt) -> String? {
        let dataLength = bytes.count
        let remainingLength = dataLength - position
        guard position <= dataLength && byteLength <= UInt(remainingLength) else {
            errorMessage = NSLocalizedString("String length exceeds available serialized data.", comment: "PHP serialized editor string length error")
            return nil
        }

        let length = Int(byteLength)
        let subdata = Data(bytes[position..<(position + length)])
        position += length

        let primaryEncoding = String.Encoding(rawValue: stringEncoding)
        let fallbackEncodings: [String.Encoding] = primaryEncoding == .utf8 ? [.utf8, .isoLatin1] : [primaryEncoding, .utf8, .isoLatin1]
        for encoding in fallbackEncodings {
            if let string = String(data: subdata, encoding: encoding) {
                return string
            }
        }

        errorMessage = NSLocalizedString("Serialized string could not be decoded as text.", comment: "PHP serialized editor string decoding error")
        return nil
    }

    private func parseValue() -> SAPHPSerializedValue? {
        guard recursionDepth < phpSerializedParserMaximumDepth else {
            errorMessage = NSLocalizedString("PHP serialized data exceeds the maximum supported nesting depth.", comment: "PHP serialized editor maximum nesting depth error")
            return nil
        }

        recursionDepth += 1
        defer { recursionDepth -= 1 }
        return parseValueAtCurrentDepth()
    }

    private func parseValueAtCurrentDepth() -> SAPHPSerializedValue? {
        guard position < bytes.count else {
            errorMessage = NSLocalizedString("Unexpected end of serialized data.", comment: "PHP serialized editor end of input error")
            return nil
        }

        let typeByte = currentByte()
        position += 1

        if typeByte == PHPSerializedASCII.null {
            guard consumeByte(PHPSerializedASCII.semicolon) else {
                return nil
            }
            return SAPHPSerializedValue.value(with: .null)
        }

        guard consumeByte(PHPSerializedASCII.colon) else {
            return nil
        }

        if typeByte == PHPSerializedASCII.boolean {
            guard let raw = readUntilByte(PHPSerializedASCII.semicolon) else {
                return nil
            }
            guard raw == "0" || raw == "1" else {
                errorMessage = NSLocalizedString("Invalid PHP boolean value.", comment: "PHP serialized editor invalid boolean error")
                return nil
            }

            let value = SAPHPSerializedValue.value(with: .boolean)
            value.scalarValue = raw
            return value
        }

        if typeByte == PHPSerializedASCII.integer {
            guard let raw = readUntilByte(PHPSerializedASCII.semicolon) else {
                return nil
            }
            guard SAPHPSerializedValue.isValidPHPIntegerString(raw) else {
                errorMessage = NSLocalizedString("Invalid PHP integer value.", comment: "PHP serialized editor invalid integer error")
                return nil
            }

            let value = SAPHPSerializedValue.value(with: .integer)
            value.scalarValue = raw
            return value
        }

        if typeByte == PHPSerializedASCII.double {
            guard let raw = readUntilByte(PHPSerializedASCII.semicolon) else {
                return nil
            }
            guard SAPHPSerializedValue.isValidPHPFloatString(raw) else {
                errorMessage = NSLocalizedString("Invalid PHP float value.", comment: "PHP serialized editor invalid float error")
                return nil
            }

            let value = SAPHPSerializedValue.value(with: .double)
            value.scalarValue = raw
            return value
        }

        if typeByte == PHPSerializedASCII.string {
            guard let lengthString = readUntilByte(PHPSerializedASCII.colon),
                  let byteLength = unsignedIntegerValue(from: lengthString),
                  consumeByte(PHPSerializedASCII.quote),
                  let string = readBytesAsString(byteLength),
                  consumeByte(PHPSerializedASCII.quote),
                  consumeByte(PHPSerializedASCII.semicolon)
            else {
                return nil
            }

            let value = SAPHPSerializedValue.value(with: .string)
            value.scalarValue = string
            return value
        }

        if typeByte == PHPSerializedASCII.array {
            guard let countString = readUntilByte(PHPSerializedASCII.colon),
                  let count = unsignedIntegerValue(from: countString),
                  consumeByte(PHPSerializedASCII.openBrace)
            else {
                return nil
            }

            let arrayValue = SAPHPSerializedValue.value(with: .array)
            for _ in 0..<count {
                guard let keyValue = parseValue() else {
                    return nil
                }
                guard keyValue.type == .integer || keyValue.type == .string else {
                    errorMessage = NSLocalizedString("PHP array keys must be integers or strings.", comment: "PHP serialized editor invalid key error")
                    return nil
                }
                guard let childValue = parseValue() else {
                    return nil
                }

                let entry = SAPHPSerializedEntry()
                entry.keyIsInteger = keyValue.type == .integer
                entry.key = keyValue.scalarValue
                entry.value = childValue
                arrayValue.children.add(entry)
            }

            guard consumeByte(PHPSerializedASCII.closeBrace) else {
                return nil
            }
            return arrayValue
        }

        if typeByte == PHPSerializedASCII.object {
            guard let classLengthString = readUntilByte(PHPSerializedASCII.colon),
                  let classByteLength = unsignedIntegerValue(from: classLengthString),
                  consumeByte(PHPSerializedASCII.quote),
                  let className = readBytesAsString(classByteLength),
                  consumeByte(PHPSerializedASCII.quote),
                  consumeByte(PHPSerializedASCII.colon),
                  let countString = readUntilByte(PHPSerializedASCII.colon),
                  let count = unsignedIntegerValue(from: countString),
                  consumeByte(PHPSerializedASCII.openBrace)
            else {
                return nil
            }

            let objectValue = SAPHPSerializedValue.value(with: .object)
            objectValue.serializedClassName = className
            for _ in 0..<count {
                guard let keyValue = parseValue() else {
                    return nil
                }
                guard keyValue.type == .integer || keyValue.type == .string else {
                    errorMessage = NSLocalizedString("PHP object property names must be integers or strings.", comment: "PHP serialized editor invalid property error")
                    return nil
                }
                guard let childValue = parseValue() else {
                    return nil
                }

                let entry = SAPHPSerializedEntry()
                entry.keyIsInteger = keyValue.type == .integer
                entry.key = keyValue.scalarValue
                entry.value = childValue
                objectValue.children.add(entry)
            }

            guard consumeByte(PHPSerializedASCII.closeBrace) else {
                return nil
            }
            return objectValue
        }

        if typeByte == PHPSerializedASCII.customSerialized {
            guard let classLengthString = readUntilByte(PHPSerializedASCII.colon),
                  let classByteLength = unsignedIntegerValue(from: classLengthString),
                  consumeByte(PHPSerializedASCII.quote),
                  let className = readBytesAsString(classByteLength),
                  consumeByte(PHPSerializedASCII.quote),
                  consumeByte(PHPSerializedASCII.colon),
                  let payloadLengthString = readUntilByte(PHPSerializedASCII.colon),
                  let payloadByteLength = unsignedIntegerValue(from: payloadLengthString),
                  consumeByte(PHPSerializedASCII.openBrace),
                  let payload = readBytesAsString(payloadByteLength),
                  consumeByte(PHPSerializedASCII.closeBrace)
            else {
                return nil
            }

            let customValue = SAPHPSerializedValue.value(with: .customSerialized)
            customValue.serializedClassName = className
            customValue.scalarValue = payload
            return customValue
        }

        if typeByte == PHPSerializedASCII.enum {
            guard let caseLengthString = readUntilByte(PHPSerializedASCII.colon),
                  let caseByteLength = unsignedIntegerValue(from: caseLengthString),
                  consumeByte(PHPSerializedASCII.quote),
                  let caseName = readBytesAsString(caseByteLength),
                  consumeByte(PHPSerializedASCII.quote),
                  consumeByte(PHPSerializedASCII.semicolon)
            else {
                return nil
            }

            let enumValue = SAPHPSerializedValue.value(with: .enum)
            enumValue.scalarValue = caseName
            return enumValue
        }

        if typeByte == PHPSerializedASCII.reference || typeByte == PHPSerializedASCII.objectReference {
            guard let reference = readUntilByte(PHPSerializedASCII.semicolon),
                  unsignedIntegerValue(from: reference) != nil
            else {
                return nil
            }

            let referenceValue = SAPHPSerializedValue.value(with: .reference)
            referenceValue.referenceType = String(UnicodeScalar(typeByte))
            referenceValue.scalarValue = reference
            return referenceValue
        }

        errorMessage = String(format: NSLocalizedString("Unsupported PHP serialized type '%c'.", comment: "PHP serialized editor unsupported type error"), Int(typeByte))
        return nil
    }

    private func unsignedIntegerValue(from string: String) -> UInt? {
        guard !string.isEmpty else {
            return nil
        }

        for scalar in string.unicodeScalars {
            if scalar.value < 48 || scalar.value > 57 {
                errorMessage = NSLocalizedString("Invalid serialized length or count.", comment: "PHP serialized editor invalid count error")
                return nil
            }
        }

        guard let parsedValue = UInt(string) else {
            errorMessage = NSLocalizedString("Serialized length or count is too large.", comment: "PHP serialized editor count overflow error")
            return nil
        }

        return parsedValue
    }
}
