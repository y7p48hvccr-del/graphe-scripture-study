import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ollama:        OllamaService
    @EnvironmentObject var notesManager:  NotesManager
    @StateObject private var bmapsService       = BMapsService()
    @StateObject private var interlinearService = InterlinearService()

    @AppStorage("themeID")           private var themeID:           String = "light"
    @AppStorage("filigreeOn")        private var filigreeOn:        Bool   = true
    @AppStorage("filigreeColor")     private var filigreeColor:     Int    = 0
    @AppStorage("filigreeIntensity") private var filigreeIntensity: Double = 0.4
    var theme: AppTheme { AppTheme.find(themeID) }
    var filigreeAccent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }

    @State private var selectedTab: Int = 0
    @AppStorage("hasSeenOnboarding")  private var hasSeenOnboarding:  Bool   = false
    @AppStorage("showGestureHints")   private var showGestureHints:   Bool   = true
    @AppStorage("showStatusHints")    private var showStatusHints:    Bool   = true
    @AppStorage("showOnboardingAgain") private var showOnboardingAgain: Bool  = true
    @State private var showingOnboarding: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Status strip pinned to very top
            SummaryStatusStrip(ollama: ollama, filigreeAccent: filigreeAccent)

            // Main content
            ZStack {
                // Filigree behind everything
                if filigreeOn {
                    FiligreeDecoration(colorIndex: filigreeColor, intensity: filigreeIntensity)
                }

                TabView(selection: $selectedTab) {
                    ZStack { Color.white; LocalBibleView() }
                        .tabItem { Label("Bible",       systemImage: "book.fill") }.tag(0)
                    ZStack { ChatView() }
                        .tabItem { Label("Chat",        systemImage: "bubble.left.and.bubble.right.fill") }.tag(10)
                    ZStack { Color.white; DevotionalView() }
                        .tabItem { Label("Devotional",  systemImage: "book.closed.fill") }.tag(8)
                    ZStack { OrganizerView() }
                        .tabItem { Label("Organizer",   systemImage: "calendar") }.tag(4)
                    ZStack { Color.white; SearchView() }
                        .tabItem { Label("Search",      systemImage: "magnifyingglass") }.tag(5)
                    ZStack { ModuleLibraryView() }
                        .tabItem { Label("Archives",    systemImage: "books.vertical.fill") }.tag(6)
                    ZStack { EPUBLibraryView() }
                        .tabItem { Label("Books",       systemImage: "books.vertical.fill") }.tag(9)
                    ZStack { SettingsView() }
                        .tabItem { Label("Settings",    systemImage: "gearshape.fill") }.tag(7)
                }
                .onReceive(NotificationCenter.default.publisher(for: .navigateToPassage)) { _ in
                    selectedTab = 0
                }
                .onReceive(NotificationCenter.default.publisher(for: .navigateToCommentary)) { _ in
                    selectedTab = 1
                }
                .onChange(of: selectedTab) { newTab in
                    // Auto-delete empty note when navigating away from Organizer tab
                    if newTab != 4, let note = notesManager.selectedNote {
                        notesManager.deleteIfEmpty(note)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("switchToNotesTab"))) { _ in
                    selectedTab = 4
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("noteCreatedFromVerse"))) { _ in
                    selectedTab = 4
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("switchToLibraryTab"))) { _ in
                    selectedTab = 6
                }
                .onAppear {
                    selectedTab = 0  // Always open on Bible tab
                    #if os(macOS)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { applyWindowBackground() }
                    #endif
                    bmapsService.loadIfNeeded()
                    interlinearService.loadIfNeeded()
                    if !hasSeenOnboarding || showOnboardingAgain {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showingOnboarding = true
                        }
                    }
                }
                #if os(macOS)
                .onChange(of: themeID) { _ in applyWindowBackground() }
                #endif
            }
        }
        .tint(filigreeAccent)
        .environmentObject(bmapsService)
        .environmentObject(interlinearService)
        .background(theme.background.ignoresSafeArea())
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView(
                showAgain: $showOnboardingAgain,
                onDismiss: {
                    hasSeenOnboarding = true
                    showingOnboarding = false
                }
            )
        }
    }

    #if os(macOS)
    private func applyWindowBackground() {
        let nsColor: NSColor
        switch themeID {
        case "sepia":     nsColor = NSColor(red: 0.950, green: 0.910, blue: 0.860, alpha: 1)
        case "blush":     nsColor = NSColor(red: 0.980, green: 0.920, blue: 0.930, alpha: 1)
        case "lightgrey": nsColor = NSColor(red: 0.910, green: 0.910, blue: 0.918, alpha: 1)
        case "charcoal":  nsColor = NSColor(red: 0.200, green: 0.220, blue: 0.231, alpha: 1)
        default:          nsColor = .windowBackgroundColor
        }
        NSApp.windows.forEach { $0.backgroundColor = nsColor }
    }
    #endif
}

// MARK: - Summary Status Strip with pulse animation

struct SummaryStatusStrip: View {
    @ObservedObject var ollama:  OllamaService
    let filigreeAccent:          Color

    @State private var opacity:     Double = 1.0
    @State private var pulseCount:  Int    = 0
    @State private var pulsing:     Bool   = false

    var statusText: String {
        if ollama.summaryIsLoading {
            return ollama.bookSummary.isEmpty
                ? "Generating book overview & chapter summary…"
                : "Generating chapter summary for \(ollama.summaryPassage)…"
        }
        return "Study summary ready"
    }

    var body: some View {
        Group {
            if ollama.summaryIsLoading || ollama.summaryReady {
                HStack(spacing: 6) {
                    if ollama.summaryIsLoading {
                        ProgressView().controlSize(.small).tint(filigreeAccent)
                    } else {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(filigreeAccent)
                    }
                    Text(statusText)
                    Spacer()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(filigreeAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(filigreeAccent.opacity(0.12 * opacity))
                .opacity(opacity)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: ollama.summaryIsLoading)
                // Trigger 4 pulses when summary becomes ready
                .onChange(of: ollama.summaryReady) { ready in
                    if ready { startPulses() }
                }
            }
        }
    }

    private func startPulses() {
        pulseCount = 0
        pulse()
    }

    private func pulse() {
        guard pulseCount < 4 else { opacity = 1.0; return }
        withAnimation(.easeInOut(duration: 0.25)) { opacity = 0.15 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeInOut(duration: 0.25)) { opacity = 1.0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                pulseCount += 1
                pulse()
            }
        }
    }
}
