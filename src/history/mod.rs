#![allow(dead_code)]

use anyhow::{Context, Result};
use rusqlite::{Connection, OptionalExtension, params};
use std::{
    fs,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

const SCHEMA_VERSION: i64 = 1;

#[derive(Debug, Clone)]
pub struct CleanupRun {
    pub id: i64,
    pub started_at: i64,
    pub finished_at: Option<i64>,
    pub disk_total: u64,
    pub free_before: u64,
    pub free_after: Option<u64>,
    pub discovered_bytes: u64,
    pub reclaimed_bytes: u64,
    pub files_deleted: u64,
    pub dirs_deleted: u64,
    pub skipped: u64,
    pub errors: u64,
    pub duration_ms: u64,
    pub status: String,
}

#[derive(Debug, Clone)]
pub struct CleanupEntry {
    pub run_id: i64,
    pub category: String,
    pub path: PathBuf,
    pub parent_path: Option<PathBuf>,
    pub kind: String,
    pub bytes_before: u64,
    pub bytes_reclaimed: u64,
    pub action: String,
    pub rule: String,
    pub result: String,
    pub error: Option<String>,
}

#[derive(Debug, Clone)]
pub struct CategoryTotal {
    pub category: String,
    pub reclaimed_bytes: u64,
    pub files: u64,
    pub errors: u64,
}

#[derive(Debug, Clone)]
pub struct StorageEntry {
    pub snapshot_id: i64,
    pub path: PathBuf,
    pub parent_path: Option<PathBuf>,
    pub kind: String,
    pub bytes: u64,
    pub file_count: u64,
    pub directory_count: u64,
}

pub struct HistoryDb {
    conn: Connection,
}

impl HistoryDb {
    pub fn open() -> Result<Self> {
        let path = database_path()?;

        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).with_context(|| format!("create {}", parent.display()))?;
        }

        let home = dirs::home_dir().context("cannot determine HOME")?;
        migrate_legacy_database(
            &home.join("Library/Application Support/Yeti3-Cleaner/history.sqlite3"),
            &path,
        )?;
        let conn = Connection::open(&path).with_context(|| format!("open {}", path.display()))?;

        let db = Self { conn };
        db.configure()?;
        db.migrate()?;

        Ok(db)
    }

    fn configure(&self) -> Result<()> {
        self.conn.execute_batch(
            r#"
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            PRAGMA foreign_keys = ON;
            PRAGMA busy_timeout = 5000;
            "#,
        )?;

        Ok(())
    }

    fn migrate(&self) -> Result<()> {
        self.conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS cleanup_runs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                started_at INTEGER NOT NULL,
                finished_at INTEGER,

                disk_total INTEGER NOT NULL DEFAULT 0,
                free_before INTEGER NOT NULL DEFAULT 0,
                free_after INTEGER,

                discovered_bytes INTEGER NOT NULL DEFAULT 0,
                reclaimed_bytes INTEGER NOT NULL DEFAULT 0,

                files_deleted INTEGER NOT NULL DEFAULT 0,
                dirs_deleted INTEGER NOT NULL DEFAULT 0,
                skipped INTEGER NOT NULL DEFAULT 0,
                errors INTEGER NOT NULL DEFAULT 0,

                duration_ms INTEGER NOT NULL DEFAULT 0,

                mode TEXT NOT NULL DEFAULT 'max',
                status TEXT NOT NULL DEFAULT 'running'
            );

            CREATE INDEX IF NOT EXISTS
                idx_cleanup_runs_started
            ON cleanup_runs(started_at DESC);

            CREATE TABLE IF NOT EXISTS cleanup_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                run_id INTEGER NOT NULL
                    REFERENCES cleanup_runs(id)
                    ON DELETE CASCADE,

                category TEXT NOT NULL,
                path TEXT NOT NULL,
                parent_path TEXT,

                kind TEXT NOT NULL,

                bytes_before INTEGER NOT NULL DEFAULT 0,
                bytes_reclaimed INTEGER NOT NULL DEFAULT 0,

                action TEXT NOT NULL,
                rule TEXT NOT NULL,
                result TEXT NOT NULL,

                error TEXT
            );

            CREATE INDEX IF NOT EXISTS
                idx_cleanup_entries_run
            ON cleanup_entries(run_id);

            CREATE INDEX IF NOT EXISTS
                idx_cleanup_entries_category
            ON cleanup_entries(run_id, category);

            CREATE INDEX IF NOT EXISTS
                idx_cleanup_entries_path
            ON cleanup_entries(path);

            CREATE TABLE IF NOT EXISTS storage_snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                scanned_at INTEGER NOT NULL,

                disk_total INTEGER NOT NULL DEFAULT 0,
                disk_free INTEGER NOT NULL DEFAULT 0,

                duration_ms INTEGER NOT NULL DEFAULT 0
            );

            CREATE INDEX IF NOT EXISTS
                idx_storage_snapshots_scanned
            ON storage_snapshots(scanned_at DESC);

            CREATE TABLE IF NOT EXISTS storage_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,

                snapshot_id INTEGER NOT NULL
                    REFERENCES storage_snapshots(id)
                    ON DELETE CASCADE,

                path TEXT NOT NULL,
                parent_path TEXT,

                kind TEXT NOT NULL,

                bytes INTEGER NOT NULL DEFAULT 0,
                file_count INTEGER NOT NULL DEFAULT 0,
                directory_count INTEGER NOT NULL DEFAULT 0
            );

            CREATE INDEX IF NOT EXISTS
                idx_storage_entries_snapshot
            ON storage_entries(snapshot_id);

            CREATE INDEX IF NOT EXISTS
                idx_storage_entries_parent
            ON storage_entries(snapshot_id, parent_path);

            CREATE INDEX IF NOT EXISTS
                idx_storage_entries_size
            ON storage_entries(snapshot_id, bytes DESC);
            "#,
        )?;

        self.conn.execute(
            r#"
            INSERT INTO meta(key, value)
            VALUES('schema_version', ?1)
            ON CONFLICT(key)
            DO UPDATE SET value = excluded.value
            "#,
            [SCHEMA_VERSION.to_string()],
        )?;

        Ok(())
    }

    pub fn begin_cleanup(
        &self,
        disk_total: u64,
        free_before: u64,
        discovered_bytes: u64,
        mode: &str,
    ) -> Result<i64> {
        self.conn.execute(
            r#"
            INSERT INTO cleanup_runs(
                started_at,
                disk_total,
                free_before,
                discovered_bytes,
                mode,
                status
            )
            VALUES(?1, ?2, ?3, ?4, ?5, 'running')
            "#,
            params![
                now(),
                to_i64(disk_total),
                to_i64(free_before),
                to_i64(discovered_bytes),
                mode,
            ],
        )?;

        Ok(self.conn.last_insert_rowid())
    }

    pub fn add_cleanup_entry(&self, entry: &CleanupEntry) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO cleanup_entries(
                run_id,
                category,
                path,
                parent_path,
                kind,
                bytes_before,
                bytes_reclaimed,
                action,
                rule,
                result,
                error
            )
            VALUES(
                ?1, ?2, ?3, ?4, ?5,
                ?6, ?7, ?8, ?9, ?10, ?11
            )
            "#,
            params![
                entry.run_id,
                entry.category,
                entry.path.to_string_lossy(),
                entry
                    .parent_path
                    .as_ref()
                    .map(|p| p.to_string_lossy().to_string()),
                entry.kind,
                to_i64(entry.bytes_before),
                to_i64(entry.bytes_reclaimed),
                entry.action,
                entry.rule,
                entry.result,
                entry.error,
            ],
        )?;

        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    pub fn finish_cleanup(
        &self,
        run_id: i64,
        free_after: u64,
        reclaimed_bytes: u64,
        files_deleted: u64,
        dirs_deleted: u64,
        skipped: u64,
        errors: u64,
        duration_ms: u64,
        status: &str,
    ) -> Result<()> {
        self.conn.execute(
            r#"
            UPDATE cleanup_runs
            SET
                finished_at = ?2,
                free_after = ?3,
                reclaimed_bytes = ?4,
                files_deleted = ?5,
                dirs_deleted = ?6,
                skipped = ?7,
                errors = ?8,
                duration_ms = ?9,
                status = ?10
            WHERE id = ?1
            "#,
            params![
                run_id,
                now(),
                to_i64(free_after),
                to_i64(reclaimed_bytes),
                to_i64(files_deleted),
                to_i64(dirs_deleted),
                to_i64(skipped),
                to_i64(errors),
                to_i64(duration_ms),
                status,
            ],
        )?;

        Ok(())
    }

    pub fn latest_cleanup(&self) -> Result<Option<CleanupRun>> {
        self.conn
            .query_row(
                r#"
                SELECT
                    id,
                    started_at,
                    finished_at,
                    disk_total,
                    free_before,
                    free_after,
                    discovered_bytes,
                    reclaimed_bytes,
                    files_deleted,
                    dirs_deleted,
                    skipped,
                    errors,
                    duration_ms,
                    status
                FROM cleanup_runs
                ORDER BY id DESC
                LIMIT 1
                "#,
                [],
                |row| {
                    Ok(CleanupRun {
                        id: row.get(0)?,
                        started_at: row.get(1)?,
                        finished_at: row.get(2)?,
                        disk_total: from_i64(row.get(3)?),
                        free_before: from_i64(row.get(4)?),
                        free_after: row.get::<_, Option<i64>>(5)?.map(from_i64),
                        discovered_bytes: from_i64(row.get(6)?),
                        reclaimed_bytes: from_i64(row.get(7)?),
                        files_deleted: from_i64(row.get(8)?),
                        dirs_deleted: from_i64(row.get(9)?),
                        skipped: from_i64(row.get(10)?),
                        errors: from_i64(row.get(11)?),
                        duration_ms: from_i64(row.get(12)?),
                        status: row.get(13)?,
                    })
                },
            )
            .optional()
            .map_err(Into::into)
    }

    pub fn category_totals(&self, run_id: i64) -> Result<Vec<CategoryTotal>> {
        let mut stmt = self.conn.prepare(
            r#"
            SELECT
                category,
                COALESCE(SUM(bytes_reclaimed), 0),
                SUM(
                    CASE
                        WHEN result = 'deleted' THEN 1
                        ELSE 0
                    END
                ),
                SUM(
                    CASE
                        WHEN result = 'error' THEN 1
                        ELSE 0
                    END
                )
            FROM cleanup_entries
            WHERE run_id = ?1
            GROUP BY category
            ORDER BY SUM(bytes_reclaimed) DESC
            "#,
        )?;

        let rows = stmt.query_map([run_id], |row| {
            Ok(CategoryTotal {
                category: row.get(0)?,
                reclaimed_bytes: from_i64(row.get(1)?),
                files: from_i64(row.get(2)?),
                errors: from_i64(row.get(3)?),
            })
        })?;

        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    pub fn begin_snapshot(&self, disk_total: u64, disk_free: u64) -> Result<i64> {
        self.conn.execute(
            r#"
            INSERT INTO storage_snapshots(
                scanned_at,
                disk_total,
                disk_free
            )
            VALUES(?1, ?2, ?3)
            "#,
            params![now(), to_i64(disk_total), to_i64(disk_free),],
        )?;

        Ok(self.conn.last_insert_rowid())
    }

    pub fn add_storage_entry(&self, entry: &StorageEntry) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO storage_entries(
                snapshot_id,
                path,
                parent_path,
                kind,
                bytes,
                file_count,
                directory_count
            )
            VALUES(?1, ?2, ?3, ?4, ?5, ?6, ?7)
            "#,
            params![
                entry.snapshot_id,
                entry.path.to_string_lossy(),
                entry
                    .parent_path
                    .as_ref()
                    .map(|p| p.to_string_lossy().to_string()),
                entry.kind,
                to_i64(entry.bytes),
                to_i64(entry.file_count),
                to_i64(entry.directory_count),
            ],
        )?;

        Ok(())
    }

    pub fn finish_snapshot(&self, snapshot_id: i64, duration_ms: u64) -> Result<()> {
        self.conn.execute(
            r#"
            UPDATE storage_snapshots
            SET duration_ms = ?2
            WHERE id = ?1
            "#,
            params![snapshot_id, to_i64(duration_ms)],
        )?;

        Ok(())
    }
}

