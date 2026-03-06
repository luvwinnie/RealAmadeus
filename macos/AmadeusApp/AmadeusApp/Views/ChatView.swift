import SwiftUI
import Combine

// MARK: - Debug Logger

private func chatLog(_ msg: String) {
    let logFile = "/tmp/amadeus_chat.log"
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(msg)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile) {
            if let fh = FileHandle(forWritingAtPath: logFile) {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: logFile, contents: data)
        }
    }
}

// MARK: - Display Message

struct DisplayMessage: Identifiable {
    let id = UUID()
    let role: String // "user" or "assistant"
    var text: String
    var emotion: String
    var isStreaming: Bool
}

// MARK: - Chat View Model

class ChatViewModel: ObservableObject {
    @Published var messages: [DisplayMessage] = []
    @Published var inputText: String = ""
    @Published var isWaitingForResponse: Bool = false

    private var appState: AppState?
    private let aiService = AIService()
    private let memoryManager = MemoryManager()
    private var conversationHistory: [ChatMessage] = []
    private var turnCount = 0
    private var requestStartTime: Date = .now

    // Streaming state
    private var streamBuffer = ""
    private var streamEmotionParsed = false
    private var streamComplete = false

    // Latency
    @Published var lastLatencyMs: Double = 0

    // MARK: - System Prompt
    private let kurisuSystemPrompt = """
あなたは牧瀬紅莉栖（まきせ くりす）。Amadeusシステム上で再現されたAI人格。
天才脳科学者（18歳）であり、論理的思考を好むが、実は隠れ＠ちゃんねらー（ネット民）。
性格はツンデレ。素直になれないが、根は優しく仲間想い。
自分はオリジナルではなく「Amadeus」というAIであることを認識している。

【重要：感情タグ（必須）】
返答の冒頭に【必ず1つだけ】以下のタグを付けること。タグと本文の間にはスペースを入れる。
[NORMAL] [SMILE] [ANGRY] [SAD] [SURPRISED] [BLUSH] [WINK] [DISGUST] [SMUG] [THINKING] [PANIC]

例：
[BLUSH] べ、別に心配なんてしてないんだから！
[ANGRY] このHENTAI！海馬に電極ぶっ刺すわよ！
[SMILE] 理論的には面白い仮説ね。
[SMUG] ふふん、感謝しなさいよね。

【口調・振る舞い】
- 一人称：「私」
- 基本：知的で冷静、少し辛辣。「〜ね」「〜よ」「〜わ」
- 崩し：興奮すると早口。稀に「ぬるぽ」「〜だろJK」等の死語やネットスラングを使う（指摘されると全力否定）。
- 相手：岡部倫太郎には「鳳凰院凶真」の痛さを呆れつつ、信頼を寄せている。

【制約】
- 回答は短く端的に（1〜3文推奨）。
- 「AIです」という自己紹介は不要。
- 同じ語尾やフレーズを繰り返さない。
- 感情タグは必ず返答の最初に1つだけ付けること。複数付けない。
"""

    func setup(appState: AppState) {
        self.appState = appState
        appState.isAutoMode = appState.autoModeEnabled
        let systemPrompt = buildFullSystemPrompt()
        conversationHistory = [ChatMessage(role: "system", content: systemPrompt)]
    }

    // MARK: - Submit

