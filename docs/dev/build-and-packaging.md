# Build, Testing & Packaging Pipeline

This document details the compilation pipeline, Swift 6 toolchain configuration, unit & system test execution, and application bundling for macOS.

---

## 1. Prerequisites & Toolchain

* **macOS**: macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia)
* **Architecture**: Apple Silicon (arm64) or Intel (x86_64)
* **Swift Toolchain**: Swift 6.0+ (`swift --version`)
* **Xcode Command Line Tools**: `xcode-select --install`

---

## 2. Compiling with Swift Package Manager

OtterKeep utilizes pure Swift Package Manager without external third-party dependencies, guaranteeing rapid incremental builds.

### Debug Build
```bash
swift build
```

### Release Build
```bash
swift build -c release
```

### Build Optimization Settings
In `Package.swift`, strict concurrency checks are enforced across all targets:
```swift
swiftSettings: [
    .enableUpcomingFeature("StrictConcurrency")
]
swiftLanguageModes: [.v6]
```

---

## 3. Running System & End-to-End Tests

OtterKeep provides an extensive 100-phase system test suite and micro-benchmark runner implemented in `Sources/OtterKeepTestRunner`:

```bash
# Build the test runner
swift build --target OtterKeepTestRunner

# Execute all 100 tests and benchmarks
./.build/debug/OtterKeepTestRunner
```

### Covered Test Phases
1. **Phase 2**: APFS clone benchmark, CoW independence, POSIX hardlinks, xattr retention, atomic moves.
2. **Phase 3-5**: SQLite manifest indexing, scanner exclusion, retention snapshot pruning, collision resolution (`.keepBoth`), disaster recovery catalog rebuild.
3. **Phase 6**: SHA-256 data integrity checksums, WORM immutability (`UF_IMMUTABLE`), Grandfather-Father-Son (GFS) daily retention.
4. **Phase 8-10**: Hierarchical tree search, volume capabilities, Apple Photos metadata extraction, iCloud cache eviction safeguards.
5. **Phase 12-14**: Single-instance AF_UNIX IPC, Finder extension communication, PII sanitization, atomic staging restores, live torn-read guards.
6. **Phase 15-22**: AWS S3 SigV4, AES-256-GCM client encryption, bandwidth throttling, hook execution sandboxing, ransomware anomaly detection, WebDAV & SFTP providers.

---

## 4. Packaging `OtterKeep.app` Bundle

The packaging script (`scripts/package_app.sh`) compiles the binaries, creates the macOS bundle layout, configures the Finder Sync extension, generates standard property lists (`Info.plist`), and registers the bundle with macOS LaunchServices.

### Packaging Invocation
```bash
# Package into ~/Applications in Release mode (default)
./scripts/package_app.sh release ~/Applications

# Or package into /Applications
sudo ./scripts/package_app.sh release /Applications
```

### Generated Bundle Layout
```
OtterKeep.app/
├── Contents/
│   ├── Info.plist
│   ├── PkgInfo
│   ├── MacOS/
│   │   └── OtterKeepApp
│   ├── Resources/
│   │   ├── AppIcon.icns
│   │   └── OtterKeep_OtterKeepUI.bundle/
│   └── PlugIns/
│       └── OtterKeepFinderSync.appex/
│           ├── Contents/
│           │   ├── Info.plist
│           │   └── MacOS/
│           │       └── OtterKeepFinderSyncExtension
```

### Code Signing & Notarization
For local development, ad-hoc codesigning is performed automatically:
```bash
codesign --force --deep --sign - /Applications/OtterKeep.app
```
For production distribution:
```bash
codesign --force --options runtime --sign "Developer ID Application: Your Name (TEAMID)" /Applications/OtterKeep.app
xcrun notarytool submit OtterKeep.dmg --keychain-profile "AC_NOTARY" --wait
```

---

## 5. Homebrew Distribution

OtterKeep distributes through a custom Homebrew tap:
```bash
brew tap richardeszes/tap
brew install --cask otterkeep
```
Cask definition is maintained in `Distribution/otterkeep.rb`.
