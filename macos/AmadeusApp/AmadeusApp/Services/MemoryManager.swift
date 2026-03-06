import Foundation

/// Manages short-term and long-term memory for the Amadeus AI system.
/// Port of Unity MemoryManager.cs to Swift.
class MemoryManager: ObservableObject {
    // Configuration
    var maxConversationTurns = 30
    var summarizeThreshold = 20
    var maxLongTermFacts = 50

    // Persistent data
    struct KurisuMemory: Codable {
        var userName: String = ""
        var userFacts: [String] = []
        var conversationSummaries: [String] = []
        var lastSessionDate: String = ""
        var totalInteractions: Int = 0
        var recentEmotions: [String] = []
        var topicsDiscussed: [String] = []
    }

    @Published private(set) var memory = KurisuMemory()
    private var emotionHistory: [String] = []
    private let emotionHistorySize = 10
    private let savePath: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AmadeusApp")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        savePath = appDir.appendingPathComponent("kurisu_memory.json")
        loadMemory()
    }

    // MARK: - Public API

    func getMemoryContext() -> String {
        var lines: [String] = []

        if !memory.userName.isEmpty {
            lines.append("【ユーザー情報】ユーザーの名前は「\(memory.userName)」。")
        }

        if !memory.userFacts.isEmpty {
            lines.append("【ユーザーについて知っていること】")
            for fact in memory.userFacts {
                lines.append("- \(fact)")
            }
        }

        if !memory.conversationSummaries.isEmpty {
            lines.append("【過去の会話の記憶】")
            let start = max(0, memory.conversationSummaries.count - 3)
            for i in start..<memory.conversationSummaries.count {
                lines.append("- \(memory.conversationSummaries[i])")
            }
        }

        if !memory.lastSessionDate.isEmpty {
            lines.append("【前回のセッション】\(memory.lastSessionDate)")
        }

        if memory.totalInteractions > 0 {
            lines.append("【累計やりとり回数】\(memory.totalInteractions)回")
        }

        if memory.recentEmotions.count >= 3 {
            lines.append("【最近の感情傾向】\(memory.recentEmotions.joined(separator: "→"))（同じ感情が続きすぎないように意識して）")
        }

        return lines.isEmpty ? "" : lines.joined(separator: "\n")
    }

    @discardableResult
    func recordEmotion(_ emotion: String) -> Bool {
        emotionHistory.append(emotion)
        if emotionHistory.count > emotionHistorySize {
            emotionHistory.removeFirst()
        }

        memory.recentEmotions.append(emotion)
        if memory.recentEmotions.count > emotionHistorySize {
            memory.recentEmotions.removeFirst()
        }

        var consecutive = 0
        var last = ""
        for e in emotionHistory {
            if e == last { consecutive += 1 }
            else { consecutive = 1; last = e }
        }
        return consecutive >= 3
    }

    func recordInteraction() {
        memory.totalInteractions += 1
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        memory.lastSessionDate = formatter.string(from: Date())
        saveMemory()
    }

    func addUserFact(_ fact: String) {
        guard !fact.isEmpty, !memory.userFacts.contains(fact) else { return }
        memory.userFacts.append(fact)
        if memory.userFacts.count > maxLongTermFacts {
            memory.userFacts.removeFirst()
        }
        saveMemory()
    }

    func setUserName(_ name: String) {
        guard !name.isEmpty else { return }
        memory.userName = name
        saveMemory()
    }

    func getUserName() -> String { memory.userName }

    func addConversationSummary(_ summary: String) {
        guard !summary.isEmpty else { return }
        memory.conversationSummaries.append(summary)
        if memory.conversationSummaries.count > 10 {
            memory.conversationSummaries.removeFirst()
        }
        saveMemory()
    }

    func addTopic(_ topic: String) {
        guard !topic.isEmpty, !memory.topicsDiscussed.contains(topic) else { return }
        memory.topicsDiscussed.append(topic)
        if memory.topicsDiscussed.count > 30 {
            memory.topicsDiscussed.removeFirst()
        }
    }

    func trimConversationHistory(_ history: inout [ChatMessage]) -> String? {
        let nonSystemCount = history.filter { $0.role != "system" }.count
        guard nonSystemCount > maxConversationTurns else { return nil }

        let toRemove = nonSystemCount - maxConversationTurns + 4
        var toSummarize: [String] = []
        var removedCount = 0
        var idx = 1 // Skip system prompt at index 0

        while idx < history.count && removedCount < toRemove {
            toSummarize.append("\(history[idx].role): \(history[idx].content)")
            history.remove(at: idx)
            removedCount += 1
        }

        if !toSummarize.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM/dd HH:mm"
            var summary = "[\(formatter.string(from: Date()))の会話] "
            summary += toSummarize.map { s in
                s.count > 50 ? String(s.prefix(50)) + "..." : s
            }.joined(separator: " / ")
            if summary.count > 300 { summary = String(summary.prefix(300)) + "..." }
            addConversationSummary(summary)
            return summary
        }
        return nil
    }

    func getTimeContext() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<10: return "朝"
        case 10..<12: return "午前中"
        case 12..<14: return "昼"
        case 14..<17: return "午後"
        case 17..<20: return "夕方"
        case 20..<24: return "夜"
        default: return "深夜"
        }
    }

    func getDynamicContext(turnCount: Int) -> String {
        var lines: [String] = []
        lines.append("【現在の状況】時間帯: \(getTimeContext()) / 会話ターン数: \(turnCount)")

        let moodHints = [
            "（今は少しリラックスしている）",
            "（知的好奇心が高まっている）",
            "（少し眠そう）",
            "（何かを考え込んでいる）",
            "（いつも通りの調子）"
        ]
        lines.append(moodHints[Int.random(in: 0..<moodHints.count)])
        return lines.joined(separator: "\n")
    }

    func clearAllMemory() {
        memory = KurisuMemory()
        emotionHistory.removeAll()
        saveMemory()
    }

    // MARK: - Persistence

    private func saveMemory() {
        do {
            let data = try JSONEncoder().encode(memory)
            try data.write(to: savePath)
        } catch {
            print("[MemoryManager] Failed to save: \(error)")
        }
    }

    private func loadMemory() {
        do {
            if FileManager.default.fileExists(atPath: savePath.path) {
                let data = try Data(contentsOf: savePath)
                memory = try JSONDecoder().decode(KurisuMemory.self, from: data)
                emotionHistory = memory.recentEmotions
                print("[MemoryManager] Loaded. \(memory.totalInteractions) total interactions.")
            }
        } catch {
            print("[MemoryManager] Failed to load: \(error)")
            memory = KurisuMemory()
        }
    }
}
