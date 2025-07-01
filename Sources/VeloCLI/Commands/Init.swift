import Foundation
import ArgumentParser
import VeloCore
import VeloSystem

extension Velo {
    struct Init: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Initialize a new velo.json file in the current directory"
        )

        @Flag(help: "Skip interactive prompts and use defaults")
        var yes = false

        func run() throws {
            try runAsyncAndWait {
                try await self.runAsync()
            }
        }

        private func runAsync() async throws {
            let fileManager = FileManager.default
            let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            let manifestPath = currentDir.appendingPathComponent("velo.json")

            // Check if velo.json already exists
            if fileManager.fileExists(atPath: manifestPath.path) {
                OSLogger.shared.error("velo.json already exists in the current directory")

                if !yes {
                    print("Overwrite? [y/N]: ", terminator: "")
                    let input = readLine()?.lowercased()
                    if input != "y" && input != "yes" {
                        return
                    }
                }
            }

            let manifestManager = VeloManifestManager()

            if yes {
                // Use defaults
                let manifest = VeloManifest(dependencies: [:])

                try manifestManager.write(manifest, to: manifestPath)
                OSLogger.shared.success("Created velo.json with default values")
            } else {
                // Interactive mode
                try manifestManager.createInteractive(at: manifestPath)
            }

            // Create .velo directory
            let localVeloPath = currentDir.appendingPathComponent(".velo")
            if !fileManager.fileExists(atPath: localVeloPath.path) {
                OSLogger.shared.info("Creating .velo directory...")
                let localPathHelper = PathHelper(customHome: localVeloPath)
                try localPathHelper.ensureVeloDirectories()
                OSLogger.shared.success("Created .velo directory structure")
            }

            // Add .velo to .gitignore if it exists
            let gitignorePath = currentDir.appendingPathComponent(".gitignore")
            if fileManager.fileExists(atPath: gitignorePath.path) {
                var gitignoreContent = try String(contentsOf: gitignorePath)

                if !gitignoreContent.contains(".velo") {
                    if !gitignoreContent.hasSuffix("\n") && !gitignoreContent.isEmpty {
                        gitignoreContent += "\n"
                    }
                    gitignoreContent += "\n# Velo local packages\n.velo/\n"

                    try gitignoreContent.write(to: gitignorePath, atomically: true, encoding: .utf8)
                    OSLogger.shared.info("Added .velo to .gitignore")
                }
            }

            print("\n✅ Project initialized successfully!")
            print("\nNext steps:")
            print("  1. Add dependencies: velo install <package>")
            print("  2. Install from velo.json: velo install")
            print("  3. Run local binaries: velo exec <command>")
        }
    }
}
