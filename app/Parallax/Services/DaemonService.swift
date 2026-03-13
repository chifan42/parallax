import Foundation
import SwiftUI

/// High-level API for interacting with the Parallax daemon
@MainActor
class DaemonService: ObservableObject {
    @Published var isConnected = false
    @Published var projects: [Project] = []
    @Published var worktreesByProject: [String: [Worktree]] = [:]
    @Published var selectedWorktree: Worktree?
    @Published var sessions: [Session] = []
    @Published var agents: [AgentConfig] = []
    @Published var connectionError: String?

    private let connection = DaemonConnection()

    func connect() async {
        do {
            try await connection.connect()
            isConnected = true
            connectionError = nil

            // Register notification handler
            connection.setNotificationHandler { [weak self] notification in
                guard let self else { return }
                Task { @MainActor in
                    self.handleNotification(notification)
                }
            }

            // Initial sync
            await syncState()
        } catch {
            isConnected = false
            connectionError = error.localizedDescription

            // Retry after delay
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await connect()
        }
    }

    func disconnect() {
        connection.disconnect()
        isConnected = false
    }

    // MARK: - Sync

    func syncState() async {
        guard let response = await call("sync/state") else { return }
        guard let result = response.result?.dictValue else { return }

        if let projectsArray = result["projects"] as? [[String: Any]] {
            projects = projectsArray.compactMap { Project(from: $0) }
        }

        if let worktreesMap = result["worktrees"] as? [String: [[String: Any]]] {
            worktreesByProject = worktreesMap.mapValues { wtArray in
                wtArray.compactMap { Worktree(from: $0) }
            }
        }

        if let agentsArray = result["agents"] as? [[String: Any]] {
            agents = agentsArray.compactMap { AgentConfig(from: $0) }
        }
    }

    // MARK: - Projects

    func addProject(repoPath: String) async -> Project? {
        guard let response = await call("project/add", params: ["repo_path": repoPath]) else { return nil }
        guard let dict = response.result?.dictValue else { return nil }
        let project = Project(from: dict)
        if let project {
            projects.append(project)
        }
        return project
    }

    func removeProject(id: String) async {
        let _ = await call("project/remove", params: ["id": id])
        projects.removeAll { $0.id == id }
        worktreesByProject.removeValue(forKey: id)
    }

    // MARK: - Worktrees

    func createWorktree(projectId: String, branch: String, sourceBranch: String) async -> Worktree? {
        guard let response = await call("worktree/create", params: [
            "project_id": projectId,
            "branch": branch,
            "source_branch": sourceBranch
        ]) else { return nil }
        guard let dict = response.result?.dictValue else { return nil }
        let wt = Worktree(from: dict)
        if let wt {
            worktreesByProject[projectId, default: []].append(wt)
        }
        return wt
    }

    func deleteWorktree(id: String, projectId: String) async {
        let _ = await call("worktree/delete", params: ["id": id])
        worktreesByProject[projectId]?.removeAll { $0.id == id }
        if selectedWorktree?.id == id {
            selectedWorktree = nil
        }
    }

    func listWorktrees(projectId: String) async {
        guard let response = await call("worktree/list", params: ["project_id": projectId]) else { return }
        guard let array = response.result?.arrayValue as? [[String: Any]] else { return }
        worktreesByProject[projectId] = array.compactMap { Worktree(from: $0) }
    }

    // MARK: - Branches

    func listBranches(projectId: String) async -> [String] {
        guard let response = await call("branch/list", params: ["project_id": projectId]) else { return [] }
        guard let dict = response.result?.dictValue,
              let branches = dict["branches"] as? [String] else { return [] }
        return branches
    }

    func defaultBranch(projectId: String) async -> String? {
        guard let response = await call("branch/default", params: ["project_id": projectId]) else { return nil }
        return response.result?.dictValue?["branch"] as? String
    }

    // MARK: - Sessions

    func createSession(worktreeId: String, agentType: String) async -> Session? {
        guard let response = await call("session/create", params: [
            "worktree_id": worktreeId,
            "agent_type": agentType
        ]) else { return nil }
        guard let dict = response.result?.dictValue else { return nil }
        let session = Session(from: dict)
        if let session {
            sessions.append(session)
        }
        return session
    }

    func sendPrompt(sessionId: String, prompt: String) async {
        let _ = await call("session/prompt", params: [
            "session_id": sessionId,
            "prompt": prompt
        ])
    }

