import SwiftUI

struct AddProjectSheet: View {
    @EnvironmentObject var daemonService: DaemonService
    @EnvironmentObject var theme: Theme
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPath: String = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Repository")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.text)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 20, height: 20)
                        .background(theme.surfaceHover)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider().overlay(theme.border)

            // Content
            VStack(alignment: .leading, spacing: 12) {
                Text("Repository path")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)

                HStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.bg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(theme.border)
                            )
                            .frame(height: 32)

                        if selectedPath.isEmpty {
                            Text("/path/to/repository")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(theme.textTertiary)
                                .padding(.horizontal, 10)
                        } else {
                            Text(selectedPath)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(theme.text)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                        }
                    }

                    Button {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            selectedPath = url.path
                        }
                    } label: {
                        Text("Browse")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.text)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(theme.surfaceHover)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)

            Spacer()

            Divider().overlay(theme.border)

            // Actions
            HStack {
                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(theme.surfaceHover)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button {
                    isLoading = true
                    Task {
                        let _ = await daemonService.addProject(repoPath: selectedPath)
                        isLoading = false
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                        }
                        Text("Add")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(selectedPath.isEmpty || isLoading ? theme.textTertiary : theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedPath.isEmpty || isLoading)
            }
            .padding(16)
        }
        .frame(width: 440, height: 220)
        .background(theme.surface)
    }
}
