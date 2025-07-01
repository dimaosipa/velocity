import Foundation
import VeloSystem

/// Actor to safely manage download progress across concurrent tasks
actor DownloadProgressActor {
    private var totalDownloaded: Int64 = 0
    private var error: Error?

    func addProgress(_ bytes: Int64) {
        totalDownloaded += bytes
    }

    func getTotalDownloaded() -> Int64 {
        return totalDownloaded
    }

    func setError(_ error: Error) {
        if self.error == nil { // Only set the first error
            self.error = error
        }
    }

    func getError() -> Error? {
        return error
    }
}

public protocol DownloadProgress {
    func downloadDidStart(url: String, totalSize: Int64?)
    func downloadDidUpdate(bytesDownloaded: Int64, totalBytes: Int64?)
    func downloadDidComplete(url: String)
    func downloadDidFail(url: String, error: Error)
}

public final class BottleDownloader {
    private let session: URLSession
    private let maxConcurrentStreams: Int
    private let chunkSize: Int64

    public init(maxConcurrentStreams: Int = 8, chunkSize: Int64 = 1024 * 1024) { // 1MB chunks
        self.maxConcurrentStreams = maxConcurrentStreams
        self.chunkSize = chunkSize

        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = maxConcurrentStreams
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true

        self.session = URLSession(configuration: config)
    }

    public func download(
        from url: String,
        to destination: URL,
        expectedSHA256: String? = nil,
        progress: DownloadProgress? = nil
    ) async throws {
        guard let downloadURL = URL(string: url) else {
            throw VeloError.downloadFailed(url: url, error: URLError(.badURL))
        }

        // For GHCR, we need special handling due to authentication
        if url.contains("ghcr.io") {
            try await downloadFromGHCR(
                url: downloadURL,
                to: destination,
                expectedSHA256: expectedSHA256,
                progress: progress
            )
        } else {
            // Check if we can do range requests
            let supportsRanges = try await checkRangeSupport(url: downloadURL)

            if supportsRanges {
                try await parallelDownload(
                    url: downloadURL,
                    destination: destination,
                    expectedSHA256: expectedSHA256,
                    progress: progress
                )
            } else {
                try await simpleDownload(
                    url: downloadURL,
                    destination: destination,
                    expectedSHA256: expectedSHA256,
                    progress: progress
                )
            }
        }
    }

    // MARK: - Simple Download

    private func simpleDownload(
        url: URL,
        destination: URL,
        expectedSHA256: String?,
        progress: DownloadProgress?
    ) async throws {
        // Create parent directory if needed
        let parentDir = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)

        let (tempURL, response) = try await session.download(from: url)

        let totalSize = response.expectedContentLength
        progress?.downloadDidStart(url: url.absoluteString, totalSize: totalSize > 0 ? totalSize : nil)

        // Move to destination
        try FileManager.default.moveItem(at: tempURL, to: destination)

        // Verify checksum if provided
        if let expectedSHA256 = expectedSHA256 {
            let actualSHA256 = try computeSHA256(of: destination)
            if actualSHA256 != expectedSHA256 {
                try? FileManager.default.removeItem(at: destination)
                throw VeloError.checksumMismatch(expected: expectedSHA256, actual: actualSHA256)
            }
        }

