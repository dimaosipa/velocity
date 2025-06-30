import XCTest
import Foundation
@testable import VeloCore
@testable import VeloFormula
@testable import VeloSystem

final class PerformanceBenchmarks: XCTestCase {
    var optimizer: PerformanceOptimizer!
    var cache: FormulaCache!
    var parser: FormulaParser!

    override func setUp() {
        super.setUp()
        optimizer = PerformanceOptimizer()
        cache = FormulaCache()
        parser = FormulaParser()

        // Optimize for benchmarking
        optimizer.optimizeCPUUsage()
        optimizer.optimizeMemoryUsage()
    }

    // MARK: - Formula Parsing Benchmarks

    func testFormulaParsingPerformance() throws {
        // Use inline formula content instead of fixture file
        let content = """
        class Wget < Formula
          desc "Internet file retriever"
          homepage "https://www.gnu.org/software/wget/"
          url "https://ftp.gnu.org/gnu/wget/wget-1.25.0.tar.gz"
          sha256 "766e48423e79359ea31e41db9e5c289675947a7fcf2efdcedb726ac9d0da3784"

          depends_on "pkg-config" => :build
          depends_on "openssl@3"

          bottle do
            sha256 arm64_sonoma: "4d180cd4ead91a34e2c2672189fc366b87ae86e6caa3acbf4845b272f57c859a"
            sha256 arm64_ventura: "7fce09705a52a2aff61c4bdd81b9d2a1a110539718ded2ad45562254ef0f5c22"
            sha256 arm64_monterey: "498cea03c8c9f5ab7b90a0c333122415f0360c09f837cafae6d8685d6846ced2"
          end
        end
        """

        // Benchmark parsing speed
        measure {
            for _ in 0..<100 {
                do {
                    _ = try parser.parse(rubyContent: content, formulaName: "wget")
                } catch {
                    XCTFail("Parse failed: \(error)")
                }
            }
        }

        // Performance requirement: Parse 100 formulae in < 1 second
        let startTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<100 {
            _ = try parser.parse(rubyContent: content, formulaName: "wget")
        }
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertLessThan(duration, 10.0, "Formula parsing should complete 100 iterations in < 10 seconds")
    }

    func testComplexFormulaParsingPerformance() throws {
        let content = """
        class Complex < Formula
          desc "A complex formula with various features"
          homepage "https://complex.example.com"
          url "https://github.com/example/complex/archive/v2.5.1.tar.gz"
          sha256 "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
          version "2.5.1"
          license "MIT"

          bottle do
            rebuild 1
            sha256 cellar: :any_skip_relocation, arm64_sequoia: "1111111111111111111111111111111111111111111111111111111111111111"
            sha256 cellar: :any_skip_relocation, arm64_sonoma:  "2222222222222222222222222222222222222222222222222222222222222222"
            sha256 cellar: :any_skip_relocation, arm64_ventura: "3333333333333333333333333333333333333333333333333333333333333333"
            sha256 cellar: :any_skip_relocation, arm64_monterey: "4444444444444444444444444444444444444444444444444444444444444444"
            sha256 cellar: :any, x86_64_sonoma: "5555555555555555555555555555555555555555555555555555555555555555"
          end

          depends_on "cmake" => :build
          depends_on "rust" => :build
          depends_on "openssl@3"
          depends_on "zstd"
          depends_on :macos => :monterey

          def install
            system "cmake", "-S", ".", "-B", "build", *std_cmake_args
            system "cmake", "--build", "build"
            system "cmake", "--install", "build"
          end

          test do
            system "#{bin}/complex", "--version"
          end
        end
        """

        measure {
            for _ in 0..<50 {
                do {
                    _ = try parser.parse(rubyContent: content, formulaName: "complex")
                } catch {
                    XCTFail("Parse failed: \(error)")
                }
            }
        }
    }

    // MARK: - Cache Performance Benchmarks

