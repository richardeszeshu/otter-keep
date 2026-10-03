# Remote Destinations & 3-2-1 Backup Rule

A local backup protects you from accidental file deletions, software corruption, and failed macOS updates. However, physical drive failures, theft, fires, or water damage require offsite protection.

OtterKeep implements an enterprise-grade **3-2-1 Backup Engine** directly within a native macOS interface.

---

## 1. The 3-2-1 Backup Standard

```mermaid
flowchart TD
    DATA["Your Vital Data\n(Mac Internal SSD)"]
    COPY1["Copy 1: Local APFS Snapshot\n(Zero-Cost CoW on Internal/Secondary Volume)"]
    COPY2["Copy 2: External Media\n(USB-C / Thunderbolt NVMe SSD)"]
    COPY3["Copy 3: Offsite / Cloud Destination\n(Encrypted S3, SFTP, or WebDAV)"]

    DATA --> COPY1
    DATA --> COPY2
    DATA --> COPY3
```

OtterKeep continuously audits your backup profile and displays real-time compliance badges:
* 🟢 **3-2-1 Compliant**: Local primary + external drive + offsite remote replica.
* 🟡 **Partially Protected**: Local backup + external drive (lacks offsite replication).
* 🔴 **Single Point of Failure (SPOF)**: Backup resides on the same physical drive as the source data.

---

## 2. Supported Remote Destinations

| Destination Type | Protocols / Providers | Best For | Encryption |
|---|---|---|---|
| **External SSD / Drive** | APFS, HFS+, ExFAT (USB-C/Thunderbolt) | Rapid full restores & Time Machine replacement | FileVault / Native APFS |
| **S3 Object Storage** | AWS S3, Cloudflare R2, Backblaze B2, Wasabi, MinIO | Cost-effective offsite cloud archiving | Client-Side AES-256-GCM |
| **SFTP (SSH)** | Linux NAS, TrueNAS, Unraid, Remote Servers | Custom home servers & secure offsite SSH storage | Client-Side AES-256-GCM + SSH |
| **WebDAV** | Nextcloud, ownCloud, Synology DSM, QNAP | Private clouds & multi-user NAS environments | Client-Side AES-256-GCM + HTTPS |
| **SMB Network Share** | macOS / Windows / Samba file shares | Local office gigabit/10GbE network drives | Client-Side AES-256-GCM + SMB |

---

## 3. Setting Up an S3 Destination (AWS, Cloudflare R2, MinIO, Backblaze B2)

OtterKeep features built-in S3-compatible replication with support for custom endpoints and Path-Style addressing.

```
┌─────────────────────────────────────────────────────────────┐
│ Remote Destination: Cloudflare R2 / AWS S3                 │
├─────────────────────────────────────────────────────────────┤
│ Endpoint:    https://<account_id>.r2.cloudflarestorage.com  │
│ Bucket Name: my-mac-backups                                 │
│ Region:      auto (or us-east-1, eu-central-1)              │
│ Prefix:      work-macbook-pro/                              │
│ Access Key:  AKIAIOSFODNN7EXAMPLE                           │
│ Secret Key:  ••••••••••••••••••••••••••••••••••••••••       │
│ [x] Enable Client-Side Encryption (AES-GCM-256)            │
│ [x] Enable Compressed Packaging (Tar.Zstandard)             │
│                                                             │
│ [ Test Connection ]                      [ Save & Verify ]  │
└─────────────────────────────────────────────────────────────┘
```

### Steps:
1. In OtterKeep, select your profile and navigate to **Remote Destinations**.
2. Click **Add Remote Destination...** and choose **Amazon S3 / S3-Compatible**.
3. Select a preset (AWS S3, Cloudflare R2, Backblaze B2, MinIO) or choose Custom.
4. Input your **Endpoint URL**, **Bucket Name**, and **Credentials**.
5. Enable **Client-Side Encryption** and enter a master encryption password (stored securely in the macOS Keychain).
6. Click **Test Connection** to verify endpoint reachability and bucket permissions.
7. Click **Save**.

---

## 4. Setting Up SFTP (SSH)

For home servers, remote VPSs, and TrueNAS appliances:

1. Click **Add Remote Destination...** and choose **SFTP (SSH)**.
2. Enter the **Hostname / IP Address** and **Port** (default: `22`).
3. Enter your **Username**.
4. Choose your **Authentication Method**:
   * **SSH Private Key (Recommended)**: Click **Browse...** to select your `~/.ssh/id_ed25519` or `id_rsa` key file.
   * **Password**: Securely stored in your encrypted macOS Keychain.
5. Specify the remote directory path (e.g., `/mnt/storage/backups/otterkeep`).
6. Click **Test Connection** to confirm SSH handshake and SFTP write privileges.

---

## 5. Setting Up WebDAV (Nextcloud / Synology)

1. Select **Add Remote Destination...** and choose **WebDAV**.
2. Enter the WebDAV URL (e.g. `https://cloud.yourdomain.com/remote.php/dav/files/username/Backups`).
3. Enter your Username and App Password.
4. Test and save.

---

## 6. Zero-Knowledge Client-Side Encryption (AES-GCM-256)

When replicating to public clouds or third-party storage, privacy is paramount:

* **Zero-Knowledge Architecture**: Files, folder hierarchies, and metadata are encrypted on your Mac **before** transmission over the network.
* **Cipher**: Industry-standard **AES-256-GCM** authenticated encryption with hardware acceleration via Apple Silicon NEON / AES instructions.
* **Key Derivation**: Passphrases are hardened using **Argon2id / PBKDF2** with dynamic salting.
* **Key Storage**: Keys are stored in the hardware-backed **macOS Keychain** with biometric Touch ID / Apple Watch authorization.

---

## 7. Compressed Packaging (Tar.Zstandard / Tar.Gzip)

Uploading thousands of small files to cloud storage incurs significant API latency and per-request costs (such as AWS S3 PUT fees).

OtterKeep offers **Archive Packaging**:
* Streams your backup snapshot into a single `.tar.zst` (Zstandard) or `.tar.gz` archive.
* **Zstandard (Zstd)** provides extreme compression ratios while decompressing at over 1 GB/s on Apple Silicon chips.
* Dramatically slashes cloud storage fees and reduces replication time by up to 80%.

---

## 8. Smart Bandwidth Throttling & Wi-Fi Protection

Replications should never degrade your video conference calls or burn through your mobile data plan:

* **Bandwidth Throttling**: Choose from **Unlimited**, **Fast** (25 MB/s), **Recommended** (10 MB/s), or **Gentle** (2 MB/s).
* **Wi-Fi Filtering**: Configure an **Allowed Wi-Fi Networks** whitelist (e.g. `Home-Fiber-5G`, `Office-LAN`) to block replication when connected to public hotspots.
* **Personal Hotspot Protection**: Automatically suspends replication when connected to an iPhone Personal Hotspot or metered cellular connection.
