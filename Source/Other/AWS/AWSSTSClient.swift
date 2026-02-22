//
//  AWSSTSClient.swift
//  Sequel Ace
//
//  Created for AWS IAM authentication support with MFA.
//  Copyright (c) 2024 Sequel-Ace. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//

import Foundation
import CommonCrypto
import OSLog

/// Errors that can occur during STS operations
@objc enum AWSSTSClientError: Int, Error, LocalizedError {
    case invalidCredentials
    case invalidParameters
    case mfaRequired
    case networkFailure
    case invalidResponse
    case accessDenied
    case requestTimeout

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return NSLocalizedString("Invalid AWS credentials", comment: "STS error")
        case .invalidParameters:
            return NSLocalizedString("Invalid parameters for STS request", comment: "STS error")
        case .mfaRequired:
            return NSLocalizedString("MFA token code is required", comment: "STS error")
        case .networkFailure:
            return NSLocalizedString("Network request failed", comment: "STS error")
        case .invalidResponse:
            return NSLocalizedString("Invalid response from STS", comment: "STS error")
        case .accessDenied:
            return NSLocalizedString("Access denied by AWS STS", comment: "STS error")
        case .requestTimeout:
            return NSLocalizedString("STS request timed out", comment: "STS error")
        }
    }
}

/// AWS STS client for assuming roles with optional MFA
@objc final class AWSSTSClient: NSObject {

    // MARK: - Constants

    private static let algorithm = "AWS4-HMAC-SHA256"
    private static let service = "sts"
    private static let awsRequest = "aws4_request"
    private static let defaultSessionDuration = 3600 // 1 hour
    private static let requestTimeout: TimeInterval = 30

