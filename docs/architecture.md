# Architecture

## Module Structure

- **VeloSystem**: Core utilities (Logger, Paths, Errors)
- **VeloFormula**: Ruby formula parsing
- **VeloCore**: Downloads, installs, caching
- **VeloCLI**: Command-line interface

## Key Components

- FormulaParser: Swift-native Ruby formula parsing
- BottleDownloader: Parallel downloads, SHA256 verification
- FormulaCache: Binary cache, memory+disk layers
- PerformanceOptimizer: CPU, memory, and network optimization

See [Performance](./usage.md#performance-features) for more details.
