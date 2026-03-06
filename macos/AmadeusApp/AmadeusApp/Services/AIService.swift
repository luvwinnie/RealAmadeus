import Foundation

/// Handles API communication with OpenAI, Gemini, Claude, Groq, and Vertex AI providers.
/// Port of the Unity AIService.cs to native Swift using URLSession.
class AIService: ObservableObject {
    @Published var isWebSearchEnabled: Bool = false

    private var cachedVertexToken: String?
    private var vertexTokenExpiry: Date = .distantPast
    private let tokenCacheMinutes: Double = 50

    // MARK: - Public API

    /// Non-streaming chat request
    func sendChat(
        messages: [ChatMessage],
        provider: APIProvider,
        apiKey: String,
        model: String,
        webSearch: Bool = false,
        vertexProject: String = "",
        vertexLocation: String = "us-central1",
        ollamaEndpoint: String = "https://llm.nishizaki-leow-lab-alps.org",
        onSuccess: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        if apiKey.isEmpty && provider != .vertexAI && provider != .ollama {
            onError("API Key が設定されていません。CONFIGから設定してください。")
            return
        }

        switch provider {
        case .openAI:
            sendOpenAI(apiKey: apiKey, model: model.isEmpty ? "gpt-4o" : model, messages: messages, onSuccess: onSuccess, onError: onError)
        case .gemini:
            let m = (model.isEmpty || model.hasPrefix("gpt")) ? "gemini-2.0-flash" : model
            sendGemini(apiKey: apiKey, model: m, messages: messages, onSuccess: onSuccess, onError: onError)
        case .claude:
            let m = (model.isEmpty || model.hasPrefix("gpt") || model.hasPrefix("gemini")) ? "claude-sonnet-4-20250514" : model
            sendClaude(apiKey: apiKey, model: m, messages: messages, onSuccess: onSuccess, onError: onError)
        case .groq:
            let m = validGroqModel(model)
            if webSearch {
                sendGroqCompound(apiKey: apiKey, messages: messages, onSuccess: onSuccess, onError: onError)
            } else {
                sendGroq(apiKey: apiKey, model: m, messages: messages, onSuccess: onSuccess, onError: onError)
            }
        case .vertexAI:
            let m = (model.isEmpty || model.hasPrefix("gpt")) ? "gemini-2.0-flash" : model
            getVertexToken { [weak self] token in
                guard let token = token, !token.isEmpty else {
                    onError("Vertex AI: アクセストークンの取得に失敗しました。\ngcloud CLI がインストールされ、gcloud auth login 済みか確認してください。")
                    return
                }
                self?.sendVertexAI(token: token, project: vertexProject, location: vertexLocation, model: m, messages: messages, onSuccess: onSuccess, onError: onError)
            }
        case .ollama:
            let m = model.isEmpty ? "gemma3:4b" : model
            sendOllama(endpoint: ollamaEndpoint, model: m, messages: messages, onSuccess: onSuccess, onError: onError)
        }
    }

    /// Streaming chat request (Groq and Vertex AI)
    func sendChatStreaming(
        messages: [ChatMessage],
        provider: APIProvider,
        apiKey: String,
        model: String,
        webSearch: Bool = false,
        vertexProject: String = "",
        vertexLocation: String = "us-central1",
        ollamaEndpoint: String = "https://llm.nishizaki-leow-lab-alps.org",
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        if apiKey.isEmpty && provider != .vertexAI && provider != .ollama {
            onError("API Key が設定されていません。CONFIGから設定してください。")
            return
        }

        if provider == .groq {
            let m = validGroqModel(model)
            if webSearch {
                sendGroqCompoundStreaming(apiKey: apiKey, messages: messages, onToken: onToken, onComplete: onComplete, onError: onError)
            } else {
                sendGroqStreaming(apiKey: apiKey, model: m, messages: messages, onToken: onToken, onComplete: onComplete, onError: onError)
            }
        } else if provider == .vertexAI {
            let m = (model.isEmpty || model.hasPrefix("gpt")) ? "gemini-2.0-flash" : model
            getVertexToken { [weak self] token in
                guard let token = token, !token.isEmpty else {
                    onError("Vertex AI: アクセストークンの取得に失敗しました。")
                    return
                }
                self?.sendVertexAIStreaming(token: token, project: vertexProject, location: vertexLocation, model: m, messages: messages, onToken: onToken, onComplete: onComplete, onError: onError)
            }
        } else if provider == .ollama {
            let m = model.isEmpty ? "gemma3:4b" : model
            sendOllamaStreaming(endpoint: ollamaEndpoint, model: m, messages: messages, onToken: onToken, onComplete: onComplete, onError: onError)
        } else {
            // Fallback: non-streaming for other providers
            sendChat(messages: messages, provider: provider, apiKey: apiKey, model: model, webSearch: webSearch, vertexProject: vertexProject, vertexLocation: vertexLocation, onSuccess: { response in
                onToken(response)
                onComplete(response)
            }, onError: onError)
        }
    }

