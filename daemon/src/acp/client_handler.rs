//! ParallaxClient — implements ACP Client trait callbacks.
//!
//! Handles permission requests, file operations, and terminal execution
//! within the context of a worktree.

use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{broadcast, oneshot, Mutex};

use agent_client_protocol as acp;
use async_trait::async_trait;

use super::manager::AgentEvent;

/// Pending permission requests waiting for UI response
pub struct PendingPermissions {
    requests: HashMap<String, oneshot::Sender<PermissionOutcome>>,
}

#[derive(Debug, Clone)]
pub enum PermissionOutcome {
    AllowOnce,
    AllowAlways,
    Reject,
}

impl PendingPermissions {
    pub fn new() -> Self {
        Self {
            requests: HashMap::new(),
        }
    }

    pub fn register(&mut self, request_id: String) -> oneshot::Receiver<PermissionOutcome> {
        let (tx, rx) = oneshot::channel();
        self.requests.insert(request_id, tx);
        rx
    }

    pub fn respond(&mut self, request_id: &str, outcome: PermissionOutcome) -> bool {
        if let Some(tx) = self.requests.remove(request_id) {
            let _ = tx.send(outcome);
            true
        } else {
            false
        }
    }
}

struct TerminalProcess {
    child: Option<tokio::process::Child>,
    output: String,
}

/// Client handler for a single agent session
pub struct ParallaxClient {
    pub session_id: String,
    pub worktree_path: String,
    pub event_tx: broadcast::Sender<AgentEvent>,
    pub pending_permissions: Arc<Mutex<PendingPermissions>>,
    terminals: Arc<Mutex<HashMap<String, TerminalProcess>>>,
}

impl ParallaxClient {
    pub fn new(
        session_id: String,
        worktree_path: String,
        event_tx: broadcast::Sender<AgentEvent>,
    ) -> Self {
        Self {
            session_id,
            worktree_path,
            event_tx,
            pending_permissions: Arc::new(Mutex::new(PendingPermissions::new())),
            terminals: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    async fn read_file_inner(&self, relative_path: &str) -> anyhow::Result<String> {
        let full_path = std::path::Path::new(&self.worktree_path).join(relative_path);
        let canonical = full_path.canonicalize()?;
        let wt_canonical = std::path::Path::new(&self.worktree_path).canonicalize()?;
        if !canonical.starts_with(&wt_canonical) {
            anyhow::bail!("path escapes worktree: {relative_path}");
        }
        Ok(tokio::fs::read_to_string(canonical).await?)
    }

    async fn write_file_inner(&self, relative_path: &str, content: &str) -> anyhow::Result<()> {
        let full_path = std::path::Path::new(&self.worktree_path).join(relative_path);
        let wt_canonical = std::path::Path::new(&self.worktree_path).canonicalize()?;

        // Validate normalized path before any filesystem side effects.
        // This catches ../../../ traversals before create_dir_all can create
        // directories outside the worktree.
        let normalized = full_path
            .components()
            .fold(std::path::PathBuf::new(), |mut acc, c| {
                match c {
                    std::path::Component::ParentDir => { acc.pop(); }
                    std::path::Component::CurDir => {}
                    other => acc.push(other),
                }
                acc
            });
        if !normalized.starts_with(&wt_canonical) && !normalized.starts_with(&self.worktree_path) {
            anyhow::bail!("path escapes worktree: {relative_path}");
        }

        if let Some(parent) = full_path.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }

        let canonical_parent = full_path
            .parent()
            .ok_or_else(|| anyhow::anyhow!("no parent directory"))?
            .canonicalize()?;
        if !canonical_parent.starts_with(&wt_canonical) {
            anyhow::bail!("path escapes worktree: {relative_path}");
        }

        let file_name = full_path
            .file_name()
            .ok_or_else(|| anyhow::anyhow!("no filename"))?;
        let safe_path = canonical_parent.join(file_name);

        if safe_path.exists() {
            let canonical_full = safe_path.canonicalize()?;
            if !canonical_full.starts_with(&wt_canonical) {
                anyhow::bail!("path resolves outside worktree via symlink: {relative_path}");
            }
        }

        Ok(tokio::fs::write(safe_path, content).await?)
    }

    fn extract_text(block: &acp::ContentBlock) -> Option<String> {
        match block {
            acp::ContentBlock::Text(t) => Some(t.text.clone()),
            _ => None,
        }
    }

    fn make_error(code: acp::ErrorCode, msg: impl ToString) -> acp::Error {
        acp::Error::new(i32::from(code), msg.to_string())
    }
}

#[async_trait(?Send)]
impl acp::Client for ParallaxClient {
    async fn request_permission(
        &self,
        args: acp::RequestPermissionRequest,
    ) -> acp::Result<acp::RequestPermissionResponse> {
        let request_id = uuid::Uuid::new_v4().to_string();

        let tool_name = args
            .tool_call
            .fields
            .title
            .clone()
            .unwrap_or_else(|| "unknown".into());
        let description = format!("{:?}", args.tool_call);

        let rx = {
            let mut pending = self.pending_permissions.lock().await;
            pending.register(request_id.clone())
        };

        let _ = self.event_tx.send(AgentEvent::PermissionRequest {
            session_id: self.session_id.clone(),
            request_id,
            tool_name,
            description,
        });

        let outcome = rx.await.unwrap_or(PermissionOutcome::Reject);

        match outcome {
            PermissionOutcome::Reject => {
                Ok(acp::RequestPermissionResponse::new(
                    acp::RequestPermissionOutcome::Cancelled,
                ))
            }
            _ => {
                let option_id = args
                    .options
                    .first()
                    .map(|o| o.option_id.clone())
                    .unwrap_or_else(|| acp::PermissionOptionId::new("allow"));
                Ok(acp::RequestPermissionResponse::new(
                    acp::RequestPermissionOutcome::Selected(
                        acp::SelectedPermissionOutcome::new(option_id),
                    ),
                ))
            }
        }
    }

