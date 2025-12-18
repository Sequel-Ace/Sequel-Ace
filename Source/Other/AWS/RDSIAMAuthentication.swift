//
//  RDSIAMAuthentication.swift
//  Sequel Ace
//
//  Created for AWS IAM authentication support.
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

/// Errors that can occur during RDS IAM authentication
@objc enum RDSIAMAuthenticationError: Int, Error, LocalizedError {
    case invalidCredentials
    case invalidParameters
    case tokenGenerationFailed

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return NSLocalizedString("Invalid AWS credentials", comment: "RDS IAM auth error")
        case .invalidParameters:
            return NSLocalizedString("Invalid parameters for IAM authentication", comment: "RDS IAM auth error")
        case .tokenGenerationFailed:
            return NSLocalizedString("Failed to generate IAM authentication token", comment: "RDS IAM auth error")
        }
    }
}

/// Generates RDS IAM authentication tokens using AWS Signature Version 4
@objc final class RDSIAMAuthentication: NSObject {

    // MARK: - Constants

    private static let algorithm = "AWS4-HMAC-SHA256"
    private static let service = "rds-db"
    private static let awsRequest = "aws4_request"
    private static let connectAction = "connect"
    private static let tokenExpirationSeconds = 900 // 15 minutes

    private static let log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "RDSIAMAuth")

    // MARK: - AWS Region Patterns

    /// Extended region pattern supporting newer AWS partitions and multi-digit suffixes
    /// Supports: us, eu, ap, sa, ca, me, af, cn, il, mx, us-gov, us-iso, us-isob
    private static let regionPattern = "^(us|eu|ap|sa|ca|me|af|cn|il|mx|us-gov|us-iso|us-isob)-(east|west|north|south|central|northeast|southeast|northwest|southwest)-[1-9][0-9]?$"

    // MARK: - Token Generation

    /// Generate an IAM authentication token for RDS
    /// - Parameters:
    ///   - hostname: RDS instance hostname
    ///   - port: Database port (defaults to 3306)
    ///   - username: Database username
    ///   - region: AWS region (will attempt to detect from hostname if nil)
    ///   - credentials: AWS credentials to use for signing
    /// - Returns: Authentication token to use as password
    /// - Note: This method throws and is for Swift callers. Use the error pointer version for Obj-C.
    static func generateAuthToken(
        forHost hostname: String,
        port: Int,
        username: String,
        region: String?,
        credentials: AWSCredentials
    ) throws -> String {
        // Validate inputs
        guard credentials.isValid else {
            throw RDSIAMAuthenticationError.invalidCredentials
        }

        guard !hostname.isEmpty else {
            throw RDSIAMAuthenticationError.invalidParameters
        }

        guard !username.isEmpty else {
            throw RDSIAMAuthenticationError.invalidParameters
        }

        // Determine region
        var effectiveRegion = region ?? ""
        if effectiveRegion.isEmpty {
            effectiveRegion = regionFromHostname(hostname) ?? ""
        }

        guard !effectiveRegion.isEmpty else {
            log.error("AWS region is required and could not be determined from hostname")
            throw RDSIAMAuthenticationError.invalidParameters
        }

        // Use port 3306 as default for MySQL
        let effectivePort = port > 0 ? port : 3306

        return buildPresignedToken(
            host: hostname,
            port: effectivePort,
            username: username,
            region: effectiveRegion,
            credentials: credentials
        )
    }

    // MARK: - Token Building

    private static func buildPresignedToken(
        host: String,
        port: Int,
        username: String,
        region: String,
        credentials: AWSCredentials
    ) -> String {
        // Get current time in UTC with POSIX locale for consistent formatting
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        // Format: YYYYMMDD'T'HHMMSS'Z'
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = dateFormatter.string(from: now)

        // Format: YYYYMMDD
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: now)

        // Build the canonical request components
        let hostWithPort = "\(host):\(port)"
        let httpMethod = "GET"
        let canonicalUri = "/"

        // Build credential scope
        let credentialScope = "\(dateStamp)/\(region)/\(service)/\(awsRequest)"

        // URL-encode the database user
        let encodedUsername = urlEncode(username)

        // Build query parameters (must be sorted alphabetically)
        // Alphabetical order: Action, DBUser, X-Amz-Algorithm, X-Amz-Credential, X-Amz-Date, X-Amz-Expires, X-Amz-Security-Token (if present), X-Amz-SignedHeaders
        var queryParams: [(String, String)] = [
            ("Action", connectAction),
            ("DBUser", encodedUsername),
            ("X-Amz-Algorithm", algorithm),
            ("X-Amz-Credential", urlEncode("\(credentials.accessKeyId)/\(credentialScope)")),
            ("X-Amz-Date", amzDate),
            ("X-Amz-Expires", String(tokenExpirationSeconds))
        ]

        // Include session token in query string if present (for temporary credentials)
        if let sessionToken = credentials.sessionToken, !sessionToken.isEmpty {
            queryParams.append(("X-Amz-Security-Token", urlEncode(sessionToken)))
        }

        queryParams.append(("X-Amz-SignedHeaders", "host"))

        let canonicalQueryString = queryParams.map { "\($0.0)=\($0.1)" }.joined(separator: "&")

        // Canonical headers - for RDS, we only include the host header
        let canonicalHeaders = "host:\(hostWithPort)\n"
        let signedHeaders = "host"

        // For RDS IAM auth token (GET request), payload hash is SHA256 of empty string
        let payloadHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

        // Build canonical request
        let canonicalRequest = [
            httpMethod,
            canonicalUri,
            canonicalQueryString,
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        // Create string to sign
        let canonicalRequestHash = sha256Hex(canonicalRequest)
        let stringToSign = [
            algorithm,
            amzDate,
            credentialScope,
            canonicalRequestHash
        ].joined(separator: "\n")

        // Calculate signing key
        let signingKey = deriveSigningKey(
            secretKey: credentials.secretAccessKey,
            dateStamp: dateStamp,
            region: region,
            service: service
        )

        // Calculate signature
        let signature = hmacSHA256Hex(stringToSign, key: signingKey)

        // Build final token (presigned URL format, but without the scheme)
        return "\(hostWithPort)/?Action=\(connectAction)&DBUser=\(encodedUsername)&X-Amz-Algorithm=\(algorithm)&X-Amz-Credential=\(urlEncode("\(credentials.accessKeyId)/\(credentialScope)"))&X-Amz-Date=\(amzDate)&X-Amz-Expires=\(tokenExpirationSeconds)\(credentials.sessionToken != nil ? "&X-Amz-Security-Token=\(urlEncode(credentials.sessionToken!))" : "")&X-Amz-SignedHeaders=host&X-Amz-Signature=\(signature)"
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
        // AWS requires specific URL encoding (RFC 3986)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    // MARK: - Region Detection

    /// Extract AWS region from RDS hostname
    @objc static func regionFromHostname(_ hostname: String) -> String? {
        guard !hostname.isEmpty else { return nil }

        // RDS hostnames typically follow these patterns:
        // - Standard: <identifier>.<account-id>.<region>.rds.amazonaws.com
        // - Aurora: <cluster-identifier>.<random>.<region>.rds.amazonaws.com
        // - Proxy: <proxy-endpoint>.<region>.rds.amazonaws.com

        let components = hostname.components(separatedBy: ".")

        // Find the component that looks like a region
        for component in components {
            if isValidAWSRegion(component) {
                return component
            }
        }

        return nil
    }

    /// Validate if a string is a valid AWS region
    @objc static func isValidAWSRegion(_ string: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: regionPattern, options: .caseInsensitive) else {
            return false
        }
        let range = NSRange(location: 0, length: string.utf16.count)
        return regex.firstMatch(in: string, options: [], range: range) != nil
    }

    /// Check if hostname appears to be an RDS endpoint
    @objc static func isRDSHostname(_ hostname: String) -> Bool {
        guard !hostname.isEmpty else { return false }

        let lowercased = hostname.lowercased()
        return lowercased.hasSuffix(".rds.amazonaws.com") ||
               lowercased.hasSuffix(".rds.amazonaws.com.cn") ||
               lowercased.contains(".rds.")
    }

    /// Token lifetime in seconds
    @objc static var tokenLifetimeSeconds: Int {
        tokenExpirationSeconds
    }
}

// MARK: - Objective-C Compatibility

extension RDSIAMAuthentication {

    /// Objective-C compatible method that returns nil on error
    @objc(generateAuthTokenForHost:port:username:region:credentials:error:)
    static func generateAuthTokenObjC(
        forHost hostname: String,
        port: Int,
        username: String,
        region: String?,
        credentials: AWSCredentials,
        error errorPointer: NSErrorPointer
    ) -> String? {
        do {
            return try generateAuthToken(
                forHost: hostname,
                port: port,
                username: username,
                region: region,
                credentials: credentials
            )
        } catch let authError as RDSIAMAuthenticationError {
            errorPointer?.pointee = NSError(
                domain: "RDSIAMAuthenticationErrorDomain",
                code: authError.rawValue,
                userInfo: [NSLocalizedDescriptionKey: authError.localizedDescription]
            )
            return nil
        } catch let otherError {
            errorPointer?.pointee = otherError as NSError
            return nil
        }
    }
}
