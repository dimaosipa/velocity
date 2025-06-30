# Testing & CI/CD

Velo includes:

- Unit tests (core components)
- Integration tests (CLI workflows)
- Performance benchmarks
- Memory leak detection
- Stress tests

## CI/CD Example

```yaml
- name: Cache Velo packages
  uses: actions/cache@v3
  with:
    path: .velo
    key: ${{ runner.os }}-velo-${{ hashFiles('velo.lock') }}

- name: Install dependencies
  run: velo install
```

See [Contributing](./contributing.md) for test instructions.