pub fn database_path() -> Result<PathBuf> {
    let home = dirs::home_dir().context("cannot determine HOME")?;

    Ok(home.join("Documents/Yeti3Cleaner/history.sqlite3"))
}

// VACUUM INTO takes a consistent SQLite snapshot, including committed WAL pages.
// Keep the old database as a recovery copy. Never overwrite an existing destination.
fn migrate_legacy_database(old: &Path, destination: &Path) -> Result<()> {
    if destination.try_exists()? || !old.try_exists()? { return Ok(()); }
    let parent = destination.parent().context("database has no parent")?;
    fs::create_dir_all(parent)?;
    let temporary = parent.join(format!(".history-migration-{}-{}.sqlite3", std::process::id(),
        SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()));
    let result = (|| -> Result<()> {
        let source = Connection::open_with_flags(old, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)?;
        source.busy_timeout(std::time::Duration::from_secs(5))?;
        source.execute("VACUUM INTO ?1", [temporary.to_str().context("invalid database path")?])?;
        let check = Connection::open_with_flags(&temporary, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)?;
        let integrity: String = check.query_row("PRAGMA integrity_check", [], |row| row.get(0))?;
        anyhow::ensure!(integrity == "ok", "history migration integrity check failed: {integrity}");
        drop(check);
        fs::File::open(&temporary)?.sync_all()?;
        match fs::hard_link(&temporary, destination) {
            Ok(()) => (),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => (),
            Err(e) => return Err(e.into()),
        }
        Ok(())
    })();
    let _ = fs::remove_file(&temporary);
    result.context("cannot migrate history to Documents/Yeti3Cleaner; original database preserved")
}

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

