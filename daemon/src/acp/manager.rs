//! Agent Process Manager
//!
//! Spawns agent subprocesses and manages their lifecycle.
//! Each agent runs on a dedicated single-threaded tokio runtime with LocalSet
//! to handle !Send ACP futures, bridged to the main runtime via mpsc channels.

use anyhow::Result;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{mpsc, oneshot, broadcast, Mutex};

use crate::domain::session::PlanEntry;

#[derive(Debug)]
pub enum AgentCommand {
    CreateSession {
        session_id: String,
        working_dir: String,
        respond: oneshot::Sender<Result<String, String>>,
    },
    SendPrompt {
        session_id: String,
        acp_session_id: String,
        prompt: String,
        respond: oneshot::Sender<Result<(), String>>,
    },
    RespondPermission {
        request_id: String,
        outcome: String,
    },
    CancelSession {
        acp_session_id: String,
    },
    Shutdown,
}

#[derive(Debug, Clone)]
pub enum AgentEvent {
    SessionCreated {
        session_id: String,
        acp_session_id: String,
    },
    OutputChunk {
        session_id: String,
        content: String,
    },
    ThinkingChunk {
        session_id: String,
        content: String,
    },
    ToolCallStarted {
        session_id: String,
        tool_call_id: String,
        title: String,
        kind: String,
    },
    ToolCallCompleted {
        session_id: String,
        tool_call_id: String,
        status: String,
    },
    PlanUpdate {
        session_id: String,
        entries: Vec<PlanEntry>,
    },
    PermissionRequest {
        session_id: String,
        request_id: String,
        tool_name: String,
        description: String,
    },
    SessionCompleted {
        session_id: String,
        stop_reason: String,
    },
    SessionFailed {
        session_id: String,
        error: String,
    },
}

pub struct AgentHandle {
    pub agent_id: String,
    pub command_tx: mpsc::Sender<AgentCommand>,
    pub event_rx: broadcast::Receiver<AgentEvent>,
}

pub struct AgentProcessManager {
    handles: Arc<Mutex<HashMap<String, mpsc::Sender<AgentCommand>>>>,
    event_tx: broadcast::Sender<AgentEvent>,
}

impl AgentProcessManager {
    pub fn new() -> Self {
        let (event_tx, _) = broadcast::channel(256);
        Self {
            handles: Arc::new(Mutex::new(HashMap::new())),
            event_tx,
        }
    }

    pub fn subscribe_events(&self) -> broadcast::Receiver<AgentEvent> {
        self.event_tx.subscribe()
    }

    pub async fn has_agent(&self, agent_id: &str) -> bool {
        self.handles.lock().await.contains_key(agent_id)
    }

    pub async fn send_command(&self, agent_id: &str, cmd: AgentCommand) -> Result<()> {
        let tx = {
            let handles = self.handles.lock().await;
            handles
                .get(agent_id)
                .ok_or_else(|| anyhow::anyhow!("agent not found: {agent_id}"))?
                .clone()
        };
        tx.send(cmd)
            .await
            .map_err(|_| anyhow::anyhow!("agent channel closed"))?;
        Ok(())
    }

    pub async fn remove_handle(&self, agent_id: &str) {
        self.handles.lock().await.remove(agent_id);
    }

