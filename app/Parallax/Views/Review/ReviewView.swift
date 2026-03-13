import SwiftUI

struct ReviewView: View {
    @EnvironmentObject var daemonService: DaemonService
    let sessionId: String
    let roundOutput: String

    @State private var comments: [Comment] = []
    @State private var showingRerunSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.accent)
                Text("Review")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()

                if !comments.isEmpty {
                    Text("\(comments.count) comments")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }

                Button {
                    showingRerunSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                        Text("Re-run")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.surface)

            Divider().overlay(Theme.border)

            // Content
            ScrollView {
                Text(roundOutput)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .textSelection(.enabled)
            }
            .background(Theme.bg)

            // Comments
            if !comments.isEmpty {
                Divider().overlay(Theme.border)

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(comments) { comment in
                            CommentRow(comment: comment)
                        }
                    }
                    .padding(12)
                }
                .frame(height: 160)
                .background(Theme.surface)
            }
        }
        .background(Theme.bg)
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
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(2)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(comment.commentText)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
        }
        .padding(8)
        .background(Theme.surfaceHover)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct RerunSheet: View {
    @EnvironmentObject var daemonService: DaemonService
    @Environment(\.dismiss) private var dismiss
    let sessionId: String

    @State private var additionalNotes = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Re-run with Feedback")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 20, height: 20)
                        .background(Theme.surfaceHover)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider().overlay(Theme.border)

            VStack(alignment: .leading, spacing: 8) {
                Text("Comments will be compiled into a feedback prompt for the agent.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)

                Text("Additional notes")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $additionalNotes)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text)
                        .scrollContentBackground(.hidden)
                        .frame(height: 80)
                        .padding(8)
                        .background(Theme.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Theme.border)
                        )

                    if additionalNotes.isEmpty {
                        Text("Optional: add context for the re-run...")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
            }
            .padding(16)

            Spacer()

            Divider().overlay(Theme.border)

            HStack {
                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Theme.surfaceHover)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button {
                    Task {
                        await daemonService.rerunSession(
                            sessionId: sessionId,
                            userNotes: additionalNotes.isEmpty ? nil : additionalNotes
                        )
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                        Text("Re-run")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 440, height: 300)
        .background(Theme.surface)
    }
}
