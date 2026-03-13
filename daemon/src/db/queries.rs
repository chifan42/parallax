use anyhow::Result;
use rusqlite::{params, Connection};

use super::models::*;

fn now() -> String {
    chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string()
}

// ── Projects ──

pub fn insert_project(conn: &Connection, project: &ProjectRow) -> Result<()> {
    conn.execute(
        "INSERT INTO projects (id, name, repo_path, default_branch, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![
            project.id,
            project.name,
            project.repo_path,
            project.default_branch,
            project.created_at,
            project.updated_at,
        ],
    )?;
    Ok(())
}

pub fn list_projects(conn: &Connection) -> Result<Vec<ProjectRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, name, repo_path, default_branch, created_at, updated_at FROM projects ORDER BY name",
    )?;
    let rows = stmt.query_map([], |row| {
        Ok(ProjectRow {
            id: row.get(0)?,
            name: row.get(1)?,
            repo_path: row.get(2)?,
            default_branch: row.get(3)?,
            created_at: row.get(4)?,
            updated_at: row.get(5)?,
        })
    })?;
    Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
}

pub fn get_project(conn: &Connection, id: &str) -> Result<Option<ProjectRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, name, repo_path, default_branch, created_at, updated_at FROM projects WHERE id = ?1",
    )?;
    let mut rows = stmt.query_map([id], |row| {
        Ok(ProjectRow {
            id: row.get(0)?,
            name: row.get(1)?,
            repo_path: row.get(2)?,
            default_branch: row.get(3)?,
            created_at: row.get(4)?,
            updated_at: row.get(5)?,
        })
    })?;
    Ok(rows.next().transpose()?)
}

pub fn delete_project(conn: &Connection, id: &str) -> Result<bool> {
    let count = conn.execute("DELETE FROM projects WHERE id = ?1", [id])?;
    Ok(count > 0)
}

// ── Worktrees ──

pub fn insert_worktree(conn: &Connection, wt: &WorktreeRow) -> Result<()> {
    conn.execute(
        "INSERT INTO worktrees (id, project_id, name, path, branch, source_branch, prescript_override, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        params![wt.id, wt.project_id, wt.name, wt.path, wt.branch, wt.source_branch, wt.prescript_override, wt.created_at],
    )?;
    Ok(())
}

pub fn list_worktrees(conn: &Connection, project_id: &str) -> Result<Vec<WorktreeRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, project_id, name, path, branch, source_branch, prescript_override, created_at
         FROM worktrees WHERE project_id = ?1 ORDER BY name",
    )?;
    let rows = stmt.query_map([project_id], |row| {
        Ok(WorktreeRow {
            id: row.get(0)?,
            project_id: row.get(1)?,
            name: row.get(2)?,
            path: row.get(3)?,
            branch: row.get(4)?,
            source_branch: row.get(5)?,
            prescript_override: row.get(6)?,
            created_at: row.get(7)?,
        })
    })?;
    Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
}

pub fn get_worktree(conn: &Connection, id: &str) -> Result<Option<WorktreeRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, project_id, name, path, branch, source_branch, prescript_override, created_at
         FROM worktrees WHERE id = ?1",
    )?;
    let mut rows = stmt.query_map([id], |row| {
        Ok(WorktreeRow {
            id: row.get(0)?,
            project_id: row.get(1)?,
            name: row.get(2)?,
            path: row.get(3)?,
            branch: row.get(4)?,
            source_branch: row.get(5)?,
            prescript_override: row.get(6)?,
            created_at: row.get(7)?,
        })
    })?;
    Ok(rows.next().transpose()?)
}

pub fn delete_worktree(conn: &Connection, id: &str) -> Result<bool> {
    let count = conn.execute("DELETE FROM worktrees WHERE id = ?1", [id])?;
    Ok(count > 0)
}

// ── Sessions ──

pub fn insert_session(conn: &Connection, s: &SessionRow) -> Result<()> {
    conn.execute(
        "INSERT INTO sessions (id, worktree_id, agent_type, acp_session_id, state, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![s.id, s.worktree_id, s.agent_type, s.acp_session_id, s.state, s.created_at, s.updated_at],
    )?;
    Ok(())
}

