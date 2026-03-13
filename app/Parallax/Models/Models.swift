import Foundation

struct Project: Identifiable {
    let id: String
    let name: String
    let repoPath: String
    let defaultBranch: String?
    let createdAt: String

    init?(from dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let name = dict["name"] as? String,
              let repoPath = dict["repo_path"] as? String,
              let createdAt = dict["created_at"] as? String
        else { return nil }
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.defaultBranch = dict["default_branch"] as? String
        self.createdAt = createdAt
    }
}

struct Worktree: Identifiable {
    let id: String
    let projectId: String
    let name: String
    let path: String
    let branch: String
    let sourceBranch: String
    let prescriptOverride: String?
    let createdAt: String

    init?(from dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let projectId = dict["project_id"] as? String,
              let name = dict["name"] as? String,
              let path = dict["path"] as? String,
              let branch = dict["branch"] as? String,
              let sourceBranch = dict["source_branch"] as? String,
              let createdAt = dict["created_at"] as? String
        else { return nil }
        self.id = id
        self.projectId = projectId
        self.name = name
        self.path = path
        self.branch = branch
        self.sourceBranch = sourceBranch
        self.prescriptOverride = dict["prescript_override"] as? String
        self.createdAt = createdAt
    }
}

struct Session: Identifiable {
    let id: String
    let worktreeId: String
    let agentType: String
    var state: String
    let createdAt: String

    init?(from dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let worktreeId = dict["worktree_id"] as? String,
              let agentType = dict["agent_type"] as? String,
              let state = dict["state"] as? String,
              let createdAt = dict["created_at"] as? String
        else { return nil }
        self.id = id
        self.worktreeId = worktreeId
        self.agentType = agentType
        self.state = state
        self.createdAt = createdAt
    }

    var isActive: Bool {
        ["queued", "running", "waiting_input"].contains(state)
    }

    var isTerminal: Bool {
        ["completed", "failed", "interrupted", "stopped"].contains(state)
    }
}

struct AgentConfig: Identifiable {
    let id: String
    let name: String
    let displayName: String
    let binaryPath: String
    let enabled: Bool

    init?(from dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let name = dict["name"] as? String,
              let displayName = dict["display_name"] as? String,
              let binaryPath = dict["binary_path"] as? String
        else { return nil }
        self.id = id
        self.name = name
        self.displayName = displayName
        self.binaryPath = binaryPath
        self.enabled = dict["enabled"] as? Bool ?? true
    }
}

struct Comment: Identifiable {
    let id: String
    let roundId: String
    let revisionId: String
    let startOffset: Int
    let endOffset: Int
    let quotedText: String
    let commentText: String
    let createdAt: String

    init?(from dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let roundId = dict["round_id"] as? String,
              let revisionId = dict["revision_id"] as? String,
              let startOffset = dict["start_offset"] as? Int,
              let endOffset = dict["end_offset"] as? Int,
              let quotedText = dict["quoted_text"] as? String,
              let commentText = dict["comment_text"] as? String,
              let createdAt = dict["created_at"] as? String
        else { return nil }
        self.id = id
        self.roundId = roundId
        self.revisionId = revisionId
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.quotedText = quotedText
        self.commentText = commentText
        self.createdAt = createdAt
    }
}
