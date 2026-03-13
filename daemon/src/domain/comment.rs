use anyhow::Result;
use std::sync::Arc;

use crate::db::models::CommentRow;
use crate::db::queries;
use crate::AppState;

pub fn create_comment(
    state: &Arc<AppState>,
    round_id: &str,
    revision_id: &str,
    start_offset: i64,
    end_offset: i64,
    quoted_text: &str,
    comment_text: &str,
) -> Result<CommentRow> {
    let now = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string();
    let comment = CommentRow {
        id: uuid::Uuid::new_v4().to_string(),
        round_id: round_id.to_string(),
        revision_id: revision_id.to_string(),
        start_offset,
        end_offset,
        quoted_text: quoted_text.to_string(),
        comment_text: comment_text.to_string(),
        created_at: now,
    };

    state.db.with_conn(|conn| {
        queries::insert_comment(conn, &comment)?;
        Ok(())
    })?;

    Ok(comment)
}

pub fn list_comments(state: &Arc<AppState>, round_id: &str) -> Result<Vec<CommentRow>> {
    state.db.with_conn(|conn| queries::list_comments(conn, round_id))
}

pub fn delete_comment(state: &Arc<AppState>, id: &str) -> Result<bool> {
    state.db.with_conn(|conn| queries::delete_comment(conn, id))
}

/// Synthesize a re-run prompt from comments and optional user notes
pub fn synthesize_rerun_prompt(comments: &[CommentRow], user_notes: Option<&str>) -> String {
    let mut prompt = String::from("Please revise based on the following feedback:\n\n");

    for (i, comment) in comments.iter().enumerate() {
        prompt.push_str(&format!(
            "{}. On \"{}\":\n   {}\n\n",
            i + 1,
            comment.quoted_text,
            comment.comment_text
        ));
    }

    if let Some(notes) = user_notes {
        if !notes.is_empty() {
            prompt.push_str(&format!("Additional notes:\n{notes}\n"));
        }
    }

    prompt
}
