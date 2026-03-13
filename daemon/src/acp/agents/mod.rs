pub mod claude_code;
pub mod cursor;

use std::collections::HashMap;

pub struct AgentSpawnConfig {
    pub binary_path: String,
    pub args: Vec<String>,
    pub env: HashMap<String, String>,
}
