use anyhow::Result;
use std::sync::Arc;

use crate::db::queries;
use crate::AppState;

pub fn log_event(
    state: &Arc<AppState>,
    event_type: &str,
    entity_type: Option<&str>,
    entity_id: Option<&str>,
    payload: &serde_json::Value,
) -> Result<i64> {
    let payload_str = serde_json::to_string(payload)?;
    state.db.with_conn(|conn| {
        queries::insert_event(conn, event_type, entity_type, entity_id, &payload_str)
    })
}
