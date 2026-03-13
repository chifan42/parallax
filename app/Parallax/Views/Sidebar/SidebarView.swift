import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var daemonService: DaemonService
    @State private var showingAddProject = false
    @State private var showingCreateWorktree: Project?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Parallax")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button {
                    showingAddProject = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Theme.surfaceHover)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().overlay(Theme.border)

            // Project list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(daemonService.projects) { project in
                        ProjectSection(
                            project: project,
                            onCreateWorktree: { showingCreateWorktree = project }
                        )
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(Theme.surface)
        .sheet(isPresented: $showingAddProject) {
            AddProjectSheet()
        }
        .sheet(item: $showingCreateWorktree) { project in
            CreateWorktreeSheet(project: project)
        }
    }
}

struct ProjectSection: View {
    @EnvironmentObject var daemonService: DaemonService
    let project: Project
    let onCreateWorktree: () -> Void
    @State private var isExpanded = true

    var worktrees: [Worktree] {
        daemonService.worktreesByProject[project.id] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Project header
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 12)

                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)

                Text(project.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Spacer()

                Button {
                    onCreateWorktree()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .opacity(0.6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture { isExpanded.toggle() }
            .contextMenu {
                Button("Remove Project", role: .destructive) {
                    Task { await daemonService.removeProject(id: project.id) }
                }
            }

            // Worktrees
            if isExpanded {
                ForEach(worktrees) { worktree in
                    WorktreeRow(worktree: worktree, projectId: project.id)
                }
            }
        }
    }
}

struct WorktreeRow: View {
    @EnvironmentObject var daemonService: DaemonService
    let worktree: Worktree
    let projectId: String

    var isSelected: Bool {
        daemonService.selectedWorktree?.id == worktree.id
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.branch")
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)

            VStack(alignment: .leading, spacing: 1) {
                Text(worktree.name)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Theme.text : Theme.textSecondary)
                    .lineLimit(1)
                Text(worktree.branch)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.leading, 20)
        .padding(.vertical, 5)
        .background(isSelected ? Theme.accent.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            daemonService.selectedWorktree = worktree
        }
        .contextMenu {
            Button("Delete Worktree", role: .destructive) {
                Task { await daemonService.deleteWorktree(id: worktree.id, projectId: projectId) }
            }
        }
    }
}
