import Foundation
import ArgumentParser
import VeloSystem

public struct Velo: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "velo",
        abstract: "A fast, modern package manager for macOS",
        version: "0.1.0",
        subcommands: [
            Velo.Init.self,
            Velo.Install.self,
            Velo.Uninstall.self,
            Velo.Switch.self,
            Velo.Exec.self,
            Velo.Which.self,
            Velo.Info.self,
            Velo.List.self,
            Velo.Search.self,
            Velo.Update.self,
            Velo.UpdateSelf.self,
            Velo.Verify.self,
            Velo.Repair.self,
            Velo.Doctor.self,
            Velo.Clean.self,
            Velo.Tap.self,
            Velo.InstallSelf.self,
            Velo.UninstallSelf.self
        ],
        defaultSubcommand: Velo.Doctor.self
    )

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose = false

    @Flag(name: .long, help: "Disable colored output")
    var noColor = false

    @Flag(name: .long, help: "Enable quiet mode (minimal output)")
    var quiet = false

    public init() {}

    private func setupLogging() {
        // Note: OSLogger uses environment variable VELO_LOG_LEVEL for configuration
        // CLI flags are maintained for compatibility but OSLogger handles the actual logging
        // No additional setup needed as OSLogger.shared is configured automatically
    }
}
