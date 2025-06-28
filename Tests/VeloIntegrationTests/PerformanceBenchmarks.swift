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
        // Load test formula
        let fixtureURL = getFixtureURL("wget.rb")
        let content = try String(contentsOf: fixtureURL)
        
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
        
        XCTAssertLessThan(duration, 1.0, "Formula parsing should complete 100 iterations in < 1 second")
    }
    
    func testComplexFormulaParsingPerformance() throws {
        let fixtureURL = getFixtureURL("complex.rb")
        let content = try String(contentsOf: fixtureURL)
        
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
        let testFormula = createTestFormula(name: "benchmark-test")
        
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
        
        // Performance requirements
        XCTAssertLessThan(writeTime, 2.0, "Cache writes should complete in < 2 seconds")
        XCTAssertLessThan(readTime, 0.5, "Cache reads should complete in < 0.5 seconds")
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
        
        // Performance requirements
        XCTAssertLessThan(buildTime, 5.0, "Index building should complete in < 5 seconds")
        XCTAssertLessThan(searchTime, 0.1, "100 searches should complete in < 0.1 seconds")
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
        
        // Performance requirements (lenient for CI environments)
        XCTAssertLessThan(dirTime, 2.0, "Directory creation should complete in < 2 seconds")
        XCTAssertLessThan(fileTime, 1.0, "File operations should complete in < 1 second")
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
        
        // Should not leak significant memory (< 10MB tolerance)
        let maxLeakage: Int64 = 10 * 1024 * 1024
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
        XCTAssertLessThan(duration, 1.0, "Large data operations should complete in < 1 second")
    }
    
    // MARK: - Regression Tests
    
    func testPerformanceRegression() throws {
        // Baseline performance measurements
        let baselineParseTime = measureFormulaParsingTime()
        let baselineCacheTime = measureCacheOperationTime()
        let baselineSearchTime = measureSearchTime()
        
        // These should not regress significantly from known good values
        // Adjust these baselines based on your system's performance
        XCTAssertLessThan(baselineParseTime, 0.010, "Formula parsing regression detected")
        XCTAssertLessThan(baselineCacheTime, 0.001, "Cache operation regression detected")
        XCTAssertLessThan(baselineSearchTime, 0.005, "Search performance regression detected")
    }
    
    // MARK: - Helper Methods
    
    private func measureFormulaParsingTime() -> TimeInterval {
        let fixtureURL = getFixtureURL("simple.rb")
        let content = try! String(contentsOf: fixtureURL)
        
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
    
    private func getFixtureURL(_ filename: String) -> URL {
        return URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Formulae")
            .appendingPathComponent(filename)
    }
}