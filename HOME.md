---
title: "Velocity - The Fastest Package Manager for Apple Silicon"
description: "Native speed. Modern architecture. Zero sudo required. A lightning-fast package manager built exclusively for Apple Silicon."
keywords: "velocity, velo, package manager, homebrew, swift, macos, apple silicon, m1, m2, m3, m4"
badge_icon: "⚠️"
badge_text: "Experimental Software - Use with caution"
hero_title: "Velocity: The Fastest<br>Package Manager for<br><span class=\"hero-title-accent\">Apple Silicon</span>"
hero_subtitle: "Native speed. Modern architecture. Zero sudo required."
cta_primary_text: "Get Started"
cta_primary_url: "./docs/installation"
cta_secondary_text: "View on GitHub"
cta_secondary_url: "https://github.com/dimaosipa/velocity"
cta_note: "<strong>Note:</strong> Velocity is experimental software. Please test thoroughly before using in production environments."
---

# Velocity 🚀

The fast, modern package manager for Apple Silicon Macs.

## Why Choose Velocity?

Velocity is a next-generation package manager for macOS, designed for speed, simplicity, and total user control. Velocity treats formulas as declarative files, installs only from pre-built bottles (never compiles from source), and runs entirely in user space—no sudo, no system writes, and no risk.

## ✨ Key Features

- **🔋 Apple Silicon Native**: Built from the ground up using Swift for Apple Silicon Macs. No legacy code, no slow emulation.
- **📝 Declarative Formula Handling**: Uses Homebrew .rb formulae as simple, predictable configuration files. No Ruby runtime or interpretation required.
- **📦 Bottle-Only Installs**: Installs exclusively from pre-built bottles. No source compilation, no build dependencies, no waiting.
- **🛡️ User-Space Operation**: Everything lives in your home directory (default \~/.velo/). Never requires sudo or writes to system directories.
- **🗃️ Flexible Installation & Caching**: Install Velocity in any directory. Cache packages locally per project, just like `node_modules` for system tools. Perfect for CI, reproducible builds, and isolated environments.
- **💼 Project-Local Dependencies**: Each project can have its own tool versions with velo.json manifests—like npm for system packages.
- **🔄 Compatible with Homebrew**: Uses existing .rb formulae from Homebrew core tap. Drop-in replacement with zero migration needed.
- **🔐 Security-First Design**: SHA256 verification, code signing, and advanced security measures built into every operation.
- **🤖 CI Ready**: Built-in GitHub Actions support with automated testing, continuous deployment, and comprehensive CI/CD workflows.
- **🧠 Safe for Automation & AI Agents**: No scripts, no side effects, no surprises—safe to run in CI, containers, and autonomous workflows.

## How to Install? 

Install using homebrew:

```sh
# Install via Homebrew tap
brew tap dimaosipa/brew
brew install dimaosipa/brew/velo
```

Or clone and install the repo:

```sh
git clone https://github.com/dimaosipa/velocity.git
cd velocity
./install.sh
```

Run project-specific commands:

```sh
# Use velo exec to run commands in the context of a project
velo exec <command>
```

## Why Not Just Use Homebrew?

Homebrew formulas are **executable Ruby scripts** — not static package definitions. Installing a package with Homebrew means running third-party code with full system access. This allows:

- Arbitrary shell commands during install/upgrade
- Silent modifications outside the install directory
- Potential use of `sudo`
- Unexpected compilation from source

**Velocity flips this model.** It treats formulas as **declarative**, like JSON or YAML — not scripts. Packages are installed only from trusted prebuilt binaries (bottles), with no custom install logic.

- No shell execution
- No filesystem writes outside `~/.velo/`
- No elevated permissions
- Fully predictable installs

This makes Velocity uniquely suited for **automation**, **CI environments**, and even **AI agents** — where **determinism, safety, and reproducibility** are critical.

| Feature              | Velocity        | Homebrew        |
| -------------------- | --------------- | --------------- |
| Bottle-only Installs | ✅               | ❌ (compiles)    |
| User-space Only      | ✅               | ❌ (system dirs) |
| Formula Handling     | Data (declarative) | Executable (Ruby DSL)|
| Project-local Cache  | ✅               | ❌               |
| Safe for AI Agents   | ✅               | ❌               |

## Who is Velocity for?

- Developers who want instant installs and zero system risk
- CI/CD pipelines needing reproducible, isolated environments
- Developers who want to avoid path pollution by keeping dependencies isolated to project directories
- AI agents and autonomous tools that require deterministic, non-interactive installs

## Try it yourself!

Ready to try Velocity? Install in seconds—no system changes, no waiting. [Get Started](./docs/installation) or [View on GitHub](https://github.com/dimaosipa/velocity)