    /// Spawn an agent process.
    ///
    /// This creates a dedicated OS thread with a single-threaded tokio runtime
    /// and LocalSet for the agent's !Send futures.
    pub async fn spawn_agent(
        &self,
        agent_id: &str,
        binary_path: &str,
        args: Vec<String>,
        env: HashMap<String, String>,
        working_dir: &str,
    ) -> Result<AgentHandle> {
        let (command_tx, mut command_rx) = mpsc::channel::<AgentCommand>(32);
        let event_tx = self.event_tx.clone();
        let event_rx = self.event_tx.subscribe();

        let binary = binary_path.to_string();
        let work_dir = working_dir.to_string();
        let aid = agent_id.to_string();
        let spawn_args = args;
        let handles_ref = Arc::clone(&self.handles);

        std::thread::Builder::new()
            .name(format!("agent-{aid}"))
            .spawn(move || {
                let rt = tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                    .expect("failed to build agent runtime");

                let local = tokio::task::LocalSet::new();
                local.block_on(&rt, async move {
                    use agent_client_protocol as acp;
                    use agent_client_protocol::Agent;
                    use tokio_util::compat::{TokioAsyncReadCompatExt, TokioAsyncWriteCompatExt};

                    tracing::info!("agent {aid} thread started: {binary}");

                    let mut cmd = tokio::process::Command::new(&binary);
                    cmd.args(&spawn_args)
                        .envs(&env)
                        .current_dir(&work_dir)
                        .stdin(std::process::Stdio::piped())
                        .stdout(std::process::Stdio::piped())
                        .stderr(std::process::Stdio::piped());
                    // Remove env vars that prevent nested Claude Code sessions
                    cmd.env_remove("CLAUDECODE");
                    cmd.env_remove("CLAUDE_CODE_ENTRYPOINT");

                    let mut child = match cmd.spawn()
                    {
                        Ok(c) => c,
                        Err(e) => {
                            tracing::error!("failed to spawn agent process: {e}");
                            return;
                        }
                    };

                    let stdin = child.stdin.take().expect("stdin not captured");
                    let stdout = child.stdout.take().expect("stdout not captured");

                    // Log stderr from agent process
                    let stderr = child.stderr.take().expect("stderr not captured");
                    let aid_for_stderr = aid.clone();
                    tokio::task::spawn_local(async move {
                        use tokio::io::{AsyncBufReadExt, BufReader};
                        let reader = BufReader::new(stderr);
                        let mut lines = reader.lines();
                        while let Ok(Some(line)) = lines.next_line().await {
                            tracing::debug!("agent {aid_for_stderr} stderr: {line}");
                        }
                    });

                    let writer = stdin.compat_write();
                    let reader = stdout.compat();

                    let client = crate::acp::client_handler::ParallaxClient::new(
                        aid.clone(),
                        work_dir.clone(),
                        event_tx.clone(),
                    );
                    let pending_perms = client.pending_permissions.clone();

                    let (conn, io_fut) = acp::ClientSideConnection::new(
                        client,
                        writer,
                        reader,
                        |fut| {
                            tokio::task::spawn_local(fut);
                        },
                    );

                    let aid_for_io = aid.clone();
                    tokio::task::spawn_local(async move {
                        if let Err(e) = io_fut.await {
                            tracing::error!("ACP I/O error for {}: {e}", aid_for_io);
                        }
                    });

                    let init_req = acp::InitializeRequest::new(
                        acp::ProtocolVersion::LATEST,
                    )
                    .client_capabilities(acp::ClientCapabilities::default())
                    .client_info(acp::Implementation::new(
                        "parallax",
                        env!("CARGO_PKG_VERSION"),
                    ));

                    let init_resp = match conn.initialize(init_req).await {
                        Ok(resp) => resp,
                        Err(e) => {
                            tracing::error!("ACP initialization failed: {e}");
                            let _ = child.kill().await;
                            return;
                        }
                    };
                    tracing::info!("ACP initialized for agent {aid}");

                    // Authenticate if the agent requires it
                    if let Some(method) = init_resp.auth_methods.first() {
                        let auth_req = acp::AuthenticateRequest::new(method.id().clone());
                        match conn.authenticate(auth_req).await {
                            Ok(_) => tracing::info!("authenticated agent {aid} via {}", method.id()),
                            Err(e) => {
                                tracing::error!("authentication failed for {aid}: {e}");
                                let _ = child.kill().await;
                                return;
                            }
                        }
                    }

                    let conn = std::rc::Rc::new(conn);

                    while let Some(cmd) = command_rx.recv().await {
                        match cmd {
                            AgentCommand::CreateSession {
                                session_id,
                                working_dir: _wd,
                                respond,
                            } => {
                                let conn = std::rc::Rc::clone(&conn);
                                let event_tx = event_tx.clone();
                                let wd = work_dir.clone();
                                tokio::task::spawn_local(async move {
                                    match conn
                                        .new_session(acp::NewSessionRequest::new(
                                            std::path::PathBuf::from(&wd),
                                        ))
                                        .await
                                    {
                                        Ok(resp) => {
                                            let acp_id = resp.session_id.to_string();
                                            let _ =
                                                event_tx.send(AgentEvent::SessionCreated {
                                                    session_id,
                                                    acp_session_id: acp_id.clone(),
                                                });
                                            let _ = respond.send(Ok(acp_id));
                                        }
                                        Err(e) => {
                                            let _ = respond.send(Err(e.to_string()));
                                        }
                                    }
                                });
                            }
                            AgentCommand::SendPrompt {
                                session_id,
                                acp_session_id,
                                prompt,
                                respond,
                            } => {
                                let conn = std::rc::Rc::clone(&conn);
                                let event_tx = event_tx.clone();
                                tokio::task::spawn_local(async move {
                                    let req = acp::PromptRequest::new(
                                        acp::SessionId::new(acp_session_id),
                                        vec![acp::ContentBlock::Text(acp::TextContent::new(
                                            prompt,
                                        ))],
                                    );
                                    match conn.prompt(req).await {
                                        Ok(resp) => {
                                            let stop = match resp.stop_reason {
                                                acp::StopReason::EndTurn => "end_turn",
                                                acp::StopReason::Cancelled => "cancelled",
                                                acp::StopReason::MaxTokens => "max_tokens",
                                                _ => "completed",
                                            };
                                            let _ =
                                                event_tx.send(AgentEvent::SessionCompleted {
                                                    session_id,
                                                    stop_reason: stop.to_string(),
                                                });
                                            let _ = respond.send(Ok(()));
                                        }
                                        Err(e) => {
                                            let _ =
                                                event_tx.send(AgentEvent::SessionFailed {
                                                    session_id,
                                                    error: e.to_string(),
                                                });
                                            let _ = respond.send(Err(e.to_string()));
                                        }
                                    }
                                });
                            }
                            AgentCommand::RespondPermission {
                                request_id,
                                outcome,
                            } => {
                                use crate::acp::client_handler::PermissionOutcome;
                                let perm_outcome = match outcome.as_str() {
                                    "allow_once" | "allow_always" => {
                                        PermissionOutcome::AllowOnce
                                    }
                                    _ => PermissionOutcome::Reject,
                                };
                                let mut perms = pending_perms.lock().await;
                                perms.respond(&request_id, perm_outcome);
                            }
                            AgentCommand::CancelSession { acp_session_id } => {
                                let conn = std::rc::Rc::clone(&conn);
                                tokio::task::spawn_local(async move {
                                    let _ = conn
                                        .cancel(acp::CancelNotification::new(
                                            acp::SessionId::new(acp_session_id),
                                        ))
                                        .await;
                                });
                            }
                            AgentCommand::Shutdown => {
                                tracing::info!("agent {aid} shutting down");
                                let _ = child.kill().await;
                                break;
                            }
                        }
                    }

                    handles_ref.lock().await.remove(&aid);
                    tracing::info!("agent {aid} handle cleaned up");
                });
            })?;

        self.handles
            .lock()
            .await
            .insert(agent_id.to_string(), command_tx.clone());

        Ok(AgentHandle {
            agent_id: agent_id.to_string(),
            command_tx,
            event_rx,
        })
    }

    pub async fn shutdown_agent(&self, agent_id: &str) -> Result<()> {
        if let Some(tx) = self.handles.lock().await.remove(agent_id) {
            let _ = tx.send(AgentCommand::Shutdown).await;
        }
        Ok(())
    }
}
