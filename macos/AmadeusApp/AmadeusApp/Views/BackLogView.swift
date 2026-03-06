import SwiftUI

/// Conversation history backlog — port of BackLogController.cs
struct BackLogView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("BACKLOG")
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

                // Log entries
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(appState.backlogEntries.enumerated()), id: \.offset) { idx, entry in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(displayName(for: entry.role))
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundColor(nameColor(for: entry.role))
                                        .frame(width: 60, alignment: .leading)

                                    Text(entry.message)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 6)
                                .id(idx)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .onChange(of: appState.backlogEntries.count) { _ in
                        if let last = appState.backlogEntries.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }

                if appState.backlogEntries.isEmpty {
                    VStack {
                        Spacer()
                        Text("No conversation history yet")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                    }
                }
            }
            .frame(width: 700, height: 500)
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

    private func displayName(for role: String) -> String {
        switch role.lowercased() {
        case "user", "me": return "あなた"
        case "assistant", "kurisu", "amadeus": return "紅莉栖"
        case "system": return "SYSTEM"
        default: return role.uppercased()
        }
    }

    private func nameColor(for role: String) -> Color {
        switch role.lowercased() {
        case "user", "me": return Color(red: 0.4, green: 0.8, blue: 1.0)
        case "assistant", "kurisu", "amadeus": return Color(red: 1.0, green: 0.4, blue: 0.4)
        default: return .gray
        }
    }

    private func close() {
        withAnimation { appState.showBackLogPanel = false }
    }
}
