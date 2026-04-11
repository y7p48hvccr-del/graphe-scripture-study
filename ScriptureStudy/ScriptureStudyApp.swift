import SwiftUI

@main
struct ScriptureStudyApp: App {
    init() {
        #if os(macOS)
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif
    }

    @StateObject private var bibleService  = BibleAPIService()
    @StateObject private var ollamaService = OllamaService()
    @StateObject private var myBible       = MyBibleService()
    @StateObject private var notesManager      = NotesManager()
    @StateObject private var bookmarksManager  = BookmarksManager()
    @StateObject private var calendarStore     = CalendarEventStore()
    @State private var launchDone: Bool = false

    @AppStorage("themeID") private var themeID = "light"

    var body: some Scene {
        WindowGroup(id: "main") {
            ZStack {
                ContentView()
                if !launchDone {
                    LaunchScreenView { withAnimation { launchDone = true } }
                        .zIndex(99)
                }
            }
                .environmentObject(bibleService)
                .environmentObject(ollamaService)
                .environmentObject(myBible)
                .environmentObject(notesManager)
                .environmentObject(bookmarksManager)
                .environmentObject(calendarStore)
                #if os(macOS)
                .frame(minWidth: 1100, minHeight: 650)
                #endif
                .preferredColorScheme(
                    themeID == "charcoal" ? .dark : .light
                )
        }
        #if os(macOS)
        .windowResizability(.contentMinSize)
        #endif
        .commands {
            NoteCommands()
        }

        #if os(macOS)
        SwiftUI.Settings {
            SettingsView()
                .environmentObject(ollamaService)
        }
        #endif
    }
}
