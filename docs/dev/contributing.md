# Contributing to OtterKeep

Thank you for your interest in contributing to OtterKeep! We welcome contributions to code, documentation, localization, and automated tests.

---

## 1. Development Prerequisites

* macOS 14.0 (Sonoma) or macOS 15.0 (Sequoia)
* Xcode 16.0+ or Command Line Tools with Swift 6.0 toolchain
* Homebrew (optional, for dependencies and packaging)

---

## 2. Building the Project

OtterKeep uses standard Swift Package Manager (SPM):

```bash
# Clone the repository
git clone https://github.com/richardeszeshu/otter-keep.git
cd otter-keep

# Build the release targets
swift build -c release

# Run the test suite
swift run OtterKeepTestRunner
```

### Packaging the macOS Application Bundle

To package a standalone `.app` bundle, codesign with ad-hoc certificates, and generate a notarized DMG:

```bash
chmod +x scripts/package_app.sh
./scripts/package_app.sh
```

---

## 3. Coding Guidelines

* **Language**: Swift 6 with strict concurrency checking enabled.
* **Code Comments**: All public APIs, structs, and complex algorithms must have descriptive English documentation comments (`///`).
* **Localization**: Never hardcode user-facing strings in SwiftUI views or CLI commands. Always add keys to `L10n.Key` in `Sources/OtterKeepCore/Localization.swift` with complete Hungarian and English translations.
* **Architecture**: Keep UI components isolated from filesystem and database operations; communicate through `AppState` and dedicated coordinators.
