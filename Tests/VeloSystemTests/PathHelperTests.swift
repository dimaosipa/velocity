import XCTest
@testable import VeloSystem

final class PathHelperTests: XCTestCase {
    var pathHelper: PathHelper!
    var testDirectory: URL!

    override func setUp() {
        super.setUp()
        pathHelper = PathHelper.shared

        // Create a temporary test directory
        testDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("velo_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        // Clean up test directory
        try? FileManager.default.removeItem(at: testDirectory)
        super.tearDown()
    }

    func testBaseDirectories() {
        let home = FileManager.default.homeDirectoryForCurrentUser

        XCTAssertEqual(pathHelper.veloHome.path, home.appendingPathComponent(".velo").path)
        XCTAssertEqual(pathHelper.cellarPath.path, home.appendingPathComponent(".velo/Cellar").path)
        XCTAssertEqual(pathHelper.binPath.path, home.appendingPathComponent(".velo/bin").path)
        XCTAssertEqual(pathHelper.cachePath.path, home.appendingPathComponent(".velo/cache").path)
        XCTAssertEqual(pathHelper.tapsPath.path, home.appendingPathComponent(".velo/taps").path)
        XCTAssertEqual(pathHelper.logsPath.path, home.appendingPathComponent(".velo/logs").path)
        XCTAssertEqual(pathHelper.tmpPath.path, home.appendingPathComponent(".velo/tmp").path)
    }

    func testEnsureDirectoryExists() throws {
        let newDir = testDirectory.appendingPathComponent("new_directory")
        XCTAssertFalse(FileManager.default.fileExists(atPath: newDir.path))

        try pathHelper.ensureDirectoryExists(at: newDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newDir.path))

        // Should not throw if directory already exists
        XCTAssertNoThrow(try pathHelper.ensureDirectoryExists(at: newDir))
    }

    func testPackagePath() {
        let path = pathHelper.packagePath(for: "wget", version: "1.21.3")
        XCTAssertTrue(path.path.contains("Cellar/wget/1.21.3"))
    }

    func testInstalledVersions() {
        // This test would need actual installed packages to work properly
        let versions = pathHelper.installedVersions(for: "nonexistent-package")
        XCTAssertEqual(versions, [])
    }

    func testIsPackageInstalled() {
        // Should return false for non-existent packages
        XCTAssertFalse(pathHelper.isPackageInstalled("nonexistent-package"))
    }

    func testSymlinkPath() {
        let symlinkPath = pathHelper.symlinkPath(for: "wget")
        XCTAssertTrue(symlinkPath.path.contains("bin/wget"))
    }

    func testCacheFile() {
        let cacheFile = pathHelper.cacheFile(for: "formula-index")
        XCTAssertTrue(cacheFile.path.contains("cache/formula-index.velocache"))
        XCTAssertEqual(cacheFile.pathExtension, "velocache")
    }

    func testTemporaryFile() {
        let tmpFile1 = pathHelper.temporaryFile()
        XCTAssertTrue(tmpFile1.path.contains("tmp/velo-"))
        XCTAssertTrue(tmpFile1.lastPathComponent.hasPrefix("velo-"))

        let tmpFile2 = pathHelper.temporaryFile(prefix: "download", extension: "tar.gz")
        XCTAssertTrue(tmpFile2.path.contains("tmp/download-"))
        XCTAssertEqual(tmpFile2.pathExtension, "gz")

        // Ensure unique filenames
        XCTAssertNotEqual(tmpFile1.lastPathComponent, tmpFile2.lastPathComponent)
    }

    func testCreateSymlink() throws {
        let source = testDirectory.appendingPathComponent("source")
        let destination = testDirectory.appendingPathComponent("destination")

        // Create source file
        try "test content".write(to: source, atomically: true, encoding: .utf8)

        // Create symlink
        try pathHelper.createSymlink(from: source, to: destination)

        // Verify symlink exists and points to correct location
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeSymbolicLink)

        // Test overwriting existing symlink
        let newSource = testDirectory.appendingPathComponent("new_source")
        try "new content".write(to: newSource, atomically: true, encoding: .utf8)

        XCTAssertNoThrow(try pathHelper.createSymlink(from: newSource, to: destination))
    }

    func testSizeCalculation() throws {
        let file = testDirectory.appendingPathComponent("test.txt")
        let content = "Hello, Velo!"
        try content.write(to: file, atomically: true, encoding: .utf8)

        let size = try pathHelper.size(of: file)
        XCTAssertEqual(size, Int64(content.utf8.count))
    }

    func testTotalSizeCalculation() throws {
        // Create a directory with some files
        let subDir = testDirectory.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        try "File 1 content".write(to: subDir.appendingPathComponent("file1.txt"), atomically: true, encoding: .utf8)
        try "File 2 content here".write(to: subDir.appendingPathComponent("file2.txt"), atomically: true, encoding: .utf8)

        let totalSize = try pathHelper.totalSize(of: subDir)
        XCTAssertGreaterThan(totalSize, 0)
        XCTAssertEqual(totalSize, Int64("File 1 content".utf8.count + "File 2 content here".utf8.count))
    }

    func testIsInPath() {
        // This test depends on the actual PATH environment
        // For now, just verify it doesn't crash
        _ = pathHelper.isInPath()
        XCTAssertTrue(true)
    }
}
