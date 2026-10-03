# 🦦 OtterKeep — Brand Identity, Lore & Guidelines

> *„Keep what you love close to your chest.”*  
> *(HU: „Őrizd a legfontosabb kincseidet biztos kezekben.”)*

---

## 🌊 1. Brand Lore & Philosophy (The Story)

Sea otters have an extraordinary, instinctive ritual: throughout their entire lives, they carry their most prized favorite pebble tucked securely into a hidden pocket of skin beneath their forearms. They use this cherished stone to crack open shells, play with it while resting on the ocean swell, and **never let it go under any circumstances**. When sleeping, they hold paws with their loved ones so the tide cannot drift them apart.

**OtterKeep** was born from this exact spirit.

Your Mac holds your life's most precious digital treasures—family photo libraries, creative projects, irreplaceable code repositories, and personal archives. OtterKeep protects these assets with the same tender vigilance, fierce devotion, and natural ease.

OtterKeep is not just another cold, clinical utility; it is a **safe harbor** for your digital life, delivering modern, whisper-quiet, and unbreakable defense against drive failures, accidental deletions, and ransomware threats.

---

## 🧭 2. Mission & Core Values

Every feature, line of code, UI component, and notification created under the OtterKeep banner is anchored in four foundational pillars:

### 1. Tender Vigilance & Zero Data Loss
* User data is sacred—it represents their "cherished pebbles".
* We never take gambles with user files. Every backup and restore operation must be atomic, verified, and non-destructive.
* Data is never overwritten or purged without explicit, informed confirmation and safe historical snapshots.

### 2. Effortless Native Power & macOS Elegance
* Just like an otter navigating the ocean with agility, OtterKeep leverages the raw power of macOS and APFS Copy-on-Write (`clonefile()`).
* Backups take zero extra bytes for unchanged blocks and execute near-instantaneously.
* We respect hardware: minimal CPU cycles, background QoS threading, low memory footprint, and zero battery drain.

### 3. Radical Trust & Cryptographic Integrity
* No opaque proprietary formats, no telemetry, and no lock-in.
* End-to-end client-side encryption (AES-256-GCM) ensures that even offsite cloud providers cannot inspect user archives.
* macOS Keychain safeguards all credentials, while transparent logs keep users in complete control.

### 4. Reassuring Warmth & Human Centricity
* Backup software is historically stressful, noisy, and intimidating. OtterKeep replaces fear with serenity.
* The experience is welcoming, intuitive, and calm—users can rest easy knowing their memories are safely protected.

---

## 🎨 3. Visual Identity & Design Tokens

The visual language bridges organic warmth with the precision and cleanliness of modern macOS.

### Brand Color Tokens

| Token Name | UI Token | Hex | SwiftUI Token | Role & Semantics |
|---|---|---|---|---|
| **Otter Brown / Warm Amber** | `primary-accent` | `#D98547` | `Color(red: 0.85, green: 0.52, blue: 0.28)` | Primary brand color: warmth, care, active protection, primary buttons |
| **Oceanic Teal / Cyber Teal** | `secondary-tech` | `#2EC7BF` | `Color(red: 0.18, green: 0.78, blue: 0.75)` | Technical accent: APFS speed, synchronization, successful snapshots |
| **Deep Sea Navy** | `surface-dark` | `#0E1926` | `Color(red: 0.055, green: 0.098, blue: 0.149)` | Deep oceanic canvas for dark mode, cards, and stable contrast |
| **Pebble Grey** | `border-subtle` | `#E2E8F0` | `Color(red: 0.88, green: 0.91, blue: 0.94)` | Subtle dividers, card borders, representing the protective pebble stone |
| **Safety Emerald** | `status-healthy` | `#2EA043` | `Color(red: 0.18, green: 0.63, blue: 0.26)` | Verified integrity, healthy storage states, clean backups |

### Mascot: Ollie the Otter
* **Character**: A wise, friendly, bright-eyed sea otter floating peacefully on his back in clear ocean waters.
* **Symbolism**: He clutches a radiant, glowing digital time capsule (or pebble drive) firmly to his chest with both paws.
* **Personality**: Ollie never panics. He is calm, vigilant, cheerful, and rock-solid—the faithful guardian of your Mac.

---

## 🗣️ 4. Tone of Voice & Copywriting

When OtterKeep communicates—whether in UI labels, push notifications, terminal output, error dialogs, or documentation—it adheres to these voice attributes:

* **Calm & Reassuring (Never Alarmist)**:
  * ❌ *„Fatal sync error! Cloud replication crashed!”*
  * ✅ *„We hit a temporary snag syncing to the cloud, but your local snapshot is safe and sound. Here is how we can resolve it together.”*
* **Empowering & Clear (Value over Jargon)**:
  * Translate complex concepts into tangible benefits: Explain *how* APFS reflink cloning saves gigabytes of disk space without dumbing down the technical precision.
* **Respectful & Direct**:
  * Speak to the user as a trusted peer. Avoid robotic bureaucracy or condescending over-simplification.
* **Bilingual Parity**:
  * Native fluency in both **English** and **Hungarian (Magyar)**. Translations must feel natural and culturally aligned, not machine-translated.

---

## 🤖 5. Agent & Contributor Mandate (Prompt Guidelines)

> [!IMPORTANT]
> **Mandatory Spirit & Architectural Directives for AI Agents and Contributors:**  
> When working in this repository—implementing features, refactoring architecture, writing documentation, generating UI copy, or diagnosing issues—you must preserve and uphold the OtterKeep brand identity.

### 1. The Sanctuary of User Data (Zero Destructive Habits)
* **Never** suggest, write, or automate blind destructive operations (`rm -rf`, destructive overwrites, unverified truncation).
* When pruning old snapshots, always adhere to strict, deterministic retention policies with fail-safe limits.
* All state mutations must be transactional and rollback-capable.

### 2. Native macOS & APFS Excellence
* Always favor Apple-native frameworks: Swift 6 Concurrency (`async/await`, actors), `clonefile()`, `FSEvents`, and native Finder Sync extensions.
* Respect machine resources: long-running background tasks must explicitly use `.utility` or `.background` Quality of Service (QoS) queues to keep the Mac responsive and cool.

### 3. Empathetic, Solution-Oriented Messages
* Every error message surfaced to the user must provide:
  1. What happened (plain language).
  2. Why it matters (assurance that their current data is unharmed).
  3. The immediate next action to take.

### 4. Cryptographic Sanctity in 3-2-1 Pipelines
* Offsite replication (S3, Cloudflare R2, MinIO, SFTP, WebDAV) must always enforce client-side encryption.
* Secrets and keys must reside in hardware-backed Keychain storage or secure enclaves—never in plaintext configuration files or logs.

---

<div align="center">
<sub>OtterKeep 🦦 • Keep what you love close to your chest.</sub>
</div>
