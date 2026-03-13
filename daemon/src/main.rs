mod acp;
mod config;
mod db;
mod domain;
mod event_log;
mod git;
mod ipc;

use anyhow::Result;
use std::sync::Arc;
use tokio::sync::broadcast;
use tracing::info;

pub struct AppState {
    pub db: db::Database,
    pub event_tx: broadcast::Sender<ipc::types::Notification>,
    pub agent_manager: Arc<acp::manager::AgentProcessManager>,
    pub terminal_manager: Arc<domain::terminal::TerminalManager>,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "parallax_daemon=info".into()),
        )
        .init();

    let db = db::Database::open()?;
    db.run_migrations()?;
    info!("database initialized");

    // Recovery: mark any sessions stuck in active states as interrupted
    {
        let active_states = ["running", "waiting_input", "queued"];
        let interrupted_count = db.with_conn(|conn| {
            let mut count = 0i64;
            for s in &active_states {
                let n = conn.execute(
                    "UPDATE sessions SET state = 'interrupted', updated_at = ?1 WHERE state = ?2",
                    rusqlite::params![chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string(), s],
                )?;
                count += n as i64;
            }
            Ok::<i64, anyhow::Error>(count)
        })?;
        if interrupted_count > 0 {
            info!("recovery: marked {} active sessions as interrupted", interrupted_count);
        }
    }

    let (event_tx, _) = broadcast::channel(256);
    let agent_manager = Arc::new(acp::manager::AgentProcessManager::new());

    let terminal_manager = Arc::new(domain::terminal::TerminalManager::new());

    let state = Arc::new(AppState {
        db,
        event_tx,
        agent_manager,
        terminal_manager,
    });

    {
        let state = Arc::clone(&state);
        let mut agent_events = state.agent_manager.subscribe_events();
        tokio::spawn(async move {
            loop {
                match agent_events.recv().await {
                    Ok(event) => {
                        acp::session_bridge::handle_agent_event(&state, event);
                    }
                    Err(broadcast::error::RecvError::Lagged(n)) => {
                        tracing::warn!("agent event bridge lagged, missed {n} events");
                    }
                    Err(broadcast::error::RecvError::Closed) => {
                        tracing::info!("agent event channel closed, bridge exiting");
                        break;
                    }
                }
            }
        });
    }

    let socket_path = config::socket_path();
    let _ = std::fs::remove_file(&socket_path);
    if let Some(parent) = std::path::Path::new(&socket_path).parent() {
        std::fs::create_dir_all(parent)?;
    }

    info!("starting IPC server at {}", socket_path);
    ipc::server::run(state, &socket_path).await?;

    Ok(())
}
