import SwiftUI

@MainActor
class TerminalViewModel: ObservableObject {
    @Published var output = ""
    @Published var isRunning = false
    let worktreeId: String
    private weak var daemonService: DaemonService?
    private var observers: [NSObjectProtocol] = []

    init(worktreeId: String) {
        self.worktreeId = worktreeId
    }

    func setDaemonService(_ service: DaemonService) {
        self.daemonService = service
        setupNotifications()
    }

    private func setupNotifications() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()

        observers.append(NotificationCenter.default.addObserver(
            forName: .terminalOutput,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let userInfo = notification.userInfo,
                  let wtId = userInfo["worktree_id"] as? String,
                  wtId == self.worktreeId,
                  let content = userInfo["content"] as? String
            else { return }
            self.output += content
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: .terminalExit,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let userInfo = notification.userInfo,
                  let wtId = userInfo["worktree_id"] as? String,
                  wtId == self.worktreeId,
                  let exitCode = userInfo["exit_code"] as? Int
            else { return }
            self.output += "\n--- exited (\(exitCode)) ---\n"
            self.isRunning = false
        })
    }

    func exec(_ command: String) async {
        isRunning = true
        output += "$ \(command)\n"
        await daemonService?.terminalExec(worktreeId: worktreeId, command: command)
    }

    func kill() async {
        await daemonService?.terminalKill(worktreeId: worktreeId)
        isRunning = false
    }

    func clear() {
        output = ""
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

struct TerminalView: View {
    @EnvironmentObject var daemonService: DaemonService
    @EnvironmentObject var theme: Theme
    @StateObject private var viewModel: TerminalViewModel
    @State private var commandText = ""

    init(worktreeId: String) {
        _viewModel = StateObject(wrappedValue: TerminalViewModel(worktreeId: worktreeId))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Terminal header
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.accent)
                Text("Terminal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                Spacer()

                if viewModel.isRunning {
                    Button {
                        Task { await viewModel.kill() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 8))
                            Text("Kill")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(theme.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(theme.red.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    viewModel.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.surface)

            Divider().overlay(theme.border)

            // Output
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if viewModel.output.isEmpty {
                            Text("Run a command below...")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.textTertiary)
                                .padding(8)
                        } else {
                            Text(viewModel.output)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .textSelection(.enabled)
                        }

                        Color.clear.frame(height: 1).id("termBottom")
                    }
                }
                .onChange(of: viewModel.output) { _, _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("termBottom", anchor: .bottom)
                    }
                }
            }
            .background(theme.bg)

            Divider().overlay(theme.border)

            // Command input
            HStack(spacing: 6) {
                Text("$")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.accent)

                TextField("", text: $commandText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        guard !commandText.isEmpty else { return }
                        let cmd = commandText
                        commandText = ""
                        Task { await viewModel.exec(cmd) }
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(theme.surface)
        }
        .task {
            viewModel.setDaemonService(daemonService)
        }
    }
}