    async fn session_notification(
        &self,
        args: acp::SessionNotification,
    ) -> acp::Result<()> {
        match args.update {
            acp::SessionUpdate::AgentMessageChunk(chunk) => {
                if let Some(text) = Self::extract_text(&chunk.content) {
                    let _ = self.event_tx.send(AgentEvent::OutputChunk {
                        session_id: self.session_id.clone(),
                        content: text,
                    });
                }
            }
            acp::SessionUpdate::AgentThoughtChunk(chunk) => {
                if let Some(text) = Self::extract_text(&chunk.content) {
                    let _ = self.event_tx.send(AgentEvent::ThinkingChunk {
                        session_id: self.session_id.clone(),
                        content: text,
                    });
                }
            }
            acp::SessionUpdate::ToolCall(tc) => {
                let _ = self.event_tx.send(AgentEvent::ToolCallStarted {
                    session_id: self.session_id.clone(),
                    tool_call_id: tc.tool_call_id.to_string(),
                    title: tc.title.clone(),
                    kind: format!("{:?}", tc.kind),
                });
            }
            acp::SessionUpdate::ToolCallUpdate(update) => {
                if let Some(status) = &update.fields.status {
                    let _ = self.event_tx.send(AgentEvent::ToolCallCompleted {
                        session_id: self.session_id.clone(),
                        tool_call_id: update.tool_call_id.to_string(),
                        status: format!("{:?}", status),
                    });
                }
            }
            acp::SessionUpdate::Plan(plan) => {
                let entries: Vec<crate::domain::session::PlanEntry> = plan
                    .entries
                    .iter()
                    .map(|e| crate::domain::session::PlanEntry {
                        title: e.content.clone(),
                        status: format!("{:?}", e.status),
                    })
                    .collect();
                let _ = self.event_tx.send(AgentEvent::PlanUpdate {
                    session_id: self.session_id.clone(),
                    entries,
                });
            }
            _ => {}
        }
        Ok(())
    }

    async fn read_text_file(
        &self,
        args: acp::ReadTextFileRequest,
    ) -> acp::Result<acp::ReadTextFileResponse> {
        let path_str = args.path.to_string_lossy();
        match self.read_file_inner(&path_str).await {
            Ok(content) => Ok(acp::ReadTextFileResponse::new(content)),
            Err(e) => Err(Self::make_error(acp::ErrorCode::InternalError, e)),
        }
    }

    async fn write_text_file(
        &self,
        args: acp::WriteTextFileRequest,
    ) -> acp::Result<acp::WriteTextFileResponse> {
        let path_str = args.path.to_string_lossy();
        match self.write_file_inner(&path_str, &args.content).await {
            Ok(()) => Ok(acp::WriteTextFileResponse::new()),
            Err(e) => Err(Self::make_error(acp::ErrorCode::InternalError, e)),
        }
    }

