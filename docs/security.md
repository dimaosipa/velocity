# Security

- User-space only: never writes to system directories
- No sudo required: all operations in ~/.velo/
- SHA256 verification: all downloads cryptographically verified
- Code signing: handles pre-signed binaries, ad-hoc re-signing
- Extended attribute handling: clears macOS metadata
- Graceful fallbacks: installation continues if some binaries can't be signed

See [Architecture](./architecture.md) for more.
