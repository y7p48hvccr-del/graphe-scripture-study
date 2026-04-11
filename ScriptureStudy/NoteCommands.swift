import SwiftUI

// MARK: - Note Menu Commands
// These appear in the menu bar when a note is being edited.
// They route through the first responder chain to reach the
// active NoteEditorController.

struct NoteCommands: Commands {
    var body: some Commands {
        // Help menu
        CommandGroup(replacing: .help) {
            #if os(macOS)
            Button("ScriptureStudy Help") {
                HelpWindowController.shared.show()
            }
            .keyboardShortcut("/", modifiers: .command)
            #endif
        }

        CommandMenu("Note") {
            Button("Bold") {
                NoteCommandRouter.shared.bold()
            }
            .keyboardShortcut("b", modifiers: .command)

            Button("Italic") {
                NoteCommandRouter.shared.italic()
            }
            .keyboardShortcut("i", modifiers: .command)

            Divider()

            Button("Heading") {
                NoteCommandRouter.shared.heading()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Button("Bullet List") {
                NoteCommandRouter.shared.bullet()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Divider()

            Button("Increase Font Size") {
                NoteCommandRouter.shared.increaseFontSize()
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Decrease Font Size") {
                NoteCommandRouter.shared.decreaseFontSize()
            }
            .keyboardShortcut("-", modifiers: .command)
        }
    }
}

// MARK: - Command Router
// A singleton that the active NoteEditorController registers with.
// Commands are forwarded only when a note editor is first responder.

class NoteCommandRouter {
    static let shared = NoteCommandRouter()
    private init() {}

    weak var activeController: NoteEditorController?

    func bold()             { activeController?.bold()           }
    func italic()           { activeController?.italic()         }
    func heading()          { activeController?.heading()        }
    func bullet()           { activeController?.bullet()         }
    func increaseFontSize() { activeController?.changeFontSize(by:  1) }
    func decreaseFontSize() { activeController?.changeFontSize(by: -1) }
}
