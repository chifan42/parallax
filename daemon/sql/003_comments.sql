CREATE TABLE comments (
    id TEXT PRIMARY KEY,
    round_id TEXT NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
    revision_id TEXT NOT NULL,
    start_offset INTEGER NOT NULL,
    end_offset INTEGER NOT NULL,
    quoted_text TEXT NOT NULL,
    comment_text TEXT NOT NULL,
    created_at TEXT NOT NULL
);
