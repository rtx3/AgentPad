[English](../../README.md)

# AgentPad

ゲームコントローラで macOS の AI コーディングエージェント（Claude Code / Cursor / Codex など）を操作するためのツール。手をパッドに置いたまま、approve / reject / diff スクロール / hunk 切替 / chat 送信を行えます。

ベースは macOS 向け Joy-Con / Pro Controller / Famicom / SNES Controller のキーマッパーです。

![screenshot](screenshot_1.png)

## なぜ AgentPad

エージェントセッションは小さな yes/no 判断の連続です。キーボードショートカットでも操作できますが、読みながら手を離すのは煩わしい。AgentPad はゲームコントローラを **エージェント専用リモコン** に変えます。

- **両手の親指だけで approve / reject** — A / B を `y` / `n`、もしくはエージェント側のショートカットへ割り当て。
- **アプリ別プロファイル** — Terminal の Claude Code、Cursor、ブラウザでそれぞれ別マッピング。フロント切替時に自動で追従。
- **ゲーム時はパススルー** — 指定アプリではコントローラを横取りせず、純正ゲームパッドとして振る舞います。

### 例：Terminal の Claude Code

| ボタン | 動作 |
| --- | --- |
| A | `y`（approve） |
| B | `n`（reject） |
| L / R | 上 / 下スクロール |
| Start | `Ctrl+C` |
| Home | ターミナルにフォーカス / プロファイル切替 |

## 機能

- ボタン / スティック → キーボードキー、マウスボタン、システムアクションへマッピング。
- **アプリ別マッピング** — フロントアプリに応じて自動切替。
- **シンプルキャプチャモード** — キーボードを 1 度押すだけで割当 & 自動確定。組合せキーは詳細モードで対応。
- **Sync from Default** — デフォルトプロファイルを 1 クリックでアプリ別マッピングに上書き（Undo 対応）。
- **アプリ別パススルー** — 指定アプリではマッピングを行わず、純正ゲームパッドとして使えます。
- **コントローラ一覧にモデル名を表示**（Joy-Con (L) / Joy-Con (R) / Pro Controller / SNES / Famicom 1 / Famicom 2）。
- **アクセシビリティ権限のガイド** — 初回起動時にシステム権限の付与手順を案内。
- システム外観（ライト / ダーク）に追従する AppKit ネイティブ UI。

現在対応するコントローラ：Joy-Con (L) / Joy-Con (R) / Pro Controller / Famicom 1・2 / SNES Online Controller。DualShock 4 / DualSense / Xbox / MFi は今後対応予定（[docs/plan.md](../../docs/plan.md) 参照）。

## GitHub からインストール

1. [Releases](<TODO: repo-url>/releases) から `AgentPad-vX.X.X.dmg` をダウンロード。
2. `AgentPad.app` を `/Applications` にコピー。

![screenshot_install](screenshot_2.png)

## 使い方

1. Bluetooth でコントローラを Mac に接続

    1.1. 「システム設定」>「Bluetooth」を開く

    1.2. コントローラのシンクロボタンを長押し

    1.3. Mac で「接続」ボタンを押す

    ![screenshot_usage_1_3](screenshot_3.png)

2. キー設定

    2.1 AgentPad.app を起動

    2.2 メニューから「設定…」を選択

    ![screenshot_usage_2_2](screenshot_4.png)

    2.3 アプリ別マッピングを行うアプリを追加（任意）。**Sync from Default** でデフォルトマッピングをコピー、**Passthrough** チェックボックスで対象アプリではマッピングを停止できます。

    ![screenshot_usage_2_3](screenshot_5.png)

    2.4 ボタンをクリックしてキー設定。キャプチャダイアログには 2 つのモード：

    - **Simple** — キーを 1 度押すだけで割当、自動でクローズ。
    - **Detailed** — キー + ⌘ / ⌥ / ⌃ / ⇧ 修飾キー、もしくはマウスボタンを選択。

    ![screenshot_usage_2_4_1](screenshot_6.png)

    ![screenshot_usage_2_4_2](screenshot_7.png)

3. AgentPad に「アクセシビリティ」を許可

    3.1 コントローラ使用時にアプリ内ガイド（またはシステムアラート）が表示されます。

    ![screenshot_usage_3_1](screenshot_8.png)

    3.2 「システム設定」>「プライバシーとセキュリティ」>「アクセシビリティ」で「AgentPad.app」を有効化。

    ![screenshot_usage_3_2](screenshot_9.png)

## ロードマップ

- `GameController.framework` 経由で DualShock 4 / DualSense / Xbox / MFi に対応。
- GitHub 配布版に Sparkle 2 で自動アップデート。

詳細は [docs/plan.md](../../docs/plan.md) を参照。

## ソースからビルド

Xcode と CocoaPods が必要です。

```sh
pod install
open AgentPad.xcworkspace
```

`AgentPad` スキームでビルド & 実行。

## 参考

[JoyConSwift](https://github.com/magicien/JoyConSwift) — Joy-Con / Pro Controller 用 IOKit ラッパー（macOS, Swift）。AgentPad の Joy-Con バックエンドで利用しています。
