import SwiftUI

/// ChangeLog panel — port of ChangeLogPanelController.cs
struct ChangeLogView: View {
    @EnvironmentObject var appState: AppState

    private let changes: [(version: String, date: String, items: [String])] = [
        ("v1.5.0", "2026-03-06", [
            "macOS native SwiftUI port",
            "All AI providers supported (OpenAI, Gemini, Claude, Groq, Vertex AI)",
            "Streaming response support for Groq and Vertex AI",
            "Persistent memory system",
            "Boot sequence animation",
            "Live2D placeholder with emotion display",
        ]),
        ("v1.4.0", "2025-xx-xx", [
            "Enterで進まなくなる問題の修正",
            "タイムアウトの実装",
        ]),
        ("v1.3.0", "2025-xx-xx", [
            "Vertex以外で、文字が一斉に表示されてしまう問題を修正",
        ]),
        ("v1.2.0", "2025-xx-xx", [
            "GPU使用率が異常に高くなってしまう問題を修正",
            "フルスクリーン状態での最小化時の問題を修正",
            "ログアウト後の再ログインが不可能になる問題を修正",
            "一部AIサービスの感情タグ表示問題を修正",
        ]),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("CHANGELOG")
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
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(change.version)
                                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                                        .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.2))
                                    Text(change.date)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.gray)
                                }

                                ForEach(change.items, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•")
                                            .foregroundColor(.gray)
                                        Text(item)
                                            .font(.system(size: 13))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                        }
                    }
                    .padding(24)
                }

                Spacer()
            }
            .frame(width: 550, height: 450)
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

    private func close() {
        withAnimation { appState.showChangeLogPanel = false }
    }
}
