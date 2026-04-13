import SwiftUI
struct ChatView: View {
    @AppStorage("fontSize") private var fontSize: Double = 16
    @AppStorage("fontName") private var fontName: String = ""
    var resolvedFont: Font {
        guard !fontName.isEmpty else { return .system(size: fontSize) }
        return .custom(fontName, size: fontSize)
    }

    @EnvironmentObject var ollama: OllamaService
    @AppStorage("themeID") private var themeID: String = "light"

    @State private var messages:      [ChatMessage] = []
    @State private var inputText      = ""
    @State private var errorMessage:  String?

    private let suggestions = [
        "What is grace?", "Explain the Beatitudes",
        "Who wrote the Psalms?", "What does Selah mean?",
        "Explain the Trinity", "Who were the apostles?",
    ]

    var body: some View {
        ZStack {
            AICircuitBackground(themeID: themeID)
                .ignoresSafeArea()
            VStack(spacing: 0) {

            // Ollama not running banner
            if !ollama.ollamaReady {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Ollama not detected. See the Settings tab for setup instructions.")
                        .font(.caption)
                    Spacer()
                    Button("Retry") { Task { await ollama.checkOllama() } }
                        .controlSize(.small)
                }
                .padding(.horizontal).padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }

            // Input bar at top
            HStack(spacing: 10) {
                TextField("Ask about scripture, theology, history…", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await send() } }
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            inputText.isEmpty || ollama.isLoading
                            ? .secondary
                            : Color(red: 0.1, green: 0.15, blue: 0.27)
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || ollama.isLoading)
            }
            .padding()

            Divider()

            // Suggestion chips (shown when no conversation yet)
            if messages.isEmpty && ollama.chapterSummary.isEmpty {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { s in
                            Button(s) { inputText = s; Task { await send() } }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                Divider()
            }

            // Content area — summary then conversation
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {

                        // Book overview card (chapter 1 only)
                        if !ollama.bookSummary.isEmpty {
                            SummaryCard(
                                title: "Book Overview — \(ollama.bookName)",
                                icon: "books.vertical.fill",
                                content: ollama.bookSummary,
                                resolvedFont: resolvedFont
                            ) {
                                ollama.bookSummary    = ""
                                ollama.bookSummaryReady = false
                            }
                        }

                        // Chapter summary card
                        if ollama.summaryIsLoading {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Generating summary for \(ollama.summaryPassage)…")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal)
                        } else if !ollama.chapterSummary.isEmpty {
                            SummaryCard(
                                title: "Chapter Summary — \(ollama.summaryPassage)",
                                icon: "text.book.closed.fill",
                                content: ollama.chapterSummary,
                                resolvedFont: resolvedFont
                            ) {
                                ollama.chapterSummary = ""
                                ollama.summaryReady   = false
                            }
                        }

                        // Conversation messages
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                        }

                        if ollama.isLoading { TypingIndicator() }

                        if let error = errorMessage {
                            Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal)
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical)
                }
                .onChange(of: messages.count)          { _ in withAnimation { proxy.scrollTo("bottom") } }
                .onChange(of: ollama.isLoading)        { _ in withAnimation { proxy.scrollTo("bottom") } }
                .onChange(of: ollama.chapterSummary)   { _ in withAnimation { proxy.scrollTo("bottom") } }
            }
        }
        }  // ZStack
    }

    private func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !ollama.isLoading else { return }
        inputText    = ""
        errorMessage = nil
        let history  = messages
        messages.append(ChatMessage(role: "user", content: text))
        do {
            let reply = try await ollama.send(history: history, userMessage: text)
            messages.append(ChatMessage(role: "assistant", content: reply))
        } catch {
            errorMessage = error.localizedDescription
            messages.removeLast()
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    @AppStorage("fontSize") private var fontSize: Double = 16
    @AppStorage("fontName") private var fontName: String = ""
    var resolvedFont: Font {
        guard !fontName.isEmpty else { return .system(size: fontSize) }
        return .custom(fontName, size: fontSize)
    }
    var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 80) }
            Text(message.content)
                .font(resolvedFont).lineSpacing(5)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(isUser
                    ? Color(red: 0.1, green: 0.15, blue: 0.27)
                    : Color.platformWindowBg.opacity(0.6))
                .foregroundStyle(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.secondary.opacity(isUser ? 0 : 0.2), lineWidth: 0.5))
            if !isUser { Spacer(minLength: 80) }
        }
        .padding(.horizontal)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animating = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Color.secondary).frame(width: 7, height: 7)
                    .scaleEffect(animating ? 1 : 0.5)
                    .animation(.easeInOut(duration: 0.5).repeatForever()
                        .delay(Double(i) * 0.15), value: animating)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.platformWindowBg.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
        .padding(.horizontal)
        .onAppear { animating = true }
    }
}

// MARK: - Summary Card

struct SummaryCard: View {
    let title:        String
    let icon:         String
    let content:      String
    let resolvedFont: Font
    let onDismiss:    () -> Void

    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)

            // Expandable content
            if expanded {
                Divider()
                Text(content)
                    .font(resolvedFont)
                    .lineSpacing(5)
                    .foregroundStyle(.primary)
                    .padding(14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }
}
