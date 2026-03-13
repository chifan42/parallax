import SwiftUI

struct ReviewView: View {
    @EnvironmentObject var daemonService: DaemonService
    let sessionId: String
    let roundOutput: String

    @State private var comments: [Comment] = []
    @State private var showingRerunSheet = false
    @State private var selectedText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Review")
                    .font(.title2.bold())
                Spacer()
                Button {
                    showingRerunSheet = true
                } label: {
                    Label("Re-run", systemImage: "arrow.clockwise")
                }
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                Text(roundOutput)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }

            // Comments sidebar
            if !comments.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Comments (\(comments.count))")
                        .font(.headline)
                    ForEach(comments) { comment in
                        CommentRow(comment: comment)
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingRerunSheet) {
            RerunSheet(sessionId: sessionId)
        }
    }
}

struct CommentRow: View {
    let comment: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(comment.quotedText)
                .font(.caption)
                .italic()
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(comment.commentText)
                .font(.body)
        }
        .padding(8)
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(6)
    }
}

struct RerunSheet: View {
    @EnvironmentObject var daemonService: DaemonService
    @Environment(\.dismiss) private var dismiss
    let sessionId: String

    @State private var additionalNotes = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Re-run with Feedback")
                .font(.headline)

            Text("Comments will be compiled into a feedback prompt for the agent.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $additionalNotes)
                .frame(height: 80)
                .border(Color.secondary.opacity(0.3))

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Re-run") {
                    Task {
                        await daemonService.rerunSession(
                            sessionId: sessionId,
                            userNotes: additionalNotes.isEmpty ? nil : additionalNotes
                        )
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
