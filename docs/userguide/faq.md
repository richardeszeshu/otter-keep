# Frequently Asked Questions & Troubleshooting

Find answers to common questions about OtterKeep's architecture, security features, troubleshooting steps, and performance optimizations.

---

## General & Concepts

### How is OtterKeep different from Apple Time Machine?
Apple Time Machine is designed for full-system restoration, often generating massive, opaque backup bundles (`.backupbundle`) that are slow to browse and prone to disk corruption.
OtterKeep is built specifically for modular, user-controlled folder profiles, developer repositories, and Apple Photos libraries. It creates transparent, native APFS Copy-on-Write snapshots that are directly browsable in the Finder, uses 0 extra bytes for unmodified files, supports direct replication to cloud S3/SFTP/WebDAV, and includes ransomware anomaly guards.

### Does OtterKeep consume twice the disk space if my source and destination are on the same APFS drive?
**No.** On APFS volumes, OtterKeep uses Apple's native `clonefile()` (reflink cloning). Unmodified files share the exact same physical disk blocks. A 50 GB folder backup on the same APFS container takes almost **0 bytes of additional disk space**, creating an instantaneous, point-in-time snapshot.

### Can I back up to or from non-APFS drives (such as exFAT, NTFS, or FAT32)?
**Yes.** OtterKeep v1.3.0 features dedicated filesystem drivers:
* **exFAT Targets & Sources**: OtterKeep uses high-performance chunked streaming with full metadata preservation and applies a **10ms timestamp tolerance** in change detection so untouched files are never re-copied unnecessarily.
* **NTFS Sources**: Fully supported for reading and backing up to APFS/cloud destinations.
* **NTFS Targets**: Since macOS mounts NTFS volumes in read-only mode by default without third-party drivers, OtterKeep includes pre-flight write validation that alerts you with clear guidance before attempting to write.
* **SQLite on Removable Disks**: The catalog database automatically adapts its journaling mode (WAL or TRUNCATE) to remain rock-solid on external flash drives.

---

## Troubleshooting & Permissions

### Why does OtterKeep display a "Full Disk Access (FDA) Missing" warning?
macOS protects user privacy by restricting access to directories like `~/Library/Mail`, `~/Library/Messages`, `~/Library/Containers`, and Safari data. Even administrator accounts cannot read these directories without explicit Full Disk Access.
* **Resolution**: Open **System Settings** > **Privacy & Security** > **Full Disk Access**, ensure OtterKeep is in the list, and turn its switch **ON**.

### What happens if my external backup drive is unplugged during a backup?
OtterKeep is built with atomic transactional safety:
1. **Live File Consistency Guard**: If a write operation is interrupted by a disconnected drive, partial files are isolated and never committed to the database.
2. **Profile Execution Lock**: Prevents conflicting concurrent operations.
3. **Automatic Resumption**: When the drive is reconnected, OtterKeep detects the volume mount and seamlessly resumes the delta backup where it left off.

### Why is the Finder context menu not showing up?
1. Check **System Settings** > **Privacy & Security** > **Extensions** > **Added Extensions** and verify **OtterKeep** is checked.
2. In OtterKeep, go to **Settings** > **Finder Integration** and click **Restart Finder**.
3. Note that Finder context menu badges appear only inside folders configured as active sources in your OtterKeep profiles.

---

## Security & Ransomware Shield

### How does the Ransomware & Rate-of-Change Guard work?
Ransomware attacks typically encrypt thousands of files rapidly, changing their extensions to `.locked`, `.crypto`, or unrecognizable strings.
OtterKeep includes an active heuristic anomaly detector:
* **Change Rate Threshold**: If more than e.g. 35% of your files or an abnormal volume of deletions occur between two consecutive snapshots, OtterKeep immediately **aborts the backup**.
* **Suspicious Extension Filter**: Detects known ransomware extension patterns.
* **Tamper Prevention**: By aborting before committing, OtterKeep ensures your historical snapshots remain 100% clean and uninfected.

### Where are my cloud passwords and encryption keys stored?
All S3 Secret Keys, SFTP Passwords, SSH private key passphrases, and WebDAV credentials are encrypted and stored in your **hardware-backed macOS Keychain**. OtterKeep never stores plain-text secrets in configuration files.

### Do diagnostic logs contain private personal data?
No. OtterKeep's logging engine runs all log lines through a **LogPrivacySanitizer**. Personal usernames, home directory paths, API tokens, and credentials are automatically redacted (e.g. replaced with `<REDACTED_TOKEN>` and `/Users/****/`).

---

## Performance & CLI

### How can I run OtterKeep backups from Terminal or automation scripts?
OtterKeep includes a high-performance command-line binary (`otterkeep`):

```bash
# List all configured profiles
otterkeep profiles

# Run an incremental backup for a specific profile
otterkeep backup --profile "Work Projects"

# Run a dry-run simulation
otterkeep dry-run --profile "Work Projects"

# Compare the latest two snapshots
otterkeep diff --profile "Work Projects"

# Verify snapshot integrity and detect bit-rot
otterkeep scrub --profile "Work Projects"

# Check daemon and system status
otterkeep doctor
```

### Can OtterKeep wake my Mac to perform scheduled backups?
OtterKeep uses macOS `IOPMAssertion` power management assertions to prevent your Mac from going to sleep in the middle of an active backup. If your Mac is asleep when a backup is scheduled, OtterKeep's **Catch-Up Engine** automatically runs the missed backup within seconds of waking up.

---

## Support & Contributing

- **GitHub Issues**: [Report a Bug or Request a Feature](https://github.com/richardeszeshu/otter-keep/issues)
- **Developer Documentation**: See the technical guides under [`docs/dev/`](../dev/)
- **License**: OtterKeep is open source under the MIT License.
