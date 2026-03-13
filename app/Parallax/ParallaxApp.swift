import SwiftUI

@main
struct ParallaxApp: App {
    @StateObject private var daemonService = DaemonService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(daemonService)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var daemonService: DaemonService

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let worktree = daemonService.selectedWorktree {
                SessionListView(worktreeId: worktree.id)
            } else {
                Text("Select a worktree to get started")
                    .foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: .bottom) {
            if !daemonService.isConnected {
                ConnectionStatusBar()
            }
        }
        .task {
            await daemonService.connect()
        }
    }
}

struct ConnectionStatusBar: View {
    @EnvironmentObject var daemonService: DaemonService

    var body: some View {
        HStack {
            ProgressView()
                .controlSize(.small)
            Text(daemonService.isConnected ? "Connected" : "Connecting to daemon...")
                .font(.caption)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
}
