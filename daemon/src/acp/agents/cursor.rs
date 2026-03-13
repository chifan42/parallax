use std::collections::HashMap;

use super::AgentSpawnConfig;

/// Cursor Agent via cursor-agent CLI (ACP stdio server)
/// Auth: set CURSOR_API_KEY or CURSOR_AUTH_TOKEN env var
pub fn spawn_config() -> AgentSpawnConfig {
    AgentSpawnConfig {
        binary_path: "cursor-agent".into(),
        args: vec!["acp".into()],
        env: HashMap::new(),
    }
}
