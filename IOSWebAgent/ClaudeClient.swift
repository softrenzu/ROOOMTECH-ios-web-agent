import Foundation

struct ClaudeClient {
    var model: String = "claude-sonnet-4-6"

    func nextAction(
        apiKey: String,
        goal: String,
        snapshot: PageSnapshot,
        history: [String]
    ) async throws -> AgentAction {
        let pageData = try JSONEncoder().encode(snapshot)
        guard let pageJSON = String(data: pageData, encoding: .utf8) else {
            throw AgentError.invalidSnapshot
        }

        let historyText = history.suffix(10).joined(separator: "\n")
        let prompt = """
        USER GOAL:
        \(goal)

        RECENT ACTIONS:
        \(historyText.isEmpty ? "none" : historyText)

        CURRENT PAGE SNAPSHOT:
        \(pageJSON)

        Decide exactly one next browser action. Return only a JSON object matching this schema:
        {"type":"tap|input|scroll|navigate|back|wait|confirm|done","target":"element id or null","text":"text or null","url":"url or null","delta":650,"message":"short reason or null"}
        """

        let system = """
        You are a cautious iPhone web-navigation agent operating only inside a WKWebView.
        Use element IDs from the snapshot whenever possible. Never invent an element ID.
        Do not read or expose password values. Do not attempt to bypass authentication, CAPTCHAs, paywalls, or site security.
        Before any consequential action that could send a message, submit a form with external effect, make a purchase/payment, publish/post, delete data, change account/security settings, or finalize a booking/order, return type=confirm with a clear Japanese message describing the exact action. After the user approves, choose the actual tap/input action.
        If the goal is satisfied, return type=done. If the page is still loading or navigation just happened, use wait.
        Output JSON only, without Markdown fences.
        """

        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 700,
            "system": system,
            "messages": [["role": "user", "content": prompt]]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AgentError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgentError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AgentError.apiError(text)
        }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? [[String: Any]],
              let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String else {
            throw AgentError.invalidResponse
        }

        let jsonText = extractJSONObject(from: text)
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw AgentError.invalidResponse
        }
        return try JSONDecoder().decode(AgentAction.self, from: jsonData)
    }

    private func extractJSONObject(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{" && trimmed.last == "}" {
            return trimmed
        }
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            return trimmed
        }
        return String(trimmed[start...end])
    }
}
