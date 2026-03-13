import SwiftUI
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let daemonService = DaemonService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = ContentView()
            .environmentObject(daemonService)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Parallax"
        window.center()
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)

        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
enum ParallaxLauncher {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
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
