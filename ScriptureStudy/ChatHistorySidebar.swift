import SwiftUI

/// Permanent left-hand panel on the Chat tab. Lists saved conversation
/// threads newest-first with title, date, passage tag (if any), and a
/// short snippet of the opening message. A "+ New" button at the top
/// starts a fresh chat.
///
/// Width is fixed at 320pt on macOS. On iOS the panel isn't shown —
/// ChatView falls back to its original single-column layout.
struct ChatHistorySidebar: View {

    @EnvironmentObject var chatHistory: ChatHistoryManager

    @AppStorage("themeID")       private var themeID:      String = "light"
    @AppStorage("filigreeColor") private var filigreeColor: Int   = 0

    var theme: AppTheme { AppTheme.find(themeID) }
    var accent: Color  { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }

    /// Called by the parent to flush the current conversation's messages
    /// before switching/starting threads, so nothing is lost on tap.
    var onSwitchRequest: (_ action: SwitchAction) -> Void

    enum SwitchAction {
        case newChat
        case open(ChatThread)
    }

    @State private var renamingID:   UUID?   = nil
    @State private var renameDraft:  String  = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            threadList
            Divider()
            footer
        }
        .frame(width: 320)
        .background(theme.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Threads")
                .font(.headline)
                .foregroundStyle(theme.text)
            Spacer()
            // iCloud sync indicator
            if chatHistory.isUsingiCloud {
                Image(systemName: "icloud")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help("Threads sync via iCloud")
            }
            Button {
                onSwitchRequest(.newChat)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("New thread")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Thread list

    @ViewBuilder
    private var threadList: some View {
        if chatHistory.threads.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.largeTitle).foregroundStyle(.quaternary)
                Text("No conversations yet")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Your chats will be saved here.")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(chatHistory.threads) { thread in
                        threadRow(thread)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func threadRow(_ thread: ChatThread) -> some View {
        let isSelected = chatHistory.currentThreadID == thread.id
        let isRenaming = renamingID == thread.id

        VStack(alignment: .leading, spacing: 3) {
            // Title line — either the static title, or a text field while renaming
            if isRenaming {
                TextField("Title", text: $renameDraft, onCommit: {
                    chatHistory.rename(thread, to: renameDraft)
                    renamingID = nil
                })
                .textFieldStyle(.roundedBorder)
                .font(.callout.weight(.medium))
            } else {
                Text(thread.displayTitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
            }

            // Snippet (first user message, truncated)
            if !thread.snippet.isEmpty && thread.snippet != thread.displayTitle {
                Text(thread.snippet)
                    .font(.caption)
                    .foregroundStyle(theme.secondary)
                    .lineLimit(2)
            }

            // Meta row — date + passage tag
            HStack(spacing: 6) {
                Text(thread.formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if !thread.passageReference.isEmpty {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 3) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 9))
                        Text(thread.passageReference)
                    }
                    .font(.caption2)
                    .foregroundStyle(accent)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? accent.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? accent.opacity(0.4) : Color.clear,
                        lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isRenaming else { return }
            onSwitchRequest(.open(thread))
        }
        .contextMenu {
            Button("Rename") {
                renameDraft = thread.displayTitle
                renamingID  = thread.id
            }
            Button("Delete", role: .destructive) {
                chatHistory.delete(thread)
            }
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("\(chatHistory.threads.count) thread\(chatHistory.threads.count == 1 ? "" : "s")")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Text(chatHistory.isUsingiCloud ? "iCloud" : "Local")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
