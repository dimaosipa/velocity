import XCTest
import Foundation
@testable import VeloCore
@testable import VeloSystem

final class BottleDownloaderTests: XCTestCase {
    var downloader: BottleDownloader!
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        downloader = BottleDownloader(maxConcurrentStreams: 2, chunkSize: 1024) // Small chunks for testing
        
        // Create temporary directory
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("velo_downloader_test_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }
    
    // MARK: - Mock Server Tests
    
    func testSimpleDownload() async throws {
        // Create a test file to "download"
        let testContent = "Hello, Velo!"
        let testFile = tempDirectory.appendingPathComponent("test_source.txt")
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)
        
        let destination = tempDirectory.appendingPathComponent("downloaded.txt")
        let progress = MockProgress()
        
        // Download using file:// URL (local file system)
        try await downloader.download(
            from: testFile.absoluteString,
            to: destination,
            progress: progress
        )
        
        // Verify download
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        let downloadedContent = try String(contentsOf: destination)
        XCTAssertEqual(downloadedContent, testContent)
        
        // Verify progress callbacks
        XCTAssertTrue(progress.didStart)
        XCTAssertTrue(progress.didComplete)
    }
    
    func testDownloadWithSHA256Verification() async throws {
        let testContent = "Test content for SHA256"
        let testFile = tempDirectory.appendingPathComponent("test_sha.txt")
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)
        
        // Calculate expected SHA256
        let expectedSHA256 = try computeSHA256(of: testFile)
        
        let destination = tempDirectory.appendingPathComponent("downloaded_sha.txt")
        
        // Download with correct SHA256
        try await downloader.download(
            from: testFile.absoluteString,
            to: destination,
            expectedSHA256: expectedSHA256
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }
    
    func testDownloadWithIncorrectSHA256() async throws {
        let testContent = "Test content"
        let testFile = tempDirectory.appendingPathComponent("test_bad_sha.txt")
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)
        
        let destination = tempDirectory.appendingPathComponent("downloaded_bad_sha.txt")
        let incorrectSHA256 = "1234567890123456789012345678901234567890123456789012345678901234"
        
        // Should throw checksum mismatch error
        await XCTAssertThrowsErrorAsync {
            try await self.downloader.download(
                from: testFile.absoluteString,
                to: destination,
                expectedSHA256: incorrectSHA256
            )
        }
        
        // File should be cleaned up on failure
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
    
    func testDownloadNonexistentFile() async {
        let destination = tempDirectory.appendingPathComponent("nonexistent.txt")
        
        await XCTAssertThrowsErrorAsync {
            try await self.downloader.download(
                from: "file:///nonexistent/path/file.txt",
                to: destination
            )
        }
    }
    
    func testDownloadInvalidURL() async {
        let destination = tempDirectory.appendingPathComponent("invalid.txt")
        
        await XCTAssertThrowsErrorAsync {
            try await self.downloader.download(
                from: "not-a-valid-url",
                to: destination
            )
        }
    }
    
    // MARK: - Performance Tests
    
    func testDownloadPerformance() async throws {
        // Create a larger test file
        let largeContent = String(repeating: "This is test content for performance testing. ", count: 1000)
        let testFile = tempDirectory.appendingPathComponent("large_test.txt")
        try largeContent.write(to: testFile, atomically: true, encoding: .utf8)
        
        let destination = tempDirectory.appendingPathComponent("large_downloaded.txt")
        
        await measureAsync {
            try await self.downloader.download(
                from: testFile.absoluteString,
                to: destination
            )
        }
        
        // Verify the download worked
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        let downloadedContent = try String(contentsOf: destination)
        XCTAssertEqual(downloadedContent, largeContent)
    }
    
    // MARK: - Helper Methods
    
    private func computeSHA256(of file: URL) throws -> String {
        let data = try Data(contentsOf: file)
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Mock Progress Handler

private class MockProgress: DownloadProgress {
    var didStart = false
    var didComplete = false
    var didFail = false
    var updateCount = 0
    
    func downloadDidStart(url: String, totalSize: Int64?) {
        didStart = true
    }
    
    func downloadDidUpdate(bytesDownloaded: Int64, totalBytes: Int64?) {
        updateCount += 1
    }
    
    func downloadDidComplete(url: String) {
        didComplete = true
    }
    
    func downloadDidFail(url: String, error: Error) {
        didFail = true
    }
}

// MARK: - Test Utilities in TestUtilities.swift

// MARK: - SHA256 for Testing

import CryptoKit

private extension SHA256 {
    static func hash(data: Data) -> SHA256.Digest {
        return CryptoKit.SHA256.hash(data: data)
    }
}