import SwiftUI

// MARK: - Data Models

struct TimelineEvent: Identifiable, Codable {
    let id:          UUID   = UUID()
    let year:        Int
    let title:       String
    let books:       [String]
    let category:    String
    let description:   String
    let dateRationale: String?
    let debate:        String?
    let sources:       [TimelineSource]?
    let perspectives:  [TimelinePerspective]?

    enum CodingKeys: String, CodingKey {
        case year, title, books, category, description, dateRationale, debate, sources, perspectives
    }
}

struct TimelinePerspective: Codable {
    let label:    String
    let summary:  String
    let thinkers: [String]
    let sources:  [TimelineSource]
}

struct TimelineSource: Codable {
    let label: String
    let url:   String
}

struct TimelineCategory: Codable {
    let id:    String
    let label: String
    let color: String
}

struct TimelineData: Codable {
    let note:       String
    let events:     [TimelineEvent]
    let categories: [TimelineCategory]
}

// MARK: - Timeline View

struct TimelineView: View {
    let bookNumber: Int
    let bookName:   String

    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    @AppStorage("themeID")       private var themeID:       String = "light"
    var theme:  AppTheme { AppTheme.find(themeID) }
    var accent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }

    @State private var events:       [TimelineEvent]    = []
    @State private var categories:   [TimelineCategory] = []
    @State private var selected:     TimelineEvent?     = nil
    @State private var filterBook:   Bool               = true
    @State private var noteText:     String             = ""

    private var bookCode: String {
        ScriptureBookCatalog.osisCode(for: bookNumber)
    }

    private var filteredEvents: [TimelineEvent] {
        if filterBook && !bookCode.isEmpty {
            let matching = events.filter { $0.books.contains(bookCode) }
            return matching.isEmpty ? events : matching
        }
        return events
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(filterBook && !bookCode.isEmpty ? bookName : "All Events")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("This book", isOn: $filterBook)
                        #if os(macOS)
                        .toggleStyle(.checkbox)
                        #endif
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text("Tap any event for scholarly notes and sources")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.platformWindowBg)

            Divider()

            if events.isEmpty {
                VStack { Spacer(); ProgressView("Loading…"); Spacer() }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredEvents) { event in
                            TimelineRow(
                                event:      event,
                                category:   categoryColor(event.category),
                                isSelected: selected?.id == event.id,
                                accent:     accent
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selected = selected?.id == event.id ? nil : event
                                }
                            }

                            // Expanded detail
                            if selected?.id == event.id {
                                TimelineDetail(event: event, accent: accent)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            Divider().padding(.leading, 52)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }

            // Disclaimer
            Divider()
            Text(noteText)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .background(theme.background)
        .onAppear { loadData() }
    }

    private func categoryColor(_ id: String) -> Color {
        guard let cat = categories.first(where: { $0.id == id }) else { return .secondary }
        return Color(hex: cat.color) ?? .secondary
    }

    private func loadData() {
        guard let url  = Bundle.main.url(forResource: "BibleTimeline", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let td   = try? JSONDecoder().decode(TimelineData.self, from: data)
        else { return }
        events     = td.events.sorted { $0.year < $1.year }
        categories = td.categories
        noteText   = td.note
    }
}

// MARK: - Timeline Row

struct TimelineRow: View {
    let event:      TimelineEvent
    let category:   Color
    let isSelected: Bool
    let accent:     Color

    var yearLabel: String {
        let y = abs(event.year)
        return event.year < 0 ? "\(y) BC" : "AD \(event.year)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Year
            Text(yearLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .padding(.top, 2)

            // Dot on timeline
            VStack(spacing: 0) {
                Circle()
                    .fill(category)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 8)

            // Title
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? accent : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !event.books.isEmpty {
                    Text(event.books.joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 6)

            Spacer()
            if isSelected {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 6)
            } else {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 6)
            }
        }
        .padding(.horizontal, 10)
        .background(isSelected ? accent.opacity(0.07) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Timeline Detail

struct TimelineDetail: View {
    let event:  TimelineEvent
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Description
            Text(event.description)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // Why this date
            if let rationale = event.dateRationale {
                Divider()
                Label("Why this date", systemImage: "calendar.badge.clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(rationale)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The scholarly debate
            if let debate = event.debate {
                Divider()
                Label("Scholarly debate", systemImage: "text.bubble")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(debate)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Perspectives on origins (Creation event)
            if let perspectives = event.perspectives, !perspectives.isEmpty {
                Divider()
                Label("Perspectives on origins", systemImage: "person.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(perspectives, id: \.label) { p in
                    PerspectiveCard(perspective: p, accent: accent)
                }
            }

            // Sources
            if let sources = event.sources, !sources.isEmpty {
                Divider()
                Label("Further reading", systemImage: "books.vertical")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(sources, id: \.url) { source in
                    Link(destination: URL(string: source.url) ?? URL(string: "https://")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10))
                            Text(source.label)
                                .font(.system(size: 13))
                                .multilineTextAlignment(.leading)
                        }
                        .foregroundStyle(accent)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.platformWindowBg.opacity(0.7))
    }
}

// MARK: - Perspective Card

struct PerspectiveCard: View {
    let perspective: TimelinePerspective
    let accent:      Color
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { expanded.toggle() } label: {
                HStack {
                    Text(perspective.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                Text(perspective.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !perspective.thinkers.isEmpty {
                    Text("Key thinkers: " + perspective.thinkers.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(perspective.sources, id: \.url) { source in
                    Link(destination: URL(string: source.url) ?? URL(string: "https://")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10))
                            Text(source.label)
                                .font(.system(size: 11))
                                .multilineTextAlignment(.leading)
                        }
                        .foregroundStyle(accent.opacity(0.8))
                    }
                }
            }
        }
        .padding(8)
        .background(accent.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Color from hex

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6,
              let v = UInt64(h, radix: 16)
        else { return nil }
        self.init(
            red:   Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8)  & 0xFF) / 255,
            blue:  Double(v         & 0xFF) / 255
        )
    }
}
