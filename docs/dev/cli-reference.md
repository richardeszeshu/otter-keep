# CLI Reference Manual

`otterkeep-cli` provides full headless control over OtterKeep backup profiles, snapshot catalogs, restore workflows, and diagnostics.

---

## 1. Global Usage

```bash
otterkeep-cli [subcommand] [options]
```

### Options
- `--help`: Display available commands and options.
- `--version`: Display OtterKeep version (1.4.0) and build number (1400).
- `--profile <name>`: Target a specific backup profile.

---

## 2. Commands

### `version`
Displays application version and component metadata.
```bash
otterkeep-cli version
```

### `backup run`
Triggers an immediate backup session for the active profile.
```bash
# Standard backup run
otterkeep-cli backup run

# Dry-run execution (simulates backup without writing files)
otterkeep-cli backup run --dry-run
```

### `snapshots list`
Lists historical snapshots available at the configured destination.
```bash
otterkeep-cli snapshots list
```

### `restore`
Restores a file or directory from a specific snapshot.
```bash
# Restore specific file to a destination
otterkeep-cli restore --snapshot <snapshot-id> --file <relative-path> --to /path/to/restore
```

### `export-archive`
Exports profile configurations and rules as a portable JSON archive.
```bash
otterkeep-cli export-archive --output ~/.otterkeep/backup_config.json
```
