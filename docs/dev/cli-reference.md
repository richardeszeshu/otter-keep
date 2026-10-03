# OtterKeep CLI Reference

The `otterkeep` command-line utility provides scriptable, headless backup automation, diagnostics, and management.

---

## 1. Synopsis

```bash
otterkeep [global-options] <command> [command-options]
```

### Global Options

| Option | Description |
|---|---|
| `-h, --help` | Display general or command-specific help documentation |
| `-v, --version` | Display main application version, build number, and individual subsystem component versions |
| `--lang <en|hu>` | Override UI/CLI localization language |
| `--debug` | Enable verbose diagnostic logging to stdout |

#### Version Output Sample
```
OtterKeep 1.3.0 (Build 1300)
Subsystem Components:
  ├── OtterKeepCore: 1.2.0
  ├── OtterKeepStorage: 1.1.0
  ├── OtterKeepDatabase: 1.1.0
  ├── OtterKeepUI: 1.3.0
  ├── OtterKeepCLI: 1.1.0
  └── FinderSync: 1.0.0
```

---

## 2. Command Reference

### `backup`
Executes a backup snapshot for a configured profile.

```bash
otterkeep backup --profile <profile-name-or-uuid> [--full] [--dry-run]
```
* `--profile`: Name or UUID of the target backup profile.
* `--full`: Force a full cryptographic hash re-check, bypassing fast delta cache.
* `--dry-run`: Simulate the backup and print estimated storage requirements without modifying disk.

### `diff`
Compares differences between two snapshots.

```bash
otterkeep diff --profile <profile-name> [--target <snapshot-id>] [--base <snapshot-id>]
```

### `restore`
Restores files or whole snapshots from history.

```bash
otterkeep restore --profile <profile-name> --file <relative-path> --target-dir <destination> [--overwrite|--keep-both]
```

### `prune`
Prunes obsolete snapshots according to profile retention policies.

```bash
otterkeep prune --profile <profile-name> [--retain <count>]
```

### `scrub`
Executes data integrity verification and bit-rot detection.

```bash
otterkeep scrub --profile <profile-name>
```

### `photos`
Triggers Apple Photos incremental library backup.

```bash
otterkeep photos backup [--structure <date|album|flat>] [--evict-icloud]
```

### `doctor`
Runs system diagnostics, verifying Full Disk Access (FDA), Finder extension status, disk health, and network reachability.

```bash
otterkeep doctor
```
