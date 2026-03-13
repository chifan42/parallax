import SwiftUI

struct SessionView: View {
    @EnvironmentObject var daemonService: DaemonService
    @EnvironmentObject var theme: Theme
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
                Image(systemName: "cpu")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.agentType)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Text(session.createdAt.prefix(19).replacingOccurrences(of: "T", with: " "))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
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
                        .foregroundStyle(theme.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(theme.red.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(theme.surface)

            Divider().overlay(theme.border)

            // Output area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if viewModel.outputContent.isEmpty {
                            HStack(spacing: 8) {
                                if session.isActive {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(theme.accent)
                                }
                                Text(session.isActive ? "Waiting for output..." : "No output")
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.textTertiary)
                            }
                            .padding(16)
                        } else {
                            Text(viewModel.outputContent)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(theme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .textSelection(.enabled)
                        }

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
            .background(theme.bg)

            // Permission dialog
            if let request = viewModel.permissionRequest {
                Divider().overlay(theme.border)
                PermissionDialogView(request: request) { outcome in
                    Task { await viewModel.respondPermission(outcome: outcome) }
                }
            }

            // Input area
            if session.isActive || session.state == "review_required" {
                Divider().overlay(theme.border)

                HStack(alignment: .center, spacing: 8) {
                    ZStack(alignment: .leading) {
                        if promptText.isEmpty {
                            Text("Type a message...")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.textTertiary)
                                .padding(.leading, 12)
                        }

                        TextField("", text: $promptText, axis: .vertical)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.text)
                            .textFieldStyle(.plain)
                            .lineLimit(1...4)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .onSubmit { sendPrompt() }
                    }
                    .background(theme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.border)
                    )

                    Button { sendPrompt() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(promptText.isEmpty ? theme.textTertiary : theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(promptText.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(12)
                .background(theme.surface)
            }
        }
        .background(theme.bg)
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
    @EnvironmentObject var theme: Theme
    let request: SessionViewModel.PermissionRequest
    let onRespond: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 18))
                .foregroundStyle(theme.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.toolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text(request.description)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: 6) {
                Button { onRespond("reject") } label: {
                    Text("Reject")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(theme.red.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)

                Button { onRespond("allow_once") } label: {
                    Text("Allow")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(theme.green.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)

                Button { onRespond("allow_always") } label: {
                    Text("Always")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(theme.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(theme.surface)
    }
}
