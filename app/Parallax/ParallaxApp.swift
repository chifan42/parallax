import SwiftUI
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let daemonService = DaemonService()
    var daemonProcess: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        startDaemon()

        let contentView = ContentView()
            .environmentObject(daemonService)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Parallax"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
        window.center()
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)

        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        daemonProcess?.terminate()
    }

    private func startDaemon() {
        let bundle = Bundle.main
        let daemonPath = bundle.bundleURL
            .appendingPathComponent("Contents/MacOS/parallax-daemon")
            .path

        guard FileManager.default.isExecutableFile(atPath: daemonPath) else {
            print("Daemon not found at \(daemonPath)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: daemonPath)
        process.environment = ProcessInfo.processInfo.environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            daemonProcess = process
            print("Daemon started (pid: \(process.processIdentifier))")
        } catch {
            print("Failed to start daemon: \(error)")
        }
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

// MARK: - Theme

enum Theme {
    static let bg = Color(red: 0.08, green: 0.08, blue: 0.10)
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.14)
    static let surfaceHover = Color(red: 0.14, green: 0.14, blue: 0.17)
    static let border = Color.white.opacity(0.08)
    static let text = Color(red: 0.93, green: 0.93, blue: 0.95)
    static let textSecondary = Color(red: 0.55, green: 0.55, blue: 0.60)
    static let textTertiary = Color(red: 0.35, green: 0.35, blue: 0.40)
    static let accent = Color(red: 0.40, green: 0.56, blue: 1.0)
    static let green = Color(red: 0.30, green: 0.78, blue: 0.55)
    static let red = Color(red: 0.90, green: 0.35, blue: 0.40)
    static let orange = Color(red: 0.95, green: 0.65, blue: 0.25)
    static let mono = Font.system(.body, design: .monospaced)
    static let monoSmall = Font.system(.caption, design: .monospaced)
}

// MARK: - Content

struct ContentView: View {
    @EnvironmentObject var daemonService: DaemonService

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 240)

            Divider()
                .overlay(Theme.border)

            // Main content
            Group {
                if let worktree = daemonService.selectedWorktree {
                    SessionListView(worktreeId: worktree.id)
                } else {
                    EmptyStateView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
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

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textTertiary)
            Text("Select a worktree")
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
            Text("Choose a project and worktree from the sidebar to start working with agents")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
    }
}

struct ConnectionStatusBar: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(Theme.accent)
            Text("Connecting to daemon...")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.surface)
        .overlay(
            Rectangle().frame(height: 1).foregroundStyle(Theme.border),
            alignment: .top
        )
    }
}
