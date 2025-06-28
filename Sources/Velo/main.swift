import Foundation
import VeloCLI

// Ensure we're running on Apple Silicon
#if !arch(arm64)
    fatalError("Velo requires Apple Silicon (M1/M2/M3) Macs. Intel Macs are not supported.")
#endif

// Launch the CLI
Velo.main()