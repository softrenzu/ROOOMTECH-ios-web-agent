# iOS Web Agent

iPhone上で「Claude in Chrome」に近いWeb画面操作を行うためのMVPです。

## できること

- アプリ内ブラウザ（WKWebView）でWebサイトを表示
- 日本語の指示から次の操作をClaudeに判断させる
- リンク・ボタンのクリック
- フォームへの文字入力
- スクロール、戻る、URL移動
- 送信・購入・削除・公開などの重要操作の前にユーザー確認
- Anthropic APIキーをKeychainに保存

## iPhone上の制約

このアプリが自動操作できるのは、アプリ自身のWKWebView内に表示したWebページです。iOSの仕様上、一般のApp StoreアプリからLINE、設定、銀行アプリなど他アプリの画面を自由にタップすることはできません。

Safariで直接動かす方式は、次段階としてSafari Web Extensionを追加できます。

## 開発環境

- Xcode 16以降を推奨
- iOS 17.0以降
- SwiftUI / WebKit
- Anthropic Messages API
- 既定モデル: `claude-sonnet-4-6`

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
- パスワード入力欄の値はページスナップショットに含めません。
- CAPTCHAや認証回避を目的とする操作は実装していません。
- 実運用ではAnthropic APIを直接アプリから呼ばず、自社バックエンド経由にしてAPIキーをサーバー側で管理する構成を推奨します。

## 現在のMVP制約

- cross-origin iframe内部のDOMは直接読めない場合があります。
- canvasだけで描画されたUIはDOM要素として取得できない場合があります。
- OAuthプロバイダによっては埋め込みブラウザでのログインを拒否します。
- App Store公開前にはプライバシーポリシー、データ送信表示、APIキー管理方式の見直しが必要です。
