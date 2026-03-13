import Foundation
import SwiftUI

@MainActor
class SessionViewModel: ObservableObject {
    @Published var outputContent = ""
    @Published var isStreaming = false
    @Published var permissionRequest: PermissionRequest?
    @Published var prescriptOutput: [String] = []
    @Published var prescriptRunning = false

    let session: Session
    private weak var daemonService: DaemonService?
    private var observers: [NSObjectProtocol] = []

    struct PermissionRequest: Identifiable {
        let id: String
        let sessionId: String
        let toolName: String
        let description: String
    }

    init(session: Session) {
        self.session = session
    }

    func setDaemonService(_ service: DaemonService) {
        self.daemonService = service
        setupNotifications()
    }

    private func setupNotifications() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .sessionOutput,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let userInfo = notification.userInfo,
                  let sessionId = userInfo["session_id"] as? String,
                  sessionId == self.session.id,
                  let content = userInfo["content"] as? String
            else { return }
            self.outputContent += content
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: .sessionStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let userInfo = notification.userInfo,
                  let sessionId = userInfo["session_id"] as? String,
                  sessionId == self.session.id,
                  let state = userInfo["state"] as? String
            else { return }
            let terminalStates: Set<String> = ["completed", "review_required", "stopped", "failed"]
            if terminalStates.contains(state) {
                self.isStreaming = false
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: .sessionPermissionRequest,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let userInfo = notification.userInfo,
                  let sessionId = userInfo["session_id"] as? String,
                  sessionId == self.session.id,
                  let requestId = userInfo["request_id"] as? String,
                  let toolName = userInfo["tool_name"] as? String,
                  let description = userInfo["description"] as? String
            else { return }
            self.permissionRequest = PermissionRequest(
                id: requestId,
                sessionId: sessionId,
                toolName: toolName,
                description: description
            )
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func sendPrompt(_ prompt: String) async {
        isStreaming = true
        await daemonService?.sendPrompt(sessionId: session.id, prompt: prompt)
    }

    func respondPermission(outcome: String) async {
        guard let request = permissionRequest else { return }
        await daemonService?.respondPermission(
            sessionId: request.sessionId,
            requestId: request.id,
            outcome: outcome
        )
        permissionRequest = nil
    }

    func stop() async {
        await daemonService?.stopSession(sessionId: session.id)
        isStreaming = false
    }
}
