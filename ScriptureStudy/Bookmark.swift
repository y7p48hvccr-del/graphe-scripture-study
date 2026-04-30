import SwiftUI
import Foundation

// MARK: - Bookmark Model

struct Bookmark: Identifiable, Codable, Equatable {
    var id:            UUID   = UUID()
    var bookNumber:    Int
    var chapterNumber: Int
    /// Optional verse this bookmark targets. nil = chapter-level bookmark
    /// (legacy data from before verse-level bookmarks were added). Existing
    /// chapter-level bookmarks continue to work — they just navigate to
    /// the chapter rather than a specific verse.
    var verseNumber:   Int?   = nil
    var addedAt:       Date   = Date()
    /// When non-nil, the bookmark has been moved to Trash via bulk
    /// delete. Individual bookmark delete is permanent and does not
    /// set this. Trash is kept forever until the user empties it.
    var deletedAt:     Date?  = nil

    var bookName: String {
        myBibleBookNumbers[bookNumber] ?? "Unknown"
    }

    var displayTitle: String {
        if let v = verseNumber {
            return "\(bookName) \(chapterNumber):\(v)"
        }
        return "\(bookName) \(chapterNumber)"
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: addedAt)
    }
}

// MARK: - Bookmark Ribbon Shape

struct BookmarkRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to:    CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.width * 0.35))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Silk Bookmark Ribbon (long, dramatic — for EPUB reader)

/// A taller, narrower ribbon shape with a more pronounced chevron tail —
/// modelled on a real silk bookmark ribbon hanging from the spine of a
/// physical Bible. The chevron at the bottom is a deeper inverted V
/// (notch depth = ribbon width × 0.7) to give it the dramatic, hand-cut
/// look of a real fabric ribbon. Used decoratively in EPUBReaderView.
struct SilkBookmarkRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        let notch = rect.width * 0.7
        var path = Path()
        path.move(to:    CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - notch))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Decorative silk bookmark ribbon used in EPUBReaderView. Renders only
/// when the current page is bookmarked. Not interactive — toggling lives
/// in the window toolbar (V7 pattern). Composed of three layers: the
/// main ribbon body in deep silk red, a thin highlight stripe down the
/// left edge to hint at silk weave / dimension, and a soft drop shadow
/// so it reads as floating slightly off the page.
struct SilkBookmarkRibbonView: View {
    /// Length of the cascade in points. Set to ~200 for a "third of page"
    /// feel on typical Mac display heights.
    var length: CGFloat = 200
    /// Width of the ribbon in points. ~12pt is roughly an eighth of an
    /// inch on a typical Mac display.
    var width:  CGFloat = 12

    /// Deep silk red — muted oxblood, not bright. Exposed as a static
    /// property so the EPUB reader's toolbar bookmark button can match
    /// the ribbon colour exactly without duplicating the literal.
    static let silkRed       = Color(red: 0.55, green: 0.10, blue: 0.12)
    /// Slightly lighter highlight along the left edge to hint at silk sheen.
    private let silkHighlight = Color(red: 0.72, green: 0.18, blue: 0.20)
    /// Slightly darker tone for a subtle vertical gradient (depth).
    private let silkShadow    = Color(red: 0.42, green: 0.07, blue: 0.09)

    var body: some View {
        ZStack(alignment: .leading) {
            // Main ribbon body — vertical gradient gives it volume.
            SilkBookmarkRibbon()
                .fill(
                    LinearGradient(
                        colors: [Self.silkRed, silkShadow],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width, height: length)
                .shadow(color: .black.opacity(0.25), radius: 4, x: 1, y: 2)

            // Left-edge highlight stripe — hints at silk sheen / fold.
            Rectangle()
                .fill(silkHighlight.opacity(0.55))
                .frame(width: 1.5, height: length - width * 0.7)
                .offset(x: 1)
        }
        .frame(width: width, height: length)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

