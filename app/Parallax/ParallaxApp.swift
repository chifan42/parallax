import SwiftUI
import AppKit

// MARK: - Theme Palette

struct ThemePalette: Equatable {
    let id: String
    let displayName: String
    let bg: Color
    let surface: Color
    let surfaceHover: Color
    let border: Color
    let text: Color
    let textSecondary: Color
    let textTertiary: Color
    let accent: Color
    let green: Color
    let red: Color
    let orange: Color
    let nsBg: NSColor

    static let dark = ThemePalette(
        id: "dark",
        displayName: "Dark",
        bg: Color(red: 0.08, green: 0.08, blue: 0.10),
        surface: Color(red: 0.11, green: 0.11, blue: 0.14),
        surfaceHover: Color(red: 0.14, green: 0.14, blue: 0.17),
        border: Color.white.opacity(0.08),
        text: Color(red: 0.93, green: 0.93, blue: 0.95),
        textSecondary: Color(red: 0.55, green: 0.55, blue: 0.60),
        textTertiary: Color(red: 0.35, green: 0.35, blue: 0.40),
        accent: Color(red: 0.40, green: 0.56, blue: 1.0),
        green: Color(red: 0.30, green: 0.78, blue: 0.55),
        red: Color(red: 0.90, green: 0.35, blue: 0.40),
        orange: Color(red: 0.95, green: 0.65, blue: 0.25),
        nsBg: NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
    )

    static let solarizedLight = ThemePalette(
        id: "solarized_light",
        displayName: "Solarized Light",
        bg: Color(red: 0.992, green: 0.965, blue: 0.890),
        surface: Color(red: 0.933, green: 0.910, blue: 0.835),
        surfaceHover: Color(red: 0.867, green: 0.839, blue: 0.757),
        border: Color(red: 0.576, green: 0.631, blue: 0.631).opacity(0.3),
        text: Color(red: 0.027, green: 0.212, blue: 0.259),
        textSecondary: Color(red: 0.345, green: 0.431, blue: 0.459),
        textTertiary: Color(red: 0.576, green: 0.631, blue: 0.631),
        accent: Color(red: 0.149, green: 0.545, blue: 0.824),
        green: Color(red: 0.522, green: 0.600, blue: 0.000),
        red: Color(red: 0.863, green: 0.196, blue: 0.184),
        orange: Color(red: 0.796, green: 0.294, blue: 0.086),
        nsBg: NSColor(red: 0.992, green: 0.965, blue: 0.890, alpha: 1.0)
    )

    static let all: [ThemePalette] = [.dark, .solarizedLight]
}

// MARK: - Theme

class Theme: ObservableObject {
    @Published private(set) var palette: ThemePalette

    var bg: Color { palette.bg }
    var surface: Color { palette.surface }
    var surfaceHover: Color { palette.surfaceHover }
    var border: Color { palette.border }
    var text: Color { palette.text }
    var textSecondary: Color { palette.textSecondary }
    var textTertiary: Color { palette.textTertiary }
    var accent: Color { palette.accent }
    var green: Color { palette.green }
    var red: Color { palette.red }
    var orange: Color { palette.orange }
    var nsBg: NSColor { palette.nsBg }

    var onPaletteChanged: ((ThemePalette) -> Void)?

    init() {
        let id = UserDefaults.standard.string(forKey: "selectedTheme") ?? "dark"
        self.palette = ThemePalette.all.first { $0.id == id } ?? .dark
    }

    func select(_ id: String) {
        guard let p = ThemePalette.all.first(where: { $0.id == id }) else { return }
        UserDefaults.standard.set(id, forKey: "selectedTheme")
        palette = p
        onPaletteChanged?(p)
    }
}

// MARK: - App

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let daemonService = DaemonService()
    let theme = Theme()
    var daemonProcess: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        startDaemon()

        let contentView = ContentView()
            .environmentObject(daemonService)
            .environmentObject(theme)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Parallax"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = theme.nsBg
        window.center()
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)

        theme.onPaletteChanged = { [weak self] palette in
            self?.window.backgroundColor = palette.nsBg
        }

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

// MARK: - Content

struct ContentView: View {
    @EnvironmentObject var daemonService: DaemonService
    @EnvironmentObject var theme: Theme
    @State private var showTerminal = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 240)

            Divider()
                .overlay(theme.border)

            // Main content + terminal
            VStack(spacing: 0) {
                Group {
                    if let worktree = daemonService.selectedWorktree {
                        SessionListView(worktreeId: worktree.id)
                    } else {
                        EmptyStateView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showTerminal, let worktree = daemonService.selectedWorktree {
                    Divider().overlay(theme.border)
                    TerminalView(worktreeId: worktree.id)
                        .frame(height: 200)
                        .id(worktree.id)
                }

                // Bottom bar
                HStack(spacing: 12) {
                    Button {
                        showTerminal.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "terminal")
                                .font(.system(size: 10))
                            Text("Terminal")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(showTerminal ? theme.accent : theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(daemonService.selectedWorktree == nil)

                    Spacer()

                    if daemonService.isConnected {
                        Circle()
                            .fill(theme.green)
                            .frame(width: 6, height: 6)
                        Text("Connected")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(theme.surface)
                .overlay(
                    Rectangle().frame(height: 1).foregroundStyle(theme.border),
                    alignment: .top
                )
            }
        }
        .background(theme.bg)
        .foregroundStyle(theme.text)
        .overlay(alignment: .bottom) {
            if !daemonService.isConnected {
                ConnectionStatusBar()
                    .padding(.bottom, 28)
            }
        }
        .task {
            await daemonService.connect()
        }
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var theme: Theme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 40))
                .foregroundStyle(theme.textTertiary)
            Text("Select a worktree")
                .font(.title3)
                .foregroundStyle(theme.textSecondary)
            Text("Choose a project and worktree from the sidebar to start working with agents")
                .font(.caption)
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
    }
}

struct ConnectionStatusBar: View {
    @EnvironmentObject var theme: Theme

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(theme.accent)
            Text("Connecting to daemon...")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.surface)
        .overlay(
            Rectangle().frame(height: 1).foregroundStyle(theme.border),
            alignment: .top
        )
    }
}
