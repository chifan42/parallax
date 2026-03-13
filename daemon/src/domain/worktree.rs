use anyhow::{Result, bail};
use std::sync::Arc;

use crate::db::models::WorktreeRow;
use crate::db::queries;
use crate::git;
use crate::AppState;

pub async fn create_worktree(
    state: &Arc<AppState>,
    project_id: &str,
    branch: &str,
    source_branch: &str,
) -> Result<WorktreeRow> {
    let project = state
        .db
        .with_conn(|conn| queries::get_project(conn, project_id))?
        .ok_or_else(|| anyhow::anyhow!("project not found: {project_id}"))?;

    let wt_path = git::worktree_add(&project.repo_path, branch, source_branch).await?;
    let name = branch.replace('/', "-");

    let now = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string();
    let wt = WorktreeRow {
        id: uuid::Uuid::new_v4().to_string(),
        project_id: project_id.to_string(),
        name,
        path: wt_path,
        branch: branch.to_string(),
        source_branch: source_branch.to_string(),
        prescript_override: None,
        created_at: now,
    };

    state.db.with_conn(|conn| {
        queries::insert_worktree(conn, &wt)?;
        Ok(())
    })?;

    Ok(wt)
}

pub async fn import_worktree(
    state: &Arc<AppState>,
    project_id: &str,
    path: &str,
    branch: &str,
) -> Result<WorktreeRow> {
    let _project = state
        .db
        .with_conn(|conn| queries::get_project(conn, project_id))?
        .ok_or_else(|| anyhow::anyhow!("project not found: {project_id}"))?;

    if !std::path::Path::new(path).exists() {
        bail!("worktree path does not exist: {path}");
    }

    let name = branch.replace('/', "-");
    let now = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string();
    let wt = WorktreeRow {
        id: uuid::Uuid::new_v4().to_string(),
        project_id: project_id.to_string(),
        name,
        path: path.to_string(),
        branch: branch.to_string(),
        source_branch: branch.to_string(),
        prescript_override: None,
        created_at: now,
    };

    state.db.with_conn(|conn| {
        queries::insert_worktree(conn, &wt)?;
        Ok(())
    })?;

    Ok(wt)
}

pub async fn delete_worktree(state: &Arc<AppState>, id: &str, remove_from_disk: bool) -> Result<bool> {
    let wt = state.db.with_conn(|conn| queries::get_worktree(conn, id))?;
    if let Some(wt) = wt {
        if remove_from_disk {
            let project = state
                .db
                .with_conn(|conn| queries::get_project(conn, &wt.project_id))?;
            if let Some(project) = project {
                let _ = git::worktree_remove(&project.repo_path, &wt.path).await;
            }
        }
        state.db.with_conn(|conn| queries::delete_worktree(conn, id))
    } else {
        Ok(false)
    }
}

pub fn list_worktrees(state: &Arc<AppState>, project_id: &str) -> Result<Vec<WorktreeRow>> {
    state.db.with_conn(|conn| queries::list_worktrees(conn, project_id))
}
