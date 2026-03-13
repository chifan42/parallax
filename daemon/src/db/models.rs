use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectRow {
    pub id: String,
    pub name: String,
    pub repo_path: String,
    pub default_branch: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorktreeRow {
    pub id: String,
    pub project_id: String,
    pub name: String,
    pub path: String,
    pub branch: String,
    pub source_branch: String,
    pub prescript_override: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionRow {
    pub id: String,
    pub worktree_id: String,
    pub agent_type: String,
    pub acp_session_id: Option<String>,
    pub state: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoundRow {
    pub id: String,
    pub session_id: String,
    pub round_number: i64,
    pub prompt_text: String,
    pub output_content: String,
    pub stop_reason: Option<String>,
    pub started_at: String,
    pub completed_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolCallRow {
    pub id: String,
    pub round_id: String,
    pub title: String,
    pub kind: String,
    pub status: String,
    pub content_json: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PermissionLogRow {
    pub id: String,
    pub session_id: String,
    pub round_id: Option<String>,
    pub tool_call_id: Option<String>,
    pub request_json: String,
    pub outcome: String,
    pub responded_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommentRow {
    pub id: String,
    pub round_id: String,
    pub revision_id: String,
    pub start_offset: i64,
    pub end_offset: i64,
    pub quoted_text: String,
    pub comment_text: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventRow {
    pub id: i64,
    pub event_type: String,
    pub entity_type: Option<String>,
    pub entity_id: Option<String>,
    pub payload_json: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentConfigRow {
    pub id: String,
    pub name: String,
    pub display_name: String,
    pub binary_path: String,
    pub args_json: String,
    pub env_json: String,
    pub enabled: bool,
    pub created_at: String,
}
