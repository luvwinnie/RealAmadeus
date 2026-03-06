import SwiftUI

/// Confirmation dialog — port of ConfirmationDialog.cs
struct ConfirmationDialogView: View {
    @EnvironmentObject var appState: AppState
    @State private var isYesSelected = true

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 20) {
                Text(appState.confirmationMessage)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                HStack(spacing: 20) {
                    // No button
                    Button(action: { onNo() }) {
                        Text("いいえ")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(!isYesSelected ? .black : .white)
                            .frame(width: 100, height: 36)
                            .background(!isYesSelected ? Color(red: 0.85, green: 0.65, blue: 0.2) : Color.white.opacity(0.1))
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)

                    // Yes button
                    Button(action: { onYes() }) {
                        Text("はい")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(isYesSelected ? .black : .white)
                            .frame(width: 100, height: 36)
                            .background(isYesSelected ? Color(red: 0.85, green: 0.65, blue: 0.2) : Color.white.opacity(0.1))
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 24)
            }
            .frame(width: 360)
            .background(Color(red: 0.12, green: 0.12, blue: 0.12))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(red: 0.85, green: 0.65, blue: 0.2).opacity(0.5), lineWidth: 1)
            )
        }
        .onKeyPress(.leftArrow) { isYesSelected = false; return .handled }
        .onKeyPress(.rightArrow) { isYesSelected = true; return .handled }
        .onKeyPress(.return) {
            if isYesSelected { onYes() } else { onNo() }
            return .handled
        }
        .onKeyPress(.escape) { onNo(); return .handled }
    }

    private func onYes() {
        withAnimation { appState.showConfirmation = false }
        appState.confirmationYesAction?()
    }

    private func onNo() {
        withAnimation { appState.showConfirmation = false }
        appState.confirmationNoAction?()
    }
}