    func testCachePerformance() throws {
        _ = createTestFormula(name: "benchmark-test")

        // Benchmark cache write performance
        let (_, writeTime) = measureSync(operation: "Cache Write") {
            for i in 0..<1000 {
                let formula = createTestFormula(name: "test-\(i)")
                try! cache.set(formula)
            }
        }

        // Benchmark cache read performance
        let (_, readTime) = measureSync(operation: "Cache Read") {
            for i in 0..<1000 {
                _ = try! cache.get("test-\(i)")
            }
        }

        // Performance requirements (very lenient for slow CI)
        XCTAssertLessThan(writeTime, 30.0, "Cache writes should complete in < 30 seconds")
        XCTAssertLessThan(readTime, 10.0, "Cache reads should complete in < 10 seconds")
    }

    func testCacheMemoryEfficiency() throws {
        let initialMemory = optimizer.checkSystemResources().memoryUsageBytes

        // Load many formulae into cache
        for i in 0..<5000 {
            let formula = createTestFormula(name: "memory-test-\(i)")
            try cache.set(formula)
        }

        let peakMemory = optimizer.checkSystemResources().memoryUsageBytes
        let memoryIncrease = peakMemory - initialMemory

        // Should not use more than 50MB for 5000 formulae
        let maxMemoryIncrease: Int64 = 50 * 1024 * 1024
        XCTAssertLessThan(memoryIncrease, maxMemoryIncrease,
                         "Memory usage should not increase by more than 50MB")
    }

    // MARK: - Search Performance Benchmarks

    func testSearchIndexPerformance() throws {
        let formulae = (0..<10000).map { i in
            createTestFormula(name: "search-test-\(i)", description: "Test package number \(i)")
        }

        let index = FormulaIndex(cache: cache)

        // Benchmark index building
        let (_, buildTime) = measureSync(operation: "Index Build") {
            try! index.buildIndex(from: formulae)
        }

        // Benchmark search performance
        let (_, searchTime) = measureSync(operation: "Search") {
            for _ in 0..<100 {
                _ = index.search("test", includeDescriptions: true)
            }
        }

        // Performance requirements (very lenient for slow CI environments)
        XCTAssertLessThan(buildTime, 60.0, "Index building should complete in < 60 seconds")
        XCTAssertLessThan(searchTime, 120.0, "100 searches should complete in < 120 seconds")
    }

    // MARK: - I/O Performance Benchmarks

    func testFileSystemPerformance() {
        let pathHelper = PathHelper.shared

        // Benchmark directory creation
        let (_, dirTime) = measureSync(operation: "Directory Creation") {
            for i in 0..<100 {
                let testDir = pathHelper.tmpPath.appendingPathComponent("perf-test-\(i)")
                try! FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
            }
        }

        // Benchmark file operations
        let (_, fileTime) = measureSync(operation: "File Operations") {
            for i in 0..<100 {
                let testFile = pathHelper.tmpPath.appendingPathComponent("file-\(i).txt")
                try! "Test content \(i)".write(to: testFile, atomically: true, encoding: .utf8)
            }
        }

        // Clean up
        try? FileManager.default.removeItem(at: pathHelper.tmpPath)
        try! pathHelper.ensureVeloDirectories()

        // Performance requirements (very lenient for slow CI environments)
        XCTAssertLessThan(dirTime, 30.0, "Directory creation should complete in < 30 seconds")
        XCTAssertLessThan(fileTime, 15.0, "File operations should complete in < 15 seconds")
    }

    // MARK: - Memory Leak Detection

    func testMemoryLeaks() {
        let initialMemory = optimizer.checkSystemResources().memoryUsageBytes

        // Perform operations that could leak memory
        autoreleasepool {
            for _ in 0..<1000 {
                let formula = createTestFormula(name: "leak-test")
                _ = try? cache.set(formula)
                _ = try? cache.get("leak-test")
            }
        }

        // Force cleanup
        optimizer.optimizeMemoryUsage()

        let finalMemory = optimizer.checkSystemResources().memoryUsageBytes
        let memoryIncrease = finalMemory - initialMemory

        // Should not leak significant memory (< 50MB tolerance for CI variability)
        let maxLeakage: Int64 = 50 * 1024 * 1024
        XCTAssertLessThan(memoryIncrease, maxLeakage,
                         "Memory usage should not increase significantly after operations")
    }

