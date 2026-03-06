import SwiftUI
import Combine

enum AppScreen {
    case login
    case loading
    case main
}

enum ChatState {
    case inputReady
    case waitingAPI
    case typing
    case streamingTyping
    case waitForAdvance
}

enum EmotionTag: String, CaseIterable {
    case normal = "NORMAL"
    case smile = "SMILE"
    case angry = "ANGRY"
    case sad = "SAD"
    case surprised = "SURPRISED"
    case blush = "BLUSH"
    case wink = "WINK"
    case disgust = "DISGUST"
    case smug = "SMUG"
    case thinking = "THINKING"
    case panic = "PANIC"
}

enum APIProvider: Int, CaseIterable, Identifiable {
    case openAI = 0
    case gemini = 1
    case claude = 2
    case groq = 3
    case vertexAI = 4
    case ollama = 5

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .gemini: return "Google Gemini"
        case .claude: return "Anthropic Claude"
        case .groq: return "Groq"
        case .vertexAI: return "Vertex AI"
        case .ollama: return "Ollama"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4o"
        case .gemini: return "gemini-2.0-flash"
        case .claude: return "claude-sonnet-4-20250514"
        case .groq: return "qwen3-32b"
        case .vertexAI: return "gemini-2.0-flash"
        case .ollama: return "gemma3:4b"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .ollama: return "https://llm.nishizaki-leow-lab-alps.org"
        default: return ""
        }
    }
}

class AppState: ObservableObject {
    // Screen state
    @Published var currentScreen: AppScreen = .login
    @Published var chatState: ChatState = .inputReady

    // Login
    let expectedLoginId = "Salieri"
    let expectedPassword = "MakiseKurisu"
    @Published var operatorName: String = ""

    // Chat
    @Published var dialogueText: String = ""
    @Published var currentEmotion: EmotionTag = .normal
    @Published var isAutoMode: Bool = false
    @Published var showWaitingIndicator: Bool = false
    @Published var isSpeaking: Bool = false

    // Menu / Panels
    @Published var isMenuOpen: Bool = false
    @Published var showConfigPanel: Bool = false
    @Published var showStatusPanel: Bool = false
    @Published var showBackLogPanel: Bool = false
    @Published var showChangeLogPanel: Bool = false
    @Published var showHelpPanel: Bool = false
    @Published var showConfirmation: Bool = false
    @Published var confirmationMessage: String = ""
    var confirmationYesAction: (() -> Void)?
    var confirmationNoAction: (() -> Void)?

    // Config / Settings
    @AppStorage("Config_ApiProvider") var apiProviderIndex: Int = 5
    @AppStorage("Config_TextSpeed") var textSpeed: Double = 1.0
    @AppStorage("Config_AutoSpeed") var autoSpeed: Double = 3.0
    @AppStorage("Config_AutoMode") var autoModeEnabled: Bool = false
    @AppStorage("Config_SkipLoading") var skipLoading: Bool = false
    @AppStorage("Config_RightClickMenu") var rightClickMenu: Bool = true
    @AppStorage("Config_WebSearch") var webSearchEnabled: Bool = false
    @AppStorage("Config_VertexProject") var vertexProject: String = ""
    @AppStorage("Config_VertexLocation") var vertexLocation: String = "us-central1"
    @AppStorage("Config_OllamaEndpoint") var ollamaEndpoint: String = "https://llm.nishizaki-leow-lab-alps.org"

    var apiProvider: APIProvider {
        APIProvider(rawValue: apiProviderIndex) ?? .ollama
    }

    init() {
        // Ensure Ollama is the default provider (fixes persisted old defaults)
        if UserDefaults.standard.object(forKey: "Config_ApiProvider_Migrated_v3") == nil {
            UserDefaults.standard.set(APIProvider.ollama.rawValue, forKey: "Config_ApiProvider")
            UserDefaults.standard.set("gemma3:4b", forKey: "Config_ModelName_\(APIProvider.ollama.rawValue)")
            UserDefaults.standard.set(true, forKey: "Config_ApiProvider_Migrated_v3")
        }
    }

    // Per-provider API keys and model names
    func apiKey(for provider: APIProvider) -> String {
        UserDefaults.standard.string(forKey: "Config_ApiKey_\(provider.rawValue)") ?? ""
    }

    func setApiKey(_ key: String, for provider: APIProvider) {
        UserDefaults.standard.set(key, forKey: "Config_ApiKey_\(provider.rawValue)")
    }

    func modelName(for provider: APIProvider) -> String {
        let stored = UserDefaults.standard.string(forKey: "Config_ModelName_\(provider.rawValue)") ?? ""
        return stored.isEmpty ? provider.defaultModel : stored
    }

    func setModelName(_ name: String, for provider: APIProvider) {
        UserDefaults.standard.set(name, forKey: "Config_ModelName_\(provider.rawValue)")
    }

    // Backlog
    @Published var backlogEntries: [(role: String, message: String)] = []

    func addBacklog(role: String, message: String) {
        let clean = cleanEmotionTags(message)
        guard !clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        backlogEntries.append((role: role, message: clean))
    }

    func clearBacklog() {
        backlogEntries.removeAll()
    }

    private func cleanEmotionTags(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("[") {
            if let close = result.firstIndex(of: "]") {
                result = String(result[result.index(after: close)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return result
    }

    // Confirmation dialog
    func showConfirmationDialog(_ message: String, onYes: @escaping () -> Void, onNo: (() -> Void)? = nil) {
        confirmationMessage = message
        confirmationYesAction = onYes
        confirmationNoAction = onNo
        showConfirmation = true
    }

    // Logout
    func logout() {
        operatorName = ""
        clearBacklog()
        currentScreen = .login
        isMenuOpen = false
        chatState = .inputReady
        dialogueText = ""
        currentEmotion = .normal
    }
}
