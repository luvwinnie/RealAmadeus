import SwiftUI

/// Configuration panel — port of ConfigPanelController.cs
struct ConfigView: View {
    @EnvironmentObject var appState: AppState
    @State private var activeCategory = 0
    @State private var editApiKey = ""
    @State private var editModelName = ""
    @State private var editVertexProject = ""
    @State private var editVertexLocation = ""
    @State private var editOllamaEndpoint = ""

    private let categories = ["General", "Text", "Sound", "Graphic", "API"]

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("CONFIG")
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

                HStack(spacing: 0) {
                    // Sidebar
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(categories.enumerated()), id: \.offset) { idx, name in
                            Button(action: { activeCategory = idx }) {
                                Text(name)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(activeCategory == idx ? .white : .gray)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(activeCategory == idx ? Color.white.opacity(0.1) : Color.clear)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .frame(width: 140)
                    .background(Color.white.opacity(0.02))

                    Divider().background(Color.gray.opacity(0.2))

                    // Content
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            switch activeCategory {
                            case 0: generalSettings
                            case 1: textSettings
                            case 2: soundSettings
                            case 3: graphicSettings
                            case 4: apiSettings
                            default: EmptyView()
                            }
                        }
                        .padding(20)
                    }
                    .frame(maxWidth: .infinity)
                }

                Divider().background(Color.gray.opacity(0.3))

                // Footer
                HStack {
                    Spacer()
                    Button("Cancel") { close() }
                        .buttonStyle(.plain)
                        .foregroundColor(.gray)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                    Button("Save") { save(); close() }
                        .buttonStyle(.plain)
                        .foregroundColor(.black)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.85, green: 0.65, blue: 0.2))
                        .cornerRadius(3)
                }
                .padding(16)
            }
            .frame(width: 650, height: 500)
            .background(Color(red: 0.1, green: 0.1, blue: 0.1))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(red: 0.85, green: 0.65, blue: 0.2).opacity(0.3), lineWidth: 1)
            )
        }
        .onAppear { loadCurrentValues() }
        .onKeyPress(.escape) { close(); return .handled }
    }

    // MARK: - General

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingLabel("General Settings")
            Toggle("Skip Loading Sequence", isOn: $appState.skipLoading)
                .toggleStyle(.switch)
                .tint(Color(red: 0.85, green: 0.65, blue: 0.2))
            Toggle("Right-Click Menu", isOn: $appState.rightClickMenu)
                .toggleStyle(.switch)
                .tint(Color(red: 0.85, green: 0.65, blue: 0.2))
        }
        .foregroundColor(.white)
        .font(.system(size: 13, design: .monospaced))
    }

    // MARK: - Text

    private var textSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingLabel("Text Settings")
            HStack {
                Text("Text Speed")
                Spacer()
                Text("x\(appState.textSpeed, specifier: "%.1f")")
                    .foregroundColor(.gray)
            }
            Slider(value: $appState.textSpeed, in: 0.1...5.0, step: 0.1)
                .tint(Color(red: 0.85, green: 0.65, blue: 0.2))

            HStack {
                Text("Auto Speed")
                Spacer()
                Text("\(appState.autoSpeed, specifier: "%.1f")s")
                    .foregroundColor(.gray)
            }
            Slider(value: $appState.autoSpeed, in: 0.5...10.0, step: 0.5)
                .tint(Color(red: 0.85, green: 0.65, blue: 0.2))

            Toggle("Auto Mode", isOn: $appState.autoModeEnabled)
                .toggleStyle(.switch)
                .tint(Color(red: 0.85, green: 0.65, blue: 0.2))
        }
        .foregroundColor(.white)
        .font(.system(size: 13, design: .monospaced))
    }

    // MARK: - Sound

    private var soundSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingLabel("Sound Settings")
            Text("(Sound settings will be available in a future update)")
                .foregroundColor(.gray)
                .font(.system(size: 12, design: .monospaced))
        }
        .foregroundColor(.white)
    }

    // MARK: - Graphic

    private var graphicSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingLabel("Graphic Settings")
            Button("Toggle Fullscreen") {
                if let window = NSApplication.shared.windows.first {
                    window.toggleFullScreen(nil)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.2))
            .font(.system(size: 13, design: .monospaced))
        }
        .foregroundColor(.white)
    }

    // MARK: - API

    private var apiSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingLabel("API Settings")

            // Provider picker
            HStack {
                Text("Provider")
                Spacer()
                Picker("", selection: $appState.apiProviderIndex) {
                    ForEach(APIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .frame(width: 200)
            }
            .onChange(of: appState.apiProviderIndex) { _ in
                loadCurrentValues()
            }

            // API Key
            HStack {
                Text("API Key")
                Spacer()
                SecureField("Enter API Key", text: $editApiKey)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.gray.opacity(0.3)))
                    .frame(width: 300)
            }

            // Model Name
            HStack {
                Text("Model")
                Spacer()
                TextField("Model name", text: $editModelName)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.gray.opacity(0.3)))
                    .frame(width: 300)
            }

            Toggle("Web Search (Groq Compound)", isOn: $appState.webSearchEnabled)
                .toggleStyle(.switch)
                .tint(Color(red: 0.85, green: 0.65, blue: 0.2))

            // Vertex AI specific
            if appState.apiProvider == .vertexAI {
                Divider().background(Color.gray.opacity(0.3))
                settingLabel("Vertex AI Settings")

                HStack {
                    Text("Project ID")
                    Spacer()
                    TextField("GCP Project ID", text: $editVertexProject)
                        .textFieldStyle(.plain)
                        .padding(6)
                        .background(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.gray.opacity(0.3)))
                        .frame(width: 300)
                }

                HStack {
                    Text("Location")
                    Spacer()
                    TextField("e.g. us-central1", text: $editVertexLocation)
                        .textFieldStyle(.plain)
                        .padding(6)
                        .background(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.gray.opacity(0.3)))
                        .frame(width: 300)
                }

                Text("Requires: gcloud auth login")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }

            // Ollama specific
            if appState.apiProvider == .ollama {
                Divider().background(Color.gray.opacity(0.3))
                settingLabel("Ollama Settings")

                HStack {
                    Text("Endpoint")
                    Spacer()
                    TextField("Ollama endpoint URL", text: $editOllamaEndpoint)
                        .textFieldStyle(.plain)
                        .padding(6)
                        .background(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.gray.opacity(0.3)))
                        .frame(width: 300)
                }

                Text("OpenAI-compatible API (/v1/chat/completions)")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
        .foregroundColor(.white)
        .font(.system(size: 13, design: .monospaced))
    }

    private func settingLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.2))
            .textCase(.uppercase)
    }

    private func loadCurrentValues() {
        let provider = appState.apiProvider
        editApiKey = appState.apiKey(for: provider)
        editModelName = appState.modelName(for: provider)
        editVertexProject = appState.vertexProject
        editVertexLocation = appState.vertexLocation
        editOllamaEndpoint = appState.ollamaEndpoint
    }

    private func save() {
        let provider = appState.apiProvider
        appState.setApiKey(editApiKey, for: provider)
        appState.setModelName(editModelName, for: provider)
        appState.vertexProject = editVertexProject
        appState.vertexLocation = editVertexLocation
        appState.ollamaEndpoint = editOllamaEndpoint
        appState.isAutoMode = appState.autoModeEnabled
    }

    private func close() {
        withAnimation { appState.showConfigPanel = false }
    }
}
