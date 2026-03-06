import XCTest
@testable import AmadeusApp

final class ChatMessageTests: XCTestCase {

    func testChatMessageInit() {
        let msg = ChatMessage(role: "user", content: "Hello")
        XCTAssertEqual(msg.role, "user")
        XCTAssertEqual(msg.content, "Hello")
    }

    func testChatMessageUniqueId() {
        let msg1 = ChatMessage(role: "user", content: "A")
        let msg2 = ChatMessage(role: "user", content: "A")
        XCTAssertNotEqual(msg1.id, msg2.id)
    }

    func testChatMessageRoles() {
        let system = ChatMessage(role: "system", content: "prompt")
        let user = ChatMessage(role: "user", content: "input")
        let assistant = ChatMessage(role: "assistant", content: "output")

        XCTAssertEqual(system.role, "system")
        XCTAssertEqual(user.role, "user")
        XCTAssertEqual(assistant.role, "assistant")
    }

    func testChatMessageMutableContent() {
        var msg = ChatMessage(role: "system", content: "original")
        msg.content = "updated"
        XCTAssertEqual(msg.content, "updated")
    }
}
