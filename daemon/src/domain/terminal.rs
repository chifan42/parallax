//! User-facing terminal: runs shell commands per worktree.

use std::collections::HashMap;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::sync::Mutex;

use crate::ipc::types::Notification;

pub struct TerminalProcess {
    child: tokio::process::Child,
}

pub struct TerminalManager {
    /// worktree_id → running process
    processes: Mutex<HashMap<String, TerminalProcess>>,
}

impl TerminalManager {
    pub fn new() -> Self {
        Self {
            processes: Mutex::new(HashMap::new()),
        }
    }

    /// Execute a command in a worktree directory, streaming output via notifications.
    pub async fn exec(
        self: &Arc<Self>,
        worktree_id: &str,
        worktree_path: &str,
        command: &str,
        event_tx: &tokio::sync::broadcast::Sender<Notification>,
    ) -> anyhow::Result<()> {
        // Kill any existing process for this worktree
        self.kill(worktree_id).await;

        let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".into());

        let mut child = Command::new(&shell)
            .arg("-c")
            .arg(command)
            .current_dir(worktree_path)
            .env("TERM", "dumb")
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()?;

        let stdout = child.stdout.take().unwrap();
        let stderr = child.stderr.take().unwrap();

        {
            let mut procs = self.processes.lock().await;
            procs.insert(worktree_id.to_string(), TerminalProcess { child });
        }

        let wt_id = worktree_id.to_string();
        let tx = event_tx.clone();

        // Stream stdout
        let wt_id_out = wt_id.clone();
        let tx_out = tx.clone();
        tokio::spawn(async move {
            let reader = BufReader::new(stdout);
            let mut lines = reader.lines();
            while let Ok(Some(line)) = lines.next_line().await {
                let _ = tx_out.send(Notification::TerminalOutput {
                    worktree_id: wt_id_out.clone(),
                    content: format!("{line}\n"),
                });
            }
        });

        // Stream stderr
        let wt_id_err = wt_id.clone();
        let tx_err = tx.clone();
        tokio::spawn(async move {
            let reader = BufReader::new(stderr);
            let mut lines = reader.lines();
            while let Ok(Some(line)) = lines.next_line().await {
                let _ = tx_err.send(Notification::TerminalOutput {
                    worktree_id: wt_id_err.clone(),
                    content: format!("{line}\n"),
                });
            }
        });

        // Wait for exit in background
        let wt_id_wait = wt_id.clone();
        let tx_wait = tx.clone();
        let mgr = Arc::clone(self);
        tokio::spawn(async move {
            let exit_code = {
                let mut procs = mgr.processes.lock().await;
                if let Some(proc) = procs.get_mut(&wt_id_wait) {
                    match proc.child.wait().await {
                        Ok(status) => status.code().unwrap_or(-1),
                        Err(_) => -1,
                    }
                } else {
                    -1
                }
            };
            mgr.processes.lock().await.remove(&wt_id_wait);
            let _ = tx_wait.send(Notification::TerminalExit {
                worktree_id: wt_id_wait,
                exit_code,
            });
        });

        Ok(())
    }

    pub async fn kill(&self, worktree_id: &str) {
        let mut procs = self.processes.lock().await;
        if let Some(mut proc) = procs.remove(worktree_id) {
            let _ = proc.child.kill().await;
        }
    }

    pub async fn is_running(&self, worktree_id: &str) -> bool {
        self.processes.lock().await.contains_key(worktree_id)
    }
}
