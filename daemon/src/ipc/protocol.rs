use std::sync::Arc;

use serde_json::{json, Value};

use super::types::{JsonRpcRequest, JsonRpcResponse};
use crate::domain::{comment, prescript, project, session, worktree};
use crate::db::queries;
use crate::git;
use crate::event_log;
use crate::AppState;

pub async fn dispatch(state: &Arc<AppState>, req: JsonRpcRequest) -> JsonRpcResponse {
    let id = req.id.clone();
    match req.method.as_str() {
        "ping" => JsonRpcResponse::success(id, json!({"status": "ok"})),

        // ── Projects ──
        "project/add" => handle_project_add(state, id, req.params).await,
        "project/list" => handle_project_list(state, id),
        "project/remove" => handle_project_remove(state, id, req.params),

        // ── Worktrees ──
        "worktree/create" => handle_worktree_create(state, id, req.params).await,
        "worktree/import" => handle_worktree_import(state, id, req.params).await,
        "worktree/delete" => handle_worktree_delete(state, id, req.params).await,
        "worktree/list" => handle_worktree_list(state, id, req.params),

        // ── Branches ──
        "branch/list" => handle_branch_list(state, id, req.params).await,
        "branch/default" => handle_branch_default(state, id, req.params).await,

        // ── Sessions ──
        "session/create" => handle_session_create(state, id, req.params),
        "session/prompt" => handle_session_prompt(state, id, req.params).await,
        "session/cancel" | "session/stop" => handle_session_stop(state, id, req.params),
        "session/list" => handle_session_list(state, id, req.params),
        "session/get" => handle_session_get(state, id, req.params),
        "session/respondPermission" => handle_session_respond_permission(state, id, req.params),
        "session/rerun" => handle_session_rerun(state, id, req.params).await,

        // ── Rounds ──
        "round/list" => handle_round_list(state, id, req.params),

        // ── Comments ──
        "comment/create" => handle_comment_create(state, id, req.params),
        "comment/list" => handle_comment_list(state, id, req.params),
        "comment/delete" => handle_comment_delete(state, id, req.params),

        // ── Prescript ──
        "prescript/run" => handle_prescript_run(state, id, req.params).await,

        // ── Sync ──
        "sync/state" => handle_sync_state(state, id),

        // ── Terminal ──
        "terminal/exec" => handle_terminal_exec(state, id, req.params).await,
        "terminal/kill" => handle_terminal_kill(state, id, req.params).await,

        // ── Agents ──
        "agent/list" => handle_agent_list(state, id),

        _ => JsonRpcResponse::error(id, -32601, format!("method not found: {}", req.method)),
    }
}

fn param_str(params: &Value, key: &str) -> Option<String> {
    params.get(key).and_then(|v| v.as_str()).map(|s| s.to_string())
}

fn require_str(params: &Value, key: &str) -> Result<String, JsonRpcResponse> {
    param_str(params, key).ok_or_else(|| {
        JsonRpcResponse::error(None, -32602, format!("missing required param: {key}"))
    })
}

// ── Project handlers ──

