import SwiftUI

struct SessionView: View {
    @EnvironmentObject var daemonService: DaemonService
    let session: Session
    @StateObject private var viewModel: SessionViewModel
    @State private var promptText = ""

    init(session: Session) {
        self.session = session
        _viewModel = StateObject(wrappedValue: SessionViewModel(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(session.agentType)
                        .font(.headline)
                    SessionStateBadge(state: session.state)
                }
                Spacer()
                if session.isActive {
                    Button("Stop") {
                        Task { await viewModel.stop() }
                    }
                    .tint(.red)
                }
            }
            .padding()

            Divider()

            // Output
            ScrollView {
                Text(viewModel.outputContent.isEmpty ? "Waiting for output..." : viewModel.outputContent)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }

            // Permission dialog
            if let request = viewModel.permissionRequest {
                PermissionDialogView(request: request) { outcome in
                    Task { await viewModel.respondPermission(outcome: outcome) }
                }
            }

            Divider()

            // Input
            if session.isActive || session.state == "review_required" {
                HStack(alignment: .bottom, spacing: 8) {
                    TextEditor(text: $promptText)
                        .font(.body)
                        .frame(height: 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                        .overlay(alignment: .topLeading) {
                            if promptText.isEmpty {
                                Text("Type a message...")
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                        }

                    Button("Send") { sendPrompt() }
                        .disabled(promptText.isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
        }
        .task {
            viewModel.setDaemonService(daemonService)
        }
    }

    private func sendPrompt() {
        let prompt = promptText
        promptText = ""
        Task {
            await viewModel.sendPrompt(prompt)
        }
    }
}

struct PermissionDialogView: View {
    let request: SessionViewModel.PermissionRequest
    let onRespond: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.shield")
                    .foregroundStyle(.orange)
                Text("Permission Request")
                    .font(.headline)
            }

            Text(request.toolName)
                .font(.body.bold())
            Text(request.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Reject") { onRespond("reject") }
                    .tint(.red)
                Button("Allow Once") { onRespond("allow_once") }
                Button("Allow Always") { onRespond("allow_always") }
                    .tint(.green)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .padding()
    }
}
