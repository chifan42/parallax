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

    let (event_tx, _) = broadcast::channel(256);
    let agent_manager = Arc::new(acp::manager::AgentProcessManager::new());

    let state = Arc::new(AppState {
        db,
        event_tx,
        agent_manager,
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
