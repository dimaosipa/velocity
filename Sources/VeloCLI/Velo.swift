import Foundation
import ArgumentParser
import VeloSystem

@main
public struct Velo: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "velo",
        abstract: "A fast, modern package manager for macOS",
        version: "0.1.0",
        subcommands: [
            Install.self,
            Uninstall.self,
            Info.self,
            List.self,
            Search.self,
            Update.self,
            Doctor.self
        ],
        defaultSubcommand: Install.self
    )
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose = false
    
    @Flag(name: .long, help: "Disable colored output")
    var noColor = false
    
    @Flag(name: .long, help: "Enable quiet mode (minimal output)")
    var quiet = false
    
    public init() {}
    
    public mutating func run() throws {
        setupLogging()
    }
    
    private func setupLogging() {
        let logger = Logger.shared
        
        if quiet {
            logger.logLevel = .error
        } else if verbose {
            logger.logLevel = .verbose
        } else {
            logger.logLevel = .info
        }
        
        logger.enableColors = !noColor
        logger.enableTimestamps = verbose
        
        // Set up log file
        let logPath = PathHelper.shared.logsPath.appendingPathComponent("velo.log").path
        try? logger.setLogFile(logPath)
    }
}