    private static let log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "AWSSTSClient")
    private static let defaultAWSDNSSuffix = "amazonaws.com"
    private static let partitionDNSSuffixByRegionPrefix: [String: String] = [
        "us-isob-": "sc2s.sgov.gov",
        "us-iso-": "c2s.ic.gov",
        "cn-": "amazonaws.com.cn",
        "us-gov-": "amazonaws.com"
    ]
    private static let regionPrefixesBySpecificity = partitionDNSSuffixByRegionPrefix.keys.sorted { $0.count > $1.count }

    // MARK: - Endpoint Helpers

    static func endpointHost(for region: String) -> String {
        let normalizedRegion = region
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let domain = endpointDNSSuffix(for: normalizedRegion)
        return "sts.\(normalizedRegion).\(domain)"
    }

    private static func endpointDNSSuffix(for region: String) -> String {
        // Longest-prefix match ensures more specific partitions win.
        for prefix in regionPrefixesBySpecificity {
            if region.hasPrefix(prefix), let suffix = partitionDNSSuffixByRegionPrefix[prefix] {
                return suffix
            }
        }
        return defaultAWSDNSSuffix
    }

    // MARK: - Role Assumption (Async)

    /// Assume an IAM role with optional MFA (async version)
    static func assumeRole(
        roleArn: String,
        roleSessionName: String? = nil,
        mfaSerialNumber: String? = nil,
        mfaTokenCode: String? = nil,
        durationSeconds: Int = 0,
        region: String,
        credentials: AWSCredentials
    ) async throws -> AWSCredentials {
        // Validate inputs
        guard credentials.isValid else {
            throw AWSSTSClientError.invalidCredentials
        }

        guard !roleArn.isEmpty else {
            throw AWSSTSClientError.invalidParameters
        }

        guard !region.isEmpty else {
            throw AWSSTSClientError.invalidParameters
        }

        // If MFA serial is provided, token code is required
        if let mfaSerial = mfaSerialNumber, !mfaSerial.isEmpty {
            guard let tokenCode = mfaTokenCode, !tokenCode.isEmpty else {
                throw AWSSTSClientError.mfaRequired
            }
        }

        // Generate session name if not provided
        let effectiveSessionName = roleSessionName?.isEmpty == false
            ? roleSessionName!
            : "SequelAce-\(Int(Date().timeIntervalSince1970))"

        // Clamp duration to valid range (900 - 43200 seconds)
        var effectiveDuration = durationSeconds > 0 ? durationSeconds : defaultSessionDuration
        effectiveDuration = max(900, min(43200, effectiveDuration))

        // Build the STS endpoint using partition-aware DNS suffix resolution.
        let host = endpointHost(for: region)
        guard let endpoint = URL(string: "https://\(host)/") else {
            throw AWSSTSClientError.invalidParameters
        }

        // Build request body
        var params: [String: String] = [
            "Action": "AssumeRole",
            "Version": "2011-06-15",
            "RoleArn": roleArn,
            "RoleSessionName": effectiveSessionName,
            "DurationSeconds": String(effectiveDuration)
        ]

        if let mfaSerial = mfaSerialNumber, !mfaSerial.isEmpty,
           let tokenCode = mfaTokenCode {
            params["SerialNumber"] = mfaSerial
            params["TokenCode"] = tokenCode
        }

        let requestBody = buildQueryString(from: params)

        // Get current time with POSIX locale
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = dateFormatter.string(from: now)
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: now)

        // Build headers
        let contentType = "application/x-www-form-urlencoded; charset=utf-8"
        let payloadHash = sha256Hex(requestBody)

        // Create canonical request
        // Include x-amz-security-token in signed headers if using temporary credentials
        let hasSessionToken = credentials.sessionToken?.isEmpty == false
        let signedHeaders = hasSessionToken
            ? "content-type;host;x-amz-date;x-amz-security-token"
            : "content-type;host;x-amz-date"

        var canonicalHeaders = "content-type:\(contentType)\nhost:\(host)\nx-amz-date:\(amzDate)\n"
        if hasSessionToken {
            canonicalHeaders += "x-amz-security-token:\(credentials.sessionToken!)\n"
        }

        let canonicalRequest = "POST\n/\n\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"

        // Create string to sign
        let credentialScope = "\(dateStamp)/\(region)/\(service)/\(awsRequest)"
        let canonicalRequestHash = sha256Hex(canonicalRequest)
        let stringToSign = "\(algorithm)\n\(amzDate)\n\(credentialScope)\n\(canonicalRequestHash)"

        // Calculate signing key and signature
        let signingKey = deriveSigningKey(
            secretKey: credentials.secretAccessKey,
            dateStamp: dateStamp,
            region: region,
            service: service
        )
        let signature = hmacSHA256Hex(stringToSign, key: signingKey)

        // Build authorization header
        let authorization = "\(algorithm) Credential=\(credentials.accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        // Create HTTP request
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        // Add session token header if using temporary credentials
        if let sessionToken = credentials.sessionToken, !sessionToken.isEmpty {
            request.setValue(sessionToken, forHTTPHeaderField: "X-Amz-Security-Token")
        }

        request.httpBody = requestBody.data(using: .utf8)
        request.timeoutInterval = requestTimeout

        // Execute request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AWSSTSClientError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let responseString = String(data: data, encoding: .utf8) ?? ""
            let errorMessage = parseErrorFromXML(responseString) ?? "AssumeRole request failed"

            log.error("STS AssumeRole failed: \(errorMessage)")

            if httpResponse.statusCode == 403 {
                throw AWSSTSClientError.accessDenied
            }
            throw AWSSTSClientError.invalidResponse
        }

        // Parse response
        let responseString = String(data: data, encoding: .utf8) ?? ""
        return try parseAssumeRoleResponse(responseString)
    }

    // MARK: - Role Assumption (Synchronous for Obj-C compatibility)

    /// Synchronous version for Objective-C callers - runs async code on a background queue.
    ///
    /// - Warning: This method blocks the calling thread using a semaphore.
    ///   **Do not call from the main thread** as it may cause UI freezes or deadlocks.
    ///   This method is designed to be called from background threads (e.g., connection threads).
    ///
    /// - Parameters:
    ///   - roleArn: The ARN of the role to assume
    ///   - roleSessionName: Optional session name (auto-generated if nil)
    ///   - mfaSerialNumber: Optional MFA device serial number
    ///   - mfaTokenCode: MFA token code (required if mfaSerialNumber is provided)
    ///   - durationSeconds: Session duration (900-43200 seconds, default 3600)
    ///   - region: AWS region for the STS endpoint
    ///   - credentials: Base credentials to use for the AssumeRole call
    ///   - error: Error pointer for Objective-C error handling
    /// - Returns: Temporary credentials from STS, or nil on failure
    @objc static func assumeRole(
        _ roleArn: String,
        roleSessionName: String?,
        mfaSerialNumber: String?,
        mfaTokenCode: String?,
        durationSeconds: Int,
        region: String,
        credentials: AWSCredentials,
        error: NSErrorPointer
    ) -> AWSCredentials? {
        // Warn if called from main thread - this could cause UI freezes
        if Thread.isMainThread {
            os_log(.error, log: log, "assumeRole called from main thread - this may cause UI freezes. Call from a background thread instead.")
            assertionFailure("AWSSTSClient.assumeRole should not be called from the main thread")
        }

        var result: AWSCredentials?
        var asyncError: Error?

        let semaphore = DispatchSemaphore(value: 0)

        // Run async code on a background queue
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                do {
                    result = try await assumeRole(
                        roleArn: roleArn,
                        roleSessionName: roleSessionName,
                        mfaSerialNumber: mfaSerialNumber,
                        mfaTokenCode: mfaTokenCode,
                        durationSeconds: durationSeconds,
                        region: region,
                        credentials: credentials
                    )
                } catch {
                    asyncError = error
                }
                semaphore.signal()
            }
        }

        // Wait with timeout (blocks current thread)
        let waitResult = semaphore.wait(timeout: .now() + requestTimeout + 5)

        if waitResult == .timedOut {
            error?.pointee = NSError(
                domain: "AWSSTSClientErrorDomain",
                code: AWSSTSClientError.requestTimeout.rawValue,
                userInfo: [NSLocalizedDescriptionKey: AWSSTSClientError.requestTimeout.localizedDescription]
            )
            return nil
        }

        if let asyncError = asyncError {
            if let stsError = asyncError as? AWSSTSClientError {
                error?.pointee = NSError(
                    domain: "AWSSTSClientErrorDomain",
                    code: stsError.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: stsError.localizedDescription]
                )
            } else {
                error?.pointee = asyncError as NSError
            }
            return nil
        }

        return result
    }

    /// Convenience method for MFA role assumption.
    ///
    /// - Warning: This method blocks the calling thread. **Do not call from the main thread.**
    ///   See `assumeRole(_:roleSessionName:mfaSerialNumber:mfaTokenCode:durationSeconds:region:credentials:error:)`
    ///   for details.
    @objc static func assumeRoleWithMFA(
        _ roleArn: String,
        mfaSerialNumber: String,
        mfaTokenCode: String,
        region: String,
        credentials: AWSCredentials,
        error: NSErrorPointer
    ) -> AWSCredentials? {
        // Main thread check is done in assumeRole
        return assumeRole(
            roleArn,
            roleSessionName: nil,
            mfaSerialNumber: mfaSerialNumber,
            mfaTokenCode: mfaTokenCode,
            durationSeconds: defaultSessionDuration,
            region: region,
            credentials: credentials,
            error: error
        )
    }

    // MARK: - XML Parsing

    private static func parseAssumeRoleResponse(_ xmlString: String) throws -> AWSCredentials {
        // Use XMLParser for robust parsing
        let parser = STSResponseParser(xmlString: xmlString)

        guard let result = parser.parse(),
              let accessKeyId = result.accessKeyId, !accessKeyId.isEmpty,
              let secretAccessKey = result.secretAccessKey, !secretAccessKey.isEmpty else {
            log.error("Failed to parse credentials from STS response")
            throw AWSSTSClientError.invalidResponse
        }

        return AWSCredentials(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            sessionToken: result.sessionToken
        )
    }

    private static func parseErrorFromXML(_ xml: String) -> String? {
        // Try to extract error message
        if let message = extractValue(for: "Message", from: xml) {
            return message
        }
        if let code = extractValue(for: "Code", from: xml) {
            return "AWS Error: \(code)"
        }
        return nil
    }

    private static func extractValue(for tag: String, from xml: String) -> String? {
        let openTag = "<\(tag)>"
        let closeTag = "</\(tag)>"

        guard let openRange = xml.range(of: openTag),
              let closeRange = xml.range(of: closeTag, range: openRange.upperBound..<xml.endIndex) else {
            return nil
        }

        return String(xml[openRange.upperBound..<closeRange.lowerBound])
    }

    // MARK: - Query String Building

    private static func buildQueryString(from params: [String: String]) -> String {
        params.keys.sorted()
            .map { key in "\(urlEncode(key))=\(urlEncode(params[key]!))" }
            .joined(separator: "&")
    }

    // MARK: - AWS Signature V4 Helper Methods

    private static func deriveSigningKey(secretKey: String, dateStamp: String, region: String, service: String) -> Data {
        let kSecret = "AWS4\(secretKey)".data(using: .utf8)!
        let kDate = hmacSHA256(dateStamp.data(using: .utf8)!, key: kSecret)
        let kRegion = hmacSHA256(region.data(using: .utf8)!, key: kDate)
        let kService = hmacSHA256(service.data(using: .utf8)!, key: kRegion)
        let kSigning = hmacSHA256(awsRequest.data(using: .utf8)!, key: kService)
        return kSigning
    }

    private static func hmacSHA256(_ data: Data, key: Data) -> Data {
        var result = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { dataPtr in
            key.withUnsafeBytes { keyPtr in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA256),
                    keyPtr.baseAddress,
                    key.count,
                    dataPtr.baseAddress,
                    data.count,
                    &result
                )
            }
        }
        return Data(result)
    }

    private static func hmacSHA256Hex(_ string: String, key: Data) -> String {
        let data = string.data(using: .utf8)!
        let hmac = hmacSHA256(data, key: key)
        return hexEncode(hmac)
    }

    private static func sha256Hex(_ string: String) -> String {
        let data = string.data(using: .utf8)!
        var result = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &result)
        }
        return hexEncode(Data(result))
    }

    private static func hexEncode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func urlEncode(_ string: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}

