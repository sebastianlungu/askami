# Contributing

Thank you for your interest in askami.

## How to Contribute

1. Fork the repository.
2. Create a feature branch.
3. Make your changes.
4. Run `swift test` to verify all tests pass.
5. Submit a pull request.

## Code Style

- Follow the project's existing code conventions.
- Keep functions focused and under 50 lines.
- Keep files under 500 lines.
- Prefer `OSAllocatedUnfairLock` over `os_unfair_lock` or `NSLock`.
- All new code must be `Sendable`-aware.

## Testing

All changes must include or update tests. Run the full suite:

```bash
swift test
```

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.
