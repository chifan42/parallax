import SwiftUI

struct SettingsView: View {
    @State private var globalPrescriptPath = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.accent)
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(16)

            Divider().overlay(Theme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Prescript section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Prescript")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)

                        Text("Script runs after worktree creation. Receives worktree path as working directory.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)

                        HStack(spacing: 8) {
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Theme.bg)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Theme.border)
                                    )
                                    .frame(height: 32)

                                if globalPrescriptPath.isEmpty {
                                    Text("~/.config/parallax/prescript.sh")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(Theme.textTertiary)
                                        .padding(.horizontal, 10)
                                } else {
                                    Text(globalPrescriptPath)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(Theme.text)
                                        .lineLimit(1)
                                        .padding(.horizontal, 10)
                                }
                            }

                            Button {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = true
                                panel.canChooseDirectories = false
                                panel.allowedContentTypes = [.shellScript]
                                if panel.runModal() == .OK, let url = panel.url {
                                    globalPrescriptPath = url.path
                                }
                            } label: {
                                Text("Browse")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.text)
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .background(Theme.surfaceHover)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(16)
            }
        }
        .background(Theme.bg)
    }
}
