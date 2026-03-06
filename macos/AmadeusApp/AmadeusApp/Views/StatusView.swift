import SwiftUI

/// Status panel — port of StatusPanelController.cs
struct StatusView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentTime = ""
    @State private var cpuUsage: Double = 0
    @State private var memoryUsage: Double = 0
    @State private var syncValue: Double = 0.95
    @State private var isOnline = true

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("STATUS")
                        .font(.system(size: 20, weight: .thin, design: .monospaced))
                        .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.2))
                        .tracking(4)
                    Spacer()
                    Button("✕") { close() }
                        .buttonStyle(.plain)
                        .foregroundColor(.gray)
                        .font(.system(size: 18))
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)

                Divider().background(Color.gray.opacity(0.3))

                VStack(alignment: .leading, spacing: 16) {
                    // Clock
                    HStack {
                        statusLabel("CLOCK")
                        Spacer()
                        Text(currentTime)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.white)
                    }

                    // Operator
                    HStack {
                        statusLabel("OPERATOR")
                        Spacer()
                        Text(appState.operatorName.isEmpty ? "---" : appState.operatorName)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.white)
                    }

                    // Network
                    HStack {
                        statusLabel("NETWORK")
                        Spacer()
                        Text(isOnline ? "ONLINE" : "OFFLINE")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(isOnline ? .green : .red)
                    }

                    Divider().background(Color.gray.opacity(0.3))

                    // LLM Info
                    HStack {
                        statusLabel("LLM")
                        Spacer()
                        Text("\(appState.apiProvider.displayName) / \(appState.modelName(for: appState.apiProvider))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }

                    // Latency (placeholder — updated by ChatViewModel)
                    HStack {
                        statusLabel("PING")
                        Spacer()
                        Text("---")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.gray)
                    }

                    Divider().background(Color.gray.opacity(0.3))

                    // CPU
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            statusLabel("CPU")
                            Spacer()
                            Text("\(cpuUsage * 100, specifier: "%.1f") %")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        ProgressView(value: cpuUsage)
                            .tint(Color(red: 0.85, green: 0.65, blue: 0.2))
                    }

                    // Memory
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            statusLabel("MEM")
                            Spacer()
                            Text("\(Int(memoryUsage)) MB")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        ProgressView(value: min(memoryUsage / 4096.0, 1.0))
                            .tint(Color(red: 0.85, green: 0.65, blue: 0.2))
                    }

                    // Sync
                    VStack(alignment: .leading, spacing: 4) {
                        statusLabel("SYNC")
                        ProgressView(value: syncValue)
                            .tint(Color(red: 0.85, green: 0.65, blue: 0.2))
                    }
                }
                .padding(24)

                Spacer()
            }
            .frame(width: 500, height: 480)
            .background(Color(red: 0.1, green: 0.1, blue: 0.1))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(red: 0.85, green: 0.65, blue: 0.2).opacity(0.3), lineWidth: 1)
            )
        }
        .onAppear { updateMetrics() }
        .onReceive(timer) { _ in updateMetrics() }
        .onKeyPress(.escape) { close(); return .handled }
        .onKeyPress(.delete) { close(); return .handled }
    }

    private func statusLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.2))
    }

    private func updateMetrics() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        currentTime = formatter.string(from: Date())

        // Approximate memory usage
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            memoryUsage = Double(info.resident_size) / (1024 * 1024)
        }

        // Simple CPU estimate
        cpuUsage = Double.random(in: 0.02...0.08) // Placeholder

        // Network check
        isOnline = true // Simplified

        // Sync (FPS stability)
        syncValue = min(Double.random(in: 0.92...1.0), 1.0)
    }

    private func close() {
        withAnimation { appState.showStatusPanel = false }
    }
}
