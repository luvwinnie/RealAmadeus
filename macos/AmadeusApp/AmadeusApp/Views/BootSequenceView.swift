import SwiftUI

struct BootSequenceView: View {
    @EnvironmentObject var appState: AppState
    @State private var visibleLines: [String] = []
    @State private var memoryCount = 0
    @State private var showLogo = false
    @State private var currentPhase: BootPhase = .terminal

    private let maxMemory = 32767

    enum BootPhase {
        case terminal, logo, done
    }

    private let bootLines: [BootLine] = [
        .init(text: "Amadeus System Ver 1.09.2 rev.2123", delay: 0.05),
        .init(text: ">>Initialize System ...  OK", delay: 0.4),
        .init(text: ">>Detecting boot device ... OK", delay: 0.4),
        .init(text: ">>Loading Kerner ...  OK", delay: 0.4),
        .init(text: ">>Detecting OS control device ...  OK", delay: 0.4),
        .init(text: ">>Booting ...", delay: 0.4),
        .init(text: ">>Processor 0 is Activate ...  OK", delay: 0.05),
        .init(text: ">>Processor 1 is Activate ...  OK", delay: 0.05),
        .init(text: ">>Processor 2 is Activate ...  OK", delay: 0.05),
        .init(text: ">>Processor 3 is Activate ...  OK", delay: 0.05),
        .init(text: ">>Memory Initialize [MEM]/32767MBytes", delay: 0.05, isMemoryLine: true),
        .init(text: "", delay: 0.05),
        .init(text: "INIT: Kernel version 2.04 booting...", delay: 0.4),
        .init(text: "", delay: 0.05),
        .init(text: "ROSS:", delay: 0.4),
        .init(text: "", delay: 0.05),
        .init(text: "Mounting proc at /proc...                [OK]", delay: 0.05),
        .init(text: "Mounting sysfs at /sts...                [OK]", delay: 0.05),
        .init(text: "Initakising network                      [OK]", delay: 0.05),
        .init(text: "Setting up localhost ...                  [OK]", delay: 0.05),
        .init(text: "Setting up inet1 ...                     [OK]", delay: 0.05),
        .init(text: "Setting up route ...                     [OK]", delay: 0.05),
        .init(text: "Accessing Croud ...                      [OK]", delay: 0.05),
        .init(text: "Starting system log at /log/sys...       [OK]", delay: 0.05),
        .init(text: "Cleaning /var/lock                       [OK]", delay: 0.05),
        .init(text: "Cleaning /tmp                            [OK]", delay: 0.05),
        .init(text: "Updating init.rc                         [OK]", delay: 0.05),
        .init(text: "", delay: 0.05),
        .init(text: "Boot Sequences Start...", delay: 0.4),
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch currentPhase {
            case .terminal:
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(visibleLines.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(Color(red: 0.0, green: 0.85, blue: 0.0))
                                    .id(idx)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                    }
                    .onChange(of: visibleLines.count) { _ in
                        withAnimation {
                            proxy.scrollTo(visibleLines.count - 1, anchor: .bottom)
                        }
                    }
                }

            case .logo:
                VStack {
                    Text("AMADEUS")
                        .font(.system(size: 72, weight: .thin, design: .monospaced))
                        .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.2))
                        .tracking(16)
                        .opacity(showLogo ? 1 : 0)
                        .animation(.easeIn(duration: 1.0), value: showLogo)
                }

            case .done:
                EmptyView()
            }
        }
        .onAppear {
            Task { await runBootSequence() }
        }
    }

    @MainActor
    private func runBootSequence() async {
        // Terminal phase
        for bootLine in bootLines {
            if bootLine.isMemoryLine {
                // Animate memory counter
                let steps = 30
                let duration = 1.5
                let stepDelay = duration / Double(steps)

                for i in 0...steps {
                    let val = Int(Double(maxMemory) * Double(i) / Double(steps))
                    let line = ">>Memory Initialize \(val)/32767MBytes"
                    if visibleLines.count > 0 && visibleLines.last?.contains("Memory Initialize") == true {
                        visibleLines[visibleLines.count - 1] = line
                    } else {
                        visibleLines.append(line)
                    }
                    try? await Task.sleep(nanoseconds: UInt64(stepDelay * 1_000_000_000))
                }
            } else {
                visibleLines.append(bootLine.text)
            }
            try? await Task.sleep(nanoseconds: UInt64(bootLine.delay * 1_000_000_000))
        }

        // Wait after boot
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        // Logo phase
        currentPhase = .logo
        try? await Task.sleep(nanoseconds: 200_000_000)
        showLogo = true
        try? await Task.sleep(nanoseconds: 4_000_000_000)

        // Transition to main
        currentPhase = .done
        appState.currentScreen = .main
    }
}

private struct BootLine {
    let text: String
    let delay: TimeInterval
    var isMemoryLine: Bool = false
}
