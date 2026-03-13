import SwiftUI

struct CreateWorktreeSheet: View {
    @EnvironmentObject var daemonService: DaemonService
    @EnvironmentObject var theme: Theme
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
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create Worktree")
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
            VStack(alignment: .leading, spacing: 16) {
                // Branch name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Branch name")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.bg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(theme.border)
                            )
                            .frame(height: 32)

                        TextField("", text: $branchName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.text)
                            .padding(.horizontal, 10)
                    }
                }

                // Source branch
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Source branch")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                        if !sourceBranch.isEmpty {
                            Text(sourceBranch)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(theme.accent.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    // Search
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.bg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(theme.border)
                            )
                            .frame(height: 32)

                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textTertiary)

                            TextField("", text: $branchSearch)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(theme.text)
                                .onChange(of: branchSearch) { _, newValue in
                                    if branches.contains(newValue) {
                                        sourceBranch = newValue
                                    }
                                }
                        }
                        .padding(.horizontal, 10)
                    }

                    // Branch list
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(filteredBranches, id: \.self) { branch in
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.branch")
                                        .font(.system(size: 10))
                                        .foregroundStyle(branch == sourceBranch ? theme.accent : theme.textTertiary)
                                    Text(branch)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(branch == sourceBranch ? theme.text : theme.textSecondary)
                                        .lineLimit(1)
                                    Spacer()
                                    if branch == sourceBranch {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(theme.accent)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(branch == sourceBranch ? theme.accent.opacity(0.08) : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    sourceBranch = branch
                                    branchSearch = branch
                                }
                            }
                        }
                    }
                    .frame(height: 140)
                    .background(theme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(theme.border)
                    )
                }
            }
            .padding(16)

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
                        let _ = await daemonService.createWorktree(
                            projectId: project.id,
                            branch: branchName,
                            sourceBranch: sourceBranch
                        )
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
                        Text("Create")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(branchName.isEmpty || sourceBranch.isEmpty || isLoading
                        ? theme.textTertiary : theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(branchName.isEmpty || sourceBranch.isEmpty || isLoading)
            }
            .padding(16)
        }
        .frame(width: 440, height: 440)
        .background(theme.surface)
        .task {
            branches = await daemonService.listBranches(projectId: project.id)
            if let defaultBranch = project.defaultBranch ?? branches.first {
                sourceBranch = defaultBranch
                branchSearch = defaultBranch
            }
        }
    }
}