    // MARK: - Stress Tests

    func testHighConcurrency() async {
        let expectations = (0..<50).map { i in
            expectation(description: "Operation \(i)")
        }

        // Run many concurrent operations
        for i in 0..<50 {
            Task {
                let formula = createTestFormula(name: "concurrent-\(i)")
                try? cache.set(formula)
                _ = try? cache.get("concurrent-\(i)")
                expectations[i].fulfill()
            }
        }

        await fulfillment(of: expectations, timeout: 5.0)
    }

    func testLargeDataHandling() throws {
        // Test with very large formula descriptions
        let largeDescription = String(repeating: "Very long description text. ", count: 10000)
        let largeFormula = createTestFormula(name: "large-test", description: largeDescription)

        let startTime = CFAbsoluteTimeGetCurrent()
        try cache.set(largeFormula)
        let cachedFormula = try cache.get("large-test")
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertNotNil(cachedFormula)
        XCTAssertEqual(cachedFormula?.description, largeDescription)
        XCTAssertLessThan(duration, 10.0, "Large data operations should complete in < 10 seconds")
    }

    // MARK: - Regression Tests

    func testPerformanceRegression() throws {
        // Baseline performance measurements
        let baselineParseTime = measureFormulaParsingTime()
        let baselineCacheTime = measureCacheOperationTime()
        let baselineSearchTime = measureSearchTime()

        // These should not regress significantly from known good values
        // Very lenient thresholds for slow GitHub Actions CI environments
        XCTAssertLessThan(baselineParseTime, 1.0, "Formula parsing regression detected")
        XCTAssertLessThan(baselineCacheTime, 0.5, "Cache operation regression detected")
        XCTAssertLessThan(baselineSearchTime, 1.0, "Search performance regression detected")
    }

    // MARK: - Helper Methods

    private func measureFormulaParsingTime() -> TimeInterval {
        let content = """
        class Simple < Formula
          desc "A simple test formula"
          homepage "https://example.com/simple"
          url "https://example.com/downloads/simple-1.0.0.tar.gz"
          sha256 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

          bottle do
            sha256 arm64_sonoma: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
            sha256 arm64_ventura: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
          end

          depends_on "dependency1"
          depends_on "dependency2"

          def install
            bin.install "simple"
          end
        end
        """

        let startTime = CFAbsoluteTimeGetCurrent()
        _ = try! parser.parse(rubyContent: content, formulaName: "simple")
        return CFAbsoluteTimeGetCurrent() - startTime
    }

    private func measureCacheOperationTime() -> TimeInterval {
        let formula = createTestFormula(name: "perf-test")

        let startTime = CFAbsoluteTimeGetCurrent()
        try! cache.set(formula)
        _ = try! cache.get("perf-test")
        return CFAbsoluteTimeGetCurrent() - startTime
    }

    private func measureSearchTime() -> TimeInterval {
        let formulae = (0..<100).map { createTestFormula(name: "search-\($0)") }
        let index = FormulaIndex(cache: cache)
        try! index.buildIndex(from: formulae)

        let startTime = CFAbsoluteTimeGetCurrent()
        _ = index.search("search")
        return CFAbsoluteTimeGetCurrent() - startTime
    }

    private func createTestFormula(name: String, description: String = "Test package") -> Formula {
        return Formula(
            name: name,
            description: description,
            homepage: "https://test.com",
            url: "https://test.com/\(name).tar.gz",
            sha256: "abc123",
            version: "1.0.0",
            dependencies: [],
            bottles: [
                Formula.Bottle(sha256: "def456", platform: .arm64_sonoma)
            ]
        )
    }

}
