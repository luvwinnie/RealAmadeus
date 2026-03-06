import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    var role: String  // "system", "user", "assistant"
    var content: String

    init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}