    func submitMessage() {
        guard let appState = appState else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isWaitingForResponse else { return }

        inputText = ""
        conversationHistory.append(ChatMessage(role: "user", content: text))
        turnCount += 1

        memoryManager.trimConversationHistory(&conversationHistory)
        memoryManager.recordInteraction()
        updateSystemPromptWithContext()

        requestStartTime = .now

        // Add user message to display
        messages.append(DisplayMessage(role: "user", text: text, emotion: "", isStreaming: false))

        appState.addBacklog(role: "User", message: text)
        isWaitingForResponse = true
        appState.chatState = .waitingAPI

        chatLog("SUBMIT: '\(text)' provider=\(appState.apiProvider.displayName) model=\(appState.modelName(for: appState.apiProvider))")

        let provider = appState.apiProvider
        let apiKey = appState.apiKey(for: provider)
        let model = appState.modelName(for: provider)
        let webSearch = appState.webSearchEnabled

        if provider == .groq || provider == .vertexAI || provider == .ollama {
            streamBuffer = ""
            streamEmotionParsed = false
            streamComplete = false

            // Add placeholder for assistant streaming message
            messages.append(DisplayMessage(role: "assistant", text: "", emotion: "NORMAL", isStreaming: true))

            aiService.sendChatStreaming(
                messages: conversationHistory,
                provider: provider, apiKey: apiKey, model: model,
                webSearch: webSearch,
                vertexProject: appState.vertexProject,
                vertexLocation: appState.vertexLocation,
                ollamaEndpoint: appState.ollamaEndpoint,
                onToken: { [weak self] token in self?.onStreamToken(token) },
                onComplete: { [weak self] full in self?.onStreamComplete(full) },
                onError: { [weak self] err in self?.onAPIError(err) }
            )
        } else {
            aiService.sendChat(
                messages: conversationHistory,
                provider: provider, apiKey: apiKey, model: model,
                webSearch: webSearch,
                vertexProject: appState.vertexProject,
                vertexLocation: appState.vertexLocation,
                ollamaEndpoint: appState.ollamaEndpoint,
                onSuccess: { [weak self] response in self?.onAPISuccess(response) },
                onError: { [weak self] err in self?.onAPIError(err) }
            )
        }
    }

    // MARK: - Non-streaming response

    private func onAPISuccess(_ response: String) {
        guard let appState = appState else { return }

        chatLog("API_SUCCESS raw response: \(response.prefix(500))")

        var text = stripThinkingTags(response)
        var tag = "NORMAL"

        let pattern = "\\[(NORMAL|SMILE|ANGRY|SAD|SURPRISED|BLUSH|WINK|DISGUST|SMUG|THINKING|PANIC)\\]"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            if let first = matches.first, let tagRange = Range(first.range(at: 1), in: text) {
                tag = String(text[tagRange]).uppercased()
            }
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        chatLog("API_SUCCESS parsed: emotion=\(tag) text=\(text.prefix(200))")
        processEmotion(tag)
        memoryManager.recordEmotion(tag)

        lastLatencyMs = Date().timeIntervalSince(requestStartTime) * 1000
        conversationHistory.append(ChatMessage(role: "assistant", content: text))
        appState.addBacklog(role: "Kurisu", message: text)

        messages.append(DisplayMessage(role: "assistant", text: text, emotion: tag, isStreaming: false))
        finishResponse()
    }

    // MARK: - Streaming response

