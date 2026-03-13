use serde::{Deserialize, Serialize};
use serde_json::Value;

/// JSON-RPC 2.0 request
#[derive(Debug, Clone, Deserialize)]
pub struct JsonRpcRequest {
    pub jsonrpc: String,
    pub id: Option<Value>,
    pub method: String,
    #[serde(default)]
    pub params: Value,
}

/// JSON-RPC 2.0 response
#[derive(Debug, Clone, Serialize)]
pub struct JsonRpcResponse {
    pub jsonrpc: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<JsonRpcError>,
}

#[derive(Debug, Clone, Serialize)]
pub struct JsonRpcError {
    pub code: i64,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
}

/// JSON-RPC 2.0 notification (no id)
#[derive(Debug, Clone, Serialize)]
pub struct JsonRpcNotification {
    pub jsonrpc: String,
    pub method: String,
    pub params: Value,
}

impl JsonRpcResponse {
    pub fn success(id: Option<Value>, result: Value) -> Self {
        Self {
            jsonrpc: "2.0".into(),
            id,
            result: Some(result),
            error: None,
        }
    }

    pub fn error(id: Option<Value>, code: i64, message: impl Into<String>) -> Self {
        Self {
            jsonrpc: "2.0".into(),
            id,
            result: None,
            error: Some(JsonRpcError {
                code,
                message: message.into(),
                data: None,
            }),
        }
    }
}

/// Internal notification types broadcast from daemon to connected clients
#[derive(Debug, Clone)]
pub enum Notification {
    SessionStateChanged {
        session_id: String,
        state: String,
    },
    SessionOutput {
        session_id: String,
        round_id: String,
        content: String,
    },
    SessionPermissionRequest {
        session_id: String,
        request_id: String,
        tool_name: String,
        description: String,
    },
    PrescriptOutput {
        worktree_id: String,
        line: String,
        stream: String,
    },
    PrescriptComplete {
        worktree_id: String,
        exit_code: i32,
    },
    WorktreeUpdated {
        worktree_id: String,
    },
    ProjectUpdated {
        project_id: String,
    },
}

impl Notification {
    pub fn to_jsonrpc(&self) -> JsonRpcNotification {
        let (method, params) = match self {
            Self::SessionStateChanged { session_id, state } => (
                "session/stateChanged",
                serde_json::json!({ "session_id": session_id, "state": state }),
            ),
            Self::SessionOutput {
                session_id,
                round_id,
                content,
            } => (
                "session/output",
                serde_json::json!({ "session_id": session_id, "round_id": round_id, "content": content }),
            ),
            Self::SessionPermissionRequest {
                session_id,
                request_id,
                tool_name,
                description,
            } => (
                "session/permissionRequest",
                serde_json::json!({
                    "session_id": session_id,
                    "request_id": request_id,
                    "tool_name": tool_name,
                    "description": description,
                }),
            ),
            Self::PrescriptOutput {
                worktree_id,
                line,
                stream,
            } => (
                "prescript/output",
                serde_json::json!({ "worktree_id": worktree_id, "line": line, "stream": stream }),
            ),
            Self::PrescriptComplete {
                worktree_id,
                exit_code,
            } => (
                "prescript/complete",
                serde_json::json!({ "worktree_id": worktree_id, "exit_code": exit_code }),
            ),
            Self::WorktreeUpdated { worktree_id } => (
                "worktree/updated",
                serde_json::json!({ "worktree_id": worktree_id }),
            ),
            Self::ProjectUpdated { project_id } => (
                "project/updated",
                serde_json::json!({ "project_id": project_id }),
            ),
        };

        JsonRpcNotification {
            jsonrpc: "2.0".into(),
            method: method.into(),
            params,
        }
    }
}
