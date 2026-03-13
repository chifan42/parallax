import SwiftUI

struct CreateWorktreeSheet: View {
    @EnvironmentObject var daemonService: DaemonService
    @Environment(\.dismiss) private var dismiss
    let project: Project

    @State private var branchName = ""
    @State private var sourceBranch = ""
    @State private var branches: [String] = []
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Create Worktree")
                .font(.headline)

            TextField("Branch name", text: $branchName)
                .textFieldStyle(.roundedBorder)

            Picker("Source branch", selection: $sourceBranch) {
                ForEach(branches, id: \.self) { branch in
                    Text(branch).tag(branch)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Create") {
                    isLoading = true
                    Task {
                        let _ = await daemonService.createWorktree(
                            projectId: project.id,
                            branch: branchName,
                            sourceBranch: sourceBranch
                        )
                        isLoading = false
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(branchName.isEmpty || sourceBranch.isEmpty || isLoading)
            }
        }
        .padding()
        .frame(width: 350)
        .task {
            branches = await daemonService.listBranches(projectId: project.id)
            if let defaultBranch = project.defaultBranch ?? branches.first {
                sourceBranch = defaultBranch
            }
        }
    }
}
