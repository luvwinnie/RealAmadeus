import SwiftUI

/// Help panel — port of HelpPanelController.cs
struct HelpView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("HELP")
                        .font(.system(size: 20, weight: .thin, design: .monospaced))
                        .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.2))
                        .tracking(4)
                    Spacer()
                    Button("✕") { close() }
                        .buttonStyle(.plain)
                        .foregroundColor(.gray)
                        .font(.system(size: 18))
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)

                Divider().background(Color.gray.opacity(0.3))

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        helpSection("Keyboard Shortcuts", items: [
                            ("Tab", "Open/Close Menu"),
                            ("Enter", "Submit message / Advance dialogue"),
                            ("F3", "Toggle Auto Mode"),
                            ("Escape", "Close panels"),
                            ("Backspace", "Close panels"),
                        ])

                        helpSection("Chat", items: [
                            ("Input", "Type a message and press Enter to chat with Kurisu"),
                            ("Typewriter", "Text appears character by character"),
                            ("Paging", "Long responses pause at sentence breaks — press Enter to continue"),
                            ("Auto Mode", "Automatically advances dialogue after a set delay"),
                        ])

                        helpSection("API Setup", items: [
                            ("Config", "Open Menu → CONFIG → API tab"),
                            ("Provider", "Select OpenAI, Gemini, Claude, Groq, Vertex AI, or Ollama"),
                            ("API Key", "Enter your API key for the selected provider"),
                            ("Model", "Specify the model name"),
                            ("Ollama", "Uses custom endpoint — set URL in Config"),
                        ])

                        helpSection("About", items: [
                            ("Project", "Real Amadeus — Steins;Gate 0 fan project"),
                            ("License", "CC BY-NC 4.0"),
                            ("macOS Port", "Native SwiftUI application"),
                        ])
                    }
                    .padding(24)
                }
            }
            .frame(width: 550, height: 500)
            .background(Color(red: 0.1, green: 0.1, blue: 0.1))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(red: 0.85, green: 0.65, blue: 0.2).opacity(0.3), lineWidth: 1)
            )
        }
        .onKeyPress(.escape) { close(); return .handled }
        .onKeyPress(.delete) { close(); return .handled }
    }

    private func helpSection(_ title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.2))

            ForEach(items, id: \.0) { key, desc in
                HStack(alignment: .top, spacing: 12) {
                    Text(key)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 100, alignment: .leading)
                    Text(desc)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }
        }
    }

    private func close() {
        withAnimation { appState.showHelpPanel = false }
    }
}
