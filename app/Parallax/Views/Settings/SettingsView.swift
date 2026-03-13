import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var theme: Theme
    @State private var globalPrescriptPath = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.accent)
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.text)
                Spacer()
            }
            .padding(16)

            Divider().overlay(theme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Theme section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Theme")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.text)

                        HStack(spacing: 10) {
                            ForEach(ThemePalette.all, id: \.id) { palette in
                                ThemeCard(
                                    palette: palette,
                                    isSelected: theme.palette.id == palette.id
                                ) {
                                    theme.select(palette.id)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Prescript section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Prescript")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.text)

                        Text("Script runs after worktree creation. Receives worktree path as working directory.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)

                        HStack(spacing: 8) {
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(theme.bg)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(theme.border)
                                    )
                                    .frame(height: 32)

                                if globalPrescriptPath.isEmpty {
                                    Text("~/.config/parallax/prescript.sh")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(theme.textTertiary)
                                        .padding(.horizontal, 10)
                                } else {
                                    Text(globalPrescriptPath)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(theme.text)
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
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(16)
            }
        }
        .background(theme.bg)
    }
}

struct ThemeCard: View {
    @EnvironmentObject var theme: Theme
    let palette: ThemePalette
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Preview swatch
                RoundedRectangle(cornerRadius: 6)
                    .fill(palette.bg)
                    .frame(height: 48)
                    .overlay(
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(palette.surface)
                                .frame(width: 50, height: 8)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(palette.accent)
                                .frame(width: 30, height: 6)
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? theme.accent : theme.border, lineWidth: isSelected ? 2 : 1)
                    )

                Text(palette.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? theme.text : theme.textSecondary)
            }
            .frame(width: 100)
        }
        .buttonStyle(.plain)
    }
}
