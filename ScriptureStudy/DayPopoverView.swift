import SwiftUI

struct DayPopoverView: View {
    let date:           Date
    @ObservedObject var calendarStore: CalendarEventStore
    @Binding var newEventText:    String
    @Binding var newEventType:    CalendarEventType
    @Binding var newEventRepeat:  CalendarRepeat
    let calRed:  Color
    let calBlue: Color

    let calPurple = Color(red: 0.55, green: 0.15, blue: 0.85)

    private var dateTitle: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: date)
    }

    private var dayEvents: [CalendarEvent] {
        calendarStore.events(for: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack {
                Text(dateTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color(white: 0.96))

            Divider()

            // Events list
            if dayEvents.isEmpty {
                Text("Nothing scheduled for this day")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.6))
                    .padding(.horizontal, 14).padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(dayEvents) { event in
                        HStack(spacing: 8) {
                            Text(event.symbol)
                                .font(.system(size: 14))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.text)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(event.isDone ? Color(white: 0.6) : .black)
                                    .strikethrough(event.isDone)
                                if event.repeatRule != .once {
                                    Text(event.repeatRule.rawValue)
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color(white: 0.6))
                                }
                            }
                            Spacer()
                            // Done toggle
                            Button {
                                calendarStore.toggle(event)
                            } label: {
                                Image(systemName: event.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(event.isDone ? Color.green : Color(white: 0.7))
                            }
                            .buttonStyle(.plain)
                            // Delete
                            Button {
                                calendarStore.delete(event)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(white: 0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        Divider().padding(.leading, 14)
                    }
                }
            }

            Divider()

            // Add new event
            VStack(alignment: .leading, spacing: 8) {

                // Type picker
                HStack(spacing: 8) {
                    Button {
                        newEventType = .prayer
                    } label: {
                        HStack(spacing: 4) {
                            Text("🙏")
                            Text("Prayer")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(newEventType == .prayer ? calPurple : Color(white: 0.88))
                        .foregroundStyle(newEventType == .prayer ? .white : Color(white: 0.4))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        newEventType = .reminder
                    } label: {
                        HStack(spacing: 4) {
                            Text("❗")
                            Text("Reminder")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(newEventType == .reminder ? calRed : Color(white: 0.88))
                        .foregroundStyle(newEventType == .reminder ? .white : Color(white: 0.4))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                // Repeat picker
                HStack(spacing: 6) {
                    ForEach(CalendarRepeat.allCases, id: \.self) { rule in
                        Button {
                            newEventRepeat = rule
                        } label: {
                            Text(rule.rawValue)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(newEventRepeat == rule
                                    ? Color(white: 0.25)
                                    : Color(white: 0.88))
                                .foregroundStyle(newEventRepeat == rule ? .white : Color(white: 0.5))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Text input
                HStack(spacing: 6) {
                    TextField("Add \(newEventType == .prayer ? "prayer request" : "reminder")…",
                              text: $newEventText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Color(white: 0.94))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onSubmit { addEvent() }

                    Button(action: addEvent) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(newEventType == .prayer ? calPurple : calRed)
                    }
                    .buttonStyle(.plain)
                    .disabled(newEventText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(Color.white)
    }

    private func addEvent() {
        let text = newEventText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let event = CalendarEvent(
            text:       text,
            type:       newEventType,
            date:       date,
            repeatRule: newEventRepeat
        )
        calendarStore.add(event)
        newEventText = ""
    }
}
