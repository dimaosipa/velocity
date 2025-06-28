import Foundation
import VeloSystem

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
    
    // MARK: - Simple Download
    
    private func simpleDownload(
        url: URL,
        destination: URL,
        expectedSHA256: String?,
        progress: DownloadProgress?
    ) async throws {
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
        
        // Download chunks in parallel
        let downloadGroup = DispatchGroup()
        let progressQueue = DispatchQueue(label: "com.velo.download.progress")
        var totalDownloaded: Int64 = 0
        var downloadError: Error?
        
        let semaphore = DispatchSemaphore(value: maxConcurrentStreams)
        
        for (index, chunk) in chunks.enumerated() {
            downloadGroup.enter()
            
            Task {
                defer { downloadGroup.leave() }
                
                await withCheckedContinuation { continuation in
                    semaphore.wait()
                    defer { semaphore.signal() }
                    
                    Task {
                        do {
                            let chunkFile = tempDir.appendingPathComponent("chunk_\(index)")
                            try await downloadChunk(
                                url: url,
                                range: chunk,
                                to: chunkFile
                            )
                            
                            progressQueue.sync {
                                totalDownloaded += (chunk.upperBound - chunk.lowerBound + 1)
                                progress?.downloadDidUpdate(
                                    bytesDownloaded: totalDownloaded,
                                    totalBytes: fileSize
                                )
                            }
                        } catch {
                            progressQueue.sync {
                                downloadError = error
                            }
                        }
                        continuation.resume()
                    }
                }
            }
        }
        
        // Wait for all chunks
        await withCheckedContinuation { continuation in
            downloadGroup.notify(queue: .global()) {
                continuation.resume()
            }
        }
        
        if let error = downloadError {
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