        progress?.downloadDidComplete(url: url.absoluteString)
    }

    // MARK: - Parallel Download

    private func parallelDownload(
        url: URL,
        destination: URL,
        expectedSHA256: String?,
        progress: DownloadProgress?
    ) async throws {
        // Get file size
        let fileSize = try await getFileSize(url: url)
        progress?.downloadDidStart(url: url.absoluteString, totalSize: fileSize)

        // Calculate chunks
        let chunks = calculateChunks(totalSize: fileSize, chunkSize: chunkSize)

        // Create temporary directory for chunks
        let tempDir = PathHelper.shared.temporaryFile(prefix: "download")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Download chunks in parallel with limited concurrency
        let progressActor = DownloadProgressActor()

        // Process chunks in batches to limit concurrency
        let batchSize = maxConcurrentStreams
        let indexedChunks = Array(chunks.enumerated())
        let chunkedIndices = indexedChunks.chunked(into: batchSize)

        for batch in chunkedIndices {
            await withTaskGroup(of: Void.self) { group in
                for (index, chunk) in batch {
                    group.addTask {
                        do {
                            let chunkFile = tempDir.appendingPathComponent("chunk_\(index)")
                            try await self.downloadChunk(
                                url: url,
                                range: chunk,
                                to: chunkFile
                            )

                            await progressActor.addProgress(chunk.upperBound - chunk.lowerBound + 1)
                            let totalDownloaded = await progressActor.getTotalDownloaded()
                            progress?.downloadDidUpdate(
                                bytesDownloaded: totalDownloaded,
                                totalBytes: fileSize
                            )
                        } catch {
                            await progressActor.setError(error)
                        }
                    }
                }
            }
        }

        if let error = await progressActor.getError() {
            throw VeloError.downloadFailed(url: url.absoluteString, error: error)
        }

        // Combine chunks
        try combineChunks(from: tempDir, to: destination, chunkCount: chunks.count)

        // Verify checksum
        if let expectedSHA256 = expectedSHA256 {
            let actualSHA256 = try computeSHA256(of: destination)
            if actualSHA256 != expectedSHA256 {
                try? FileManager.default.removeItem(at: destination)
                throw VeloError.checksumMismatch(expected: expectedSHA256, actual: actualSHA256)
            }
        }

        progress?.downloadDidComplete(url: url.absoluteString)
    }

    private func downloadChunk(url: URL, range: Range<Int64>, to destination: URL) async throws {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 206 else {
            throw VeloError.downloadFailed(
                url: url.absoluteString,
                error: URLError(.badServerResponse)
            )
        }

        try data.write(to: destination)
    }

    // MARK: - GHCR Download

    private func downloadFromGHCR(
        url: URL,
        to destination: URL,
        expectedSHA256: String?,
        progress: DownloadProgress?
    ) async throws {
        // First, get the authentication token
        var initialRequest = URLRequest(url: url)
        initialRequest.httpMethod = "HEAD"

        let (_, initialResponse) = try await session.data(for: initialRequest)

        guard let httpResponse = initialResponse as? HTTPURLResponse,
              httpResponse.statusCode == 401,
              let authHeader = httpResponse.allHeaderFields["Www-Authenticate"] as? String else {
            // If no auth required, just download normally
            try await simpleDownload(url: url, destination: destination, expectedSHA256: expectedSHA256, progress: progress)
            return
        }

        // Extract token endpoint details
        let components = authHeader.components(separatedBy: ",")
        var realm = ""
        var scope = ""
        var service = ""

        for component in components {
            if component.contains("realm=") {
                realm = component.replacingOccurrences(of: "Bearer realm=", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if component.contains("scope=") {
                scope = component.replacingOccurrences(of: "scope=", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if component.contains("service=") {
                service = component.replacingOccurrences(of: "service=", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        // Get anonymous token
        let tokenURL = "\(realm)?scope=\(scope)&service=\(service)"
        guard let tokenEndpoint = URL(string: tokenURL) else {
            throw VeloError.downloadFailed(url: url.absoluteString, error: URLError(.badURL))
        }

        let (tokenData, _) = try await session.data(from: tokenEndpoint)

        struct TokenResponse: Codable {
            let token: String?
            let accessToken: String?
            let errors: [ErrorResponse]?

            enum CodingKeys: String, CodingKey {
                case token
                case accessToken = "access_token"
                case errors
            }

            var validToken: String? {
                return token ?? accessToken
            }
        }

        struct ErrorResponse: Codable {
            let code: String
            let message: String
        }

        let tokenResponse: TokenResponse
        do {
            tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: tokenData)
        } catch {
            OSLogger.shared.downloadWarning("Failed to parse GHCR token response, attempting direct download")
            try await simpleDownload(url: url, destination: destination, expectedSHA256: expectedSHA256, progress: progress)
            return
        }

        // Check for authentication errors
        if let errors = tokenResponse.errors, !errors.isEmpty {
            // Log the GHCR access issue but don't fail hard - some bottles may not be accessible
            let errorMessages = errors.map { "\($0.code): \($0.message)" }.joined(separator: ", ")
            OSLogger.shared.downloadWarning("GHCR access denied for \(url.absoluteString): \(errorMessages)")
            OSLogger.shared.downloadWarning("Some bottles may not be publicly accessible via GHCR. This is a known limitation.")

            // Throw a more informative error that can be handled gracefully by the caller
            throw VeloError.bottleNotAccessible(
                url: url.absoluteString,
                reason: "GHCR access denied: \(errorMessages)"
            )
        }

        guard let authToken = tokenResponse.validToken else {
            OSLogger.shared.downloadWarning("No valid token received from GHCR, attempting direct download")
            try await simpleDownload(url: url, destination: destination, expectedSHA256: expectedSHA256, progress: progress)
            return
        }

        // Now download with authentication
        var authenticatedRequest = URLRequest(url: url)
        authenticatedRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        // Create parent directory if needed
        let parentDir = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)

        let (tempURL, response) = try await session.download(for: authenticatedRequest)

        let totalSize = response.expectedContentLength
        progress?.downloadDidStart(url: url.absoluteString, totalSize: totalSize > 0 ? totalSize : nil)

        // Move to destination
        try FileManager.default.moveItem(at: tempURL, to: destination)

        // Verify checksum if provided
        if let expectedSHA256 = expectedSHA256 {
            let actualSHA256 = try computeSHA256(of: destination)
            if actualSHA256 != expectedSHA256 {
                try? FileManager.default.removeItem(at: destination)
                throw VeloError.checksumMismatch(expected: expectedSHA256, actual: actualSHA256)
            }
        }

        progress?.downloadDidComplete(url: url.absoluteString)
    }

    // MARK: - Helper Methods

    private func checkRangeSupport(url: URL) async throws -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.allHeaderFields["Accept-Ranges"] as? String == "bytes"
    }

    private func getFileSize(url: URL) async throws -> Int64 {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              let contentLength = httpResponse.allHeaderFields["Content-Length"] as? String,
              let size = Int64(contentLength) else {
            throw VeloError.downloadFailed(
                url: url.absoluteString,
                error: URLError(.badServerResponse)
            )
        }

        return size
    }

    private func calculateChunks(totalSize: Int64, chunkSize: Int64) -> [Range<Int64>] {
        var chunks: [Range<Int64>] = []
        var offset: Int64 = 0

        while offset < totalSize {
            let end = min(offset + chunkSize - 1, totalSize - 1)
            chunks.append(offset..<end)
            offset = end + 1
        }

        return chunks
    }

    private func combineChunks(from directory: URL, to destination: URL, chunkCount: Int) throws {
        guard let outputStream = OutputStream(url: destination, append: false) else {
            throw VeloError.ioError(CocoaError(.fileWriteUnknown))
        }

        outputStream.open()
        defer { outputStream.close() }

        for i in 0..<chunkCount {
            let chunkFile = directory.appendingPathComponent("chunk_\(i)")
            let chunkData = try Data(contentsOf: chunkFile)

            _ = chunkData.withUnsafeBytes { bytes in
                outputStream.write(bytes.bindMemory(to: UInt8.self).baseAddress!, maxLength: chunkData.count)
            }
        }
    }

    private func computeSHA256(of file: URL) throws -> String {
        let bufferSize = 1024 * 1024 // 1MB buffer
        guard let stream = InputStream(url: file) else {
            throw VeloError.ioError(CocoaError(.fileReadUnknown))
        }

        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                hasher.update(data: Data(bytes: buffer, count: bytesRead))
            }
        }

        let digest = hasher.finalize()
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - SHA256 using CryptoKit

import CryptoKit

extension BottleDownloader {
    private struct SHA256 {
        private var hasher = CryptoKit.SHA256()

        mutating func update(data: Data) {
            hasher.update(data: data)
        }

        func finalize() -> CryptoKit.SHA256.Digest {
            return hasher.finalize()
        }
    }
}

// MARK: - Collection Extensions

private extension Collection {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[index(startIndex, offsetBy: $0)..<index(startIndex, offsetBy: Swift.min($0 + size, count))])
        }
    }
}
