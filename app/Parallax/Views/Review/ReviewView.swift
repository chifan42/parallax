import SwiftUI

struct ReviewView: View {
    @EnvironmentObject var daemonService: DaemonService
    @EnvironmentObject var theme: Theme
    let sessionId: String
    let roundOutput: String

    @State private var comments: [Comment] = []
    @State private var showingRerunSheet = false
    @State private var newCommentText = ""
    @State private var showingCommentSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.accent)
                Text("Review")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.text)
                Spacer()

                if !comments.isEmpty {
                    Text("\(comments.count) comments")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
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
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(theme.surface)

            Divider().overlay(theme.border)

            // Content
            ScrollView {
                Text(roundOutput)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .textSelection(.enabled)
            }
            .background(theme.bg)

            // Add comment button
            HStack {
                Spacer()
                Button {
                    showingCommentSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.bubble")
                            .font(.system(size: 11))
                        Text("Add Comment")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            // Comments
            if !comments.isEmpty {
                Divider().overlay(theme.border)

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(comments) { comment in
                            CommentRow(comment: comment)
                        }
                    }
                    .padding(12)
                }
                .frame(height: 160)
                .background(theme.surface)
            }
        }
        .background(theme.bg)
        .sheet(isPresented: $showingRerunSheet) {
            RerunSheet(sessionId: sessionId)
        }
        .sheet(isPresented: $showingCommentSheet) {
            AddCommentSheet(sessionId: sessionId) {
                Task { await loadComments() }
            }
        }
        .task {
            await loadComments()
        }
    }

    private func loadComments() async {
        // Get latest round for this session
        let rounds = await daemonService.listRounds(sessionId: sessionId)
        if let lastRound = rounds.last {
            comments = await daemonService.listComments(roundId: lastRound.id)
        }
    }
}

struct CommentRow: View {
    @EnvironmentObject var theme: Theme
    let comment: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(comment.quotedText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.textTertiary)
                .lineLimit(2)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(comment.commentText)
                .font(.system(size: 12))
                .foregroundStyle(theme.text)
        }
        .padding(8)
        .background(theme.surfaceHover)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct RerunSheet: View {
    @EnvironmentObject var daemonService: DaemonService
    @EnvironmentObject var theme: Theme
    @Environment(\.dismiss) private var dismiss
    let sessionId: String

    @State private var additionalNotes = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Re-run with Feedback")
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Comments will be compiled into a feedback prompt for the agent.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)

                Text("Additional notes")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $additionalNotes)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.text)
                        .scrollContentBackground(.hidden)
                        .frame(height: 80)
                        .padding(8)
                        .background(theme.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(theme.border)
                        )

                    if additionalNotes.isEmpty {
                        Text("Optional: add context for the re-run...")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
            }
            .padding(16)

            Spacer()

            Divider().overlay(theme.border)

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
                    .background(theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 440, height: 300)
        .background(theme.surface)
    }
}

struct AddCommentSheet: View {
    @EnvironmentObject var daemonService: DaemonService
    @EnvironmentObject var theme: Theme
    @Environment(\.dismiss) private var dismiss
    let sessionId: String
    let onComplete: () -> Void

    @State private var quotedText = ""
    @State private var commentText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Comment")
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

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected text (quote)")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                    TextField("Paste the text you want to comment on...", text: $quotedText, axis: .vertical)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.text)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .padding(8)
                        .background(theme.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(theme.border)
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Comment")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                    TextField("Your feedback...", text: $commentText, axis: .vertical)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.text)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .padding(8)
                        .background(theme.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(theme.border)
                        )
                }
            }
            .padding(16)

            Spacer()

            Divider().overlay(theme.border)

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
                    Task {
                        let rounds = await daemonService.listRounds(sessionId: sessionId)
                        if let lastRound = rounds.last {
                            await daemonService.createComment(
                                roundId: lastRound.id,
                                revisionId: "rev-1",
                                startOffset: 0,
                                endOffset: quotedText.count,
                                quotedText: quotedText,
                                commentText: commentText
                            )
                        }
                        onComplete()
                        dismiss()
                    }
                } label: {
                    Text("Add Comment")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(commentText.isEmpty ? theme.textTertiary : theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(commentText.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 440, height: 360)
        .background(theme.surface)
    }
}
