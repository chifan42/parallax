import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var daemonService: DaemonService
    @State private var showingAddProject = false
    @State private var showingCreateWorktree = false
    @State private var selectedProjectForWorktree: Project?

    var body: some View {
        List(selection: Binding(
            get: { daemonService.selectedWorktree?.id },
            set: { id in
                daemonService.selectedWorktree = allWorktrees.first { $0.id == id }
            }
        )) {
            ForEach(daemonService.projects) { project in
                Section(header: projectHeader(project)) {
                    let worktrees = daemonService.worktreesByProject[project.id] ?? []
                    ForEach(worktrees) { worktree in
                        WorktreeRow(worktree: worktree)
                            .tag(worktree.id)
                            .contextMenu {
                                Button("Delete Worktree", role: .destructive) {
                                    Task {
                                        await daemonService.deleteWorktree(
                                            id: worktree.id,
                                            projectId: project.id
                                        )
                                    }
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button {
                    showingAddProject = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddProject) {
            AddProjectSheet()
        }
        .sheet(item: $selectedProjectForWorktree) { project in
            CreateWorktreeSheet(project: project)
        }
    }

    private var allWorktrees: [Worktree] {
        daemonService.worktreesByProject.values.flatMap { $0 }
    }

    private func projectHeader(_ project: Project) -> some View {
        HStack {
            Text(project.name)
            Spacer()
            Button {
                selectedProjectForWorktree = project
            } label: {
                Image(systemName: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button("Remove Project", role: .destructive) {
                Task { await daemonService.removeProject(id: project.id) }
            }
        }
    }
}

struct WorktreeRow: View {
    let worktree: Worktree

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(worktree.name)
                .font(.body)
            Text(worktree.branch)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
