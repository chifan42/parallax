import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var daemonService: DaemonService
    let worktreeId: String
    @State private var showingNewSession = false

    var body: some View {
        VStack {
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
                Button {
                    showingNewSession = true
                } label: {
                    Label("New Session", systemImage: "plus")
                }
            }
            .padding()

            Divider()

            // Session list
            if daemonService.sessions.isEmpty {
                Spacer()
                Text("No sessions yet")
                    .foregroundStyle(.secondary)
                Text("Start a new session to begin working with an agent")
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
        .sheet(isPresented: $showingNewSession) {
            NewSessionSheet(worktreeId: worktreeId)
        }
        .task {
            await daemonService.listSessions(worktreeId: worktreeId)
        }
    }

    private var filteredSessions: [Session] {
        daemonService.sessions.filter { $0.worktreeId == worktreeId }
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

struct NewSessionSheet: View {
    @EnvironmentObject var daemonService: DaemonService
    @Environment(\.dismiss) private var dismiss
    let worktreeId: String

    @State private var selectedAgent = ""
    @State private var taskDescription = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("New Session")
                .font(.headline)

            Picker("Agent", selection: $selectedAgent) {
                ForEach(daemonService.agents) { agent in
                    Text(agent.displayName).tag(agent.id)
                }
            }
            .pickerStyle(.menu)

            TextEditor(text: $taskDescription)
                .frame(height: 100)
                .border(Color.secondary.opacity(0.3))
                .font(.body)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Start") {
                    Task {
                        if let session = await daemonService.createSession(
                            worktreeId: worktreeId,
                            agentType: selectedAgent
                        ) {
                            if !taskDescription.isEmpty {
                                await daemonService.sendPrompt(
                                    sessionId: session.id,
                                    prompt: taskDescription
                                )
                            }
                        }
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedAgent.isEmpty)
            }
        }
        .padding()
        .frame(width: 450)
        .onAppear {
            if let first = daemonService.agents.first {
                selectedAgent = first.id
            }
        }
    }
}
