use anyhow::{Result, bail};
use tokio::process::Command;

async fn run_git(repo_path: &str, args: &[&str]) -> Result<String> {
    let output = Command::new("git")
        .args(args)
        .current_dir(repo_path)
        .output()
        .await?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!("git {} failed: {}", args.join(" "), stderr.trim());
    }

    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

pub async fn worktree_add(repo_path: &str, branch: &str, source_branch: &str) -> Result<String> {
    // Determine worktree path: sibling directory named after branch
    let repo = std::path::Path::new(repo_path);
    let parent = repo.parent().unwrap_or(repo);
    let safe_name = branch.replace('/', "-");
    let repo_name = repo
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();
    let wt_path = parent.join(format!("{repo_name}-{safe_name}"));
    let wt_path_str = wt_path.to_string_lossy().to_string();

    run_git(
        repo_path,
        &[
            "worktree",
            "add",
            "-b",
            branch,
            &wt_path_str,
            source_branch,
        ],
    )
    .await?;

    Ok(wt_path_str)
}

pub async fn worktree_list(repo_path: &str) -> Result<Vec<(String, String)>> {
    let output = run_git(repo_path, &["worktree", "list", "--porcelain"]).await?;
    let mut worktrees = Vec::new();
    let mut current_path = String::new();
    let mut current_branch = String::new();

    for line in output.lines() {
        if let Some(path) = line.strip_prefix("worktree ") {
            current_path = path.to_string();
        } else if let Some(branch) = line.strip_prefix("branch refs/heads/") {
            current_branch = branch.to_string();
        } else if line.is_empty() && !current_path.is_empty() {
            worktrees.push((current_path.clone(), current_branch.clone()));
            current_path.clear();
            current_branch.clear();
        }
    }
    if !current_path.is_empty() {
        worktrees.push((current_path, current_branch));
    }

    Ok(worktrees)
}

pub async fn worktree_remove(repo_path: &str, wt_path: &str) -> Result<()> {
    run_git(repo_path, &["worktree", "remove", "--force", wt_path]).await?;
    Ok(())
}

pub async fn default_branch(repo_path: &str) -> Result<String> {
    // Try symbolic-ref for origin/HEAD
    if let Ok(output) = run_git(repo_path, &["symbolic-ref", "refs/remotes/origin/HEAD"]).await {
        if let Some(branch) = output.strip_prefix("refs/remotes/origin/") {
            return Ok(branch.to_string());
        }
    }

    // Fallback: check if main or master exists
    for candidate in &["main", "master"] {
        if run_git(repo_path, &["rev-parse", "--verify", candidate])
            .await
            .is_ok()
        {
            return Ok(candidate.to_string());
        }
    }

    bail!("could not determine default branch")
}

pub async fn list_branches(repo_path: &str) -> Result<Vec<String>> {
    let output = run_git(repo_path, &["branch", "--format=%(refname:short)"]).await?;
    Ok(output.lines().map(|s| s.to_string()).collect())
}
