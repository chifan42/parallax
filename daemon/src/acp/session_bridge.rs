//! Maps ACP session events to domain Session/Round updates.

use std::sync::Arc;

use crate::db::queries;
use crate::domain::session::{
    self, OutputBlock, SessionState, parse_output_blocks, serialize_output_blocks,
};
use crate::ipc::types::Notification;
use crate::AppState;

use super::manager::AgentEvent;

/// Process an agent event and update domain state accordingly
pub fn handle_agent_event(state: &Arc<AppState>, event: AgentEvent) {
    match event {
        AgentEvent::SessionCreated {
            session_id,
            acp_session_id,
        } => {
            let _ = state.db.with_conn(|conn| {
                queries::update_session_acp_id(conn, &session_id, &acp_session_id)
            });
        }

        AgentEvent::OutputChunk {
            session_id,
            content,
        } => {
            if let Ok(Some(round)) = state
                .db
                .with_conn(|conn| queries::get_latest_round(conn, &session_id))
            {
                let mut blocks = parse_output_blocks(&round.output_content);
                blocks.push(OutputBlock::Text { content: content.clone() });
                let new_output = serialize_output_blocks(&blocks);

                let _ = state
                    .db
                    .with_conn(|conn| queries::update_round_output(conn, &round.id, &new_output));

                let _ = state.event_tx.send(Notification::SessionOutput {
                    session_id,
                    round_id: round.id,
                    content,
                });
            }
        }

        AgentEvent::ThinkingChunk {
            session_id,
            content,
        } => {
            if let Ok(Some(round)) = state
                .db
                .with_conn(|conn| queries::get_latest_round(conn, &session_id))
            {
                let mut blocks = parse_output_blocks(&round.output_content);
                blocks.push(OutputBlock::Thinking { content: content.clone() });
                let new_output = serialize_output_blocks(&blocks);

                let _ = state
                    .db
                    .with_conn(|conn| queries::update_round_output(conn, &round.id, &new_output));

                let _ = state.event_tx.send(Notification::SessionOutput {
                    session_id,
                    round_id: round.id,
                    content,
                });
            }
        }

        AgentEvent::ToolCallStarted {
            session_id,
            tool_call_id,
            title,
            kind,
        } => {
            if let Ok(Some(round)) = state
                .db
                .with_conn(|conn| queries::get_latest_round(conn, &session_id))
            {
                let mut blocks = parse_output_blocks(&round.output_content);
                blocks.push(OutputBlock::ToolCall {
                    id: tool_call_id.clone(),
                    title: title.clone(),
                    kind: kind.clone(),
                    status: "running".into(),
                    content: None,
                });
                let new_output = serialize_output_blocks(&blocks);

                let _ = state
                    .db
                    .with_conn(|conn| queries::update_round_output(conn, &round.id, &new_output));

                let now = chrono::Utc::now()
                    .format("%Y-%m-%dT%H:%M:%S%.3fZ")
                    .to_string();
                let tc = crate::db::models::ToolCallRow {
                    id: tool_call_id,
                    round_id: round.id,
                    title,
                    kind,
                    status: "running".into(),
                    content_json: None,
                    created_at: now.clone(),
                    updated_at: now,
                };
                let _ = state.db.with_conn(|conn| queries::insert_tool_call(conn, &tc));
            }
        }

        AgentEvent::ToolCallCompleted {
            session_id,
            tool_call_id,
            status,
        } => {
            if let Ok(Some(round)) = state
                .db
                .with_conn(|conn| queries::get_latest_round(conn, &session_id))
            {
                let mut blocks = parse_output_blocks(&round.output_content);
                for block in blocks.iter_mut() {
                    if let OutputBlock::ToolCall { id, status: s, .. } = block {
                        if *id == tool_call_id {
                            *s = status.clone();
                        }
                    }
                }
                let new_output = serialize_output_blocks(&blocks);
                let _ = state
                    .db
                    .with_conn(|conn| queries::update_round_output(conn, &round.id, &new_output));
            }

            let _ = state
                .db
                .with_conn(|conn| queries::update_tool_call_status(conn, &tool_call_id, &status));
        }

        AgentEvent::PlanUpdate {
            session_id,
            entries,
        } => {
            if let Ok(Some(round)) = state
                .db
                .with_conn(|conn| queries::get_latest_round(conn, &session_id))
            {
                let mut blocks = parse_output_blocks(&round.output_content);
                blocks.push(OutputBlock::Plan { entries });
                let new_output = serialize_output_blocks(&blocks);
                let _ = state
                    .db
                    .with_conn(|conn| queries::update_round_output(conn, &round.id, &new_output));
            }
        }

        AgentEvent::PermissionRequest {
            session_id,
            request_id,
            tool_name,
            description,
        } => {
            let _ = state.event_tx.send(Notification::SessionPermissionRequest {
                session_id,
                request_id,
                tool_name,
                description,
            });
        }

        AgentEvent::SessionCompleted {
            session_id,
            stop_reason,
        } => {
            if let Ok(Some(round)) = state
                .db
                .with_conn(|conn| queries::get_latest_round(conn, &session_id))
            {
                let _ = state
                    .db
                    .with_conn(|conn| queries::complete_round(conn, &round.id, &stop_reason));
            }

            let new_state = match stop_reason.as_str() {
                "end_turn" => SessionState::ReviewRequired,
                "cancelled" => SessionState::Stopped,
                "max_tokens" => SessionState::ReviewRequired,
                _ => SessionState::Completed,
            };

            if session::update_state(state, &session_id, new_state).is_ok() {
                let _ = state.event_tx.send(Notification::SessionStateChanged {
                    session_id,
                    state: new_state.as_str().to_string(),
                });
            }
        }

        AgentEvent::SessionFailed {
            session_id,
            error,
        } => {
            if let Ok(Some(round)) = state
                .db
                .with_conn(|conn| queries::get_latest_round(conn, &session_id))
            {
                let _ = state.db.with_conn(|conn| {
                    queries::complete_round(conn, &round.id, &format!("error: {error}"))
                });
            }

            if session::update_state(state, &session_id, SessionState::Failed).is_ok() {
                let _ = state.event_tx.send(Notification::SessionStateChanged {
                    session_id,
                    state: "failed".into(),
                });
            }
        }
    }
}