    async fn create_terminal(
        &self,
        args: acp::CreateTerminalRequest,
    ) -> acp::Result<acp::CreateTerminalResponse> {
        let terminal_id = uuid::Uuid::new_v4().to_string();

        let child = tokio::process::Command::new(&args.command)
            .args(&args.args)
            .current_dir(&self.worktree_path)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .map_err(|e| Self::make_error(acp::ErrorCode::InternalError, e))?;

        self.terminals.lock().await.insert(
            terminal_id.clone(),
            TerminalProcess {
                child: Some(child),
                output: String::new(),
            },
        );

        Ok(acp::CreateTerminalResponse::new(
            acp::TerminalId::new(terminal_id),
        ))
    }

    async fn terminal_output(
        &self,
        args: acp::TerminalOutputRequest,
    ) -> acp::Result<acp::TerminalOutputResponse> {
        let mut terminals = self.terminals.lock().await;
        let tid = args.terminal_id.to_string();
        if let Some(term) = terminals.get_mut(&tid) {
            if let Some(ref mut child) = term.child {
                if let Some(stdout) = child.stdout.as_mut() {
                    use tokio::io::AsyncReadExt;
                    let mut buf = vec![0u8; 4096];
                    match tokio::time::timeout(
                        std::time::Duration::from_millis(50),
                        stdout.read(&mut buf),
                    )
                    .await
                    {
                        Ok(Ok(n)) if n > 0 => {
                            let chunk = String::from_utf8_lossy(&buf[..n]);
                            term.output.push_str(&chunk);
                        }
                        _ => {}
                    }
                }
            }
            let exit_status = term
                .child
                .as_mut()
                .and_then(|c| c.try_wait().ok().flatten())
                .map(|s| {
                    acp::TerminalExitStatus::new()
                        .exit_code(s.code().map(|c| c as u32))
                });
            Ok(acp::TerminalOutputResponse::new(term.output.clone(), false)
                .exit_status(exit_status))
        } else {
            Err(Self::make_error(
                acp::ErrorCode::InvalidParams,
                format!("terminal not found: {tid}"),
            ))
        }
    }

    async fn wait_for_terminal_exit(
        &self,
        args: acp::WaitForTerminalExitRequest,
    ) -> acp::Result<acp::WaitForTerminalExitResponse> {
        let tid = args.terminal_id.to_string();
        let mut child = {
            let mut terminals = self.terminals.lock().await;
            let term = terminals.get_mut(&tid).ok_or_else(|| {
                Self::make_error(
                    acp::ErrorCode::InvalidParams,
                    format!("terminal not found: {tid}"),
                )
            })?;
            term.child.take().ok_or_else(|| {
                Self::make_error(
                    acp::ErrorCode::InternalError,
                    format!("terminal already being waited on: {tid}"),
                )
            })?
        };
        match child.wait().await {
            Ok(status) => {
                let exit_status = acp::TerminalExitStatus::new()
                    .exit_code(status.code().map(|c| c as u32));
                Ok(acp::WaitForTerminalExitResponse::new(exit_status))
            }
            Err(e) => Err(Self::make_error(acp::ErrorCode::InternalError, e)),
        }
    }

    async fn kill_terminal(
        &self,
        args: acp::KillTerminalRequest,
    ) -> acp::Result<acp::KillTerminalResponse> {
        let tid = args.terminal_id.to_string();
        let mut terminals = self.terminals.lock().await;
        if let Some(term) = terminals.get_mut(&tid) {
            if let Some(ref mut child) = term.child {
                let _ = child.kill().await;
            }
            Ok(acp::KillTerminalResponse::new())
        } else {
            Err(Self::make_error(
                acp::ErrorCode::InvalidParams,
                format!("terminal not found: {tid}"),
            ))
        }
    }

    async fn release_terminal(
        &self,
        args: acp::ReleaseTerminalRequest,
    ) -> acp::Result<acp::ReleaseTerminalResponse> {
        let tid = args.terminal_id.to_string();
        let mut terminals = self.terminals.lock().await;
        if let Some(mut term) = terminals.remove(&tid) {
            if let Some(ref mut child) = term.child {
                let _ = child.kill().await;
            }
            Ok(acp::ReleaseTerminalResponse::new())
        } else {
            Err(Self::make_error(
                acp::ErrorCode::InvalidParams,
                format!("terminal not found: {tid}"),
            ))
        }
    }
}
