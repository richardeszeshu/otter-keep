# Contributing to OtterKeep

We welcome contributions to OtterKeep! As a software project dedicated to data preservation, reliability and test verification are our highest priorities.

---

## 1. Core Principles

1. **Safety First**: Never perform destructive filesystem operations without affirmative verification.
2. **Swift 6 Concurrency**: Write strict actor-isolated, Sendable-safe Swift code. Avoid locks or `@unchecked Sendable` unless strictly required for C-interop.
3. **Bilingual Parity**: Any new user-facing string must be registered in `Localization.swift` with both Hungarian and English translations.
4. **Comprehensive Testing**: Any architectural enhancement must include corresponding test cases in `OtterKeepTestRunner`.

---

## 2. Development Workflow

1. Fork the repository and create a feature branch (`feature/your-feature-name` or `bugfix/issue-description`).
2. Implement your changes.
3. Ensure the test suite passes with 100% success rate:
   ```bash
   swift run OtterKeepTestRunner
   ```
4. Commit your changes using [Conventional Commits](https://www.conventionalcommits.org/):
   - `feat(...)`: New feature
   - `fix(...)`: Bug fix
   - `chore(...)`: Maintenance or release
5. Open a Pull Request against the `release` or `develop` branch.
