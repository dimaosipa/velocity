# Tap Management

Velo supports multiple package repositories (taps).

## Managing Taps

- `velo tap list` — List installed taps
- `velo tap add <tap>` — Add a tap
- `velo tap remove <tap>` — Remove a tap
- `velo tap update` — Update all taps

Taps can be added by name or URL. Project-local taps are tracked in velo.json.

## Tap Priority

- homebrew/core — Highest
- Other homebrew taps — Medium
- Third-party taps — Lower

When multiple taps contain the same package, the highest priority version is used.
