import SwiftUI

// MARK: - Licence Redemption View
// Self-contained. To deprecate: delete this file and remove the
// .sheet(isPresented: $showingRedemption) block from ModuleLibraryView.

// MARK: - Redemption State

enum RedemptionState: Equatable {
    case idle
    case validating
    case downloading(progress: Double)
    case success(moduleName: String)
    case failed(message: String)
}

// MARK: - Redemption Service

@MainActor
final class RedemptionService: ObservableObject {

    @Published var state: RedemptionState = .idle

    // ── Server configuration ─────────────────────────────────────────
    // Replace these with your actual server endpoints once set up.
    // The validate endpoint should accept POST { "code": "XXXX-XXXX-XXXX" }
    // and return JSON { "valid": true, "module_name": "KJV Bible",
    //                   "download_url": "https://...", "filename": "KJV.SQLite3" }
    // or             { "valid": false, "message": "Code not found or already used" }

    private let validateEndpoint = "https://api.graphescripture.com/v1/redeem/validate"
    private let userAgent        = "GrapheScriptureStudy/1.0"
    // ─────────────────────────────────────────────────────────────────

    func redeem(code: String, destinationFolder: String) async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else {
            state = .failed(message: "Please enter a licence code.")
            return
        }

        // ── Step 1: Validate code ─────────────────────────────────────
        state = .validating

        let validation: ValidationResponse
        do {
            validation = try await validateCode(trimmed)
        } catch {
            state = .failed(message: "Could not reach the server. Check your connection and try again.")
            return
        }

        guard validation.valid, let downloadURL = validation.downloadURL,
              let filename = validation.filename
        else {
            state = .failed(message: validation.message ?? "Invalid or already used licence code.")
            return
        }

        // ── Step 2: Download module ───────────────────────────────────
        state = .downloading(progress: 0)

        do {
            try await downloadModule(
                from:     downloadURL,
                filename: filename,
                folder:   destinationFolder
            )
            state = .success(moduleName: validation.moduleName ?? filename)
        } catch {
            state = .failed(message: "Download failed: \(error.localizedDescription)")
        }
    }

    func reset() { state = .idle }

    // MARK: - Private: validate

    private func validateCode(_ code: String) async throws -> ValidationResponse {

        // ── Stub (active until server is live) ──────────────────────
        // Simulates a successful response for UI testing.
        // Remove this block and uncomment the real request below
        // once your server endpoint is set up.
        try await Task.sleep(nanoseconds: 1_200_000_000) // simulate network
        return ValidationResponse(
            valid:       true,
            moduleName:  "King James Bible (KJV)",
            downloadURL: nil,   // no actual download in stub
            filename:    "KJV.SQLite3",
            message:     nil
        )
        // ── End stub ─────────────────────────────────────────────────

        /*
        // ── Real request (uncomment when server is live) ──────────────
        guard let url = URL(string: validateEndpoint) else {
            throw URLError(.badURL)
        }
        var request        = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent,          forHTTPHeaderField: "User-Agent")
        request.httpBody   = try JSONEncoder().encode(["code": code])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ValidationResponse.self, from: data)
        // ─────────────────────────────────────────────────────────────
        */
    }

    // MARK: - Private: download

    private func downloadModule(from urlString: String,
                                filename: String,
                                folder: String) async throws {
        // Stub — no real download until server is live
        // Replace with actual URLSession download task when ready
        for i in 1...10 {
            try await Task.sleep(nanoseconds: 150_000_000)
            state = .downloading(progress: Double(i) / 10.0)
        }

        /*
        // ── Real download (uncomment when server is live) ─────────────
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        let (tempURL, _) = try await URLSession.shared.download(from: url)
        let dest = URL(fileURLWithPath: folder).appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)
        // ─────────────────────────────────────────────────────────────
        */
    }
}

// MARK: - Response model

private struct ValidationResponse: Codable {
    let valid:       Bool
    let moduleName:  String?
    let downloadURL: String?
    let filename:    String?
    let message:     String?
}

// MARK: - Redemption Sheet UI

struct LicenceRedemptionView: View {
    @ObservedObject var myBible:    MyBibleService
    let onSuccess:                  () -> Void

    @StateObject private var service = RedemptionService()
    @State private var code:         String = ""
    @State private var showingHelp   = false

    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    @AppStorage("themeID")       private var themeID:       String = "light"
    var accent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image("GrapheLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    Text("Redeem a Licence Code")
                        .font(.title3.weight(.bold))
                }
                Text("Enter the code from your purchase confirmation email to download your module.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            Divider()

            // ── Main content ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 20) {

                switch service.state {

                case .idle, .failed:
                    // Code entry
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Licence Code")
                            .font(.subheadline.weight(.medium))

                        TextField("XXXX-XXXX-XXXX-XXXX", text: $code)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 15, design: .monospaced))
                            .textCase(.uppercase)
                            .autocorrectionDisabled()
                            .onSubmit { startRedemption() }

                        if case .failed(let message) = service.state {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    // Destination info
                    if !myBible.modulesFolder.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(accent)
                                .font(.system(size: 13))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Downloads to your modules folder")
                                    .font(.caption.weight(.medium))
                                Text(myBible.modulesFolder)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(10)
                        .background(accent.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("No modules folder set. Choose a folder in Module Archives first.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                case .validating:
                    statusRow(icon: "network", label: "Validating code…", spinning: true)

                case .downloading(let progress):
                    VStack(alignment: .leading, spacing: 8) {
                        statusRow(icon: "arrow.down.circle", label: "Downloading module…", spinning: false)
                        ProgressView(value: progress)
                            .tint(accent)
                        Text("\(Int(progress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                case .success(let moduleName):
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Module Unlocked")
                                    .font(.headline)
                                Text(moduleName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("The module has been saved to your library and is ready to use.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(20)

            Divider()

            // ── Footer buttons ────────────────────────────────────────
            HStack {
                Button("Help") { showingHelp = true }
                    .foregroundStyle(accent)
                    .buttonStyle(.plain)
                    .font(.subheadline)

                Spacer()

                if case .success = service.state {
                    Button("Done") {
                        onSuccess()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                } else {
                    Button("Cancel") { onSuccess() }
                        .keyboardShortcut(.cancelAction)

                    Button("Redeem") { startRedemption() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || myBible.modulesFolder.isEmpty
                                  || service.state == .validating
                                  || {
                                      if case .downloading = service.state { return true }
                                      return false
                                  }())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 420)
        .alert("About Licence Codes", isPresented: $showingHelp) {
            Button("OK") {}
        } message: {
            Text("Purchase a Bible or module from graphescripture.com or an authorised publisher. You'll receive a unique licence code by email. Enter it here to download and unlock your module.\n\nEach code can only be used once. Keep your confirmation email as proof of purchase.")
        }
    }

    // MARK: - Helpers

    private func startRedemption() {
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            await service.redeem(
                code:              code.uppercased(),
                destinationFolder: myBible.modulesFolder
            )
            if case .success = service.state {
                await myBible.scanModules()
            }
        }
    }

    private func statusRow(icon: String, label: String, spinning: Bool) -> some View {
        HStack(spacing: 10) {
            if spinning {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: icon)
                    .foregroundStyle(accent)
            }
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
