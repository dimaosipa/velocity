import Foundation
import VeloCLI
import VeloCore
import VeloSystem

// Ensure we're running on Apple Silicon
#if !arch(arm64)
    fatalError("Velo requires Apple Silicon (M1/M2/M3) Macs. Intel Macs are not supported.")
#endif

// Custom argument preprocessing to handle --prefix
func preprocessArguments(_ args: [String]) -> [String] {
    // Check for --prefix flag
    if let prefixIndex = args.firstIndex(of: "--prefix") {
        // Handle --prefix specially
        let context = ProjectContext()

        // Check if there's a formula name after --prefix
        let formulaName: String? = {
            let nextIndex = prefixIndex + 1
            if nextIndex < args.count && !args[nextIndex].hasPrefix("-") {
                return args[nextIndex]
            }
            return nil
        }()

        // Print the prefix and exit
        if let formulaName = formulaName {
            do {
                try printFormulaPrefix(formulaName: formulaName, context: context)
            } catch {
                fputs("Error: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        } else {
            printBasePrefix(context: context)
        }
        exit(0)
    }

    return args
}

func printBasePrefix(context: ProjectContext) {
    if context.isProjectContext {
        // Local context - return local .velo directory
        if let localPath = context.localVeloPath {
            print(localPath.path)
        } else {
            // Fallback to global if somehow local path is nil
            print(PathHelper.shared.veloHome.path)
        }
    } else {
        // Global context - return global Velo home
        print(PathHelper.shared.veloHome.path)
    }
}

func printFormulaPrefix(formulaName: String, context: ProjectContext) throws {
    let pathHelper = context.getPathHelper(preferLocal: context.isProjectContext)

    // Check if formula is installed
    guard pathHelper.isPackageInstalled(formulaName) else {
        throw VeloError.formulaNotFound(name: formulaName)
    }

    // Get installed versions
    let versions = pathHelper.installedVersions(for: formulaName)
    guard let latestVersion = versions.sorted().last else {
        throw VeloError.formulaNotFound(name: formulaName)
    }

    // Return the package directory path
    let packagePath = pathHelper.packagePath(for: formulaName, version: latestVersion)
    print(packagePath.path)
}

// Preprocess command line arguments
let allArgs = Array(CommandLine.arguments)
let processedArgs = preprocessArguments(allArgs)

// Launch the CLI with processed arguments (excluding program name)
if processedArgs.count > 1 {
    Velo.main(Array(processedArgs.dropFirst()))
} else {
    Velo.main()
}
