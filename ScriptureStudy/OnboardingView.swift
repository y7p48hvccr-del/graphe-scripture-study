import SwiftUI

struct OnboardingView: View {
    @Binding var showAgain: Bool
    let onDismiss: () -> Void

    @State private var page = 0
    @EnvironmentObject var myBible: MyBibleService

    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    @AppStorage("themeID")       private var themeID:       String = "light"
    var filigreeAccent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }

    private let pages: [(icon: String, title: String, body: String, action: String?)] = [
        (
            icon: "book.fill",
            title: "Welcome to ScriptureStudy",
            body: "A focused Bible study environment for Mac. Everything you need is one tap away — cross-references, commentaries, notes, devotionals and more.",
            action: nil
        ),
        (
            icon: "folder.badge.plus",
            title: "Add your modules",
            body: "ScriptureStudy reads MyBible-format files. Go to the Archives tab and tap Choose Modules Folder to point the app to your collection. Hundreds of free modules are available at mybible.zone.",
            action: "Open Library"
        ),
        (
            icon: "hand.tap.fill",
            title: "Reading is simple",
            body: "Tap a verse number to select it — cross-references load automatically in the panel alongside.\n\nLong-press a verse number to create a personal note anchored to that verse.\n\nTap any word to look up its original Hebrew or Greek meaning.",
            action: nil
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Dismiss button top right
            HStack {
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(.top, 12).padding(.trailing, 16)
            }
            // Page content
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { idx, p in
                    pageView(p, index: idx)
                        .tag(idx)
                }
            }
            .tabViewStyle(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Footer
            VStack(spacing: 12) {
                // Page dots
                HStack(spacing: 6) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Circle()
                            .fill(i == page ? filigreeAccent : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                            .animation(.easeInOut, value: page)
                    }
                }

                HStack(spacing: 16) {
                    if page < pages.count - 1 {
                        VStack(alignment: .leading, spacing: 2) {
                            Button("Don't show again") {
                                showAgain = false
                                onDismiss()
                            }
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .buttonStyle(.plain)
                            Text("You can re-enable this in Settings.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary.opacity(0.7))
                        }
                        Spacer()
                        Button("Next →") {
                            withAnimation { page += 1 }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 8)
                        .background(filigreeAccent)
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(isOn: $showAgain) {
                                Text("Show on next launch")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            #if os(macOS)
                            .toggleStyle(.checkbox)
                            #endif
                            Text("You can always reactivate this guide in Settings → Behaviour.")
                                .font(.caption2)
                                .foregroundStyle(.secondary.opacity(0.7))
                        }
                        Spacer()
                        Button("Start Reading") { onDismiss() }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20).padding(.vertical, 8)
                            .background(filigreeAccent)
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .background(Color.platformWindowBg)
        }
        .frame(width: 460, height: 400)
    }

    private func pageView(_ p: (icon: String, title: String, body: String, action: String?), index: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: p.icon)
                .font(.system(size: 52))
                .foregroundStyle(filigreeAccent)

            Text(p.title)
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)

            Text(p.body)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)

            if let action = p.action {
                Button(action) {
                    NotificationCenter.default.post(
                        name: Notification.Name("switchToLibraryTab"),
                        object: nil)
                    onDismiss()
                }
                .foregroundStyle(filigreeAccent)
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
            }
            Spacer()
        }
    }
}
