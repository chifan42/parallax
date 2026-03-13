CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    worktree_id TEXT NOT NULL REFERENCES worktrees(id) ON DELETE CASCADE,
    agent_type TEXT NOT NULL,
    acp_session_id TEXT,
    state TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE rounds (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    round_number INTEGER NOT NULL,
    prompt_text TEXT NOT NULL,
    output_content TEXT NOT NULL DEFAULT '',
    stop_reason TEXT,
    started_at TEXT NOT NULL,
    completed_at TEXT
);

CREATE TABLE tool_calls (
    id TEXT PRIMARY KEY,
    round_id TEXT NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    kind TEXT NOT NULL,
    status TEXT NOT NULL,
    content_json TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE permission_log (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    round_id TEXT,
    tool_call_id TEXT,
    request_json TEXT NOT NULL,
    outcome TEXT NOT NULL,
    responded_at TEXT NOT NULL
);