fn to_i64(value: u64) -> i64 {
    value.min(i64::MAX as u64) as i64
}

fn from_i64(value: i64) -> u64 {
    value.max(0) as u64
}

pub fn parent_path(path: &Path) -> Option<PathBuf> {
    path.parent().map(Path::to_path_buf)
}

pub fn latest_result_json() -> Result<String> {
    let db = HistoryDb::open()?;

    let Some(run) = db.latest_cleanup()? else {
        return Ok("{}".to_string());
    };

    let categories = db.category_totals(run.id)?;

    let category_json = categories
        .iter()
        .take(5)
        .map(|c| {
            serde_json::json!({
                "category": c.category,
                "bytes": c.reclaimed_bytes,
                "files": c.files,
                "errors": c.errors
            })
        })
        .collect::<Vec<_>>();

    Ok(serde_json::json!({
        "id": run.id,
        "started_at": run.started_at,
        "finished_at": run.finished_at,
        "disk_total": run.disk_total,
        "free_before": run.free_before,
        "free_after": run.free_after.unwrap_or(run.free_before),
        "discovered_bytes": run.discovered_bytes,
        "reclaimed_bytes": run.reclaimed_bytes,
        "files_deleted": run.files_deleted,
        "dirs_deleted": run.dirs_deleted,
        "skipped": run.skipped,
        "errors": run.errors,
        "duration_ms": run.duration_ms,
        "status": run.status,
        "categories": category_json
    })
    .to_string())
}

