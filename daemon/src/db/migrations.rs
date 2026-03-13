use anyhow::Result;
use rusqlite::Connection;

const MIGRATIONS: &[(&str, &str)] = &[
    ("001_projects_worktrees", include_str!("../../sql/001_projects_worktrees.sql")),
    ("002_sessions", include_str!("../../sql/002_sessions.sql")),
    ("003_comments", include_str!("../../sql/003_comments.sql")),
    ("004_events", include_str!("../../sql/004_events.sql")),
    ("005_agent_configs", include_str!("../../sql/005_agent_configs.sql")),
];

pub fn run(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS schema_migrations (
            name TEXT PRIMARY KEY,
            applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%f','now'))
        );",
    )?;

    for (name, sql) in MIGRATIONS {
        let already_applied: bool = conn.query_row(
            "SELECT COUNT(*) > 0 FROM schema_migrations WHERE name = ?1",
            [name],
            |row| row.get(0),
        )?;

        if !already_applied {
            tracing::info!("applying migration: {name}");
            conn.execute_batch(sql)?;
            conn.execute(
                "INSERT INTO schema_migrations (name) VALUES (?1)",
                [name],
            )?;
        }
    }

    Ok(())
}
