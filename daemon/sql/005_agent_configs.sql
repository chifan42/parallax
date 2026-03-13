CREATE TABLE agent_configs (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    binary_path TEXT NOT NULL,
    args_json TEXT NOT NULL DEFAULT '[]',
    env_json TEXT NOT NULL DEFAULT '{}',
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL
);

-- Seed default agents
INSERT INTO agent_configs (id, name, display_name, binary_path, args_json, env_json, created_at)
VALUES
    ('claude-code', 'claude_code', 'Claude Code', 'claude-agent-acp', '[]', '{}', strftime('%Y-%m-%dT%H:%M:%f','now')),
    ('cursor', 'cursor', 'Cursor', 'cursor-agent', '["acp"]', '{}', strftime('%Y-%m-%dT%H:%M:%f','now'));
