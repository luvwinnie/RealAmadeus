import XCTest
@testable import AmadeusApp

final class AIServiceTests: XCTestCase {

    var aiService: AIService!

    override func setUp() {
        super.setUp()
        aiService = AIService()
    }

    // MARK: - Missing API Key Handling

    func testSendChatWithoutAPIKeyReturnsError() {
        let expectation = expectation(description: "Error callback")
        let messages = [ChatMessage(role: "user", content: "Hello")]

        aiService.sendChat(
            messages: messages,
            provider: .openAI,
            apiKey: "",
            model: "gpt-4o",
            onSuccess: { _ in XCTFail("Should not succeed") },
            onError: { error in
                XCTAssertTrue(error.contains("API Key"))
                expectation.fulfill()
            }
        )

        waitForExpectations(timeout: 5)
    }

    func testSendChatStreamingWithoutAPIKeyReturnsError() {
        let expectation = expectation(description: "Error callback")
        let messages = [ChatMessage(role: "user", content: "Hello")]

        aiService.sendChatStreaming(
            messages: messages,
            provider: .claude,
            apiKey: "",
            model: "claude-sonnet-4-20250514",
            onToken: { _ in },
            onComplete: { _ in XCTFail("Should not succeed") },
            onError: { error in
                XCTAssertTrue(error.contains("API Key"))
                expectation.fulfill()
            }
        )

        waitForExpectations(timeout: 5)
    }

    // MARK: - Ollama & Vertex don't require API key

    func testOllamaDoesNotRequireAPIKey() {
        // Ollama should not fail due to empty API key
        // (it may fail due to network, but not API key validation)
        let expectation = expectation(description: "No API key error")
        let messages = [ChatMessage(role: "user", content: "Hello")]

        aiService.sendChat(
            messages: messages,
            provider: .ollama,
            apiKey: "",
            model: "qwen3:32b",
            ollamaEndpoint: "http://localhost:99999", // intentionally invalid to trigger network error, not API key error
            onSuccess: { _ in
                // Could succeed if somehow a server is running
                expectation.fulfill()
            },
            onError: { error in
                XCTAssertFalse(error.contains("API Key"), "Ollama should not require API key")
                expectation.fulfill()
            }
        )

        waitForExpectations(timeout: 10)
    }

    func testVertexAIDoesNotRequireAPIKey() {
        let expectation = expectation(description: "No API key error")
        let messages = [ChatMessage(role: "user", content: "Hello")]

        aiService.sendChat(
            messages: messages,
            provider: .vertexAI,
            apiKey: "",
            model: "gemini-2.0-flash",
            vertexProject: "test-project",
            onSuccess: { _ in expectation.fulfill() },
            onError: { error in
                // Should fail on token, not on API key
                XCTAssertFalse(error.contains("API Key"))
                expectation.fulfill()
            }
        )

        waitForExpectations(timeout: 15)
    }

    // MARK: - Provider Routing

    func testSendChatRoutesToCorrectProvider() {
        // Test that each provider triggers the correct error message prefix
        let providers: [(APIProvider, String)] = [
            (.openAI, "API Key"),
            (.gemini, "API Key"),
            (.claude, "API Key"),
            (.groq, "API Key"),
        ]

        for (provider, expectedError) in providers {
            let expectation = expectation(description: "Error for \(provider.displayName)")
            let messages = [ChatMessage(role: "user", content: "test")]

            aiService.sendChat(
                messages: messages,
                provider: provider,
                apiKey: "",
                model: provider.defaultModel,
                onSuccess: { _ in XCTFail("Should not succeed for \(provider.displayName)") },
                onError: { error in
                    XCTAssertTrue(error.contains(expectedError), "\(provider.displayName) error should contain '\(expectedError)', got: \(error)")
                    expectation.fulfill()
                }
            )
        }

        waitForExpectations(timeout: 10)
    }

    // MARK: - Streaming Fallback

    func testNonStreamingProviderFallsBackInStreaming() {
        // OpenAI uses non-streaming fallback in sendChatStreaming
        let expectation = expectation(description: "Fallback error")
        let messages = [ChatMessage(role: "user", content: "test")]

        aiService.sendChatStreaming(
            messages: messages,
            provider: .openAI,
            apiKey: "",
            model: "gpt-4o",
            onToken: { _ in },
            onComplete: { _ in XCTFail("Should not complete") },
            onError: { error in
                XCTAssertTrue(error.contains("API Key"))
                expectation.fulfill()
            }
        )

        waitForExpectations(timeout: 5)
    }
}
