import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var chatViewModel = ChatViewModel()

    var body: some View {
        ZStack {
            // Background image (same as Windows Amadeus_BG.png)
            Group {
                if let bgImage = loadBundleImage("Amadeus_BG") {
                    Image(nsImage: bgImage)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                }
            }

            // Main content: Live2D character (left) + Chat (right)
            GeometryReader { geo in
                ZStack {
                    HStack(spacing: 0) {
                        // Live2D character on left
                        Live2DView(emotion: $appState.currentEmotion, isSpeaking: $appState.isSpeaking)
                            .frame(width: geo.size.width * 0.5, height: geo.size.height)

                        // Chat panel on right — fills full height
                        ChatView(viewModel: chatViewModel)
                            .frame(width: geo.size.width * 0.5, height: geo.size.height)
                    }

                    // Auto mode indicator
                    if appState.isAutoMode {
                        VStack {
                            HStack {
                                Spacer()
                                Text("AUTO")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.2))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(3)
                                    .padding(.trailing, 16)
                                    .padding(.top, 16)
                            }
                            Spacer()
                        }
                    }

                    // Menu overlay
                    if appState.isMenuOpen {
                        MenuView()
                            .transition(.opacity)
                    }

                    // Sub-panels
                    if appState.showConfigPanel {
                        ConfigView()
                            .transition(.opacity)
                    }
                    if appState.showStatusPanel {
                        StatusView()
                            .transition(.opacity)
                    }
                    if appState.showBackLogPanel {
                        BackLogView()
                            .transition(.opacity)
                    }
                    if appState.showChangeLogPanel {
                        ChangeLogView()
                            .transition(.opacity)
                    }
                    if appState.showHelpPanel {
                        HelpView()
                            .transition(.opacity)
                    }
                    if appState.showConfirmation {
                        ConfirmationDialogView()
                            .transition(.opacity)
                    }
                }
            }
        }
        .onAppear {
            chatViewModel.setup(appState: appState)
        }
        // Global keyboard handlers
        .onKeyPress(.tab) {
            // Don't intercept Tab when user is typing (IME uses Tab for candidates)
            guard appState.chatState != .inputReady else { return .ignored }
            if !appState.isAnySubPanelOpen {
                withAnimation(.easeInOut(duration: 0.3)) {
                    appState.isMenuOpen.toggle()
                }
            }
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "a")) { press in
            // 'A' key toggles auto mode — only when not typing in input field
            guard appState.chatState != .inputReady else { return .ignored }
            appState.isAutoMode.toggle()
            appState.autoModeEnabled = appState.isAutoMode
            return .handled
        }
        .contextMenu {
            if appState.rightClickMenu {
                Button("Menu") {
                    withAnimation { appState.isMenuOpen.toggle() }
                }
            }
        }
    }

    private func loadBundleImage(_ name: String) -> NSImage? {
        for ext in ["png", "jpg"] {
            if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources/Images") {
                return NSImage(contentsOf: url)
            }
            if let url = Bundle.module.url(forResource: name, withExtension: ext) {
                return NSImage(contentsOf: url)
            }
        }
        return nil
    }
}

extension AppState {
    var isAnySubPanelOpen: Bool {
        showConfigPanel || showStatusPanel || showBackLogPanel ||
        showChangeLogPanel || showHelpPanel || showConfirmation
    }
}
