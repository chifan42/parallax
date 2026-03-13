import SwiftUI

struct SettingsView: View {
    @State private var globalPrescriptPath = ""

    var body: some View {
        Form {
            Section("Prescript") {
                HStack {
                    TextField("Global prescript path", text: $globalPrescriptPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowedContentTypes = [.shellScript]
                        if panel.runModal() == .OK, let url = panel.url {
                            globalPrescriptPath = url.path
                        }
                    }
                }
                Text("Script runs after worktree creation. Receives worktree path as working directory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 500)
    }
}
