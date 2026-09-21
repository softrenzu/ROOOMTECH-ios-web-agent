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
    private var runTask: Task<Void, Never>?

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
        runTask = Task { await runLoop(goal: goal) }
    }

    func stop() {
        shouldStop = true
        runTask?.cancel()
        runTask = nil
        if confirmationContinuation != nil {
            resolveConfirmation(approved: false)
        }
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
        var confirmationCredit = 0

        defer {
            isRunning = false
            runTask = nil
            if status != "完了" && !shouldStop && errorMessage == nil {
                status = "停止"
            }
        }

        do {
            for step in 1...30 {
                try Task.checkCancellation()
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
                    confirmationCredit = 2
                    history.append("confirm approved: \(message)")
                    continue
                }

                if action.type == "input",
                   let target = action.target,
                   let element = snapshot.elements.first(where: { $0.id == target }),
                   element.sensitive {
                    errorMessage = "パスワード、暗証番号、ワンタイムコード、カード情報などの機密項目はAIに入力させません。画面で手動入力してから、もう一度実行してください。"
                    status = "機密情報の手動入力が必要"
                    return
                }

                if let localMessage = localSafetyMessage(for: action, snapshot: snapshot) {
                    if confirmationCredit > 0 {
                        confirmationCredit = 0
                    } else {
                        let approved = await requestConfirmation(localMessage)
                        if !approved {
                            status = "ユーザーがキャンセルしました"
                            return
                        }
                    }
                } else if confirmationCredit > 0 {
                    confirmationCredit -= 1
                }

                approvedConfirmation = nil
                status = "操作中: \(describe(action))"
                do {
                    try await browser.execute(action)
                } catch AgentError.actionFailed(let message) {
                    history.append("ACTION FAILED: \(message). Re-read the page and choose another target.")
                    status = "画面が変化したため再判定中"
                    continue
                }
                history.append(describe(action))

                if action.type == "navigate" || action.type == "tap" {
                    try await browser.waitForPageSettled()
                } else {
                    try await Task.sleep(for: .milliseconds(350))
                }
            }
            status = "最大操作回数に到達"
        } catch is CancellationError {
            status = "停止しました"
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

    private func localSafetyMessage(for action: AgentAction, snapshot: PageSnapshot) -> String? {
        guard action.type == "tap", let target = action.target,
              let element = snapshot.elements.first(where: { $0.id == target }) else {
            return nil
        }

        let context = [
            element.text,
            element.ariaLabel ?? "",
            element.placeholder ?? "",
            element.href ?? "",
            element.formAction ?? ""
        ].joined(separator: " ").lowercased()

        let consequentialTerms = [
            "購入", "注文", "予約", "送信", "削除", "公開", "投稿", "支払", "決済", "振込", "確定", "申込", "申し込", "応募", "解約", "退会", "登録",
            "buy", "purchase", "order", "book", "reserve", "send", "submit", "delete", "remove", "publish", "post", "pay", "payment", "transfer", "confirm", "apply", "unsubscribe", "cancel subscription"
        ]

        guard consequentialTerms.contains(where: { context.contains($0) }) else {
            return nil
        }

        let label = element.text.isEmpty ? (element.ariaLabel ?? "このボタン") : element.text
        return "「\(label)」を実行しようとしています。外部への送信・購入・予約・削除などの結果が発生する可能性があります。実行しますか？"
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
