use anyhow::{Result, bail};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

use crate::db::models::{RoundRow, SessionRow};
use crate::db::queries;
use crate::AppState;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SessionState {
    Queued,
    Running,
    WaitingInput,
    ReviewRequired,
    Completed,
    Failed,
    Interrupted,
    Stopped,
}

impl SessionState {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Queued => "queued",
            Self::Running => "running",
            Self::WaitingInput => "waiting_input",
            Self::ReviewRequired => "review_required",
            Self::Completed => "completed",
            Self::Failed => "failed",
            Self::Interrupted => "interrupted",
            Self::Stopped => "stopped",
        }
    }

    pub fn from_str(s: &str) -> Result<Self> {
        match s {
            "queued" => Ok(Self::Queued),
            "running" => Ok(Self::Running),
            "waiting_input" => Ok(Self::WaitingInput),
            "review_required" => Ok(Self::ReviewRequired),
            "completed" => Ok(Self::Completed),
            "failed" => Ok(Self::Failed),
            "interrupted" => Ok(Self::Interrupted),
            "stopped" => Ok(Self::Stopped),
            _ => bail!("unknown session state: {s}"),
        }
    }

    pub fn is_terminal(&self) -> bool {
        matches!(
            self,
            Self::Completed | Self::Failed | Self::Interrupted | Self::Stopped
        )
    }

    pub fn can_transition_to(&self, next: Self) -> bool {
        use SessionState::*;
        match (self, next) {
            (Queued, Running) => true,
            (Running, WaitingInput | ReviewRequired | Completed | Failed | Stopped) => true,
            (WaitingInput, Running | Stopped | Failed) => true,
            (ReviewRequired, Running) => true, // re-run
            (Completed, Running) => true,
            _ => false,
        }
    }
}

pub fn create_session(
    state: &Arc<AppState>,
    worktree_id: &str,
    agent_type: &str,
) -> Result<SessionRow> {
    // Verify worktree exists
    let _wt = state
        .db
        .with_conn(|conn| queries::get_worktree(conn, worktree_id))?
        .ok_or_else(|| anyhow::anyhow!("worktree not found: {worktree_id}"))?;

    let now = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string();
    let session = SessionRow {
        id: uuid::Uuid::new_v4().to_string(),
        worktree_id: worktree_id.to_string(),
        agent_type: agent_type.to_string(),
        acp_session_id: None,
        state: SessionState::Queued.as_str().to_string(),
        created_at: now.clone(),
        updated_at: now,
    };

    state.db.with_conn(|conn| {
        queries::insert_session(conn, &session)?;
        Ok(())
    })?;

    Ok(session)
}

pub fn update_state(state: &Arc<AppState>, session_id: &str, new_state: SessionState) -> Result<()> {
    let session = state
        .db
        .with_conn(|conn| queries::get_session(conn, session_id))?
        .ok_or_else(|| anyhow::anyhow!("session not found: {session_id}"))?;

    let current = SessionState::from_str(&session.state)?;
    if !current.can_transition_to(new_state) {
        bail!(
            "invalid state transition: {} -> {}",
            current.as_str(),
            new_state.as_str()
        );
    }

    state.db.with_conn(|conn| {
        queries::update_session_state(conn, session_id, new_state.as_str())
    })
}

pub fn create_round(
    state: &Arc<AppState>,
    session_id: &str,
    prompt_text: &str,
) -> Result<RoundRow> {
    let round_number = state.db.with_conn(|conn| {
        let latest = queries::get_latest_round(conn, session_id)?;
        Ok::<i64, anyhow::Error>(latest.map(|r| r.round_number + 1).unwrap_or(1))
    })?;

    let now = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string();
    let round = RoundRow {
        id: uuid::Uuid::new_v4().to_string(),
        session_id: session_id.to_string(),
        round_number,
        prompt_text: prompt_text.to_string(),
        output_content: String::new(),
        stop_reason: None,
        started_at: now,
        completed_at: None,
    };

    state.db.with_conn(|conn| {
        queries::insert_round(conn, &round)?;
        Ok(())
    })?;

    Ok(round)
}

pub fn list_sessions(state: &Arc<AppState>, worktree_id: &str) -> Result<Vec<SessionRow>> {
    state.db.with_conn(|conn| queries::list_sessions(conn, worktree_id))
}

pub fn get_session(state: &Arc<AppState>, id: &str) -> Result<Option<SessionRow>> {
    state.db.with_conn(|conn| queries::get_session(conn, id))
}

// ── Output Block types ──

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum OutputBlock {
    Text { content: String },
    Thinking { content: String },
    ToolCall {
        id: String,
        title: String,
        kind: String,
        status: String,
        content: Option<String>,
    },
    Plan { entries: Vec<PlanEntry> },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanEntry {
    pub title: String,
    pub status: String,
}

pub fn parse_output_blocks(output_content: &str) -> Vec<OutputBlock> {
    if output_content.is_empty() {
        return Vec::new();
    }
    serde_json::from_str(output_content).unwrap_or_default()
}

pub fn serialize_output_blocks(blocks: &[OutputBlock]) -> String {
    serde_json::to_string(blocks).unwrap_or_else(|_| "[]".to_string())
}
