# Usage

## Basic Commands

- `velo init` — Initialize project with velo.json
- `velo install <pkg>` — Install a package
- `velo uninstall <pkg>` — Remove a package
- `velo exec <cmd>` — Run command with local packages
- `velo which <cmd>` — Show which binary will be used
- `velo info <pkg>` — Show package details
- `velo list` — List installed packages
- `velo search <query>` — Search for packages
- `velo update` — Update repositories
- `velo update-self` — Update velo itself
- `velo verify` — Check installed packages vs velo.lock
- `velo doctor` — Check system health
- `velo clean` — Clean packages or cache
- `velo tap` — Manage package repositories

See [Local Packages](./local-packages.md) for project-local workflows.

## Examples

```bash
velo install wget
velo exec convert image.jpg
velo which wget
```

For all commands and options, run `velo --help` or see the [full command reference](./usage.md).
