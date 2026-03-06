import SwiftUI
import WebKit

/// Renders the Live2D Kurisu model using WKWebView + pixi-live2d-display.
/// Serves model files from a local HTTP server so the WebView can access them.
struct Live2DView: NSViewRepresentable {
    @Binding var emotion: EmotionTag
    @Binding var isSpeaking: Bool

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        // Add console.log handler
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "consoleLog")
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator

        // Start local server for Live2D files, then load HTML
        let serverPort = Live2DLocalServer.shared.start()
        Coordinator.log("Server port: \(serverPort)")
        let html = Live2DHTML.generate(serverPort: serverPort)
        if serverPort > 0 {
            // Store HTML in server and load via URL so CDN scripts work
            Live2DLocalServer.shared.htmlContent = html
            webView.load(URLRequest(url: URL(string: "http://127.0.0.1:\(serverPort)/index.html")!))
        } else {
            webView.loadHTMLString(html, baseURL: nil)
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let expressionName = emotionToExpression(emotion)

        // Only send JS calls when values actually change
        if expressionName != context.coordinator.lastExpression {
            context.coordinator.lastExpression = expressionName
            Coordinator.log("updateNSView: emotion=\(emotion.rawValue) -> expression=\(expressionName)")
            webView.evaluateJavaScript("setExpression('\(expressionName)')", completionHandler: nil)
        }

        if isSpeaking != context.coordinator.lastSpeaking {
            context.coordinator.lastSpeaking = isSpeaking
            Coordinator.log("updateNSView: isSpeaking=\(isSpeaking)")
            let speakingJS = isSpeaking ? "startLipSync()" : "stopLipSync()"
            webView.evaluateJavaScript(speakingJS, completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var lastExpression: String = ""
        var lastSpeaking: Bool = false
        static let logFile = "/tmp/amadeus_live2d.log"

        static func log(_ msg: String) {
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

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let body = message.body as? String {
                Coordinator.log("JS: \(body)")
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Coordinator.log("Navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Coordinator.log("Provisional navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Coordinator.log("Page loaded successfully")
        }
    }

    private func emotionToExpression(_ emotion: EmotionTag) -> String {
        switch emotion {
        case .normal: return "Normal"
        case .smile, .smug: return "Smile"
        case .angry: return "Angry"
        case .sad: return "Sad"
        case .surprised, .panic: return "Surprised"
        case .blush: return "Blushing"
        case .wink: return "Smile"
        case .disgust: return "Angry"
        case .thinking: return "Normal"
        }
    }
}

// MARK: - Local HTTP Server for Live2D files

/// Minimal HTTP server to serve Live2D model files to WKWebView.
/// WKWebView requires HTTP URLs for cross-origin resource loading (moc3, textures, etc.)
class Live2DLocalServer {
    static let shared = Live2DLocalServer()
    private var serverSocket: Int32 = -1
    private var port: Int = 0
    private var isRunning = false
    private var live2dResourcePath: String?
    var htmlContent: String = ""

    func start() -> Int {
        guard !isRunning else { return port }

        // Find Live2D resources path
        // Bundle.module.resourceURL already includes /Resources, so just append "Live2D"
        if let bundleURL = Bundle.module.resourceURL {
            let candidate = bundleURL.appendingPathComponent("Live2D").path
            if FileManager.default.fileExists(atPath: candidate) {
                live2dResourcePath = candidate
            }
        }

        guard live2dResourcePath != nil else {
            Live2DView.Coordinator.log("Server: No Live2D resources found. Bundle.module.resourceURL=\(Bundle.module.resourceURL?.path ?? "nil")")
            return 0
        }

        // Create socket
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { return 0 }

        var opt: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // Let OS pick a port
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { close(serverSocket); return 0 }

        // Get assigned port
        var assignedAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &assignedAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(serverSocket, $0, &addrLen)
            }
        }
        port = Int(CFSwapInt16BigToHost(assignedAddr.sin_port))

        guard listen(serverSocket, 10) == 0 else { close(serverSocket); return 0 }

        isRunning = true
        Live2DView.Coordinator.log("Server: Serving on http://127.0.0.1:\(port), path=\(live2dResourcePath ?? "nil")")

        // Accept connections in background
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while self?.isRunning == true {
                guard let self = self else { break }
                let clientSocket = accept(self.serverSocket, nil, nil)
                if clientSocket >= 0 {
                    DispatchQueue.global(qos: .utility).async {
                        self.handleClient(clientSocket)
                    }
                }
            }
        }

        return port
    }

    private func handleClient(_ clientSocket: Int32) {
        defer { close(clientSocket) }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = recv(clientSocket, &buffer, buffer.count, 0)
        guard bytesRead > 0 else { return }

        let requestStr = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
        guard let firstLine = requestStr.components(separatedBy: "\r\n").first else { return }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return }

        var path = parts[1]
        if path.hasPrefix("/") { path = String(path.dropFirst()) }
        path = path.removingPercentEncoding ?? path

        Live2DView.Coordinator.log("HTTP GET /\(path)")

        // Serve HTML page at root
        if path.isEmpty || path == "index.html" {
            sendResponse(clientSocket, status: "200 OK", contentType: "text/html", body: Data(htmlContent.utf8))
            return
        }

        guard let basePath = live2dResourcePath else { return }
        let filePath = (basePath as NSString).appendingPathComponent(path)

        // Security: prevent directory traversal
        guard filePath.hasPrefix(basePath) else {
            sendResponse(clientSocket, status: "403 Forbidden", contentType: "text/plain", body: Data("Forbidden".utf8))
            return
        }

        guard FileManager.default.fileExists(atPath: filePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
            sendResponse(clientSocket, status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8))
            return
        }

        let contentType = mimeType(for: filePath)
        sendResponse(clientSocket, status: "200 OK", contentType: contentType, body: data)
    }

    private func sendResponse(_ socket: Int32, status: String, contentType: String, body: Data) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        header.data(using: .utf8)?.withUnsafeBytes { ptr in
            _ = send(socket, ptr.baseAddress, ptr.count, 0)
        }
        body.withUnsafeBytes { ptr in
            _ = send(socket, ptr.baseAddress!, ptr.count, 0)
        }
    }

    private func mimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "json": return "application/json"
        case "moc3": return "application/octet-stream"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Live2D HTML Generator