    func stopSession(sessionId: String) async {
        let _ = await call("session/stop", params: ["session_id": sessionId])
    }

    func listSessions(worktreeId: String) async {
        guard let response = await call("session/list", params: ["worktree_id": worktreeId]) else { return }
        guard let array = response.result?.arrayValue as? [[String: Any]] else { return }
        sessions = array.compactMap { Session(from: $0) }
    }

    func respondPermission(sessionId: String, requestId: String, outcome: String) async {
        let _ = await call("session/respondPermission", params: [
            "session_id": sessionId,
            "request_id": requestId,
            "outcome": outcome
        ])
    }

    // MARK: - Comments

    func createComment(roundId: String, revisionId: String, startOffset: Int, endOffset: Int, quotedText: String, commentText: String) async {
        let _ = await call("comment/create", params: [
            "round_id": roundId,
            "revision_id": revisionId,
            "start_offset": startOffset,
            "end_offset": endOffset,
            "quoted_text": quotedText,
            "comment_text": commentText
        ])
    }

    func rerunSession(sessionId: String, userNotes: String?) async {
        var params: [String: Any] = ["session_id": sessionId]
        if let notes = userNotes {
            params["user_notes"] = notes
        }
        let _ = await call("session/rerun", params: params)
    }

    // MARK: - Prescript

    func runPrescript(worktreeId: String) async {
        let _ = await call("prescript/run", params: ["worktree_id": worktreeId])
    }

    // MARK: - Terminal

    func terminalExec(worktreeId: String, command: String) async {
        let _ = await call("terminal/exec", params: [
            "worktree_id": worktreeId,
            "command": command
        ])
    }

    func terminalKill(worktreeId: String) async {
        let _ = await call("terminal/kill", params: ["worktree_id": worktreeId])
    }

    // MARK: - Agents

    func listAgents() async {
        guard let response = await call("agent/list") else { return }
        guard let array = response.result?.arrayValue as? [[String: Any]] else { return }
        agents = array.compactMap { AgentConfig(from: $0) }
    }

    // MARK: - Internal

    private func call(_ method: String, params: [String: Any]? = nil) async -> JsonRpcResponse? {
        let request = JsonRpcRequest(method: method, params: params)
        do {
            return try await connection.sendRequest(request)
        } catch {
            if error is DaemonError {
                isConnected = false
                connectionError = error.localizedDescription
            }
            return nil
        }
    }

    private func handleNotification(_ notification: JsonRpcNotification) {
        let params = notification.params ?? [:]
        let dict = params.mapValues { $0.value }

        switch notification.method {
        case "session/stateChanged":
            if let sessionId = dict["session_id"] as? String,
               let state = dict["state"] as? String {
                if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
                    sessions[index].state = state
                }
                NotificationCenter.default.post(
                    name: .sessionStateChanged,
                    object: nil,
                    userInfo: dict
                )
            }

        case "session/output":
            // Forward to session view model via notification center
            NotificationCenter.default.post(
                name: .sessionOutput,
                object: nil,
                userInfo: dict
            )

        case "session/permissionRequest":
            NotificationCenter.default.post(
                name: .sessionPermissionRequest,
                object: nil,
                userInfo: dict
            )

        case "prescript/output":
            NotificationCenter.default.post(
                name: .prescriptOutput,
                object: nil,
                userInfo: dict
            )

        case "prescript/complete":
            NotificationCenter.default.post(
                name: .prescriptComplete,
                object: nil,
                userInfo: dict
            )

        case "terminal/output":
            NotificationCenter.default.post(
                name: .terminalOutput,
                object: nil,
                userInfo: dict
            )

        case "terminal/exit":
            NotificationCenter.default.post(
                name: .terminalExit,
                object: nil,
                userInfo: dict
            )

        default:
            break
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let sessionOutput = Notification.Name("parallax.session.output")
    static let sessionStateChanged = Notification.Name("parallax.session.stateChanged")
    static let sessionPermissionRequest = Notification.Name("parallax.session.permissionRequest")
    static let prescriptOutput = Notification.Name("parallax.prescript.output")
    static let prescriptComplete = Notification.Name("parallax.prescript.complete")
    static let terminalOutput = Notification.Name("parallax.terminal.output")
    static let terminalExit = Notification.Name("parallax.terminal.exit")
}
