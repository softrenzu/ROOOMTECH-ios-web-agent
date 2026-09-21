import Foundation

struct PageSnapshot: Codable {
    struct Element: Codable, Identifiable {
        let id: String
        let tag: String
        let text: String
        let ariaLabel: String?
        let placeholder: String?
        let type: String?
        let href: String?
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    let title: String
    let url: String
    let bodyText: String
    let viewportWidth: Double
    let viewportHeight: Double
    let elements: [Element]
}

struct AgentAction: Codable {
    let type: String
    let target: String?
    let text: String?
    let url: String?
    let delta: Double?
    let message: String?
}

enum AgentError: LocalizedError {
    case noWebView
    case invalidSnapshot
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case actionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noWebView:
            return "ブラウザが準備できていません。"
        case .invalidSnapshot:
            return "ページ情報を取得できませんでした。"
        case .missingAPIKey:
            return "Anthropic APIキーを設定してください。"
        case .invalidResponse:
            return "Claudeの応答を解釈できませんでした。"
        case .apiError(let message):
            return "Claude APIエラー: \(message)"
        case .actionFailed(let message):
            return "画面操作に失敗しました: \(message)"
        }
    }
}
