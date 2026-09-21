import SwiftUI

struct ContentView: View {
    @ObservedObject var browser: BrowserController
    @ObservedObject var agent: AgentController

    @State private var address = "https://www.google.com"
    @State private var goal = ""
    @State private var showSettings = false
    @State private var tranbiStatus = "未確認"
    @State private var checkingTranbiStatus = false

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
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            HStack(spacing: 8) {
                Menu {
                    Button("ログイン画面") {
                        browser.load("https://www.tranbi.com/login/")
                        tranbiStatus = "ログインしてください"
                    }
                    Button("売却交渉オファー一覧") {
                        browser.load("https://www.tranbi.com/sell/list/")
                        tranbiStatus = "確認中"
                        Task { await refreshTranbiStatus() }
                    }
                    Button("公式自動オファー設定") {
                        browser.load("https://www.tranbi.com/mypage/sell/case/")
                        tranbiStatus = "確認中"
                        Task { await refreshTranbiStatus() }
                    }
                } label: {
                    Label("TRANBI", systemImage: "briefcase")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    Task { await refreshTranbiStatus() }
                } label: {
                    if checkingTranbiStatus {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.shield")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("TRANBIログイン状態を確認")

                Text(tranbiStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 10)

            if browser.isLoading {
                ProgressView()
                    .progressViewStyle(.linear)
            }
        }
        .onChange(of: browser.currentURL) { _, newValue in
            address = newValue
            if newValue.contains("tranbi.com") {
                Task { await refreshTranbiStatus() }
            }
        }
    }

    private var agentPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("例: 条件に合う候補を確認して。送信はしないで", text: $goal, axis: .vertical)
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

    @MainActor
    private func refreshTranbiStatus() async {
        guard !checkingTranbiStatus else { return }
        checkingTranbiStatus = true
        defer { checkingTranbiStatus = false }
        tranbiStatus = await browser.tranbiSessionStatus()
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

                Section("TRANBIログイン") {
                    Text("TRANBIログイン画面のメールアドレスまたはパスワード欄をタップし、iPhoneのパスワード自動入力からChromeに保存したTRANBIの認証情報を選択してください。")
                    Text("ログイン時は「ログイン状態を30日間保持する」を有効にすると、アプリ内ブラウザのセッションを維持しやすくなります。")
                        .foregroundStyle(.secondary)
                }

                Section("TRANBIオファー") {
                    Text("TRANBI公式の自動オファー機能は、上部のTRANBIメニューから「公式自動オファー設定」を開いて設定できます。")
                    Text("外部ソフトによる自動投稿はTRANBIのルール上制限されているため、本アプリは候補検索・分析を支援し、公式自動オファー機能を優先します。")
                        .foregroundStyle(.secondary)
                }

                Section("動作範囲") {
                    Text("このアプリ内のWebページだけを操作します。iPhone上の他アプリを自動操作することはできません。")
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
