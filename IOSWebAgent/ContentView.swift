import SwiftUI

struct ContentView: View {
    @ObservedObject var browser: BrowserController
    @ObservedObject var agent: AgentController

    @State private var address = "https://www.google.com"
    @State private var goal = ""
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            browserBar
            Divider()
            BrowserView(browser: browser)
            Divider()
            agentPanel
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(agent: agent)
        }
        .alert("確認が必要です", isPresented: Binding(
            get: { agent.confirmationMessage != nil },
            set: { if !$0 && agent.confirmationMessage != nil { agent.resolveConfirmation(approved: false) } }
        )) {
            Button("キャンセル", role: .cancel) { agent.resolveConfirmation(approved: false) }
            Button("実行する") { agent.resolveConfirmation(approved: true) }
        } message: {
            Text(agent.confirmationMessage ?? "")
        }
        .alert("エラー", isPresented: Binding(
            get: { agent.errorMessage != nil },
            set: { if !$0 { agent.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { agent.errorMessage = nil }
        } message: {
            Text(agent.errorMessage ?? "")
        }
    }

    private var browserBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    browser.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)

                TextField("URL", text: $address)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { browser.load(address) }

                Button {
                    browser.load(address)
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderless)

                Button {
                    browser.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            if browser.isLoading {
                ProgressView()
                    .progressViewStyle(.linear)
            }
        }
        .onChange(of: browser.currentURL) { _, newValue in
            address = newValue
        }
    }

    private var agentPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("このページで何をするか入力", text: $goal, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)

                if agent.isRunning {
                    Button("停止", role: .destructive) {
                        agent.stop()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("実行") {
                        agent.run(goal: goal)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            HStack {
                Text(agent.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !agent.lastAction.isEmpty {
                    Text(agent.lastAction)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var agent: AgentController
    @State private var apiKey = ""
    @State private var saved = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Anthropic API") {
                    SecureField("sk-ant-...", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("APIキーを保存") {
                        do {
                            try agent.saveAPIKey(apiKey)
                            apiKey = ""
                            saved = true
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if agent.hasAPIKey() || saved {
                        Label("APIキー保存済み", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)

                        Button("保存したAPIキーを削除", role: .destructive) {
                            do {
                                try agent.deleteAPIKey()
                                saved = false
                                apiKey = ""
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                }

                Section("ログイン") {
                    Text("各サイトのログイン情報はAIに渡しません。ログイン画面ではiPhoneのパスワード自動入力などを使って手動でログインしてください。ログイン後のCookieはアプリ内ブラウザで継続利用します。")
                }

                Section("動作範囲") {
                    Text("このアプリ内のWebページを操作します。iPhone上の他アプリを直接操作することはできません。")
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("保存エラー", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }
}
