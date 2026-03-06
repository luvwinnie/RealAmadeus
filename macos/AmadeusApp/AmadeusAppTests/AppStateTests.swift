import XCTest
@testable import AmadeusApp

final class AppStateTests: XCTestCase {

    var appState: AppState!

    override func setUp() {
        super.setUp()
        appState = AppState()
    }

    // MARK: - APIProvider

    func testAPIProviderDisplayNames() {
        XCTAssertEqual(APIProvider.openAI.displayName, "OpenAI")
        XCTAssertEqual(APIProvider.gemini.displayName, "Google Gemini")
        XCTAssertEqual(APIProvider.claude.displayName, "Anthropic Claude")
        XCTAssertEqual(APIProvider.groq.displayName, "Groq")
        XCTAssertEqual(APIProvider.vertexAI.displayName, "Vertex AI")
        XCTAssertEqual(APIProvider.ollama.displayName, "Ollama")
    }

    func testAPIProviderDefaultModels() {
        XCTAssertEqual(APIProvider.openAI.defaultModel, "gpt-4o")
        XCTAssertEqual(APIProvider.gemini.defaultModel, "gemini-2.0-flash")
        XCTAssertEqual(APIProvider.claude.defaultModel, "claude-sonnet-4-20250514")
        XCTAssertEqual(APIProvider.groq.defaultModel, "qwen3-32b")
        XCTAssertEqual(APIProvider.vertexAI.defaultModel, "gemini-2.0-flash")
        XCTAssertEqual(APIProvider.ollama.defaultModel, "qwen3:32b")
    }

    func testAPIProviderDefaultEndpoint() {
        XCTAssertEqual(APIProvider.ollama.defaultEndpoint, "https://llm.nishizaki-leow-lab-alps.org")
        XCTAssertEqual(APIProvider.openAI.defaultEndpoint, "")
    }

    func testAPIProviderAllCases() {
        XCTAssertEqual(APIProvider.allCases.count, 6)
    }

    func testAPIProviderFromRawValue() {
        XCTAssertEqual(APIProvider(rawValue: 0), .openAI)
        XCTAssertEqual(APIProvider(rawValue: 5), .ollama)
        XCTAssertNil(APIProvider(rawValue: 99))
    }

    // MARK: - EmotionTag

    func testEmotionTagAllCases() {
        XCTAssertEqual(EmotionTag.allCases.count, 11)
    }

    func testEmotionTagRawValues() {
        XCTAssertEqual(EmotionTag.normal.rawValue, "NORMAL")
        XCTAssertEqual(EmotionTag.smile.rawValue, "SMILE")
        XCTAssertEqual(EmotionTag.angry.rawValue, "ANGRY")
        XCTAssertEqual(EmotionTag.sad.rawValue, "SAD")
        XCTAssertEqual(EmotionTag.surprised.rawValue, "SURPRISED")
        XCTAssertEqual(EmotionTag.blush.rawValue, "BLUSH")
        XCTAssertEqual(EmotionTag.wink.rawValue, "WINK")
        XCTAssertEqual(EmotionTag.disgust.rawValue, "DISGUST")
        XCTAssertEqual(EmotionTag.smug.rawValue, "SMUG")
        XCTAssertEqual(EmotionTag.thinking.rawValue, "THINKING")
        XCTAssertEqual(EmotionTag.panic.rawValue, "PANIC")
    }

    func testEmotionTagFromRawValue() {
        XCTAssertEqual(EmotionTag(rawValue: "SMILE"), .smile)
        XCTAssertNil(EmotionTag(rawValue: "INVALID"))
    }

    // MARK: - ChatState

    func testInitialChatState() {
        XCTAssertEqual(appState.chatState, .inputReady)
    }

    // MARK: - AppScreen

    func testInitialScreen() {
        XCTAssertEqual(appState.currentScreen, .login)
    }

    // MARK: - Login

    func testLoginCredentials() {
        XCTAssertEqual(appState.expectedLoginId, "Salieri")
        XCTAssertEqual(appState.expectedPassword, "MakiseKurisu")
    }

    // MARK: - Backlog

    func testAddBacklog() {
        appState.addBacklog(role: "User", message: "Hello")
        XCTAssertEqual(appState.backlogEntries.count, 1)
        XCTAssertEqual(appState.backlogEntries[0].role, "User")
        XCTAssertEqual(appState.backlogEntries[0].message, "Hello")
    }

    func testAddBacklogStripsEmotionTag() {
        appState.addBacklog(role: "Kurisu", message: "[SMILE] Hi there")
        XCTAssertEqual(appState.backlogEntries.count, 1)
        XCTAssertEqual(appState.backlogEntries[0].message, "Hi there")
    }

    func testAddBacklogIgnoresEmpty() {
        appState.addBacklog(role: "User", message: "   ")
        XCTAssertEqual(appState.backlogEntries.count, 0)
    }

    func testClearBacklog() {
        appState.addBacklog(role: "User", message: "Hello")
        appState.addBacklog(role: "Kurisu", message: "Hi")
        appState.clearBacklog()
        XCTAssertEqual(appState.backlogEntries.count, 0)
    }

    // MARK: - Logout

    func testLogout() {
        appState.operatorName = "Test"
        appState.currentScreen = .main
        appState.chatState = .typing
        appState.dialogueText = "Some text"
        appState.currentEmotion = .smile
        appState.isMenuOpen = true
        appState.addBacklog(role: "User", message: "Hello")

        appState.logout()

        XCTAssertEqual(appState.operatorName, "")
        XCTAssertEqual(appState.currentScreen, .login)
        XCTAssertEqual(appState.chatState, .inputReady)
        XCTAssertEqual(appState.dialogueText, "")
        XCTAssertEqual(appState.currentEmotion, .normal)
        XCTAssertFalse(appState.isMenuOpen)
        XCTAssertEqual(appState.backlogEntries.count, 0)
    }

    // MARK: - Confirmation Dialog

    func testConfirmationDialog() {
        var yesCalled = false
        var noCalled = false

        appState.showConfirmationDialog("Test?",
            onYes: { yesCalled = true },
            onNo: { noCalled = true }
        )

        XCTAssertTrue(appState.showConfirmation)
        XCTAssertEqual(appState.confirmationMessage, "Test?")

        appState.confirmationYesAction?()
        XCTAssertTrue(yesCalled)

        appState.confirmationNoAction?()
        XCTAssertTrue(noCalled)
    }

    // MARK: - Per-Provider Settings

    func testApiKeyStorage() {
        appState.setApiKey("test-key-123", for: .openAI)
        XCTAssertEqual(appState.apiKey(for: .openAI), "test-key-123")

        // Clean up
        appState.setApiKey("", for: .openAI)
    }

    func testModelNameStorage() {
        appState.setModelName("gpt-4o-mini", for: .openAI)
        XCTAssertEqual(appState.modelName(for: .openAI), "gpt-4o-mini")

        // Clean up
        appState.setModelName("", for: .openAI)
    }

    func testModelNameFallsBackToDefault() {
        appState.setModelName("", for: .gemini)
        XCTAssertEqual(appState.modelName(for: .gemini), "gemini-2.0-flash")
    }

    // MARK: - Sub Panel State

    func testIsAnySubPanelOpenFalseByDefault() {
        XCTAssertFalse(appState.isAnySubPanelOpen)
    }

    func testIsAnySubPanelOpenWhenConfigOpen() {
        appState.showConfigPanel = true
        XCTAssertTrue(appState.isAnySubPanelOpen)
    }
}
