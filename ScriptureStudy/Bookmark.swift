import SwiftUI
import Foundation

// MARK: - Bookmark Model

struct Bookmark: Identifiable, Codable, Equatable {
    var id:            UUID   = UUID()
    var bookNumber:    Int
    var chapterNumber: Int
    var addedAt:       Date   = Date()

    var bookName: String {
        myBibleBookNumbers[bookNumber] ?? "Unknown"
    }

    var displayTitle: String {
        "\(bookName) \(chapterNumber)"
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