pub fn update_session_state(conn: &Connection, id: &str, state: &str) -> Result<()> {
    conn.execute(
        "UPDATE sessions SET state = ?2, updated_at = ?3 WHERE id = ?1",
        params![id, state, now()],
    )?;
    Ok(())
}

pub fn update_session_acp_id(conn: &Connection, id: &str, acp_session_id: &str) -> Result<()> {
    conn.execute(
        "UPDATE sessions SET acp_session_id = ?2, updated_at = ?3 WHERE id = ?1",
        params![id, acp_session_id, now()],
    )?;
    Ok(())
}

pub fn list_sessions(conn: &Connection, worktree_id: &str) -> Result<Vec<SessionRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, worktree_id, agent_type, acp_session_id, state, created_at, updated_at
         FROM sessions WHERE worktree_id = ?1 ORDER BY created_at DESC",
    )?;
    let rows = stmt.query_map([worktree_id], |row| {
        Ok(SessionRow {
            id: row.get(0)?,
            worktree_id: row.get(1)?,
            agent_type: row.get(2)?,
            acp_session_id: row.get(3)?,
            state: row.get(4)?,
            created_at: row.get(5)?,
            updated_at: row.get(6)?,
        })
    })?;
    Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
}

pub fn get_session(conn: &Connection, id: &str) -> Result<Option<SessionRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, worktree_id, agent_type, acp_session_id, state, created_at, updated_at
         FROM sessions WHERE id = ?1",
    )?;
    let mut rows = stmt.query_map([id], |row| {
        Ok(SessionRow {
            id: row.get(0)?,
            worktree_id: row.get(1)?,
            agent_type: row.get(2)?,
            acp_session_id: row.get(3)?,
            state: row.get(4)?,
            created_at: row.get(5)?,
            updated_at: row.get(6)?,
        })
    })?;
    Ok(rows.next().transpose()?)
}

// ── Rounds ──

pub fn insert_round(conn: &Connection, r: &RoundRow) -> Result<()> {
    conn.execute(
        "INSERT INTO rounds (id, session_id, round_number, prompt_text, output_content, stop_reason, started_at, completed_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        params![r.id, r.session_id, r.round_number, r.prompt_text, r.output_content, r.stop_reason, r.started_at, r.completed_at],
    )?;
    Ok(())
}

pub fn update_round_output(conn: &Connection, id: &str, output: &str) -> Result<()> {
    conn.execute(
        "UPDATE rounds SET output_content = ?2 WHERE id = ?1",
        params![id, output],
    )?;
    Ok(())
}

pub fn complete_round(conn: &Connection, id: &str, stop_reason: &str) -> Result<()> {
    conn.execute(
        "UPDATE rounds SET stop_reason = ?2, completed_at = ?3 WHERE id = ?1",
        params![id, stop_reason, now()],
    )?;
    Ok(())
}

pub fn list_rounds(conn: &Connection, session_id: &str) -> Result<Vec<RoundRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, session_id, round_number, prompt_text, output_content, stop_reason, started_at, completed_at
         FROM rounds WHERE session_id = ?1 ORDER BY round_number",
    )?;
    let rows = stmt.query_map([session_id], |row| {
        Ok(RoundRow {
            id: row.get(0)?,
            session_id: row.get(1)?,
            round_number: row.get(2)?,
            prompt_text: row.get(3)?,
            output_content: row.get(4)?,
            stop_reason: row.get(5)?,
            started_at: row.get(6)?,
            completed_at: row.get(7)?,
        })
    })?;
    Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
}

pub fn get_latest_round(conn: &Connection, session_id: &str) -> Result<Option<RoundRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, session_id, round_number, prompt_text, output_content, stop_reason, started_at, completed_at
         FROM rounds WHERE session_id = ?1 ORDER BY round_number DESC LIMIT 1",
    )?;
    let mut rows = stmt.query_map([session_id], |row| {
        Ok(RoundRow {
            id: row.get(0)?,
            session_id: row.get(1)?,
            round_number: row.get(2)?,
            prompt_text: row.get(3)?,
            output_content: row.get(4)?,
            stop_reason: row.get(5)?,
            started_at: row.get(6)?,
            completed_at: row.get(7)?,
        })
    })?;
    Ok(rows.next().transpose()?)
}

// ── Tool Calls ──

