import SwiftUI

struct StrongsDetailView: View {

    let strongsNumber: String
    let entry:         StrongsEntry?
    let isLoading:     Bool
    @Binding var isPresented: Bool

    var isGreek: Bool { strongsNumber.hasPrefix("G") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Title bar
            HStack {
                Text(strongsNumber)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isGreek ? Color.blue : Color.orange)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(isGreek ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                    .clipShape(Capsule())
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal).padding(.vertical, 10)

            Divider()

            if isLoading {
                HStack { Spacer(); ProgressView("Looking up...").padding(); Spacer() }

            } else if let e = entry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {

                        // Line 1: lexeme (transliteration | pronunciation | short definition)
                        Text(headerText(e))
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal).padding(.vertical, 12)

                        // Cross-references (ETCBC#, TWOT, GK, Hebrew/Greek equivalents)
                        if !e.references.isEmpty {
                            Divider()
                            Text(e.references)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal).padding(.vertical, 8)
                        }

                        // Strong's definition
                        let definition = e.strongsDefinition.isEmpty ? e.shortDefinition : e.strongsDefinition
                        if !definition.isEmpty {
                            Divider()
                            Text("Strong's")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal).padding(.top, 10).padding(.bottom, 2)
                            Text(definition)
                                .font(.body)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal).padding(.bottom, 10)
                        }

                        // Derivation
                        if !e.derivation.isEmpty {
                            Divider()
                            Text("Derivation")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal).padding(.top, 10).padding(.bottom, 2)
                            Text(e.derivation)
                                .font(.body)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal).padding(.bottom, 10)
                        }

                        // KJV
                        if !e.kjv.isEmpty {
                            Divider()
                            Text("KJV Usage")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal).padding(.top, 10).padding(.bottom, 2)
                            Text(e.kjv)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal).padding(.bottom, 10)
                        }

                        // Cognates
                        if !e.cognates.isEmpty {
                            Divider()
                            Text("Cognates: \(e.cognates.joined(separator: ", "))")
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal).padding(.vertical, 12)
                        }
                    }
                }

            } else {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle).foregroundStyle(.quaternary)
                    Text("No entry found for \(strongsNumber)")
                        .foregroundStyle(.secondary)
                    Text("Make sure a Strong's dictionary is installed in your Library.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
            }
        }
        .frame(width: 420, height: 360)
    }

    private func headerText(_ e: StrongsEntry) -> String {
        var parts: [String] = []
        if !e.transliteration.isEmpty { parts.append(e.transliteration) }
        if !e.pronunciation.isEmpty   { parts.append(e.pronunciation) }
        if !e.shortDefinition.isEmpty { parts.append(e.shortDefinition) }
        let inner = parts.joined(separator: "\u{FF5C}")
        return inner.isEmpty ? e.lexeme : "\(e.lexeme) (\(inner))"
    }
}
