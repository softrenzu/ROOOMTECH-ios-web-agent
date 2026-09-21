# iOS Web Agent

iPhone上で「Claude in Chrome」に近いWeb画面操作を行うためのMVPです。

## できること

- アプリ内ブラウザ（WKWebView）でWebサイトを表示
- 日本語の指示から次の操作をClaudeに判断させる
- リンク・ボタンのクリック
- フォームへの文字入力
- スクロール、戻る、URL移動
- DOM要素を十分に取得できないページでは、必要時だけ画面画像をClaudeへ送り座標操作を補助
- JavaScriptのalert / confirm / promptに対応
- 送信・購入・予約・削除・公開などの重要操作の前にユーザー確認
- Anthropic APIキーをKeychainに保存・削除
- WKWebViewの通常データストアを利用するため、アプリ内でのCookie・ログイン状態を継続利用

## iPhone上の制約

このアプリが自動操作できるのは、アプリ自身のWKWebView内に表示したWebページです。iOSの仕様上、一般のApp StoreアプリからLINE、設定、銀行アプリなど他アプリの画面を自由にタップすることはできません。

SafariのCookieやログイン状態はこのアプリへ自動共有されません。対象サイトには原則としてこのアプリ内で一度ログインします。Safariで直接動かす方式はSafari Web Extensionとして次段階で追加できます。

## 開発環境

- Xcode 16以降を推奨
- iOS 17.0以降
- SwiftUI / WebKit
- Anthropic Messages API
- 既定モデル: `claude-sonnet-4-6`
- GitHub ActionsでiOS Simulator向けビルドを自動検証

## 起動

1. `IOSWebAgent.xcodeproj` をXcodeで開く
2. Signing & Capabilitiesで自分のTeamを選ぶ
3. iPhoneまたはSimulatorでRun
4. 右上の歯車からAnthropic APIキーを保存
5. URLを開き、画面下部に自然言語で操作内容を入力して「実行」

## 例

- `このサイトの料金ページを開いて`
- `お問い合わせフォームの名前に吉岡祐と入力して。送信はしないで`
- `予約できる最も早い日を探して`

## セキュリティ

- APIキーはソースコードに保存せずKeychainに保存します。
- 設定画面から保存済みAPIキーを削除できます。
- パスワード、暗証番号、ワンタイムコード、カード番号、CVV/CVCなどの機密入力値はページスナップショットに含めません。
- 機密項目へのAI自動入力は拒否し、ユーザーの手動入力を要求します。
- 機密項目が検出される画面ではスクリーンショットをClaudeへ送りません。
- 座標タップはDOMで対象の意味を検証できないため、実行前に必ず確認します。
- CAPTCHAや認証回避を目的とする操作は実装していません。
- 実運用ではAnthropic APIを直接アプリから呼ばず、自社バックエンド経由にしてAPIキーをサーバー側で管理する構成を推奨します。

## 現在のMVP制約

- cross-origin iframe内部のDOMは直接読めない場合があります。
- canvasだけで描画されたUIはDOM要素として取得できないため、画面画像フォールバックを使う場合があります。
- OAuthプロバイダによっては埋め込みブラウザでのログインを拒否します。
- Safari側ですでにログイン済みでも、そのセッションをWKWebViewへそのまま移すことはできません。
- App Store公開前にはプライバシーポリシー、データ送信表示、APIキー管理方式の見直しが必要です。

## CI

`main`へのpushごとにGitHub ActionsでXcodeビルドを実行します。成功時は`IOSWebAgent-Simulator`というSimulator用成果物も生成します。実機iPhone向け署名済みIPA/TestFlight配信にはApple Developerの署名設定が別途必要です。