enum Live2DHTML {
    static func generate(serverPort: Int = 0) -> String {
        let modelURL = serverPort > 0
            ? "http://127.0.0.1:\(serverPort)/Live2D%E7%B4%85%E8%8E%89%E6%A0%96forSDK5.0.model3.json"
            : ""

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            * { margin: 0; padding: 0; }
            html, body { width: 100%; height: 100%; overflow: hidden; background: transparent; }
            canvas { display: block; background: transparent; }
            #placeholder {
                width: 100%; height: 100%;
                display: flex; flex-direction: column;
                align-items: center; justify-content: center;
                font-family: -apple-system, sans-serif;
                color: rgba(255, 255, 255, 0.6);
            }
            #placeholder .name {
                font-size: 24px; font-weight: 300;
                color: rgba(218, 165, 32, 0.8);
                margin-bottom: 8px;
            }
            #placeholder .emotion { font-size: 48px; margin-bottom: 16px; }
            #placeholder .label {
                font-size: 13px; font-family: monospace;
                color: rgba(255, 255, 255, 0.3);
            }
            #live2d-canvas { display: none; }
            .speaking-indicator {
                position: absolute; bottom: 20px; left: 50%;
                transform: translateX(-50%);
                display: flex; gap: 3px; opacity: 0;
                transition: opacity 0.2s;
            }
            .speaking-indicator.active { opacity: 1; }
            .speaking-indicator .bar {
                width: 3px; background: rgba(218, 165, 32, 0.6);
                border-radius: 2px; animation: lipSync 0.4s ease-in-out infinite alternate;
            }
            .speaking-indicator .bar:nth-child(2) { animation-delay: 0.1s; }
            .speaking-indicator .bar:nth-child(3) { animation-delay: 0.2s; }
            .speaking-indicator .bar:nth-child(4) { animation-delay: 0.15s; }
            .speaking-indicator .bar:nth-child(5) { animation-delay: 0.05s; }
            @keyframes lipSync { from { height: 4px; } to { height: 16px; } }
        </style>
        </head>
        <body>
        <div id="placeholder">
            <div class="name">牧瀬 紅莉栖</div>
            <div class="emotion" id="emotion-display">😐</div>
            <div class="label">AMADEUS SYSTEM</div>
            <div class="label" id="expression-label">LOADING...</div>
        </div>
        <canvas id="live2d-canvas"></canvas>
        <div class="speaking-indicator" id="speaking-indicator">
            <div class="bar"></div><div class="bar"></div><div class="bar"></div>
            <div class="bar"></div><div class="bar"></div>
        </div>

        <script>
        // ═══ Console log bridge to native Swift ═══
        const _origLog = console.log;
        const _origErr = console.error;
        const _origWarn = console.warn;
        function _nativeLog(level, args) {
            try {
                window.webkit.messageHandlers.consoleLog.postMessage(level + ': ' + Array.from(args).map(a => {
                    try { return typeof a === 'object' ? JSON.stringify(a) : String(a); } catch(e) { return String(a); }
                }).join(' '));
            } catch(e) {}
        }
        console.log = function() { _origLog.apply(console, arguments); _nativeLog('LOG', arguments); };
        console.error = function() { _origErr.apply(console, arguments); _nativeLog('ERROR', arguments); };
        console.warn = function() { _origWarn.apply(console, arguments); _nativeLog('WARN', arguments); };
        window.onerror = function(msg, url, line, col, err) {
            _nativeLog('UNCAUGHT', ['Error: ' + msg + ' at ' + url + ':' + line]);
        };

        // ═══ Placeholder fallback ═══
        const emotionEmojis = {
            'Normal': '😐', 'Smile': '😊', 'Angry': '😠', 'Sad': '😢',
            'Surprised': '😲', 'Blushing': '😳',
        };

        // ═══ Emotion animation system (ported from Windows AmadeusChatController.cs) ═══
        const emotionTargets = {
            NORMAL:    { browY:0, browForm:0.5, browAngle:0, eyeOpen:1, eyeSmile:0, mouthForm:0, bodyX:0, bodyY:0, bodyZ:0, headX:0, headY:0, headZ:0, cheek:0, isWink:false },
            SMILE:     { browY:0.4, browForm:0.8, browAngle:0.2, eyeOpen:0.6, eyeSmile:1.0, mouthForm:1.0, bodyX:3, bodyY:0, bodyZ:-2, headX:5, headY:3, headZ:-3, cheek:0.3, isWink:false },
            ANGRY:     { browY:-0.6, browForm:-0.8, browAngle:-0.8, eyeOpen:0.5, eyeSmile:0, mouthForm:-0.8, bodyX:-4, bodyY:0, bodyZ:0, headX:-5, headY:-5, headZ:0, cheek:0, isWink:false },
            SAD:       { browY:-0.5, browForm:-0.6, browAngle:0.6, eyeOpen:0.4, eyeSmile:0, mouthForm:-0.5, bodyX:-3, bodyY:-3, bodyZ:-3, headX:-8, headY:-7, headZ:-5, cheek:0, isWink:false },
            SURPRISED: { browY:0.8, browForm:0.5, browAngle:0, eyeOpen:1.25, eyeSmile:0, mouthForm:-0.4, bodyX:-2, bodyY:5, bodyZ:2, headX:2, headY:8, headZ:0, cheek:0, isWink:false },
            BLUSH:     { browY:0.2, browForm:0.4, browAngle:0.3, eyeOpen:0.6, eyeSmile:0.7, mouthForm:0.3, bodyX:8, bodyY:-3, bodyZ:-3, headX:8, headY:-8, headZ:-7, cheek:1.0, isWink:false },
            WINK:      { browY:0.5, browForm:0.8, browAngle:0.2, eyeOpen:1, eyeSmile:0.7, mouthForm:0.5, bodyX:2, bodyY:0, bodyZ:-5, headX:5, headY:2, headZ:-5, cheek:0, isWink:true },
            DISGUST:   { browY:-0.3, browForm:-0.9, browAngle:-0.5, eyeOpen:0.4, eyeSmile:0, mouthForm:-0.9, bodyX:5, bodyY:4, bodyZ:2, headX:5, headY:-4, headZ:3, cheek:0, isWink:false },
            SMUG:      { browY:0.3, browForm:0.7, browAngle:0.4, eyeOpen:0.6, eyeSmile:0.8, mouthForm:0.6, bodyX:4, bodyY:0, bodyZ:-2, headX:10, headY:5, headZ:-2, cheek:0, isWink:false },
            THINKING:  { browY:-0.2, browForm:-0.3, browAngle:0.2, eyeOpen:0.8, eyeSmile:0, mouthForm:-0.2, bodyX:-2, bodyY:5, bodyZ:5, headX:5, headY:-8, headZ:5, cheek:0, isWink:false },
            PANIC:     { browY:0.6, browForm:-0.5, browAngle:-0.3, eyeOpen:1.2, eyeSmile:0, mouthForm:-0.5, bodyX:-3, bodyY:0, bodyZ:0, headX:-2, headY:0, headZ:0, cheek:0.6, isWink:false },
        };

        const motionBursts = {
            NORMAL:    { bodyX:0, bodyY:1, bodyZ:0, headX:0, headY:1, headZ:0, duration:0.4, intensity:0.5 },
            SMILE:     { bodyX:4, bodyY:2, bodyZ:-2, headX:5, headY:3, headZ:-3, duration:0.5, intensity:0.8 },
            ANGRY:     { bodyX:-5, bodyY:-3, bodyZ:0, headX:-5, headY:-5, headZ:0, duration:0.5, intensity:1.2 },
            SAD:       { bodyX:-2, bodyY:-3, bodyZ:-2, headX:-3, headY:-4, headZ:-2, duration:0.8, intensity:0.7 },
            SURPRISED: { bodyX:-2, bodyY:5, bodyZ:2, headX:0, headY:8, headZ:0, duration:0.4, intensity:1.5 },
            BLUSH:     { bodyX:8, bodyY:-2, bodyZ:-3, headX:12, headY:-3, headZ:-5, duration:0.6, intensity:1.0 },
            WINK:      { bodyX:5, bodyY:2, bodyZ:-2, headX:6, headY:3, headZ:-4, duration:0.4, intensity:0.9 },
            DISGUST:   { bodyX:5, bodyY:4, bodyZ:2, headX:7, headY:-3, headZ:3, duration:0.5, intensity:1.1 },
            SMUG:      { bodyX:2, bodyY:2, bodyZ:-1, headX:5, headY:3, headZ:-1, duration:0.7, intensity:0.6 },
            THINKING:  { bodyX:0, bodyY:0, bodyZ:0, headX:2, headY:-3, headZ:1, duration:0.8, intensity:0.3 },
            PANIC:     { bodyX:0, bodyY:0, bodyZ:0, headX:0, headY:0, headZ:0, duration:0.2, intensity:2.0 },
        };

        // Animation state
        let currentEmotion = {...emotionTargets.NORMAL};
        let targetEmotion = {...emotionTargets.NORMAL};
        let currentEmotionTag = 'NORMAL';
        let idlePhase = 0;
        let emotionLerpSpeed = 3.0;
        let lipSyncActive = false;
        let activeBurst = null;
        let burstProgress = 1;
        let burstTimer = 0;

        // Blinking state
        let blinkState = 'open';
        let blinkTimer = 0;
        let blinkInterval = 4.0;
        let blinkDuration = 0.1;
        let blinkValue = 1.0;
        let lastFrameTime = performance.now();

        // Attempt to match Unity's Mathf.PerlinNoise (returns 0..1)
        // Simple coherent noise using interpolated hash
        function _fade(t) { return t*t*t*(t*(t*6-15)+10); }
        function _hash(x, y) {
            let h = (Math.sin(x*127.1+y*311.7)*43758.5453) % 1;
            return h < 0 ? h + 1 : h;
        }
        function perlinNoise(x, y) {
            const xi = Math.floor(x), yi = Math.floor(y);
            const xf = x - xi, yf = y - yi;
            const u = _fade(xf), v = _fade(yf);
            const a = _hash(xi,yi), b = _hash(xi+1,yi);
            const c = _hash(xi,yi+1), d = _hash(xi+1,yi+1);
            const x1 = a + u*(b-a), x2 = c + u*(d-c);
            return x1 + v*(x2-x1); // returns 0..1
        }

        function drift(phase, speed, seed, amplitude) {
            // Match Unity: (PerlinNoise - 0.5) * 2 gives -1..1
            const slow   = (perlinNoise(phase * speed * 0.3, seed) - 0.5) * 2;
            const medium = (perlinNoise(phase * speed * 0.8, seed + 50) - 0.5) * 2;
            const micro  = (perlinNoise(phase * speed * 2.5, seed + 100) - 0.5) * 2;
            return (slow * 0.5 + medium * 0.35 + micro * 0.15) * amplitude;
        }

        function lerp(a, b, t) { return a + (b - a) * Math.min(t, 1); }

        function setExpression(name) {
            console.log('setExpression called: ' + name);
            const emojiEl = document.getElementById('emotion-display');
            const labelEl = document.getElementById('expression-label');
            if (emojiEl) emojiEl.textContent = emotionEmojis[name] || '😐';
            if (labelEl) labelEl.textContent = name.toUpperCase();

            const tagMap = { Normal:'NORMAL', Smile:'SMILE', Angry:'ANGRY', Sad:'SAD',
                            Surprised:'SURPRISED', Blushing:'BLUSH' };
            const tag = tagMap[name] || 'NORMAL';

            if (emotionTargets[tag]) {
                targetEmotion = {...emotionTargets[tag]};
                if (tag !== currentEmotionTag) {
                    currentEmotionTag = tag;
                    activeBurst = motionBursts[tag] || null;
                    burstTimer = 0;
                    burstProgress = 0;
                    idlePhase = 0;
                }
            }

            if (window.live2dModel) {
                try { window.live2dModel.expression(name); } catch(e) {}
            }
        }

        function startLipSync() {
            document.getElementById('speaking-indicator').classList.add('active');
            lipSyncActive = true;
        }

        function stopLipSync() {
            document.getElementById('speaking-indicator').classList.remove('active');
            lipSyncActive = false;
        }

        function animationLoop() {
            const now = performance.now();
            const dt = (now - lastFrameTime) / 1000;
            lastFrameTime = now;
            if (!window.live2dModel) { requestAnimationFrame(animationLoop); return; }

            const core = window.live2dModel.internalModel.coreModel;
            idlePhase += dt;

            for (const key of ['browY','browForm','browAngle','eyeOpen','eyeSmile','mouthForm',
                              'bodyX','bodyY','bodyZ','headX','headY','headZ','cheek']) {
                currentEmotion[key] = lerp(currentEmotion[key], targetEmotion[key], dt * emotionLerpSpeed);
            }

            let burstBodyX=0, burstBodyY=0, burstBodyZ=0, burstHeadX=0, burstHeadY=0, burstHeadZ=0;
            if (activeBurst && burstProgress < 1) {
                burstTimer += dt;
                burstProgress = Math.min(burstTimer / activeBurst.duration, 1);
                const t = burstProgress;
                // Match Windows: spring = sin(t * PI * 2.5) * (1-t)^2
                const spring = Math.sin(t * Math.PI * 2.5) * (1-t) * (1-t);
                const intensity = activeBurst.intensity * spring;
                burstBodyX = activeBurst.bodyX * intensity;
                burstBodyY = activeBurst.bodyY * intensity;
                burstBodyZ = activeBurst.bodyZ * intensity;
                burstHeadX = activeBurst.headX * intensity;
                burstHeadY = activeBurst.headY * intensity;
                burstHeadZ = activeBurst.headZ * intensity;
            }

            let idleBodyX=0, idleBodyY=0, idleBodyZ=0, idleHeadX=0, idleHeadY=0, idleHeadZ=0;
            const tag = currentEmotionTag;
            const p = idlePhase;
            if (tag === 'NORMAL') {
                idleBodyX = drift(p,0.6,0,1.8); idleBodyY = drift(p,0.4,10,0.8)+Math.sin(p*0.8)*0.3;
                idleBodyZ = drift(p,0.35,20,0.6); idleHeadX = drift(p,0.5,30,3.0);
                idleHeadY = drift(p,0.4,40,2.0); idleHeadZ = drift(p,0.3,50,1.0);
            } else if (tag === 'SMILE') {
                idleBodyX = drift(p,1.2,5,3.0); idleBodyY = drift(p,1.0,15,1.5);
                idleBodyZ = drift(p,0.7,25,1.5); idleHeadX = drift(p,1.0,35,4.0);
                idleHeadY = drift(p,0.8,45,2.5); idleHeadZ = drift(p,0.9,55,2.0);
            } else if (tag === 'ANGRY') {
                const tension = (perlinNoise(p*3,7) - 0.5) * 2;
                idleBodyX = drift(p,1.5,8,2.5)+tension*1.5; idleBodyY = drift(p,0.5,18,0.8);
                idleBodyZ = drift(p,2.0,28,1.2); idleHeadX = drift(p,1.8,38,3.0)+tension;
                idleHeadY = drift(p,1.2,48,2.0); idleHeadZ = drift(p,0.8,58,1.0);
            } else if (tag === 'SAD') {
                idleBodyX = drift(p,0.4,3,2.5); idleBodyY = drift(p,0.3,13,1.5);
                idleBodyZ = drift(p,0.35,23,1.8); idleHeadX = drift(p,0.3,33,3.5);
                idleHeadY = drift(p,0.25,43,2.5); idleHeadZ = drift(p,0.3,53,1.5);
            } else if (tag === 'SURPRISED') {
                idleBodyX = drift(p,1.8,6,3.0); idleBodyY = drift(p,1.5,16,1.5)+Math.abs(Math.sin(p*1.5))*0.8;
                idleBodyZ = drift(p,1.0,26,1.5); idleHeadX = drift(p,2.0,36,5.0);
                idleHeadY = drift(p,1.8,46,4.5); idleHeadZ = drift(p,1.0,56,1.5);
            } else if (tag === 'BLUSH') {
                const fidget = (perlinNoise(p*4,99) - 0.5) * 1.5;
                idleBodyX = drift(p,0.8,9,3.0)+1; idleBodyY = drift(p,0.6,19,1.0);
                idleBodyZ = drift(p,0.9,29,2.0); idleHeadX = drift(p,0.6,39,4.0)+2+fidget;
                idleHeadY = drift(p,0.5,49,3.0); idleHeadZ = drift(p,0.7,59,2.5);
            } else if (tag === 'PANIC') {
                const panic = (perlinNoise(p*15,999) - 0.5) * 4;
                idleBodyX = drift(p,2.0,6,2.0)+panic; idleBodyY = drift(p,2.0,16,2.0);
                idleBodyZ = drift(p,2.0,26,2.0); idleHeadX = drift(p,3.0,36,3.0)+panic;
                idleHeadY = panic*1.5; idleHeadZ = panic*0.5;
            } else if (tag === 'THINKING') {
                idleBodyX = drift(p,0.2,5,1.0); idleBodyY = drift(p,0.2,15,0.5);
                idleBodyZ = drift(p,0.2,25,0.5); idleHeadX = drift(p,0.2,35,1.0);
                idleHeadY = drift(p,0.2,45,1.0); idleHeadZ = drift(p,0.2,55,0.5);
            } else if (tag === 'SMUG') {
                idleBodyX = drift(p,0.5,4,2.0); idleBodyY = drift(p,0.4,14,1.0);
                idleBodyZ = drift(p,0.4,24,1.5); idleHeadX = drift(p,0.6,34,3.0)+3;
                idleHeadY = drift(p,0.5,44,2.0); idleHeadZ = drift(p,0.5,54,1.0);
            } else {
                idleBodyX = drift(p,0.6,0,1.8); idleBodyY = drift(p,0.4,10,0.8);
                idleBodyZ = drift(p,0.35,20,0.6); idleHeadX = drift(p,0.5,30,3.0);
                idleHeadY = drift(p,0.4,40,2.0); idleHeadZ = drift(p,0.3,50,1.0);
            }

            try {
                core.setParameterValueById('ParamBrowLY', currentEmotion.browY);
                core.setParameterValueById('ParamBrowRY', currentEmotion.browY);
                core.setParameterValueById('ParamBrowLForm', currentEmotion.browForm);
                core.setParameterValueById('ParamBrowRForm', currentEmotion.browForm);
                core.setParameterValueById('ParamBrowLAngle', currentEmotion.browAngle);
                core.setParameterValueById('ParamBrowRAngle', currentEmotion.browAngle);
                core.setParameterValueById('ParamEyeLSmile', currentEmotion.eyeSmile);
                core.setParameterValueById('ParamEyeRSmile', currentEmotion.eyeSmile);
                core.setParameterValueById('ParamMouthForm', currentEmotion.mouthForm);
                core.setParameterValueById('ParamCheek', currentEmotion.cheek);
            } catch(e) {}

            updateBlink(dt);
            const eyeOpenVal = currentEmotion.eyeOpen * blinkValue;
            try {
                if (currentEmotion.isWink || targetEmotion.isWink) {
                    core.setParameterValueById('ParamEyeLOpen', eyeOpenVal);
                    core.setParameterValueById('ParamEyeROpen', 0);
                } else {
                    core.setParameterValueById('ParamEyeLOpen', eyeOpenVal);
                    core.setParameterValueById('ParamEyeROpen', eyeOpenVal);
                }
            } catch(e) {}

            try {
                core.setParameterValueById('ParamBodyAngleX', currentEmotion.bodyX + burstBodyX + idleBodyX);
                core.setParameterValueById('ParamBodyAngleY', currentEmotion.bodyY + burstBodyY + idleBodyY);
                core.setParameterValueById('ParamBodyAngleZ', currentEmotion.bodyZ + burstBodyZ + idleBodyZ);
                core.setParameterValueById('ParamAngleX', currentEmotion.headX + burstHeadX + idleHeadX);
                core.setParameterValueById('ParamAngleY', currentEmotion.headY + burstHeadY + idleHeadY);
                core.setParameterValueById('ParamAngleZ', currentEmotion.headZ + burstHeadZ + idleHeadZ);
            } catch(e) {}

            // Lip sync - match Windows: sin-based multi-frequency
            try {
                if (lipSyncActive) {
                    const t = performance.now() / 1000;
                    const mouth = Math.abs(Math.sin(t * 12)) * 0.5
                               + Math.abs(Math.sin(t * 7.3)) * 0.3
                               + perlinNoise(t * 8, 5) * 0.2;
                    core.setParameterValueById('ParamMouthOpenY', Math.min(1, Math.max(0, mouth)));
                } else {
                    const cur = core.getParameterValueById('ParamMouthOpenY') || 0;
                    core.setParameterValueById('ParamMouthOpenY', lerp(cur, 0, dt * 10));
                }
            } catch(e) {}

            // Breathing - match Windows: sin(t * 1.2)
            try {
                core.setParameterValueById('ParamBreath', (Math.sin(performance.now()/1000 * 1.2) + 1) * 0.5);
            } catch(e) {}

            requestAnimationFrame(animationLoop);
        }

        function updateBlink(dt) {
            switch (blinkState) {
                case 'open':
                    blinkTimer += dt;
                    if (blinkTimer >= blinkInterval) {
                        blinkTimer = 0;
                        blinkState = 'closing';
                        blinkInterval = 2.5 + Math.random() * 3.5;
                    }
                    blinkValue = 1.0;
                    break;
                case 'closing':
                    blinkTimer += dt;
                    blinkValue = lerp(1.0, 0.0, blinkTimer / (blinkDuration * 0.5));
                    if (blinkTimer >= blinkDuration * 0.5) { blinkTimer = 0; blinkState = 'opening'; }
                    break;
                case 'opening':
                    blinkTimer += dt;
                    blinkValue = lerp(0.0, 1.0, blinkTimer / (blinkDuration * 0.5));
                    if (blinkTimer >= blinkDuration * 0.5) { blinkTimer = 0; blinkState = 'open'; }
                    break;
            }
        }

        const MODEL_URL = '\(modelURL)';

        // ═══ Load CDN scripts dynamically, then init Live2D ═══
        const cdnScripts = [
            'https://cdnjs.cloudflare.com/ajax/libs/pixi.js/6.5.10/browser/pixi.min.js',
            'https://cubism.live2d.com/sdk-web/cubismcore/live2dcubismcore.min.js',
            'https://cdn.jsdelivr.net/npm/pixi-live2d-display/dist/cubism4.min.js'
        ];

        function loadScriptsSequentially(idx) {
            if (idx >= cdnScripts.length) {
                console.log('CDN scripts done. PIXI=' + (typeof window.PIXI) + ' live2d=' + (window.PIXI && window.PIXI.live2d ? 'yes' : 'no'));
                tryLoadLive2D();
                return;
            }
            const s = document.createElement('script');
            s.src = cdnScripts[idx];
            s.onload = function() {
                console.log('Loaded: ' + cdnScripts[idx]);
                loadScriptsSequentially(idx + 1);
            };
            s.onerror = function(e) {
                console.error('FAILED: ' + cdnScripts[idx]);
                loadScriptsSequentially(idx + 1);
            };
            document.head.appendChild(s);
        }

        async function tryLoadLive2D() {
            if (!MODEL_URL || !window.PIXI || !window.PIXI.live2d) {
                console.log('Live2D: Using placeholder mode. MODEL_URL=' + MODEL_URL + ' PIXI=' + (typeof window.PIXI));
                document.getElementById('expression-label').textContent = 'NORMAL';
                requestAnimationFrame(animationLoop);
                return;
            }
            try {
                console.log('Live2D: Creating PIXI app...');
                const app = new PIXI.Application({
                    view: document.getElementById('live2d-canvas'),
                    transparent: true, resizeTo: window, antialias: true,
                });
                console.log('Live2D: Loading model from ' + MODEL_URL);
                const model = await PIXI.live2d.Live2DModel.from(MODEL_URL);
                app.stage.addChild(model);

                function positionModel(m) {
                    const W = window.innerWidth, H = window.innerHeight;
                    const s = H / m.height * 2.0;
                    m.scale.set(s);
                    m.anchor.set(0.5, 0.1);
                    m.x = W * 0.45;
                    m.y = H / 2;
                }
                positionModel(model);
                // Disable mouse tracking - model should not follow cursor
                model.interactive = false;
                model.interactiveChildren = false;
                if (model.internalModel && model.internalModel.focusController) {
                    model.internalModel.focusController.focus = function() {};
                }
                model.tracker = null;
                window.live2dModel = model;

                document.getElementById('placeholder').style.display = 'none';
                document.getElementById('live2d-canvas').style.display = 'block';
                setExpression('Normal');

                window.addEventListener('resize', () => positionModel(model));

                console.log('Live2D: Model loaded successfully!');
                requestAnimationFrame(animationLoop);
            } catch(e) {
                console.error('Live2D: Failed to load model:', e.message || e);
                document.getElementById('expression-label').textContent = 'LOAD ERROR';
                requestAnimationFrame(animationLoop);
            }
        }

        loadScriptsSequentially(0);
        </script>
        </body>
        </html>
        """
    }
}
