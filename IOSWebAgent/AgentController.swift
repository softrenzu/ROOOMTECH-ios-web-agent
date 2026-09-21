import Foundation

@MainActor
final class AgentController: ObservableObject {
    @Published var isRunning = false
    @Published var status = "待機中"
    @Published var lastAction = ""
    @Published var confirmationMessage: String?
    @Published var errorMessage: String?

    private weak var browser: BrowserController?
    private let keychain = KeychainStore()
    private var shouldStop = false
    private var confirmationContinuation: CheckedContinuation<Bool, Never>?

    func attach(browser: BrowserController) {
        self.browser = browser
    }

    func saveAPIKey(_ key: String) throws {
        try keychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func hasAPIKey() -> Bool {
        !(keychain.read() ?? "").isEmpty
    }

    func run(goal: String) {
        guard !isRunning else { return }
        shouldStop = false
        errorMessage = nil
        Task { await runLoop(goal: goal) }
    }

    func stop() {
        shouldStop = true
        isRunning = false
        status = "停止しました"
    }

    func resolveConfirmation(approved: Bool) {
        confirmationMessage = nil
        confirmationContinuation?.resume(returning: approved)
        confirmationContinuation = nil
    }

    private func runLoop(goal: String) async {
        guard let browser else {
            errorMessage = AgentError.noWebView.localizedDescription
            return
        }
        guard let apiKey = keychain.read(), !apiKey.isEmpty else {
            errorMessage = AgentError.missingAPIKey.localizedDescription
            return
        }
        guard !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isRunning = true
        status = "AIが画面を確認中"
        var history: [String] = []
        var approvedConfirmation: String?

        defer {
            isRunning = false
            if status != "完了" && !shouldStop && errorMessage == nil {
                status = "停止"
            }
        }

        do {
            for step in 1...30 {
                if shouldStop { return }
                status = "画面確認 \(step)/30"
                let snapshot = try await browser.snapshot()

                let client = ClaudeClient()
                var contextHistory = history
                if let approvedConfirmation {
                    contextHistory.append("USER APPROVED: \(approvedConfirmation)")
                }

                status = "次の操作を判断中"
                let action = try await client.nextAction(
                    apiKey: apiKey,
                    goal: goal,
                    snapshot: snapshot,
                    history: contextHistory
                )
                lastAction = describe(action)

                if action.type == "done" {
                    status = "完了"
                    return
                }

                if action.type == "confirm" {
                    let message = action.message ?? "この操作を実行してよいですか？"
                    let approved = await requestConfirmation(message)
                    if !approved {
                        status = "ユーザーがキャンセルしました"
                        return
                    }
                    approvedConfirmation = message
                    history.append("confirm approved: \(message)")
                    continue
                }

                approvedConfirmation = nil
                status = "操作中: \(describe(action))"
                try await browser.execute(action)
                history.append(describe(action))
                try await Task.sleep(nanoseconds: action.type == "navigate" || action.type == "tap" ? 1_300_000_000 : 450_000_000)
            }
            status = "最大操作回数に到達"
        } catch {
            errorMessage = error.localizedDescription
            status = "エラー"
        }
    }

    private func requestConfirmation(_ message: String) async -> Bool {
        confirmationMessage = message
        return await withCheckedContinuation { continuation in
            confirmationContinuation = continuation
        }
    }

    private func describe(_ action: AgentAction) -> String {
        switch action.type {
        case "tap": return "tap \(action.target ?? "")"
        case "input": return "input \(action.target ?? "")"
        case "scroll": return "scroll \(Int(action.delta ?? 650))"
        case "navigate": return "navigate \(action.url ?? "")"
        case "back": return "back"
        case "wait": return "wait"
        case "confirm": return "confirm \(action.message ?? "")"
        case "done": return "done"
        default: return action.type
        }
    }
}
