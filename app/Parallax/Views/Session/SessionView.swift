import SwiftUI

struct SessionView: View {
    @EnvironmentObject var daemonService: DaemonService
    let session: Session
    @StateObject private var viewModel: SessionViewModel
    @State private var promptText = ""
    @State private var autoScroll = true

    init(session: Session) {
        self.session = session
        _viewModel = StateObject(wrappedValue: SessionViewModel(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                // Agent icon
                Image(systemName: "cpu")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.agentType)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(session.createdAt.prefix(19).replacingOccurrences(of: "T", with: " "))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

                SessionStateBadge(state: session.state)

                if session.isActive {
                    Button {
                        Task { await viewModel.stop() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9))
                            Text("Stop")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Theme.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.red.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.surface)

            Divider().overlay(Theme.border)

            // Output area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if viewModel.outputContent.isEmpty {
                            HStack(spacing: 8) {
                                if session.isActive {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(Theme.accent)
                                }
                                Text(session.isActive ? "Waiting for output..." : "No output")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .padding(16)
                        } else {
                            Text(viewModel.outputContent)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .textSelection(.enabled)
                        }

                        // Scroll anchor
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                }
                .onChange(of: viewModel.outputContent) { _, _ in
                    if autoScroll {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
            .background(Theme.bg)

            // Permission dialog
            if let request = viewModel.permissionRequest {
                Divider().overlay(Theme.border)
                PermissionDialogView(request: request) { outcome in
                    Task { await viewModel.respondPermission(outcome: outcome) }
                }
            }

            // Input area
            if session.isActive || session.state == "review_required" {
                Divider().overlay(Theme.border)

                HStack(alignment: .bottom, spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $promptText)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text)
                            .scrollContentBackground(.hidden)
                            .frame(height: 48)
                            .padding(8)
                            .background(Theme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Theme.border)
                            )

                        if promptText.isEmpty {
                            Text("Type a message...")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }

                    Button { sendPrompt() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(promptText.isEmpty ? Theme.textTertiary : Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(promptText.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(12)
                .background(Theme.surface)
            }
        }
        .background(Theme.bg)
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
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.toolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(request.description)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: 6) {
                Button { onRespond("reject") } label: {
                    Text("Reject")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.red.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)

                Button { onRespond("allow_once") } label: {
                    Text("Allow")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.green.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)

                Button { onRespond("allow_always") } label: {
                    Text("Always")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.surface)
    }
}
