use anyhow::Result;
use std::sync::Arc;
use tokio::net::UnixListener;
use tracing::{info, error};

use super::connection::Connection;
use super::protocol;
use crate::AppState;

pub async fn run(state: Arc<AppState>, socket_path: &str) -> Result<()> {
    let listener = UnixListener::bind(socket_path)?;
    info!("listening on {socket_path}");

    loop {
        match listener.accept().await {
            Ok((stream, _addr)) => {
                info!("client connected");
                let state = Arc::clone(&state);
                tokio::spawn(async move {
                    if let Err(e) = handle_client(state, stream).await {
                        error!("client error: {e}");
                    }
                    info!("client disconnected");
                });
            }
            Err(e) => {
                error!("accept error: {e}");
            }
        }
    }
}

async fn handle_client(state: Arc<AppState>, stream: tokio::net::UnixStream) -> Result<()> {
    let mut conn = Connection::new(stream);

    // Subscribe to broadcast notifications
    let mut event_rx = state.event_tx.subscribe();

    loop {
        tokio::select! {
            // Handle incoming requests from client
            request = conn.read_request() => {
                match request {
                    Ok(Some(req)) => {
                        let response = protocol::dispatch(&state, req).await;
                        conn.write_response(&response).await?;
                    }
                    Ok(None) => break, // Client disconnected
                    Err(e) => {
                        tracing::warn!("malformed request: {e}");
                        continue;
                    }
                }
            }
            // Forward broadcast notifications to client
            notification = event_rx.recv() => {
                match notification {
                    Ok(notif) => {
                        let jsonrpc = notif.to_jsonrpc();
                        if let Err(e) = conn.write_notification(&jsonrpc).await {
                            tracing::warn!("failed to send notification: {e}");
                            break;
                        }
                    }
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                        tracing::warn!("notification receiver lagged by {n} messages");
                    }
                    Err(_) => break,
                }
            }
        }
    }

    Ok(())
}