pub fn insert_tool_call(conn: &Connection, tc: &ToolCallRow) -> Result<()> {
    conn.execute(
        "INSERT INTO tool_calls (id, round_id, title, kind, status, content_json, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        params![tc.id, tc.round_id, tc.title, tc.kind, tc.status, tc.content_json, tc.created_at, tc.updated_at],
    )?;
    Ok(())
}

pub fn update_tool_call_status(conn: &Connection, id: &str, status: &str) -> Result<()> {
    conn.execute(
        "UPDATE tool_calls SET status = ?2, updated_at = ?3 WHERE id = ?1",
        params![id, status, now()],
    )?;
    Ok(())
}

// ── Permission Log ──

pub fn insert_permission_log(conn: &Connection, pl: &PermissionLogRow) -> Result<()> {
    conn.execute(
        "INSERT INTO permission_log (id, session_id, round_id, tool_call_id, request_json, outcome, responded_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![pl.id, pl.session_id, pl.round_id, pl.tool_call_id, pl.request_json, pl.outcome, pl.responded_at],
    )?;
    Ok(())
}

// ── Comments ──

pub fn insert_comment(conn: &Connection, c: &CommentRow) -> Result<()> {
    conn.execute(
        "INSERT INTO comments (id, round_id, revision_id, start_offset, end_offset, quoted_text, comment_text, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        params![c.id, c.round_id, c.revision_id, c.start_offset, c.end_offset, c.quoted_text, c.comment_text, c.created_at],
    )?;
    Ok(())
}

pub fn list_comments(conn: &Connection, round_id: &str) -> Result<Vec<CommentRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, round_id, revision_id, start_offset, end_offset, quoted_text, comment_text, created_at
         FROM comments WHERE round_id = ?1 ORDER BY start_offset",
    )?;
    let rows = stmt.query_map([round_id], |row| {
        Ok(CommentRow {
            id: row.get(0)?,
            round_id: row.get(1)?,
            revision_id: row.get(2)?,
            start_offset: row.get(3)?,
            end_offset: row.get(4)?,
            quoted_text: row.get(5)?,
            comment_text: row.get(6)?,
            created_at: row.get(7)?,
        })
    })?;
    Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
}

pub fn delete_comment(conn: &Connection, id: &str) -> Result<bool> {
    let count = conn.execute("DELETE FROM comments WHERE id = ?1", [id])?;
    Ok(count > 0)
}

// ── Events ──

pub fn insert_event(
    conn: &Connection,
    event_type: &str,
    entity_type: Option<&str>,
    entity_id: Option<&str>,
    payload_json: &str,
) -> Result<i64> {
    conn.execute(
        "INSERT INTO events (event_type, entity_type, entity_id, payload_json)
         VALUES (?1, ?2, ?3, ?4)",
        params![event_type, entity_type, entity_id, payload_json],
    )?;
    Ok(conn.last_insert_rowid())
}

// ── Agent Configs ──

pub fn list_agent_configs(conn: &Connection) -> Result<Vec<AgentConfigRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, name, display_name, binary_path, args_json, env_json, enabled, created_at
         FROM agent_configs WHERE enabled = 1 ORDER BY display_name",
    )?;
    let rows = stmt.query_map([], |row| {
        Ok(AgentConfigRow {
            id: row.get(0)?,
            name: row.get(1)?,
            display_name: row.get(2)?,
            binary_path: row.get(3)?,
            args_json: row.get(4)?,
            env_json: row.get(5)?,
            enabled: row.get(6)?,
            created_at: row.get(7)?,
        })
    })?;
    Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
}

pub fn get_agent_config(conn: &Connection, id: &str) -> Result<Option<AgentConfigRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, name, display_name, binary_path, args_json, env_json, enabled, created_at
         FROM agent_configs WHERE id = ?1",
    )?;
    let mut rows = stmt.query_map([id], |row| {
        Ok(AgentConfigRow {
            id: row.get(0)?,
            name: row.get(1)?,
            display_name: row.get(2)?,
            binary_path: row.get(3)?,
            args_json: row.get(4)?,
            env_json: row.get(5)?,
            enabled: row.get(6)?,
            created_at: row.get(7)?,
        })
    })?;
    Ok(rows.next().transpose()?)
}