pub fn result_path() -> Result<PathBuf> {
    let home = dirs::home_dir().context("cannot determine HOME")?;

    Ok(home.join("Library/Application Support/Yeti3-Cleaner/latest-result.json"))
}

pub fn write_latest_result() -> Result<()> {
    let path = result_path()?;

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    let tmp = path.with_extension("tmp");

    fs::write(&tmp, latest_result_json()?)?;
    fs::rename(tmp, path)?;

    Ok(())
}

#[derive(Debug, Clone)]
pub struct StatisticsRun {
    pub started_at: i64,
    pub reclaimed_bytes: u64,
    pub free_before: u64,
    pub free_after: u64,
    pub errors: u64,
}

#[derive(Debug, Clone)]
pub struct StatisticsCategory {
    pub category: String,
    pub reclaimed_bytes: u64,
    pub objects: u64,
}

#[derive(Debug, Clone)]
pub struct StatisticsSnapshot {
    pub runs: u64,
    pub reclaimed_bytes: u64,
    pub files_deleted: u64,
    pub dirs_deleted: u64,
    pub skipped: u64,
    pub errors: u64,
    pub first_free_before: u64,
    pub latest_free_after: u64,
    pub recent_runs: Vec<StatisticsRun>,
    pub categories: Vec<StatisticsCategory>,
}

