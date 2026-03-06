import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var loginId = ""
    @State private var password = ""
    @State private var loginFailed = false
    @FocusState private var focusedField: Field?

    enum Field { case loginId, password }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Amadeus Logo
                if let logoImage = loadBundleImage("amadeus_logo_v3") {
                    Image(nsImage: logoImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 400, maxHeight: 120)
                        .padding(.bottom, 40)
                } else {
                    Text("AMADEUS")
                        .font(.system(size: 48, weight: .thin, design: .monospaced))
                        .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.2))
                        .tracking(12)
                        .padding(.bottom, 40)
                }

                // Login Form
                VStack(spacing: 16) {
                    // Login ID
                    HStack {
                        Text("LOGIN ID")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                            .frame(width: 100, alignment: .leading)

                        TextField("", text: $loginId)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .focused($focusedField, equals: .loginId)
                            .onSubmit {
                                focusedField = .password
                            }
                    }

                    // Password
                    HStack {
                        Text("PASSWORD")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                            .frame(width: 100, alignment: .leading)

                        SecureField("", text: $password)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .focused($focusedField, equals: .password)
                            .onSubmit {
                                attemptLogin()
                            }
                    }

                    if loginFailed {
                        Text("Login Failed")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.red)
                    }
                }
                .frame(width: 400)
                .padding(.bottom, 30)

                // Login Button
                Button(action: attemptLogin) {
                    if let btnImage = loadBundleImage("amadeus_login_button_v2") {
                        Image(nsImage: btnImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240, maxHeight: 50)
                    } else {
                        Text("LOGIN")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 10)
                            .background(Color(red: 0.85, green: 0.65, blue: 0.2))
                    }
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .onAppear {
            focusedField = .loginId
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

    private func attemptLogin() {
        if loginId == appState.expectedLoginId && password == appState.expectedPassword {
            appState.operatorName = loginId
            UserDefaults.standard.set(loginId, forKey: "Config_OperatorName")
            if appState.skipLoading {
                appState.currentScreen = .main
            } else {
                appState.currentScreen = .loading
            }
        } else {
            loginFailed = true
        }
    }
}
