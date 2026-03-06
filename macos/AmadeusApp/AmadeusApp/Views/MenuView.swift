import SwiftUI

/// Side menu panel — port of MenuPanelController.cs
struct MenuView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedIndex = 0

    // 0:BACKLOG, 1:CONFIG, 2:STATUS, 3:FULLSCREEN, 4:CHANGELOG,
    // 5:LOGOUT, 6:HELP, 7:SHUTDOWN, 8:CLOSEMENU
    private let menuItems: [(index: Int, label: String, imageName: String, selectedImageName: String)] = [
        (0, "BACKLOG", "Backlog", "BacklogSelected"),
        (1, "CONFIG", "Config", "ConfigSelected"),
        (2, "STATUS", "Status", "StatusSelected"),
        (4, "CHANGELOG", "ChangeLog", "ChangeLogSelected"),
        (6, "HELP", "Help", "HelpSelected"),
    ]

    private let actionItems: [(index: Int, label: String)] = [
        (3, "FULLSCREEN"),
        (5, "LOGOUT"),
        (7, "SHUTDOWN"),
        (8, "CLOSE MENU"),
    ]

    var body: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    closeMenu()
                }

            HStack {
                Spacer()

                // Menu panel
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    Text("MENU")
                        .font(.system(size: 18, weight: .thin, design: .monospaced))
                        .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.2))
                        .tracking(6)
                        .padding(.top, 30)
                        .padding(.bottom, 20)
                        .padding(.horizontal, 24)

                    Divider().background(Color.gray.opacity(0.3))

                    // Menu items
                    ForEach(menuItems, id: \.index) { item in
                        menuButton(
                            label: item.label,
                            imageName: selectedIndex == item.index ? item.selectedImageName : item.imageName,
                            isSelected: selectedIndex == item.index
                        ) {
                            selectedIndex = item.index
                            executeSelection(item.index)
                        }
                    }

                    Divider().background(Color.gray.opacity(0.3)).padding(.vertical, 8)

                    // Action items
                    ForEach(actionItems, id: \.index) { item in
                        menuTextButton(label: item.label, isSelected: selectedIndex == item.index) {
                            selectedIndex = item.index
                            executeSelection(item.index)
                        }
                    }

                    Spacer()
                }
                .frame(width: 220)
                .background(
                    Group {
                        if let bgImage = loadMenuImage("RealAmadeus_Menu_BG_v3") ?? loadMenuBGImage() {
                            Image(nsImage: bgImage)
                                .resizable()
                                .scaledToFill()
                                .opacity(0.3)
                        }
                        Color(red: 0.08, green: 0.08, blue: 0.08).opacity(0.92)
                    }
                )
            }
        }
        .onKeyPress(.escape) { closeMenu(); return .handled }
        .onKeyPress(.delete) { closeMenu(); return .handled }
        .onKeyPress(.upArrow) { navigateUp(); return .handled }
        .onKeyPress(.downArrow) { navigateDown(); return .handled }
        .onKeyPress(.return) { executeSelection(selectedIndex); return .handled }
    }

    private func menuButton(label: String, imageName: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let img = loadMenuImage(imageName) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 14))
                        .frame(width: 20)
                }
                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                Spacer()
            }
            .foregroundColor(isSelected ? .white : Color.gray)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func loadMenuImage(_ name: String) -> NSImage? {
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

    private func loadMenuBGImage() -> NSImage? {
        if let url = Bundle.module.url(forResource: "RealAmadeus_Menu_BG_v3", withExtension: "jpg", subdirectory: "Resources/Images") {
            return NSImage(contentsOf: url)
        }
        if let url = Bundle.module.url(forResource: "RealAmadeus_Menu_BG_v3", withExtension: "jpg") {
            return NSImage(contentsOf: url)
        }
        return nil
    }

    private func menuTextButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Spacer()
            }
            .foregroundColor(isSelected ? .white : Color.gray.opacity(0.6))
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(isSelected ? Color.white.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func navigateUp() {
        let allIndices = (menuItems.map(\.index) + actionItems.map(\.index))
        if let currentPos = allIndices.firstIndex(of: selectedIndex) {
            let newPos = (currentPos - 1 + allIndices.count) % allIndices.count
            selectedIndex = allIndices[newPos]
        }
    }

    private func navigateDown() {
        let allIndices = (menuItems.map(\.index) + actionItems.map(\.index))
        if let currentPos = allIndices.firstIndex(of: selectedIndex) {
            let newPos = (currentPos + 1) % allIndices.count
            selectedIndex = allIndices[newPos]
        }
    }

    private func executeSelection(_ index: Int) {
        switch index {
        case 0: // BACKLOG
            withAnimation { appState.showBackLogPanel = true }
        case 1: // CONFIG
            withAnimation { appState.showConfigPanel = true }
        case 2: // STATUS
            withAnimation { appState.showStatusPanel = true }
        case 3: // FULLSCREEN
            toggleFullscreen()
        case 4: // CHANGELOG
            withAnimation { appState.showChangeLogPanel = true }
        case 5: // LOGOUT
            appState.showConfirmationDialog("ログアウトしますか？") {
                appState.logout()
                closeMenu()
            }
        case 6: // HELP
            withAnimation { appState.showHelpPanel = true }
        case 7: // SHUTDOWN
            appState.showConfirmationDialog("ゲームを終了しますか？") {
                NSApplication.shared.terminate(nil)
            }
        case 8: // CLOSE MENU
            closeMenu()
        default:
            break
        }
    }

    private func closeMenu() {
        withAnimation(.easeInOut(duration: 0.3)) {
            appState.isMenuOpen = false
        }
    }

    private func toggleFullscreen() {
        if let window = NSApplication.shared.windows.first {
            window.toggleFullScreen(nil)
        }
    }
}
