import Foundation
import ArgumentParser
import VeloCore
import VeloSystem

extension Velo {
    struct Which: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show which version of a command will be executed"
        )

        @Argument(help: "The command to locate")
        var command: String

        @Flag(name: .shortAndLong, help: "Show all matching executables in order of precedence")
        var all = false

        func run() throws {
            // Use a simple blocking approach for async operations
            let group = DispatchGroup()
            var result: Result<Void, Error>?

            group.enter()
            Task {
                do {
                    try await self.runAsync()
                    result = .success(())
                } catch {
                    result = .failure(error)
                }
                group.leave()
            }

            group.wait()
            try result?.get()
        }

        private func runAsync() async throws {
            let context = ProjectContext()
            let resolver = PathResolver()

            let result = resolver.which(command, context: context)

            if result.matches.isEmpty {
                logError("\(command): not found")
                throw ExitCode.failure
            }

            if all {
                // Show all matches in order of precedence
                print("Matches for '\(command)' in order of precedence:")
                for (index, match) in result.matches.enumerated() {
                    let marker = match.isDefault ? " (default)" : ""
                    let versionInfo = match.version.map { " [\($0)]" } ?? ""
                    let scopeInfo = "(\(match.scope))"

                    print("\(index + 1). \(match.path.path)\(versionInfo) \(scopeInfo)\(marker)")
                }
            } else {
                // Show only the default match
                if let defaultMatch = result.defaultMatch {
                    print(defaultMatch.path.path)

                    // Show additional info if available
                    if let version = defaultMatch.version {
                        print("Version: \(version)")
                    }
                    print("Scope: \(defaultMatch.scope)")
                } else {
                    // Shouldn't happen if matches exist, but handle gracefully
                    print(result.matches.first!.path.path)
                }
            }

            // If in project context, show helpful info
            if context.isProjectContext && result.matches.first?.scope != .local {
                print("\nNote: No local version found. Install with: velo install \(command) --save")
            }
        }
    }
}
