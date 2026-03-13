import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var daemonService: DaemonService
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
                        ForEach(daemonService.agents) { agent in
                            AgentTab(
                                name: agent.displayName,
                                isSelected: selectedAgent == agent.id
                            ) {
                                selectedAgent = agent.id
                            }
                        }
                        Spacer()
                    }
                }

                // Prompt input
                HStack(alignment: .bottom, spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $taskDescription)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text)
                            .scrollContentBackground(.hidden)
                            .frame(height: 56)
                            .padding(8)
                            .background(Theme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Theme.border)
                            )

                        if taskDescription.isEmpty {
                            Text("Describe your task...")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }

                    Button {
                        startSession()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(selectedAgent.isEmpty || taskDescription.isEmpty
                                ? Theme.textTertiary : Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedAgent.isEmpty || taskDescription.isEmpty)
                }
            }
            .padding(16)

            Divider().overlay(Theme.border)

            // Worktree header
            if let wt = daemonService.selectedWorktree {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.branch")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                    Text(wt.branch)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(filteredSessions.count) sessions")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider().overlay(Theme.border)
            }

            // Session list
            if filteredSessions.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.textTertiary)
                    Text("No sessions yet")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    Text("Choose an agent and describe your task above")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
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
        .background(Theme.bg)
        .onAppear {
            if selectedAgent.isEmpty, let first = daemonService.agents.first {
                selectedAgent = first.id
            }
        }
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
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.text : Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Theme.accent.opacity(0.15) : Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Theme.accent.opacity(0.4) : Theme.border)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

struct SessionCard: View {
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
                        .foregroundStyle(Theme.text)
                    Spacer()
                    SessionStateBadge(state: session.state)
                }

                Text(session.createdAt.prefix(19).replacingOccurrences(of: "T", with: " "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusColor: Color {
        switch session.state {
        case "running": return Theme.accent
        case "completed", "review_required": return Theme.green
        case "failed": return Theme.red
        case "waiting_input": return Theme.orange
        default: return Theme.textTertiary
        }
    }
}

struct SessionStateBadge: View {
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
        case "running": return Theme.accent.opacity(0.15)
        case "completed", "review_required": return Theme.green.opacity(0.15)
        case "failed": return Theme.red.opacity(0.15)
        case "waiting_input": return Theme.orange.opacity(0.15)
        default: return Theme.textTertiary.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch state {
        case "running": return Theme.accent
        case "completed", "review_required": return Theme.green
        case "failed": return Theme.red
        case "waiting_input": return Theme.orange
        default: return Theme.textTertiary
        }
    }
}
