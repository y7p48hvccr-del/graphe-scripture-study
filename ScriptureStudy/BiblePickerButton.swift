import SwiftUI

// Custom Bible picker with guaranteed fixed width
// Uses a popover list instead of Menu — Menu cannot be width-constrained on macOS
struct BiblePickerButton: View {
    let modules:    [MyBibleModule]
    @Binding var selected: MyBibleModule?
    let accent:     Color
    let textColor:  Color

    @State private var showPopover  = false
    @State private var searchText   = ""

    private var filtered: [MyBibleModule] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return modules }
        return modules.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        Button { showPopover.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "book.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                Text(selected?.name ?? "Select Bible")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(textColor.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(width: 160)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {

                // Search box
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    TextField("Search…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 12))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color.secondary.opacity(0.08))

                Divider()

                // None option — only show when not searching
                if searchText.isEmpty {
                    Button {
                        selected = nil
                        showPopover = false
                    } label: {
                        Text("None")
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(selected == nil ? accent.opacity(0.1) : Color.clear)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered) { m in
                            Button {
                                selected = m
                                showPopover = false
                                searchText = ""
                            } label: {
                                Text(m.name)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background(selected?.filePath == m.filePath
                                                ? accent.opacity(0.1) : Color.clear)
                            }
                            .buttonStyle(.plain)
                            .help(m.name)
                        }
                        if filtered.isEmpty {
                            Text("No results")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .frame(width: 280)
            .onDisappear { searchText = "" }
        }
    }
}