// MARK: - STS Response Parser

/// XMLParser delegate for parsing STS AssumeRole responses
private class STSResponseParser: NSObject, XMLParserDelegate {
    private let xmlString: String
    private var currentElement = ""
    private var currentValue = ""

    var accessKeyId: String?
    var secretAccessKey: String?
    var sessionToken: String?
    var expiration: String?

    private var inCredentials = false

    init(xmlString: String) {
        self.xmlString = xmlString
        super.init()
    }

    func parse() -> STSResponseParser? {
        guard let data = xmlString.data(using: .utf8) else { return nil }

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false

        return parser.parse() ? self : nil
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentValue = ""

        if elementName == "Credentials" {
            inCredentials = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let trimmedValue = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if inCredentials {
            switch elementName {
            case "AccessKeyId":
                accessKeyId = trimmedValue
            case "SecretAccessKey":
                secretAccessKey = trimmedValue
            case "SessionToken":
                sessionToken = trimmedValue
            case "Expiration":
                expiration = trimmedValue
            case "Credentials":
                inCredentials = false
            default:
                break
            }
        }

        currentElement = ""
        currentValue = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        // Log parse error but don't fail completely - we might still have partial data
        let log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "AWSSTSClient")
        log.error("XML parse error: \(parseError.localizedDescription)")
    }
}
