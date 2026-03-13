import SwiftUI

struct CreateWorktreeSheet: View {
    @EnvironmentObject var daemonService: DaemonService
    @Environment(\.dismiss) private var dismiss
    let project: Project

    @State private var branchName = ""
    @State private var sourceBranch = ""
    @State private var branchSearch = ""
    @State private var branches: [String] = []
    @State private var isLoading = false

    var filteredBranches: [String] {
        if branchSearch.isEmpty { return branches }
        return branches.filter { $0.localizedCaseInsensitiveContains(branchSearch) }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Create Worktree")
                .font(.headline)

            TextField("Branch name", text: $branchName)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("Source branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Search branches...", text: $branchSearch)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: branchSearch) { _, newValue in
                        // Auto-select exact match
                        if branches.contains(newValue) {
                            sourceBranch = newValue
                        }
                    }

                List(filteredBranches, id: \.self, selection: $sourceBranch) { branch in
                    Text(branch)
                        .font(.system(.body, design: .monospaced))
                        .tag(branch)
                }
                .listStyle(.bordered)
                .frame(height: 150)
            }

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
        .frame(width: 400, height: 350)
        .task {
            branches = await daemonService.listBranches(projectId: project.id)
            if let defaultBranch = project.defaultBranch ?? branches.first {
                sourceBranch = defaultBranch
                branchSearch = defaultBranch
            }
        }
    }
}
