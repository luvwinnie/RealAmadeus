import XCTest
@testable import AmadeusApp

final class IntegrationTests: XCTestCase {

    // MARK: - Emotion Parsing Integration

    func testEmotionTagParsingFromResponse() {
        let response = "[SMILE] ふふん、なかなか面白い質問ね。"
        let pattern = "\\[(NORMAL|SMILE|ANGRY|SAD|SURPRISED|BLUSH|WINK|DISGUST|SMUG|THINKING|PANIC)\\]"
        let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(response.startIndex..., in: response)

        let matches = regex.matches(in: response, range: range)
        XCTAssertEqual(matches.count, 1)

        if let match = matches.first, let tagRange = Range(match.range(at: 1), in: response) {
            let tag = String(response[tagRange]).uppercased()
            XCTAssertEqual(tag, "SMILE")
            let emotion = EmotionTag(rawValue: tag)
            XCTAssertEqual(emotion, .smile)
        }

        // Strip tag
        let cleaned = regex.stringByReplacingMatches(in: response, range: range, withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(cleaned, "ふふん、なかなか面白い質問ね。")
    }

    func testEmotionTagParsingMultipleTags() {
        // Only the first tag should be used
        let response = "[ANGRY] [BLUSH] 何言ってるの！"
        let pattern = "\\[(NORMAL|SMILE|ANGRY|SAD|SURPRISED|BLUSH|WINK|DISGUST|SMUG|THINKING|PANIC)\\]"
        let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(response.startIndex..., in: response)

        let matches = regex.matches(in: response, range: range)
        XCTAssertGreaterThanOrEqual(matches.count, 1)

        if let match = matches.first, let tagRange = Range(match.range(at: 1), in: response) {
            let tag = String(response[tagRange]).uppercased()
            XCTAssertEqual(tag, "ANGRY")
        }
    }

    func testEmotionTagMissing() {
        let response = "タイムマシンの理論について話しましょう。"
        let pattern = "\\[(NORMAL|SMILE|ANGRY|SAD|SURPRISED|BLUSH|WINK|DISGUST|SMUG|THINKING|PANIC)\\]"
        let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(response.startIndex..., in: response)

        let matches = regex.matches(in: response, range: range)
        XCTAssertEqual(matches.count, 0)
    }

    // MARK: - Thinking Tag Stripping

    func testStripThinkingTags() {
        let input = "<think>Let me think about this...</think>[SMILE] Here is my answer."
        var result = input
        while let start = result.range(of: "<think>") {
            if let end = result.range(of: "</think>") {
                result = String(result[..<start.lowerBound]) + String(result[end.upperBound...])
            } else {
                result = String(result[..<start.lowerBound])
                break
            }
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(result, "[SMILE] Here is my answer.")
    }

    func testStripThinkingTagsNested() {
        let input = "<think>thinking</think>Hello<think>more thinking</think> world"
        var result = input
        while let start = result.range(of: "<think>") {
            if let end = result.range(of: "</think>") {
                result = String(result[..<start.lowerBound]) + String(result[end.upperBound...])
            } else {
                result = String(result[..<start.lowerBound])
                break
            }
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(result, "Hello world")
    }

    func testStripThinkingTagsUnclosed() {
        let input = "<think>endless thinking"
        var result = input
        while let start = result.range(of: "<think>") {
            if let end = result.range(of: "</think>") {
                result = String(result[..<start.lowerBound]) + String(result[end.upperBound...])
            } else {
                result = String(result[..<start.lowerBound])
                break
            }
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(result, "")
    }

    // MARK: - Memory + Chat Integration

    func testMemoryPersistsThroughConversation() {
        let memory = MemoryManager()
        memory.clearAllMemory()

        // Simulate a conversation
        memory.setUserName("Okabe")
        memory.addUserFact("Self-proclaimed mad scientist")
        memory.recordInteraction()
        memory.recordEmotion("SMILE")
        memory.recordEmotion("ANGRY")
        memory.addConversationSummary("Discussed time travel")

        let context = memory.getMemoryContext()
        XCTAssertTrue(context.contains("Okabe"))
        XCTAssertTrue(context.contains("Self-proclaimed mad scientist"))
        XCTAssertTrue(context.contains("Discussed time travel"))
        XCTAssertTrue(context.contains("1回"))

        memory.clearAllMemory()
    }

    // MARK: - Conversation History Trimming Integration

    func testConversationTrimPreservesSystemPrompt() {
        let memory = MemoryManager()
        memory.maxConversationTurns = 10

        var history: [ChatMessage] = [
            ChatMessage(role: "system", content: "You are Kurisu")
        ]
        for i in 0..<20 {
            history.append(ChatMessage(role: "user", content: "Msg \(i)"))
            history.append(ChatMessage(role: "assistant", content: "Reply \(i)"))
        }

        let _ = memory.trimConversationHistory(&history)

        // System prompt should remain at index 0
        XCTAssertEqual(history[0].role, "system")
        XCTAssertEqual(history[0].content, "You are Kurisu")

        memory.clearAllMemory()
    }

    // MARK: - AppState + Chat Flow Integration

    func testChatFlowStateTransitions() {
        let appState = AppState()

        // Initial state
        XCTAssertEqual(appState.chatState, .inputReady)

        // Simulate waiting for API
        appState.chatState = .waitingAPI
        XCTAssertEqual(appState.chatState, .waitingAPI)

        // Simulate typing
        appState.chatState = .typing
        XCTAssertEqual(appState.chatState, .typing)

        // Simulate wait for advance
        appState.chatState = .waitForAdvance
        appState.showWaitingIndicator = true
        XCTAssertTrue(appState.showWaitingIndicator)

        // Simulate user pressing Enter to advance
        appState.chatState = .inputReady
        appState.showWaitingIndicator = false
        XCTAssertEqual(appState.chatState, .inputReady)
        XCTAssertFalse(appState.showWaitingIndicator)
    }

    func testStreamingStateTransitions() {
        let appState = AppState()

        appState.chatState = .waitingAPI
        appState.chatState = .streamingTyping
        XCTAssertEqual(appState.chatState, .streamingTyping)

        appState.chatState = .waitForAdvance
        XCTAssertEqual(appState.chatState, .waitForAdvance)
    }

    // MARK: - Backlog Integration

    func testBacklogAccumulatesAcrossConversation() {
        let appState = AppState()

        appState.addBacklog(role: "User", message: "First message")
        appState.addBacklog(role: "Kurisu", message: "[SMILE] First reply")
        appState.addBacklog(role: "User", message: "Second message")
        appState.addBacklog(role: "Kurisu", message: "[ANGRY] Second reply")

        XCTAssertEqual(appState.backlogEntries.count, 4)
        XCTAssertEqual(appState.backlogEntries[0].role, "User")
        XCTAssertEqual(appState.backlogEntries[1].role, "Kurisu")
        XCTAssertEqual(appState.backlogEntries[1].message, "First reply") // tag stripped
        XCTAssertEqual(appState.backlogEntries[3].message, "Second reply") // tag stripped
    }

    // MARK: - OpenAI Response Parsing

    func testParseOpenAIFormatResponse() {
        let json = """
        {
            "choices": [
                {
                    "message": {
                        "content": "[SMILE] Hello!"
                    }
                }
            ]
        }
        """
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            XCTFail("Failed to parse")
            return
        }
        XCTAssertEqual(content, "[SMILE] Hello!")
    }

    // MARK: - Gemini Response Parsing

    func testParseGeminiFormatResponse() {
        let json = """
        {
            "candidates": [
                {
                    "content": {
                        "parts": [
                            {"text": "[THINKING] Interesting question."}
                        ]
                    }
                }
            ]
        }
        """
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = obj["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            XCTFail("Failed to parse")
            return
        }
        XCTAssertEqual(text, "[THINKING] Interesting question.")
    }

    // MARK: - Claude Response Parsing

    func testParseClaudeFormatResponse() {
        let json = """
        {
            "content": [
                {
                    "type": "text",
                    "text": "[BLUSH] It's not like I care or anything!"
                }
            ]
        }
        """
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            XCTFail("Failed to parse")
            return
        }
        XCTAssertEqual(text, "[BLUSH] It's not like I care or anything!")
    }

    // MARK: - SSE Chunk Parsing

    func testParseSSEDataLine() {
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}"
        XCTAssertTrue(line.hasPrefix("data: "))

        let payload = String(line.dropFirst(6))
        XCTAssertNotEqual(payload, "[DONE]")

        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String else {
            XCTFail("Failed to parse SSE chunk")
            return
        }
        XCTAssertEqual(content, "Hello")
    }

    func testParseSSEDoneLine() {
        let line = "data: [DONE]"
        let payload = String(line.dropFirst(6))
        XCTAssertEqual(payload, "[DONE]")
    }

    // MARK: - Ollama Endpoint URL Construction

    func testOllamaEndpointURLConstruction() {
        let endpoint = "https://llm.nishizaki-leow-lab-alps.org"
        let baseURL = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
        let url = URL(string: "\(baseURL)/v1/chat/completions")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "https://llm.nishizaki-leow-lab-alps.org/v1/chat/completions")
    }

    func testOllamaEndpointURLWithTrailingSlash() {
        let endpoint = "https://llm.nishizaki-leow-lab-alps.org/"
        let baseURL = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
        let url = URL(string: "\(baseURL)/v1/chat/completions")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "https://llm.nishizaki-leow-lab-alps.org/v1/chat/completions")
    }
}