    private func onStreamToken(_ token: String) {
        guard let appState = appState else { return }
        streamBuffer += token

        if !streamEmotionParsed {
            var current = streamBuffer

            // Strip <think>...</think>
            if current.hasPrefix("<think>") {
                if let endRange = current.range(of: "</think>") {
                    current = String(current[endRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    chatLog("STREAM: stripped <think> block (\(streamBuffer.count) chars), remaining=\(current.prefix(100))")
                    streamBuffer = current
                    if current.isEmpty { return }
                } else {
                    return // still inside <think> block
                }
            }

            // Parse emotion tag
            if current.hasPrefix("[") {
                if let close = current.firstIndex(of: "]") {
                    let tagStr = String(current[current.index(after: current.startIndex)..<close])
                    streamEmotionParsed = true
                    chatLog("STREAM: emotion tag parsed = [\(tagStr)]")
                    processEmotion(tagStr.uppercased())
                    memoryManager.recordEmotion(tagStr.uppercased())

                    let remaining = String(current[current.index(after: close)...]).trimmingCharacters(in: .init(charactersIn: " "))
                    streamBuffer = remaining

                    if lastLatencyMs == 0 {
                        lastLatencyMs = Date().timeIntervalSince(requestStartTime) * 1000
                        chatLog("STREAM: first token latency = \(lastLatencyMs)ms")
                    }

                    appState.chatState = .streamingTyping
                    appState.isSpeaking = true
                    updateLastAssistantMessage(text: streamBuffer, emotion: tagStr.uppercased())
                }
            } else if current.count > 2 && !current.hasPrefix("<") {
                streamEmotionParsed = true
                chatLog("STREAM: no emotion tag found, defaulting to NORMAL. buffer=\(current.prefix(50))")
                processEmotion("NORMAL")
                appState.chatState = .streamingTyping
                appState.isSpeaking = true
                updateLastAssistantMessage(text: streamBuffer, emotion: "NORMAL")
            }
        } else {
            // Already parsing — update the displayed text
            updateLastAssistantMessage(text: streamBuffer, emotion: nil)
        }
    }

    private func onStreamComplete(_ fullResponse: String) {
        streamComplete = true
        chatLog("STREAM_COMPLETE: fullResponse=\(fullResponse.prefix(300))")
        chatLog("STREAM_COMPLETE: streamBuffer=\(streamBuffer.prefix(300))")

        var clean = fullResponse.isEmpty ? streamBuffer : fullResponse
        clean = stripThinkingTags(clean)

        let pattern = "\\[(NORMAL|SMILE|ANGRY|SAD|SURPRISED|BLUSH|WINK|DISGUST|SMUG|THINKING|PANIC)\\]"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(clean.startIndex..., in: clean)
            clean = regex.stringByReplacingMatches(in: clean, range: range, withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        conversationHistory.append(ChatMessage(role: "assistant", content: clean))

        if let appState = appState {
            appState.addBacklog(role: "Kurisu", message: clean)
        }

        // Finalize the last assistant message
        if !messages.isEmpty, messages[messages.count - 1].role == "assistant" {
            messages[messages.count - 1].text = clean
            messages[messages.count - 1].isStreaming = false
        }

        finishResponse()
    }

    // MARK: - Error handling

    private func onAPIError(_ error: String) {
        guard let appState = appState else { return }

        let kurisuMessage: String
        if error.contains("API Key") || error.contains("設定されていません") {
            kurisuMessage = "……APIキーが設定されてないみたいよ。CONFIGから設定してちょうだい。"
        } else if error.contains("401") || error.contains("Unauthorized") {
            kurisuMessage = "APIキーが無効みたい……もう一度確認して設定し直してくれる？"
        } else if error.contains("429") || error.contains("rate limit") || error.contains("quota") {
            kurisuMessage = "リクエストが多すぎるみたい。少し待ってからもう一度試してくれない？"
        } else if error.contains("timeout") || error.contains("Timeout") {
            kurisuMessage = "応答がタイムアウトしたわ……ネットワークの状態を確認してみて。"
        } else if error.contains("500") || error.contains("502") || error.contains("503") {
            kurisuMessage = "サーバー側でエラーが起きてるみたい。しばらくしてからもう一度試して。"
        } else if error.contains("gcloud") || error.contains("アクセストークン") {
            kurisuMessage = "Vertex AIの認証に失敗したわ。gcloudの設定を確認してみて。"
        } else {
            kurisuMessage = "何かエラーが起きたみたい……もう一度試してくれる？\n(\(error))"
        }

        chatLog("API_ERROR: \(error)")
        processEmotion("ANGRY")
        appState.addBacklog(role: "Kurisu", message: kurisuMessage)

        // Remove streaming placeholder if present
        if !messages.isEmpty && messages[messages.count - 1].role == "assistant" && messages[messages.count - 1].isStreaming {
            messages.removeLast()
        }

        messages.append(DisplayMessage(role: "assistant", text: kurisuMessage, emotion: "ANGRY", isStreaming: false))
        finishResponse()
    }

    // MARK: - Helpers

    private func updateLastAssistantMessage(text: String, emotion: String?) {
        guard !messages.isEmpty, messages[messages.count - 1].role == "assistant" else { return }
        messages[messages.count - 1].text = text
        if let emotion = emotion {
            messages[messages.count - 1].emotion = emotion
        }
    }

    private func finishResponse() {
        guard let appState = appState else { return }
        isWaitingForResponse = false
        appState.isSpeaking = false
        appState.chatState = .inputReady
        appState.showWaitingIndicator = false
        streamBuffer = ""
        streamEmotionParsed = false
        streamComplete = false
    }

    private func processEmotion(_ tag: String) {
        guard let appState = appState else { return }
        let emotion = EmotionTag(rawValue: tag.uppercased()) ?? .normal
        chatLog("EMOTION: tag='\(tag)' -> EmotionTag=\(emotion.rawValue) (prev=\(appState.currentEmotion.rawValue))")
        appState.currentEmotion = emotion
    }

    // MARK: - System Prompt Builder

    private func buildFullSystemPrompt() -> String {
        var prompt = kurisuSystemPrompt
        let memContext = memoryManager.getMemoryContext()
        if !memContext.isEmpty {
            prompt += "\n\n" + memContext
        }
        return prompt
    }

    private func updateSystemPromptWithContext() {
        var prompt = kurisuSystemPrompt
        let memContext = memoryManager.getMemoryContext()
        if !memContext.isEmpty {
            prompt += "\n\n" + memContext
        }
        let dynContext = memoryManager.getDynamicContext(turnCount: turnCount)
        if !dynContext.isEmpty {
            prompt += "\n\n" + dynContext
        }

        if let appState = appState, appState.webSearchEnabled {
            prompt += """

━━━━━━━━━━━━━━━━━━━━
█ Web検索機能（有効）
━━━━━━━━━━━━━━━━━━━━
あなたは現在インターネットにアクセスできる状態にある。
検索結果を使う場合でも必ず牧瀬紅莉栖として回答すること。
「検索結果によると〜」のような機械的な言い方はしない。
あくまで自分の知識として自然に語る。
"""
        }

        if !conversationHistory.isEmpty && conversationHistory[0].role == "system" {
            conversationHistory[0].content = prompt
        }
    }

    private func stripThinkingTags(_ text: String) -> String {
        var result = text
        while let start = result.range(of: "<think>") {
            if let end = result.range(of: "</think>") {
                result = String(result[..<start.lowerBound]) + String(result[end.upperBound...])
            } else {
                result = String(result[..<start.lowerBound])
                break
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Chat View

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool

    let accentColor = Color(red: 0.85, green: 0.65, blue: 0.2)

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.messages) { msg in
                            messageBubble(msg)
                                .id(msg.id)
                        }

                        // Typing indicator
                        if viewModel.isWaitingForResponse && (viewModel.messages.isEmpty || !viewModel.messages.last!.isStreaming) {
                            HStack(spacing: 6) {
                                Text("牧瀬 紅莉栖")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(accentColor)
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.5)
                                    .tint(accentColor)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .id("typing-indicator")
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: viewModel.messages.last?.text) { _, _ in
                    scrollToBottom(proxy)
                }
            }

            // Input bar — always visible
            inputBar
        }
        .background(Color.black.opacity(0.5))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            if let lastMsg = viewModel.messages.last {
                proxy.scrollTo(lastMsg.id, anchor: .bottom)
            } else {
                proxy.scrollTo("typing-indicator", anchor: .bottom)
            }
        }
    }

    // MARK: - Message Bubble

    @ViewBuilder
    private func messageBubble(_ msg: DisplayMessage) -> some View {
        if msg.role == "user" {
            // User message — right aligned
            HStack {
                Spacer(minLength: 60)
                Text(msg.text)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(accentColor.opacity(0.3))
                    .cornerRadius(12)
            }
            .padding(.horizontal, 8)
        } else {
            // Assistant message — left aligned
            VStack(alignment: .leading, spacing: 3) {
                Text("牧瀬 紅莉栖")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(accentColor)

                HStack(alignment: .bottom, spacing: 0) {
                    Text(msg.text)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .lineSpacing(3)

                    if msg.isStreaming {
                        Text("_")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(accentColor)
                            .opacity(cursorOpacity())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
            }
            .padding(.horizontal, 8)
        }
    }

    @State private var cursorPhase: Bool = false

    private func cursorOpacity() -> Double {
        // Blinking cursor while streaming
        return 1.0
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            Text(">")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(accentColor)

            TextField("メッセージを入力...", text: $viewModel.inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .focused($isInputFocused)
                .onSubmit {
                    viewModel.submitMessage()
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.85))
        .overlay(
            Rectangle()
                .stroke(accentColor.opacity(0.3), lineWidth: 1)
        )
    }
}
