use anyhow::Result;
use std::path::Path;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tracing::{info, warn};

use crate::ipc::types::Notification;
use crate::AppState;

const DEFAULT_TIMEOUT_SECS: u64 = 300; // 5 minutes

#[derive(Debug)]
pub struct PrescriptOutput {
    pub line: String,
    pub stream: String, // "stdout" or "stderr"
}

/// Resolve prescript path: per-worktree override → repo .parallax/prescript.sh → global
pub fn resolve_prescript(
    prescript_override: Option<&str>,
    repo_path: &str,
) -> Option<String> {
    // Per-worktree override
    if let Some(p) = prescript_override {
        if Path::new(p).exists() {
            return Some(p.to_string());
        }
    }

    // Per-repo .parallax/prescript.sh
    let repo_prescript = Path::new(repo_path).join(".parallax/prescript.sh");
    if repo_prescript.exists() {
        return Some(repo_prescript.to_string_lossy().to_string());
    }

    // Global
    let global = crate::config::global_prescript_path();
    if global.exists() {
        return Some(global.to_string_lossy().to_string());
    }

    None
}

/// Run a prescript in the given worktree directory, streaming output
pub async fn run_prescript(
    state: &Arc<AppState>,
    worktree_id: &str,
    script_path: &str,
    working_dir: &str,
) -> Result<i32> {
    info!("running prescript: {script_path} in {working_dir}");

    let mut child = Command::new("/bin/sh")
        .arg(script_path)
        .current_dir(working_dir)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()?;

    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();

    let wt_id = worktree_id.to_string();
    let event_tx = state.event_tx.clone();

    let wt_id_out = wt_id.clone();
    let event_tx_out = event_tx.clone();
    let stdout_task = tokio::spawn(async move {
        let reader = BufReader::new(stdout);
        let mut lines = reader.lines();
        while let Ok(Some(line)) = lines.next_line().await {
            let _ = event_tx_out.send(Notification::PrescriptOutput {
                worktree_id: wt_id_out.clone(),
                line,
                stream: "stdout".into(),
            });
        }
    });

    let wt_id_err = wt_id.clone();
    let event_tx_err = event_tx.clone();
    let stderr_task = tokio::spawn(async move {
        let reader = BufReader::new(stderr);
        let mut lines = reader.lines();
        while let Ok(Some(line)) = lines.next_line().await {
            let _ = event_tx_err.send(Notification::PrescriptOutput {
                worktree_id: wt_id_err.clone(),
                line,
                stream: "stderr".into(),
            });
        }
    });

    let exit_status = tokio::time::timeout(
        std::time::Duration::from_secs(DEFAULT_TIMEOUT_SECS),
        child.wait(),
    )
    .await;

    let _ = stdout_task.await;
    let _ = stderr_task.await;

    let exit_code = match exit_status {
        Ok(Ok(status)) => status.code().unwrap_or(-1),
        Ok(Err(e)) => {
            warn!("prescript process error: {e}");
            -1
        }
        Err(_) => {
            warn!("prescript timed out after {DEFAULT_TIMEOUT_SECS}s");
            let _ = child.kill().await;
            -2
        }
    };

    let _ = event_tx.send(Notification::PrescriptComplete {
        worktree_id: wt_id,
        exit_code,
    });

    Ok(exit_code)
}