impl HistoryDb {
    pub fn statistics_snapshot(&self, days: Option<u64>) -> Result<StatisticsSnapshot> {
        let cutoff = days
            .map(|days| {
                now().saturating_sub((days.saturating_mul(86_400)).min(i64::MAX as u64) as i64)
            })
            .unwrap_or(0);

        let (runs, reclaimed, files, dirs, skipped, errors): (i64, i64, i64, i64, i64, i64) =
            self.conn.query_row(
                r#"
                SELECT
                    COUNT(*),
                    COALESCE(SUM(reclaimed_bytes), 0),
                    COALESCE(SUM(files_deleted), 0),
                    COALESCE(SUM(dirs_deleted), 0),
                    COALESCE(SUM(skipped), 0),
                    COALESCE(SUM(errors), 0)
                FROM cleanup_runs
                WHERE started_at >= ?1
                  AND status != 'running'
                "#,
                [cutoff],
                |row| {
                    Ok((
                        row.get(0)?,
                        row.get(1)?,
                        row.get(2)?,
                        row.get(3)?,
                        row.get(4)?,
                        row.get(5)?,
                    ))
                },
            )?;

        let first_free_before = self
            .conn
            .query_row(
                r#"
                SELECT free_before
                FROM cleanup_runs
                WHERE started_at >= ?1
                  AND status != 'running'
                ORDER BY started_at ASC
                LIMIT 1
                "#,
                [cutoff],
                |row| row.get::<_, i64>(0),
            )
            .optional()?
            .map(from_i64)
            .unwrap_or(0);

        let latest_free_after = self
            .conn
            .query_row(
                r#"
                SELECT COALESCE(free_after, free_before)
                FROM cleanup_runs
                WHERE started_at >= ?1
                  AND status != 'running'
                ORDER BY started_at DESC
                LIMIT 1
                "#,
                [cutoff],
                |row| row.get::<_, i64>(0),
            )
            .optional()?
            .map(from_i64)
            .unwrap_or(0);

        let mut recent_stmt = self.conn.prepare(
            r#"
            SELECT
                started_at,
                reclaimed_bytes,
                free_before,
                COALESCE(free_after, free_before),
                errors
            FROM cleanup_runs
            WHERE started_at >= ?1
              AND status != 'running'
            ORDER BY started_at DESC
            LIMIT 12
            "#,
        )?;

        let recent_runs = recent_stmt
            .query_map([cutoff], |row| {
                Ok(StatisticsRun {
                    started_at: row.get(0)?,
                    reclaimed_bytes: from_i64(row.get(1)?),
                    free_before: from_i64(row.get(2)?),
                    free_after: from_i64(row.get(3)?),
                    errors: from_i64(row.get(4)?),
                })
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;

        let mut category_stmt = self.conn.prepare(
            r#"
            SELECT
                e.category,
                COALESCE(SUM(e.bytes_reclaimed), 0),
                COUNT(*)
            FROM cleanup_entries e
            JOIN cleanup_runs r ON r.id = e.run_id
            WHERE r.started_at >= ?1
              AND r.status != 'running'
            GROUP BY e.category
            ORDER BY SUM(e.bytes_reclaimed) DESC
            LIMIT 8
            "#,
        )?;

        let categories = category_stmt
            .query_map([cutoff], |row| {
                Ok(StatisticsCategory {
                    category: row.get(0)?,
                    reclaimed_bytes: from_i64(row.get(1)?),
                    objects: from_i64(row.get(2)?),
                })
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;

        Ok(StatisticsSnapshot {
            runs: from_i64(runs),
            reclaimed_bytes: from_i64(reclaimed),
            files_deleted: from_i64(files),
            dirs_deleted: from_i64(dirs),
            skipped: from_i64(skipped),
            errors: from_i64(errors),
            first_free_before,
            latest_free_after,
            recent_runs,
            categories,
        })
    }
}

#[derive(Debug, Clone)]
pub struct StatisticsDetail {
    pub category: String,
    pub path: String,
    pub parent_path: Option<String>,
    pub kind: String,
    pub bytes_before: u64,
    pub bytes_reclaimed: u64,
    pub rule: String,
    pub result: String,
    pub error: Option<String>,
}

impl HistoryDb {
    pub fn latest_errors(&self) -> Result<Vec<(String, String, String)>> {
        let mut statement = self.conn.prepare(
            "SELECT category, path, COALESCE(error, 'Причина не указана') \
             FROM cleanup_entries \
             WHERE run_id = (SELECT MAX(id) FROM cleanup_runs WHERE status != 'running') \
               AND result = 'error' ORDER BY id",
        )?;
        let rows = statement.query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?))
        })?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    pub fn statistics_details(
        &self,
        days: Option<u64>,
        limit: usize,
    ) -> Result<Vec<StatisticsDetail>> {
        let cutoff = days
            .map(|days| {
                now().saturating_sub((days.saturating_mul(86_400)).min(i64::MAX as u64) as i64)
            })
            .unwrap_or(0);

        let safe_limit = i64::try_from(limit.min(500)).unwrap_or(500);

        let mut statement = self.conn.prepare(
            r#"
            SELECT
                e.category,
                e.path,
                e.parent_path,
                e.kind,
                e.bytes_before,
                e.bytes_reclaimed,
                e.rule,
                e.result,
                e.error
            FROM cleanup_entries e
            JOIN cleanup_runs r
              ON r.id = e.run_id
            WHERE r.started_at >= ?1
              AND r.status != 'running'
            ORDER BY
                e.bytes_reclaimed DESC,
                e.id DESC
            LIMIT ?2
            "#,
        )?;

        let rows = statement.query_map(rusqlite::params![cutoff, safe_limit], |row| {
            Ok(StatisticsDetail {
                category: row.get(0)?,
                path: row.get(1)?,
                parent_path: row.get(2)?,
                kind: row.get(3)?,
                bytes_before: from_i64(row.get(4)?),
                bytes_reclaimed: from_i64(row.get(5)?),
                rule: row.get(6)?,
                result: row.get(7)?,
                error: row.get(8)?,
            })
        })?;

        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn migration_preserves_wal_and_existing_destination() -> Result<()> {
        let root = std::env::temp_dir().join(format!("yeti-history-test-{}-{}", std::process::id(), SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()));
        fs::create_dir_all(&root)?;
        let old = root.join("old.sqlite3");
        let new = root.join("Documents/Yeti3Cleaner/history.sqlite3");
        let source = Connection::open(&old)?;
        source.execute_batch("PRAGMA journal_mode=WAL; CREATE TABLE sample(value); INSERT INTO sample VALUES(42);")?;
        migrate_legacy_database(&old, &new)?;
        let target = Connection::open(&new)?;
        assert_eq!(target.query_row("SELECT value FROM sample", [], |row| row.get::<_, i64>(0))?, 42);
        source.execute("INSERT INTO sample VALUES(99)", [])?;
        migrate_legacy_database(&old, &new)?;
        assert_eq!(target.query_row("SELECT count(*) FROM sample", [], |row| row.get::<_, i64>(0))?, 1);
        assert!(old.exists());
        drop(target); drop(source);
        fs::remove_file(&new)?;
        fs::write(&old, b"corrupt database")?;
        assert!(migrate_legacy_database(&old, &new).is_err());
        assert!(!new.exists());
        fs::remove_dir_all(root)?;
        Ok(())
    }

    #[test]
    fn unsigned_database_conversion_is_safe() {
        assert_eq!(from_i64(-1), 0);
        assert_eq!(from_i64(42), 42);
        assert_eq!(to_i64(42), 42);
    }

    #[test]
    fn parent_is_calculated() {
        assert_eq!(
            parent_path(Path::new("/tmp/a/b")),
            Some(PathBuf::from("/tmp/a"))
        );
    }
}
