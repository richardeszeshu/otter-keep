# Security & Unified Logging Architecture

This document details security controls, cryptographic implementations, IPC protections, and privacy-preserving observability in OtterKeep v1.4.0.

---

## 1. Zero-Knowledge Cryptography (OKENC2)

Remote archives and cloud backups are encrypted client-side using **AES-256-GCM**:

### Key Derivation
- Key Derivation Function: **PBKDF2-HMAC-SHA256**
- Iteration Rounds: **600,000 rounds** (aligned with modern OWASP standards)
- Salt Size: **32 bytes** generated cryptographically via `SecRandomCopyBytes`
- Header Identifier: `OKENC2\0` (Modern) with automatic backward compatibility for legacy `DSENC2\0` and `DSENC1\0` blobs.

### Envelope Structure
```
[ 7 bytes Magic: "OKENC2\0" ]
[ 32 bytes Salt ]
[ 12 bytes AES-GCM Nonce ]
[ N bytes Ciphertext ]
[ 16 bytes Authentication Tag ]
```

---

## 2. Process Security & Local IPC

OtterKeep utilizes a hardened Unix Domain Socket architecture:
- **Socket Path**: `~/.otterkeep/gui.sock`
- **File Permissions**: `0600` (owner read/write only). The containing folder `~/.otterkeep/` is set to `0700`.
- **Peer UID Verification**:
  ```c
  uid_t peerUID;
  gid_t peerGID;
  if (getpeereid(clientFD, &peerUID, &peerGID) == 0) {
      if (peerUID != geteuid()) {
          // Reject foreign local user
          close(clientFD);
      }
  }
  ```
- **Shell Argument Injection Neutralization**: Remote SFTP parameters and paths are sanitized against shell injection attacks.

---

## 3. Privacy-Preserving Unified Logging

To ensure diagnostic logs can be safely exported without leaking personal information, all telemetry passes through `LogPrivacySanitizer`:

### Redacted Elements
- **Usernames**: NSUserName and NSFullUserName replaced with `<USER>`.
- **Home Paths**: User home paths replaced with `<USER_HOME>`.
- **AWS Credentials**: `AKIA...` access keys replaced with `<AWS_ACCESS_KEY_ID>`.
- **Tokens & Passwords**: URL query parameters (`?token=...`) replaced with `<REDACTED>`.
- **Webhooks**: Slack and Discord webhook endpoints redacted.

### Preserved Diagnostic Context
- File extensions (`.pdf`, `.sqlite`, `.heic`)
- Error codes (`ENOENT`, `EACCES`, `ENOSPC`)
- Snapshot IDs and ISO 8601 timestamps
- File sizes and transfer byte rates
