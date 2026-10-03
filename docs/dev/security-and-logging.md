# Security Hardening, Cryptography & Privacy-Preserving Logging

OtterKeep implements defense-in-depth system security across process boundaries, network interfaces, persistent storage, and diagnostic telemetry.

---

## 1. Zero-Knowledge Client-Side Encryption

To guarantee privacy on untrusted remote replication targets (AWS S3, SFTP, WebDAV), OtterKeep employs client-side AES-256-GCM encryption before data leaves the local machine.

### Blob Format Specification (`DSENC2\0`)
Encrypted blobs are prefixed by an 8-byte magic header:
```
+------------------+------------------+-------------------+-----------------+
| Magic: "DSENC2\0" | Salt (32 bytes)  | Nonce (12 bytes)  | Ciphertext + Tag|
| (8 bytes)        | PBKDF2 Salt      | GCM Nonce         | (Variable)      |
+------------------+------------------+-------------------+-----------------+
```

* **Key Derivation**: PBKDF2 using HMAC-SHA256 with **600,000 rounds** and a cryptographically secure 32-byte random salt (complying with modern OWASP recommendations).
* **Cipher**: AES-GCM-256 with 128-bit authentication tag, preventing tampering and chosen-ciphertext attacks.
* **Backward Compatibility**: OtterKeep automatically recognizes legacy `DSENC1\0` blobs (100,000 rounds) for seamless upgrades without requiring catalog re-encryption.

---

## 2. Process Hardening & Inter-Process Communication (IPC)

* **AF_UNIX Socket Hardening**: The single-instance IPC socket located at `~/.otterkeep/ipc.sock` enforces strict path length validation (`< sizeof(sockaddr_un.sun_path)`) to prevent buffer overflows, and applies `chmod(0600)` immediately after binding to restrict access solely to the current user UID.
* **POSIX `flock` File Locking**: Profile execution locks (`~/.otterkeep/locks/<profile-id>.lock`) preserve the 0-byte lock file across releases, completely eliminating inode reuse race conditions.
* **Sandbox & Shell Escaping**:
  * Shell hook resolution is confined to `~/.otterkeep/hooks/<profile>` and validated paths.
  * All external command executions (e.g. `sftp`, `mount_smbfs`, `hdiutil`) use POSIX array arguments or `sanitizeShellArgument` to prevent command injection.
  * Direct network credentials are passed via standard input or secure temporary configuration files rather than CLI arguments visible in `ps aux`.

---

## 3. Keychain Credential Security

All sensitive credentials—including cloud secret keys, encryption passphrases, and SMB passwords—are stored securely in the hardware-backed macOS Keychain (`Security.framework`):
* Stored with `kSecAttrAccessibleAfterFirstUnlock`.
* Automatically purged when a backup profile is deleted via GUI or CLI.
* Password credentials are never written to disk in plain text.

---

## 4. Dual-Tier Logging Architecture

OtterKeep separates operational logs from deep diagnostic logs to balance user privacy, performance, and troubleshooting.

### 1. Standard Tier (User-Facing & In-Memory Ring Buffer)
* Kept in a thread-safe circular ring buffer (up to 500 entries) in `LogManager`.
* Contains high-level lifecycle events (`info`, `warning`, `error`).
* Clean of noisy low-level I/O chatter.

### 2. Deep Diagnostic Tier (Disk Log Files)
* Written to `~/.otterkeep/logs/otterkeep-YYYY-MM-DD.log`.
* Contains verbose trace messages, query timings, and system diagnostics.
* Retains debug-level statements when diagnostic logging is enabled.

### Privacy Sanitizer (`LogPrivacySanitizer`)
All log entries pass through an automated privacy redaction filter before being recorded or displayed:
1. **Credentials & Tokens**: Redacts Authorization headers, bearer tokens, AWS secret keys (`AKIA...`), and basic auth URLs (`https://user:pass@host`).
2. **Webhooks**: Obfuscates Slack, Discord, and Pushover webhook endpoints.
3. **Personal Paths**: Redacts macOS home directory username paths (`/Users/<username>/` -> `/Users/[REDACTED]/`).
