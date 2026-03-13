use std::collections::HashMap;

use super::AgentSpawnConfig;

/// Claude Code via claude-agent-acp (ACP stdio server)
/// Install: npm install -g @zed-industries/claude-agent-acp
/// Auth: set ANTHROPIC_API_KEY env var
pub fn spawn_config() -> AgentSpawnConfig {
    AgentSpawnConfig {
        binary_path: "claude-agent-acp".into(),
        args: vec![],
        env: HashMap::new(),
    }
}