async fn handle_project_add(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let repo_path = match require_str(&params, "repo_path") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    match project::add_project_async(state, &repo_path).await {
        Ok(p) => {
            let _ = state.event_tx.send(crate::ipc::types::Notification::ProjectUpdated {
                project_id: p.id.clone(),
            });
            JsonRpcResponse::success(id, serde_json::to_value(&p).unwrap())
        }
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

fn handle_project_list(state: &Arc<AppState>, id: Option<Value>) -> JsonRpcResponse {
    match project::list_projects(state) {
        Ok(projects) => JsonRpcResponse::success(id, serde_json::to_value(&projects).unwrap()),
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

fn handle_project_remove(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let project_id = match require_str(&params, "id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    match project::remove_project(state, &project_id) {
        Ok(removed) => JsonRpcResponse::success(id, json!({"removed": removed})),
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

// ── Worktree handlers ──

async fn handle_worktree_create(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let project_id = match require_str(&params, "project_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };
    let branch = match require_str(&params, "branch") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };
    let source_branch = match require_str(&params, "source_branch") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    match worktree::create_worktree(state, &project_id, &branch, &source_branch).await {
        Ok(wt) => {
            // Auto-trigger prescript
            let project = state.db.with_conn(|conn| queries::get_project(conn, &project_id)).ok().flatten();
            if let Some(project) = project {
                let script = prescript::resolve_prescript(wt.prescript_override.as_deref(), &project.repo_path);
                if let Some(script_path) = script {
                    let state_clone = Arc::clone(state);
                    let wt_id = wt.id.clone();
                    let wt_path = wt.path.clone();
                    tokio::spawn(async move {
                        let _ = prescript::run_prescript(&state_clone, &wt_id, &script_path, &wt_path).await;
                    });
                }
            }

            let _ = state.event_tx.send(crate::ipc::types::Notification::WorktreeUpdated {
                worktree_id: wt.id.clone(),
            });
            JsonRpcResponse::success(id, serde_json::to_value(&wt).unwrap())
        }
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

async fn handle_worktree_import(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let project_id = match require_str(&params, "project_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };
    let path = match require_str(&params, "path") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };
    let branch = match require_str(&params, "branch") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    match worktree::import_worktree(state, &project_id, &path, &branch).await {
        Ok(wt) => JsonRpcResponse::success(id, serde_json::to_value(&wt).unwrap()),
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

async fn handle_worktree_delete(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let wt_id = match require_str(&params, "id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };
    let remove_from_disk = params.get("remove_from_disk").and_then(|v| v.as_bool()).unwrap_or(true);

    match worktree::delete_worktree(state, &wt_id, remove_from_disk).await {
        Ok(removed) => JsonRpcResponse::success(id, json!({"removed": removed})),
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

fn handle_worktree_list(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let project_id = match require_str(&params, "project_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    match worktree::list_worktrees(state, &project_id) {
        Ok(wts) => JsonRpcResponse::success(id, serde_json::to_value(&wts).unwrap()),
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

// ── Branch handlers ──

async fn handle_branch_list(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let project_id = match require_str(&params, "project_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    let project = match state.db.with_conn(|conn| queries::get_project(conn, &project_id)) {
        Ok(Some(p)) => p,
        Ok(None) => return JsonRpcResponse::error(id, -32000, "project not found"),
        Err(e) => return JsonRpcResponse::error(id, -32000, e.to_string()),
    };

    match git::list_branches(&project.repo_path).await {
        Ok(branches) => JsonRpcResponse::success(id, json!({"branches": branches})),
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

async fn handle_branch_default(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let project_id = match require_str(&params, "project_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    let project = match state.db.with_conn(|conn| queries::get_project(conn, &project_id)) {
        Ok(Some(p)) => p,
        Ok(None) => return JsonRpcResponse::error(id, -32000, "project not found"),
        Err(e) => return JsonRpcResponse::error(id, -32000, e.to_string()),
    };

    match git::default_branch(&project.repo_path).await {
        Ok(branch) => JsonRpcResponse::success(id, json!({"branch": branch})),
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

// ── Session handlers ──

fn handle_session_create(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let worktree_id = match require_str(&params, "worktree_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };
    let agent_type = match require_str(&params, "agent_type") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    match session::create_session(state, &worktree_id, &agent_type) {
        Ok(s) => {
            let _ = event_log::log_event(
                state,
                "session_created",
                Some("session"),
                Some(&s.id),
                &serde_json::to_value(&s).unwrap(),
            );
            JsonRpcResponse::success(id, serde_json::to_value(&s).unwrap())
        }
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

async fn handle_session_prompt(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let session_id = match require_str(&params, "session_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };
    let prompt = match require_str(&params, "prompt") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    let sess = match state.db.with_conn(|conn| queries::get_session(conn, &session_id)) {
        Ok(Some(s)) => s,
        Ok(None) => return JsonRpcResponse::error(id, -32000, "session not found"),
        Err(e) => return JsonRpcResponse::error(id, -32000, e.to_string()),
    };
    let valid_prompt_states = ["queued", "waiting_input", "review_required"];
    if !valid_prompt_states.contains(&sess.state.as_str()) {
        return JsonRpcResponse::error(id, -32000, format!("cannot prompt session in state: {}", sess.state));
    }

    match session::create_round(state, &session_id, &prompt) {
        Ok(round) => {
            let _ = session::update_state(state, &session_id, session::SessionState::Running);
            let _ = state.event_tx.send(crate::ipc::types::Notification::SessionStateChanged {
                session_id: session_id.clone(),
                state: "running".into(),
            });

            if let Err(e) = spawn_agent_and_prompt(state, &session_id, &prompt).await {
                tracing::error!("failed to send prompt to agent: {e}");
                let _ = session::update_state(state, &session_id, session::SessionState::Failed);
                let _ = state.event_tx.send(crate::ipc::types::Notification::SessionStateChanged {
                    session_id: session_id.clone(),
                    state: "failed".into(),
                });
                return JsonRpcResponse::error(id, -32000, e.to_string());
            }

            JsonRpcResponse::success(id, serde_json::to_value(&round).unwrap())
        }
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

fn handle_session_stop(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let session_id = match require_str(&params, "session_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    let sess = match state.db.with_conn(|conn| queries::get_session(conn, &session_id)) {
        Ok(Some(s)) => s,
        Ok(None) => return JsonRpcResponse::error(id, -32000, "session not found"),
        Err(e) => return JsonRpcResponse::error(id, -32000, e.to_string()),
    };

    if let Some(ref acp_id) = sess.acp_session_id {
        let mgr = Arc::clone(&state.agent_manager);
        let sid = session_id.clone();
        let acp_id = acp_id.clone();
        tokio::spawn(async move {
            let _ = mgr.send_command(
                &sid,
                crate::acp::manager::AgentCommand::CancelSession {
                    acp_session_id: acp_id,
                },
            ).await;
        });
    }

    match session::update_state(state, &session_id, session::SessionState::Stopped) {
        Ok(()) => {
            let _ = state.event_tx.send(crate::ipc::types::Notification::SessionStateChanged {
                session_id,
                state: "stopped".into(),
            });
            JsonRpcResponse::success(id, json!({"ok": true}))
        }
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

fn handle_session_list(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let worktree_id = match require_str(&params, "worktree_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    match session::list_sessions(state, &worktree_id) {
        Ok(sessions) => JsonRpcResponse::success(id, serde_json::to_value(&sessions).unwrap()),
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

fn handle_session_get(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let session_id = match require_str(&params, "session_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    match session::get_session(state, &session_id) {
        Ok(Some(s)) => JsonRpcResponse::success(id, serde_json::to_value(&s).unwrap()),
        Ok(None) => JsonRpcResponse::error(id, -32000, "session not found"),
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

fn handle_session_respond_permission(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let session_id = match require_str(&params, "session_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };
    let request_id = match require_str(&params, "request_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };
    let outcome = match require_str(&params, "outcome") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    let mgr = Arc::clone(&state.agent_manager);
    let sid = session_id.clone();
    tokio::spawn(async move {
        let _ = mgr.send_command(
            &sid,
            crate::acp::manager::AgentCommand::RespondPermission {
                request_id,
                outcome,
            },
        ).await;
    });

    JsonRpcResponse::success(id, json!({"ok": true}))
}

async fn handle_session_rerun(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let session_id = match require_str(&params, "session_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };
    let user_notes = param_str(&params, "user_notes");

    let sess = match state.db.with_conn(|conn| queries::get_session(conn, &session_id)) {
        Ok(Some(s)) => s,
        Ok(None) => return JsonRpcResponse::error(id, -32000, "session not found"),
        Err(e) => return JsonRpcResponse::error(id, -32000, e.to_string()),
    };
    let valid_rerun_states = ["review_required", "completed"];
    if !valid_rerun_states.contains(&sess.state.as_str()) {
        return JsonRpcResponse::error(id, -32000, format!("cannot rerun session in state: {}", sess.state));
    }

    let latest_round = match state.db.with_conn(|conn| queries::get_latest_round(conn, &session_id)) {
        Ok(Some(r)) => r,
        Ok(None) => return JsonRpcResponse::error(id, -32000, "no rounds found for session"),
        Err(e) => return JsonRpcResponse::error(id, -32000, e.to_string()),
    };

    let comments = match comment::list_comments(state, &latest_round.id) {
        Ok(c) => c,
        Err(e) => return JsonRpcResponse::error(id, -32000, e.to_string()),
    };

    let prompt = comment::synthesize_rerun_prompt(&comments, user_notes.as_deref());

    match session::create_round(state, &session_id, &prompt) {
        Ok(round) => {
            let _ = session::update_state(state, &session_id, session::SessionState::Running);
            let _ = state.event_tx.send(crate::ipc::types::Notification::SessionStateChanged {
                session_id: session_id.clone(),
                state: "running".into(),
            });

            if let Err(e) = spawn_agent_and_prompt(state, &session_id, &prompt).await {
                tracing::error!("failed to send rerun prompt to agent: {e}");
                let _ = session::update_state(state, &session_id, session::SessionState::Failed);
                let _ = state.event_tx.send(crate::ipc::types::Notification::SessionStateChanged {
                    session_id: session_id.clone(),
                    state: "failed".into(),
                });
                return JsonRpcResponse::error(id, -32000, e.to_string());
            }

            JsonRpcResponse::success(id, serde_json::to_value(&round).unwrap())
        }
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

/// Ensure the agent is spawned for a session and send a prompt.
async fn spawn_agent_and_prompt(
    state: &Arc<AppState>,
    session_id: &str,
    prompt: &str,
) -> Result<(), String> {
    let sess = state
        .db
        .with_conn(|conn| queries::get_session(conn, session_id))
        .map_err(|e| e.to_string())?
        .ok_or_else(|| format!("session not found: {session_id}"))?;

    let wt = state
        .db
        .with_conn(|conn| queries::get_worktree(conn, &sess.worktree_id))
        .map_err(|e| e.to_string())?
        .ok_or_else(|| format!("worktree not found: {}", sess.worktree_id))?;

    let agent_config = state
        .db
        .with_conn(|conn| {
            let configs = queries::list_agent_configs(conn)?;
            Ok(configs.into_iter().find(|a| a.name == sess.agent_type))
        })
        .map_err(|e: anyhow::Error| e.to_string())?
        .ok_or_else(|| format!("agent config not found for type: {}", sess.agent_type))?;

    let args: Vec<String> =
        serde_json::from_str(&agent_config.args_json).unwrap_or_default();
    let env: std::collections::HashMap<String, String> =
        serde_json::from_str(&agent_config.env_json).unwrap_or_default();

    let needs_spawn = !state.agent_manager.has_agent(session_id).await;

    if needs_spawn {
        state
            .agent_manager
            .spawn_agent(session_id, &agent_config.binary_path, args, env, &wt.path)
            .await
            .map_err(|e| e.to_string())?;

        let (respond_tx, respond_rx) = tokio::sync::oneshot::channel();
        state
            .agent_manager
            .send_command(
                session_id,
                crate::acp::manager::AgentCommand::CreateSession {
                    session_id: session_id.to_string(),
                    working_dir: wt.path.clone(),
                    respond: respond_tx,
                },
            )
            .await
            .map_err(|e| e.to_string())?;

        respond_rx.await.map_err(|_| "channel closed".to_string())??;
    }

    let acp_session_id = state
        .db
        .with_conn(|conn| queries::get_session(conn, session_id))
        .map_err(|e| e.to_string())?
        .and_then(|s| s.acp_session_id)
        .ok_or_else(|| "no ACP session ID after creation".to_string())?;

    let (respond_tx, respond_rx) = tokio::sync::oneshot::channel();
    state
        .agent_manager
        .send_command(
            session_id,
            crate::acp::manager::AgentCommand::SendPrompt {
                session_id: session_id.to_string(),
                acp_session_id,
                prompt: prompt.to_string(),
                respond: respond_tx,
            },
        )
        .await
        .map_err(|e| e.to_string())?;

    tokio::spawn(async move {
        if let Ok(Err(e)) = respond_rx.await {
            tracing::error!("prompt execution failed: {e}");
        }
    });

    Ok(())
}

// ── Round handlers ──

fn handle_round_list(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let session_id = match require_str(&params, "session_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    match state.db.with_conn(|conn| queries::list_rounds(conn, &session_id)) {
        Ok(rounds) => JsonRpcResponse::success(id, serde_json::to_value(&rounds).unwrap()),
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

// ── Comment handlers ──

fn handle_comment_create(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let round_id = match require_str(&params, "round_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };
    let revision_id = match require_str(&params, "revision_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };
    let start_offset = params.get("start_offset").and_then(|v| v.as_i64()).unwrap_or(0);
    let end_offset = params.get("end_offset").and_then(|v| v.as_i64()).unwrap_or(0);
    let quoted_text = match require_str(&params, "quoted_text") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };
    let comment_text = match require_str(&params, "comment_text") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    match comment::create_comment(state, &round_id, &revision_id, start_offset, end_offset, &quoted_text, &comment_text) {
        Ok(c) => JsonRpcResponse::success(id, serde_json::to_value(&c).unwrap()),
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

fn handle_comment_list(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let round_id = match require_str(&params, "round_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    match comment::list_comments(state, &round_id) {
        Ok(comments) => JsonRpcResponse::success(id, serde_json::to_value(&comments).unwrap()),
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

fn handle_comment_delete(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let comment_id = match require_str(&params, "id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    match comment::delete_comment(state, &comment_id) {
        Ok(removed) => JsonRpcResponse::success(id, json!({"removed": removed})),
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

// ── Prescript handler ──

async fn handle_prescript_run(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let worktree_id = match require_str(&params, "worktree_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    let wt = match state.db.with_conn(|conn| queries::get_worktree(conn, &worktree_id)) {
        Ok(Some(w)) => w,
        Ok(None) => return JsonRpcResponse::error(id, -32000, "worktree not found"),
        Err(e) => return JsonRpcResponse::error(id, -32000, e.to_string()),
    };

    let project = match state.db.with_conn(|conn| queries::get_project(conn, &wt.project_id)) {
        Ok(Some(p)) => p,
        Ok(None) => return JsonRpcResponse::error(id, -32000, "project not found"),
        Err(e) => return JsonRpcResponse::error(id, -32000, e.to_string()),
    };

    let script = prescript::resolve_prescript(wt.prescript_override.as_deref(), &project.repo_path);
    match script {
        Some(script_path) => {
            let state_clone = Arc::clone(state);
            let wt_id = wt.id.clone();
            let wt_path = wt.path.clone();
            let script_path_clone = script_path.clone();
            tokio::spawn(async move {
                let _ = prescript::run_prescript(&state_clone, &wt_id, &script_path_clone, &wt_path).await;
            });
            JsonRpcResponse::success(id, json!({"started": true, "script_path": script_path}))
        }
        None => JsonRpcResponse::success(id, json!({"started": false, "reason": "no prescript found"})),
    }
}

// ── Sync handler ──

fn handle_sync_state(state: &Arc<AppState>, id: Option<Value>) -> JsonRpcResponse {
    let projects = project::list_projects(state).unwrap_or_default();

    let mut worktrees_map = serde_json::Map::new();
    for p in &projects {
        let wts = worktree::list_worktrees(state, &p.id).unwrap_or_default();
        worktrees_map.insert(p.id.clone(), serde_json::to_value(&wts).unwrap());
    }

    let mut sessions_list = Vec::new();
    let mut rounds_map = serde_json::Map::new();
    for p in &projects {
        let wts = worktree::list_worktrees(state, &p.id).unwrap_or_default();
        for wt in &wts {
            let sessions = session::list_sessions(state, &wt.id).unwrap_or_default();
            for sess in &sessions {
                // Include rounds for active or review_required sessions
                let active_states = ["running", "waiting_input", "review_required", "queued"];
                if active_states.contains(&sess.state.as_str()) {
                    if let Ok(rounds) = state.db.with_conn(|conn| queries::list_rounds(conn, &sess.id)) {
                        rounds_map.insert(sess.id.clone(), serde_json::to_value(&rounds).unwrap());
                    }
                }
            }
            sessions_list.extend(sessions);
        }
    }

    let agents = state
        .db
        .with_conn(|conn| queries::list_agent_configs(conn))
        .unwrap_or_default();

    JsonRpcResponse::success(
        id,
        json!({
            "projects": projects,
            "worktrees": worktrees_map,
            "sessions": sessions_list,
            "rounds": rounds_map,
            "agents": agents,
        }),
    )
}

// ── Terminal handlers ──

async fn handle_terminal_exec(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let worktree_id = match require_str(&params, "worktree_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };
    let command = match require_str(&params, "command") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    let wt = match state.db.with_conn(|conn| queries::get_worktree(conn, &worktree_id)) {
        Ok(Some(w)) => w,
        Ok(None) => return JsonRpcResponse::error(id, -32000, "worktree not found"),
        Err(e) => return JsonRpcResponse::error(id, -32000, e.to_string()),
    };

    match state.terminal_manager.exec(&worktree_id, &wt.path, &command, &state.event_tx).await {
        Ok(()) => JsonRpcResponse::success(id, json!({"started": true})),
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}

async fn handle_terminal_kill(state: &Arc<AppState>, id: Option<Value>, params: Value) -> JsonRpcResponse {
    let worktree_id = match require_str(&params, "worktree_id") {
        Ok(v) => v,
        Err(mut e) => { e.id = id; return e; }
    };

    state.terminal_manager.kill(&worktree_id).await;
    JsonRpcResponse::success(id, json!({"ok": true}))
}

// ── Agent handler ──

fn handle_agent_list(state: &Arc<AppState>, id: Option<Value>) -> JsonRpcResponse {
    match state.db.with_conn(|conn| queries::list_agent_configs(conn)) {
        Ok(agents) => JsonRpcResponse::success(id, serde_json::to_value(&agents).unwrap()),
        Err(e) => JsonRpcResponse::error(id, -32000, e.to_string()),
    }
}