    // MARK: - OpenAI

    private func sendOpenAI(apiKey: String, model: String, messages: [ChatMessage], onSuccess: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        let messagesJson = buildOpenAIMessages(messages)
        let bodyDict: [String: Any] = [
            "model": model,
            "messages": messagesJson,
            "max_tokens": 2048
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        request.httpBody = try? JSONSerialization.data(withJSONObject: bodyDict)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    onError("OpenAI Error: \(error.localizedDescription)")
                    return
                }
                guard let data = data, let json = String(data: data, encoding: .utf8) else {
                    onError("OpenAI Error: No data received")
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    onError("OpenAI Error (\(httpResponse.statusCode)): \(json)")
                    return
                }
                let content = self.extractOpenAIResponse(json)
                onSuccess(content)
            }
        }.resume()
    }

    private func buildOpenAIMessages(_ messages: [ChatMessage]) -> [[String: String]] {
        messages.map { ["role": $0.role, "content": $0.content] }
    }

    private func extractOpenAIResponse(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return "[Parse Error]"
        }
        return content
    }

    // MARK: - Gemini

    private func sendGemini(apiKey: String, model: String, messages: [ChatMessage], onSuccess: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        let body = buildGeminiBody(messages)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    onError("Gemini Error: \(error.localizedDescription)")
                    return
                }
                guard let data = data, let json = String(data: data, encoding: .utf8) else {
                    onError("Gemini Error: No data received")
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    onError("Gemini Error (\(httpResponse.statusCode)): \(json)")
                    return
                }
                let content = self.extractGeminiResponse(data)
                onSuccess(content)
            }
        }.resume()
    }

    private func buildGeminiBody(_ messages: [ChatMessage], useGrounding: Bool = false) -> [String: Any] {
        var systemInstruction = ""
        var contents: [[String: Any]] = []

        for msg in messages {
            if msg.role == "system" {
                systemInstruction = msg.content
                continue
            }
            let geminiRole = msg.role == "assistant" ? "model" : "user"
            contents.append([
                "role": geminiRole,
                "parts": [["text": msg.content]]
            ])
        }

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": ["maxOutputTokens": 2048]
        ]

        if !systemInstruction.isEmpty {
            body["system_instruction"] = ["parts": [["text": systemInstruction]]]
        }

        if useGrounding {
            body["tools"] = [["googleSearch": [:]]]
        }

        return body
    }

    private func extractGeminiResponse(_ data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = obj["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            return "[Parse Error]"
        }
        return text
    }

    // MARK: - Claude

    private func sendClaude(apiKey: String, model: String, messages: [ChatMessage], onSuccess: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!

        var systemText = ""
        var msgArray: [[String: String]] = []
        for msg in messages {
            if msg.role == "system" {
                systemText = msg.content
                continue
            }
            msgArray.append(["role": msg.role, "content": msg.content])
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "messages": msgArray
        ]
        if !systemText.isEmpty {
            body["system"] = systemText
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    onError("Claude Error: \(error.localizedDescription)")
                    return
                }
                guard let data = data, let json = String(data: data, encoding: .utf8) else {
                    onError("Claude Error: No data received")
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    onError("Claude Error (\(httpResponse.statusCode)): \(json)")
                    return
                }
                let content = self.extractClaudeResponse(data)
                onSuccess(content)
            }
        }.resume()
    }

    private func extractClaudeResponse(_ data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            return "[Parse Error]"
        }
        return text
    }

    // MARK: - Groq

    private func validGroqModel(_ model: String) -> String {
        let valid = ["llama", "mixtral", "gemma", "qwen", "deepseek", "compound"]
        if model.isEmpty || !valid.contains(where: { model.contains($0) }) {
            return "qwen3-32b"
        }
        return model
    }

    private func sendGroq(apiKey: String, model: String, messages: [ChatMessage], onSuccess: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

        var body: [String: Any] = [
            "model": model,
            "messages": buildOpenAIMessages(messages),
            "max_tokens": 2048,
            "temperature": 0.85,
            "top_p": 0.9
        ]
        if model.contains("qwen") {
            body["reasoning_format"] = "hidden"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    onError("Groq Error: \(error.localizedDescription)")
                    return
                }
                guard let data = data, let json = String(data: data, encoding: .utf8) else {
                    onError("Groq Error: No data received")
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    onError("Groq Error (\(httpResponse.statusCode)): \(json)")
                    return
                }
                let content = self.extractOpenAIResponse(json)
                onSuccess(content)
            }
        }.resume()
    }

    // MARK: - Groq Streaming (SSE)

    private func sendGroqStreaming(apiKey: String, model: String, messages: [ChatMessage], onToken: @escaping (String) -> Void, onComplete: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

        var body: [String: Any] = [
            "model": model,
            "messages": buildOpenAIMessages(messages),
            "max_tokens": 2048,
            "temperature": 0.85,
            "top_p": 0.9,
            "stream": true
        ]
        if model.contains("qwen") {
            body["reasoning_format"] = "hidden"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let delegate = SSEDelegate(onToken: onToken, onComplete: onComplete, onError: onError)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: .main)
        session.dataTask(with: request).resume()
    }

    // MARK: - Groq Compound (Web Search)

    private func sendGroqCompound(apiKey: String, messages: [ChatMessage], onSuccess: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

        let body: [String: Any] = [
            "model": "compound-beta",
            "messages": buildOpenAIMessages(messages),
            "max_tokens": 2048
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    onError("Groq Compound Error: \(error.localizedDescription)")
                    return
                }
                guard let data = data, let json = String(data: data, encoding: .utf8) else {
                    onError("Groq Compound Error: No data received")
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    onError("Groq Compound Error (\(httpResponse.statusCode)): \(json)")
                    return
                }
                let content = self.extractOpenAIResponse(json)
                onSuccess(content)
            }
        }.resume()
    }

    private func sendGroqCompoundStreaming(apiKey: String, messages: [ChatMessage], onToken: @escaping (String) -> Void, onComplete: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

        let body: [String: Any] = [
            "model": "compound-beta",
            "messages": buildOpenAIMessages(messages),
            "max_tokens": 2048,
            "stream": true
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let delegate = SSEDelegate(onToken: onToken, onComplete: onComplete, onError: onError)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: .main)
        session.dataTask(with: request).resume()
    }

    // MARK: - Vertex AI

    private func getVertexToken(completion: @escaping (String?) -> Void) {
        if let cached = cachedVertexToken, Date() < vertexTokenExpiry {
            completion(cached)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gcloud", "auth", "print-access-token"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let token = token, !token.isEmpty {
                cachedVertexToken = token
                vertexTokenExpiry = Date().addingTimeInterval(tokenCacheMinutes * 60)
            }
            DispatchQueue.main.async { completion(token) }
        } catch {
            DispatchQueue.main.async { completion(nil) }
        }
    }

    private func sendVertexAI(token: String, project: String, location: String, model: String, messages: [ChatMessage], onSuccess: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        let urlString = "https://\(location)-aiplatform.googleapis.com/v1/projects/\(project)/locations/\(location)/publishers/google/models/\(model):generateContent"
        guard let url = URL(string: urlString) else {
            onError("Vertex AI: Invalid URL")
            return
        }

        let body = buildGeminiBody(messages, useGrounding: isWebSearchEnabled)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    onError("Vertex AI Error: \(error.localizedDescription)")
                    return
                }
                guard let data = data else {
                    onError("Vertex AI Error: No data received")
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    let json = String(data: data, encoding: .utf8) ?? ""
                    onError("Vertex AI Error (\(httpResponse.statusCode)): \(json)")
                    return
                }
                let content = self.extractGeminiResponse(data)
                onSuccess(content)
            }
        }.resume()
    }

    private func sendVertexAIStreaming(token: String, project: String, location: String, model: String, messages: [ChatMessage], onToken: @escaping (String) -> Void, onComplete: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        let urlString = "https://\(location)-aiplatform.googleapis.com/v1/projects/\(project)/locations/\(location)/publishers/google/models/\(model):streamGenerateContent?alt=sse"
        guard let url = URL(string: urlString) else {
            onError("Vertex AI: Invalid URL")
            return
        }

        let body = buildGeminiBody(messages, useGrounding: isWebSearchEnabled)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let delegate = VertexSSEDelegate(onToken: onToken, onComplete: onComplete, onError: onError)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: .main)
        session.dataTask(with: request).resume()
    }
    // MARK: - Ollama (OpenAI-compatible API)

    private func sendOllama(endpoint: String, model: String, messages: [ChatMessage], onSuccess: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        let baseURL = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            onError("Ollama Error: Invalid endpoint URL")
            return
        }

        let bodyDict: [String: Any] = [
            "model": model,
            "messages": buildOpenAIMessages(messages),
            "max_tokens": 2048,
            "temperature": 0.85,
            "top_p": 0.9
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try? JSONSerialization.data(withJSONObject: bodyDict)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    onError("Ollama Error: \(error.localizedDescription)")
                    return
                }
                guard let data = data, let json = String(data: data, encoding: .utf8) else {
                    onError("Ollama Error: No data received")
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    onError("Ollama Error (\(httpResponse.statusCode)): \(json)")
                    return
                }
                let content = self.extractOpenAIResponse(json)
                onSuccess(content)
            }
        }.resume()
    }

    private func sendOllamaStreaming(endpoint: String, model: String, messages: [ChatMessage], onToken: @escaping (String) -> Void, onComplete: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        let baseURL = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            onError("Ollama Error: Invalid endpoint URL")
            return
        }

        let bodyDict: [String: Any] = [
            "model": model,
            "messages": buildOpenAIMessages(messages),
            "max_tokens": 2048,
            "temperature": 0.85,
            "top_p": 0.9,
            "stream": true
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        request.httpBody = try? JSONSerialization.data(withJSONObject: bodyDict)

        let delegate = SSEDelegate(onToken: onToken, onComplete: onComplete, onError: onError)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: .main)
        session.dataTask(with: request).resume()
    }
}

