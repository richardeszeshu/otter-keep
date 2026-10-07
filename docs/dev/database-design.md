# Database Design & Cataloging

This document outlines the SQLite database architecture within `OtterKeepDatabase`, covering relational schema design, WAL mode configuration, batch indexing performance, and timeline search queries.

---

## 1. Database Configuration & Pragmas

OtterKeep maintains a dedicated SQLite database (`catalog.sqlite`) at the root of every backup destination. On connection open, the engine executes high-performance pragmas:

```sql
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;
PRAGMA temp_store = MEMORY;
```

### Clean Closure Protocol
When closing the database:
```sql
PRAGMA wal_checkpoint(TRUNCATE);
```
Following the checkpoint, `sqlite3_close_v2(db)` is called. This flushes all shared-memory segments (`-shm`) and WAL journals (`-wal`), releasing open file descriptors and eliminating external drive ejection locks.

---

## 2. Schema Architecture

```
┌──────────────────────────────────────┐
│              snapshots               │
├──────────────────────────────────────┤
│ id: TEXT PRIMARY KEY                 │
│ timestamp: REAL                      │
│ status: TEXT                         │
│ total_files: INTEGER                 │
│ total_bytes: INTEGER                 │
│ snapshot_path: TEXT                  │
│ backup_type: TEXT                    │
└──────────────────┬───────────────────┘
                   │ 1:N CASCADE
                   ▼
┌──────────────────────────────────────┐
│             file_records             │
├──────────────────────────────────────┤
│ id: INTEGER PRIMARY KEY AUTOINCREMENT│
│ snapshot_id: TEXT REFERENCES snapshot│
│ relative_path: TEXT                  │
│ file_size: INTEGER                   │
│ mtime: REAL                          │
│ inode: INTEGER                       │
│ checksum: TEXT                       │
│ sample_hash: TEXT                    │
│ is_directory: INTEGER                │
│ is_symlink: INTEGER                  │
└──────────────────────────────────────┘
```

---

## 3. Performance Indexes

To support rapid timeline exploration and cross-snapshot searching:
- `idx_file_records_snap`: `(snapshot_id)`
- `idx_file_records_path`: `(relative_path)`
- `idx_file_records_snap_path`: `(snapshot_id, relative_path)`
- `idx_snapshots_timestamp`: `(timestamp DESC)`

---

## 4. Batch Catalog Indexing

Rather than executing individual `INSERT` operations per file, `DatabaseEngine` uses bulk transactions:
- Files are buffered into batches of 1,000 items.
- Prepared statement handles are reused across iterations.
- Batch operations reduce SQLite transaction overhead from seconds to single-digit milliseconds.
