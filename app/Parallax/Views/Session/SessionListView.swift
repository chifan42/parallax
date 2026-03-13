import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var daemonService: DaemonService
    @EnvironmentObject var theme: Theme
    let worktreeId: String
    @State private var selectedAgent = ""
    @State private var taskDescription = ""

    var body: some View {
        VStack(spacing: 0) {
            // Agent bar + prompt
            VStack(spacing: 10) {
                // Agent selector
                if !daemonService.agents.isEmpty {
                    HStack(spacing: 6) {
                        Text("Agent")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)

                        ForEach(daemonService.agents) { agent in
                            AgentTab(
                                name: agent.displayName,
                                isSelected: selectedAgent == agent.id
                            ) {
                                if selectedAgent == agent.id {
                                    selectedAgent = ""
                                } else {
                                    selectedAgent = agent.id
                                }
                            }
                        }
                        Spacer()
                    }
                }

                // Prompt input
                HStack(alignment: .center, spacing: 8) {
                    ZStack(alignment: .leading) {
                        if taskDescription.isEmpty {
                            Text("Describe your task...")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.textTertiary)
                                .padding(.leading, 12)
                        }

                        TextField("", text: $taskDescription, axis: .vertical)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.text)
                            .textFieldStyle(.plain)
                            .lineLimit(1...3)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .onSubmit {
                                if !selectedAgent.isEmpty && !taskDescription.isEmpty {
                                    startSession()
                                }
                            }
                    }
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.border)
                    )

                    Button {
                        startSession()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(selectedAgent.isEmpty || taskDescription.isEmpty
                                ? theme.textTertiary : theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedAgent.isEmpty || taskDescription.isEmpty)
                }
            }
            .padding(16)

            Divider().overlay(theme.border)

            // Worktree header
            if let wt = daemonService.selectedWorktree {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.branch")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.accent)
                    Text(wt.branch)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                    Text("\(filteredSessions.count) sessions")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider().overlay(theme.border)
            }

            // Session list
            if filteredSessions.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 28))
                        .foregroundStyle(theme.textTertiary)
                    Text("No sessions yet")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                    Text(selectedAgent.isEmpty
                        ? "Select an agent above to get started"
                        : "Describe your task and press play")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredSessions) { session in
                            NavigationLink {
                                SessionView(session: session)
                            } label: {
                                SessionCard(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(theme.bg)
        .task {
            await daemonService.listSessions(worktreeId: worktreeId)
        }
    }

    private var filteredSessions: [Session] {
        daemonService.sessions.filter { $0.worktreeId == worktreeId }
    }

    private func startSession() {
        let agent = selectedAgent
        let prompt = taskDescription
        taskDescription = ""
        Task {
            if let session = await daemonService.createSession(
                worktreeId: worktreeId,
                agentType: agent
            ) {
                if !prompt.isEmpty {
                    await daemonService.sendPrompt(
                        sessionId: session.id,
                        prompt: prompt
                    )
                }
            }
        }
    }
}

// MARK: - Components

struct AgentTab: View {
    @EnvironmentObject var theme: Theme
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.text : theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? theme.accent.opacity(0.15) : theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? theme.accent.opacity(0.4) : theme.border)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

struct SessionCard: View {
    @EnvironmentObject var theme: Theme
    let session: Session

    var body: some View {
        HStack(spacing: 12) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(session.agentType)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.text)
                    Spacer()
                    SessionStateBadge(state: session.state)
                }

                Text(session.createdAt.prefix(19).replacingOccurrences(of: "T", with: " "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusColor: Color {
        switch session.state {
        case "running": return theme.accent
        case "completed", "review_required": return theme.green
        case "failed": return theme.red
        case "waiting_input": return theme.orange
        default: return theme.textTertiary
        }
    }
}

struct SessionStateBadge: View {
    @EnvironmentObject var theme: Theme
    let state: String

    var body: some View {
        Text(state.replacingOccurrences(of: "_", with: " "))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var backgroundColor: Color {
        switch state {
        case "running": return theme.accent.opacity(0.15)
        case "completed", "review_required": return theme.green.opacity(0.15)
        case "failed": return theme.red.opacity(0.15)
        case "waiting_input": return theme.orange.opacity(0.15)
        default: return theme.textTertiary.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch state {
        case "running": return theme.accent
        case "completed", "review_required": return theme.green
        case "failed": return theme.red
        case "waiting_input": return theme.orange
        default: return theme.textTertiary
        }
    }
}
