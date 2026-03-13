import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var daemonService: DaemonService
    let worktreeId: String
    @State private var showingNewSession = false
    @State private var selectedAgent = ""
    @State private var taskDescription = ""

    var body: some View {
        VStack(spacing: 0) {
            // Agent bar
            if !daemonService.agents.isEmpty {
                VStack(spacing: 8) {
                    Picker("Agent", selection: $selectedAgent) {
                        ForEach(daemonService.agents) { agent in
                            Text(agent.displayName).tag(agent.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    HStack(spacing: 8) {
                        TextEditor(text: $taskDescription)
                            .font(.body)
                            .frame(height: 60)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3))
                            )
                            .overlay(alignment: .topLeading) {
                                if taskDescription.isEmpty {
                                    Text("Describe your task...")
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 8)
                                        .allowsHitTesting(false)
                                }
                            }

                        Button {
                            startSession()
                        } label: {
                            Image(systemName: "play.fill")
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedAgent.isEmpty || taskDescription.isEmpty)
                    }
                }
                .padding()

                Divider()
            }

            // Header
            HStack {
                if let wt = daemonService.selectedWorktree {
                    VStack(alignment: .leading) {
                        Text(wt.name)
                            .font(.title2.bold())
                        Text(wt.branch)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Session list
            if daemonService.sessions.isEmpty {
                Spacer()
                Text("No sessions yet")
                    .foregroundStyle(.secondary)
                Text("Choose an agent above and describe your task")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                List(filteredSessions) { session in
                    NavigationLink {
                        SessionView(session: session)
                    } label: {
                        SessionRowView(session: session)
                    }
                }
            }
        }
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

struct SessionRowView: View {
    let session: Session

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(session.agentType)
                    .font(.body)
                Text(session.createdAt.prefix(19).replacingOccurrences(of: "T", with: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SessionStateBadge(state: session.state)
        }
    }
}

struct SessionStateBadge: View {
    let state: String

    var body: some View {
        Text(state.replacingOccurrences(of: "_", with: " "))
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch state {
        case "running": return .blue.opacity(0.2)
        case "completed", "review_required": return .green.opacity(0.2)
        case "failed": return .red.opacity(0.2)
        case "waiting_input": return .orange.opacity(0.2)
        case "stopped": return .gray.opacity(0.2)
        default: return .gray.opacity(0.1)
        }
    }

    private var foregroundColor: Color {
        switch state {
        case "running": return .blue
        case "completed", "review_required": return .green
        case "failed": return .red
        case "waiting_input": return .orange
        default: return .secondary
        }
    }
}
