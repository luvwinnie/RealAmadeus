import XCTest
@testable import AmadeusApp

final class MemoryManagerTests: XCTestCase {

    var memoryManager: MemoryManager!

    override func setUp() {
        super.setUp()
        memoryManager = MemoryManager()
        memoryManager.clearAllMemory()
    }

    override func tearDown() {
        memoryManager.clearAllMemory()
        super.tearDown()
    }

    // MARK: - User Name

    func testSetAndGetUserName() {
        memoryManager.setUserName("Okabe")
        XCTAssertEqual(memoryManager.getUserName(), "Okabe")
    }

    func testSetEmptyUserNameIgnored() {
        memoryManager.setUserName("Okabe")
        memoryManager.setUserName("")
        XCTAssertEqual(memoryManager.getUserName(), "Okabe")
    }

    // MARK: - User Facts

    func testAddUserFact() {
        memoryManager.addUserFact("Likes Dr Pepper")
        let context = memoryManager.getMemoryContext()
        XCTAssertTrue(context.contains("Likes Dr Pepper"))
    }

    func testAddDuplicateFactIgnored() {
        memoryManager.addUserFact("Likes Dr Pepper")
        memoryManager.addUserFact("Likes Dr Pepper")
        let context = memoryManager.getMemoryContext()
        let count = context.components(separatedBy: "Likes Dr Pepper").count - 1
        XCTAssertEqual(count, 1)
    }

    func testAddEmptyFactIgnored() {
        memoryManager.addUserFact("")
        let context = memoryManager.getMemoryContext()
        XCTAssertFalse(context.contains("ユーザーについて"))
    }

    func testMaxLongTermFacts() {
        for i in 0..<60 {
            memoryManager.addUserFact("Fact \(i)")
        }
        // Should cap at maxLongTermFacts (50)
        let context = memoryManager.getMemoryContext()
        XCTAssertFalse(context.contains("Fact 0"))
        XCTAssertTrue(context.contains("Fact 59"))
    }

    // MARK: - Emotions

    func testRecordEmotion() {
        let repeating = memoryManager.recordEmotion("SMILE")
        XCTAssertFalse(repeating) // Only 1 occurrence
    }

    func testRecordEmotionDetectsConsecutiveRepetition() {
        memoryManager.recordEmotion("SMILE")
        memoryManager.recordEmotion("SMILE")
        let repeating = memoryManager.recordEmotion("SMILE")
        XCTAssertTrue(repeating) // 3 consecutive
    }

    func testRecordEmotionNonConsecutive() {
        memoryManager.recordEmotion("SMILE")
        memoryManager.recordEmotion("ANGRY")
        let repeating = memoryManager.recordEmotion("SMILE")
        XCTAssertFalse(repeating)
    }

    // MARK: - Interactions

    func testRecordInteraction() {
        memoryManager.recordInteraction()
        let context = memoryManager.getMemoryContext()
        XCTAssertTrue(context.contains("累計やりとり回数"))
        XCTAssertTrue(context.contains("1回"))
    }

    // MARK: - Conversation Summaries

    func testAddConversationSummary() {
        memoryManager.addConversationSummary("Discussed physics")
        let context = memoryManager.getMemoryContext()
        XCTAssertTrue(context.contains("Discussed physics"))
    }

    func testAddEmptySummaryIgnored() {
        memoryManager.addConversationSummary("")
        let context = memoryManager.getMemoryContext()
        XCTAssertFalse(context.contains("過去の会話"))
    }

    func testMaxConversationSummaries() {
        for i in 0..<15 {
            memoryManager.addConversationSummary("Summary \(i)")
        }
        let context = memoryManager.getMemoryContext()
        // Only last 3 summaries shown in context
        XCTAssertTrue(context.contains("Summary 14"))
        XCTAssertTrue(context.contains("Summary 13"))
        XCTAssertTrue(context.contains("Summary 12"))
        XCTAssertFalse(context.contains("Summary 0"))
    }

    // MARK: - Conversation History Trimming

    func testTrimConversationHistoryBelowThreshold() {
        var history: [ChatMessage] = [
            ChatMessage(role: "system", content: "prompt"),
            ChatMessage(role: "user", content: "hello"),
            ChatMessage(role: "assistant", content: "hi")
        ]
        let summary = memoryManager.trimConversationHistory(&history)
        XCTAssertNil(summary)
        XCTAssertEqual(history.count, 3)
    }

    func testTrimConversationHistoryAboveThreshold() {
        var history: [ChatMessage] = [ChatMessage(role: "system", content: "prompt")]
        for i in 0..<35 {
            history.append(ChatMessage(role: "user", content: "Message \(i)"))
            history.append(ChatMessage(role: "assistant", content: "Reply \(i)"))
        }

        memoryManager.maxConversationTurns = 30
        let summary = memoryManager.trimConversationHistory(&history)

        XCTAssertNotNil(summary)
        // History should be trimmed
        let nonSystemCount = history.filter { $0.role != "system" }.count
        XCTAssertLessThanOrEqual(nonSystemCount, 30)
    }

    // MARK: - Time Context

    func testGetTimeContext() {
        let timeContext = memoryManager.getTimeContext()
        let validContexts = ["朝", "午前中", "昼", "午後", "夕方", "夜", "深夜"]
        XCTAssertTrue(validContexts.contains(timeContext))
    }

    // MARK: - Dynamic Context

    func testGetDynamicContext() {
        let context = memoryManager.getDynamicContext(turnCount: 5)
        XCTAssertTrue(context.contains("会話ターン数: 5"))
    }

    // MARK: - Memory Context

    func testGetMemoryContextEmpty() {
        let context = memoryManager.getMemoryContext()
        XCTAssertTrue(context.isEmpty)
    }

    func testGetMemoryContextWithData() {
        memoryManager.setUserName("Okabe")
        memoryManager.addUserFact("Mad scientist")
        memoryManager.recordInteraction()

        let context = memoryManager.getMemoryContext()
        XCTAssertTrue(context.contains("Okabe"))
        XCTAssertTrue(context.contains("Mad scientist"))
        XCTAssertTrue(context.contains("累計やりとり回数"))
    }

    // MARK: - Clear All Memory

    func testClearAllMemory() {
        memoryManager.setUserName("Test")
        memoryManager.addUserFact("Fact")
        memoryManager.recordInteraction()

        memoryManager.clearAllMemory()

        XCTAssertEqual(memoryManager.getUserName(), "")
        XCTAssertTrue(memoryManager.getMemoryContext().isEmpty)
    }

    // MARK: - Topics

    func testAddTopic() {
        memoryManager.addTopic("Physics")
        memoryManager.addTopic("Time Travel")
        // Topics don't appear in getMemoryContext directly, but verify no crash
        memoryManager.addTopic("Physics") // duplicate ignored
    }

    func testAddEmptyTopicIgnored() {
        memoryManager.addTopic("")
        // No crash expected
    }
}
