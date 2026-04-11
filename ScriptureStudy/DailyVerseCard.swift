import SwiftUI

struct DailyVerseCard: View {

    private let verse = todayVerse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Verse of the Day")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.77, green: 0.64, blue: 0.40))
                .tracking(1)
                .textCase(.uppercase)

            Text("\u{201C}\(verse.text)\u{201D}")
                .font(.body)
                .italic()
                .foregroundStyle(Color.white.opacity(0.9))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Text(verse.reference)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color(red: 0.77, green: 0.64, blue: 0.40))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.10, green: 0.15, blue: 0.27))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    DailyVerseCard()
        .padding()
}
