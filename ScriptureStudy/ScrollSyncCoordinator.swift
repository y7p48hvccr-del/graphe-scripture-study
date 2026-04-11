import SwiftUI

// MARK: - Scroll position preference key

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct VerseFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Scroll offset reader

/// Invisible view placed inside a ScrollView to read the current scroll offset
struct ScrollOffsetReader: View {
    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: ScrollOffsetKey.self,
                value: geo.frame(in: .named("scrollCoordinate")).minY
            )
        }
        .frame(height: 0)
    }
}

// MARK: - Verse position anchor modifier

/// Attach to each verse row to report its Y position within the scroll coordinate space
struct VerseAnchorModifier: ViewModifier {
    let verseNumber: Int

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: VerseFrameKey.self,
                        value: [verseNumber: geo.frame(in: .named("scrollCoordinate")).minY]
                    )
                }
            )
    }
}

extension View {
    func verseAnchor(_ verseNumber: Int) -> some View {
        modifier(VerseAnchorModifier(verseNumber: verseNumber))
    }
}

// MARK: - Scroll sync manager

/// Determines which verse number is currently at the top of the viewport
struct ScrollSyncManager {
    /// Given the current scroll offset and all verse Y positions,
    /// find the topmost verse in view
    static func topVisibleVerse(
        scrollOffset: CGFloat,
        verseFrames: [Int: CGFloat]
    ) -> Int? {
        // verseFrames values are positions in scroll coordinate space
        // A verse is "at the top" when its Y position is near 0 (i.e. at viewport top)
        // scrollOffset is negative when scrolled down
        let viewportTop = -scrollOffset

        // Find verse whose top is closest to but not below the viewport top
        let candidates = verseFrames.filter { _, y in y <= viewportTop + 60 }
        return candidates.max(by: { $0.value < $1.value })?.key
    }
}
