# Contributing to Knex Dart

Thank you for your interest in contributing to Knex Dart!

## Current Status

**Phase 1 (Query Builder):** Complete ✅  
**Phase 2 (Database Execution):** In progress 🚧

## How to Contribute

### Reporting Issues
- Use GitHub Issues
- Include: Dart version, code snippet, expected vs actual behavior
- For query generation bugs, include the equivalent Knex.js code

### Pull Requests
1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Write tests for your changes
4. Ensure all tests pass: `dart test`
5. Follow existing code style
6. Submit PR with clear description

### Testing Philosophy
- Every feature must have comparison tests against Knex.js
- Unit tests for edge cases
- 100% API parity is the goal

### Priority Areas
- Phase 2: Database driver integration
- Extended WHERE clauses (BETWEEN, EXISTS, column comparisons)
- MySQL/SQLite support
- Documentation improvements

## Development Setup

```bash
git clone https://github.com/kartikey321/knex-dart.git
cd knex-dart
dart pub get
dart test
```

## Questions?
Open an issue or discussion!
