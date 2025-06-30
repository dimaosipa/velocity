# Architecture

## Module Structure

- VeloSystem    # Core utilities (Logger, Paths, Errors)
- VeloFormula   # Ruby formula parsing
- VeloCore      # Downloads, installs, caching
- VeloCLI       # Command-line interface

## Key Components

- **FormulaParser**: Swift-native Ruby formula parsing with regex optimization
- **BottleDownloader**: Multi-stream parallel downloads with SHA256 verification
- **FormulaCache**: Binary cache with memory + disk layers for fast lookups
- **PerformanceOptimizer**: CPU, memory, and network optimization framework

See [Performance](./usage.md#performance-features) for more details.