// MARK: - SSE Delegate for Groq Streaming

private class SSEDelegate: NSObject, URLSessionDataDelegate {
    let onToken: (String) -> Void
    let onComplete: (String) -> Void
    let onError: (String) -> Void
    var fullResponse = ""

    init(onToken: @escaping (String) -> Void, onComplete: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.onToken = onToken
        self.onComplete = onComplete
        self.onError = onError
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\n")

        for line in lines {
            if line.hasPrefix("data: ") {
                let payload = String(line.dropFirst(6))
                if payload == "[DONE]" {
                    onComplete(fullResponse)
                    session.invalidateAndCancel()
                    return
                }
                if let data = payload.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = obj["choices"] as? [[String: Any]],
                   let delta = choices.first?["delta"] as? [String: Any],
                   let content = delta["content"] as? String {
                    fullResponse += content
                    onToken(content)
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error, (error as NSError).code != NSURLErrorCancelled {
            onError("Streaming Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - SSE Delegate for Vertex AI Streaming

private class VertexSSEDelegate: NSObject, URLSessionDataDelegate {
    let onToken: (String) -> Void
    let onComplete: (String) -> Void
    let onError: (String) -> Void
    var fullResponse = ""

    init(onToken: @escaping (String) -> Void, onComplete: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.onToken = onToken
        self.onComplete = onComplete
        self.onError = onError
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\n")

        for line in lines {
            if line.hasPrefix("data: ") {
                let payload = String(line.dropFirst(6))
                if let data = payload.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = obj["candidates"] as? [[String: Any]],
                   let first = candidates.first,
                   let content = first["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let firstPart = parts.first,
                   let partText = firstPart["text"] as? String {
                    fullResponse += partText
                    onToken(partText)
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error, (error as NSError).code != NSURLErrorCancelled {
            onError("Vertex Streaming Error: \(error.localizedDescription)")
        } else {
            onComplete(fullResponse)
        }
    }
}
