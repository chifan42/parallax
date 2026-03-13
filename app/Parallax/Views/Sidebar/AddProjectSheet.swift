import SwiftUI

struct AddProjectSheet: View {
    @EnvironmentObject var daemonService: DaemonService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPath: String = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Repository")
                .font(.headline)

            HStack {
                TextField("Repository path", text: $selectedPath)
                    .textFieldStyle(.roundedBorder)

                Button("Browse...") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        selectedPath = url.path
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Add") {
                    isLoading = true
                    Task {
                        let _ = await daemonService.addProject(repoPath: selectedPath)
                        isLoading = false
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedPath.isEmpty || isLoading)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
