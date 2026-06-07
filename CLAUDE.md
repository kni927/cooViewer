# CLAUDE.md

## プロジェクト概要
cooViewer — macOS向けシンプルコミックビューワー（Objective-C / Cocoa）

## 技術スタック
- Language: Objective-C
- Framework: Cocoa (AppKit)
- Build: Xcode / xcodebuild
- Submodules: XADMaster（アーカイブ展開）、UniversalDetector（文字コード検出）

## セットアップ
```bash
git clone --recursive https://github.com/<yourname>/cooViewer.git
cd cooViewer
xcodebuild -configuration Deployment
open build/Deployment/cooViewer.app
```

## ビルドコマンド
```bash
xcodebuild -configuration Deployment   # リリースビルド
xcodebuild -configuration Debug        # デバッグビルド
```
※ テスト自動化なし。動作確認は手動。

## 主要ファイル
- Controller.m / Controller.h       — メインコントローラー（ページ制御・UI全般）
- Controller_input.m                — キー・マウス入力処理
- CustomImageView.m / .h            — 画像表示View
- AccessoryView.m / .h              — ページバー（下部HUD）
- COImageLoader.m / .h              — 画像・アーカイブ読み込み

## コーディングルール
- Objective-C (MRC / ARC混在に注意。基本MRC)
- IBOutlet / IBAction の変更はInterface Builder (.xib) も合わせて編集すること
- NSUserDefaults のキー追加時はawakeFromNib内でdefault値を登録する
- ローカライズ文字列はen.lproj / ja.lproj の Localizable.strings に追加する

## 変更禁止
- XADMaster/, UniversalDetector/ — サブモジュール。直接編集しない
- MainMenu~.nib — レガシーnib。触らない

## コミットルール
- prefix: feat: / fix: / refactor: / docs:
- 1機能1コミット推奨
