use anyhow::{Result, bail};
use std::path::Path;
use std::sync::Arc;

use crate::db::models::ProjectRow;
use crate::db::queries;
use crate::git;
use crate::AppState;

pub fn add_project(state: &Arc<AppState>, repo_path: &str) -> Result<ProjectRow> {
    let path = Path::new(repo_path);
    if !path.join(".git").exists() && !path.is_dir() {
        bail!("not a valid git repository: {repo_path}");
    }

    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "unknown".into());

    let now = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string();

    let project = ProjectRow {
        id: uuid::Uuid::new_v4().to_string(),
        name,
        repo_path: repo_path.to_string(),
        default_branch: None,
        created_at: now.clone(),
        updated_at: now,
    };

    state.db.with_conn(|conn| {
        queries::insert_project(conn, &project)?;
        Ok(())
    })?;

    Ok(project)
}

pub async fn add_project_async(state: &Arc<AppState>, repo_path: &str) -> Result<ProjectRow> {
    let path = Path::new(repo_path);
    if !path.join(".git").exists() && !path.is_dir() {
        bail!("not a valid git repository: {repo_path}");
    }

    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "unknown".into());

    let default_branch = git::default_branch(repo_path).await.ok();

    let now = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string();

    let project = ProjectRow {
        id: uuid::Uuid::new_v4().to_string(),
        name,
        repo_path: repo_path.to_string(),
        default_branch,
        created_at: now.clone(),
        updated_at: now,
    };

    state.db.with_conn(|conn| {
        queries::insert_project(conn, &project)?;
        Ok(())
    })?;

    Ok(project)
}

pub fn list_projects(state: &Arc<AppState>) -> Result<Vec<ProjectRow>> {
    state.db.with_conn(|conn| queries::list_projects(conn))
}

pub fn remove_project(state: &Arc<AppState>, id: &str) -> Result<bool> {
    state.db.with_conn(|conn| queries::delete_project(conn, id))
}
