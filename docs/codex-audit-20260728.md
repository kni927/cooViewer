# Multi-window 対応 調査レポート

## 結論

Multi-window 対応は可能ですが、現在の `Controller` を単純に複製する実装は危険です。

推奨方針は、`NSDocument` への全面移行ではなく、まず次の構成へ段階的に分離することです。

- アプリ単位: `AppController` / `AppDelegate`
- ウィンドウ単位: `BookWindowController : NSWindowController`
- 閲覧セッション単位: 当面は既存 `Controller` を再利用し、1ウィンドウにつき1インスタンス
- 共通永続化: Recent Items、Book Settings、Preferencesを専用サービス経由で更新

一括改修ではなく、複数タスクに分けるべき規模です。

## 現在の制約

過去調査の内容は現在のコードにも当てはまります。

- `NSDocument`、`NSWindowController` は使用されていません。
- `MainMenu.xib` がアプリ起動時に、唯一のウィンドウと唯一の `Controller` を生成します。
- `Controller` が以下をすべて兼任しています。

  - `NSApplicationDelegate`
  - `NSWindowDelegate`
  - ファイルを開く処理
  - ページ・画像キャッシュ・表示状態
  - スライドショー
  - Recent ItemsとBook Settingsの永続化
  - メニュー状態
  - Apple Remote
  - アーカイブ進捗とパスワードUI

これは[過去の監査](/Users/kni/Projects/GitHub/cooViewer/docs/audit-20260711.md:10)でも指摘されています。現在も [`Controller` は `NSObject` のまま](/Users/kni/Projects/GitHub/cooViewer/Sources/Controller.h:19)で、約6,800行の `Controller.m`＋`Controller_input.m`に処理が集中しています。

さらに、`MainMenu.xib`には `Controller` オブジェクト484を直接参照するaction/outletが42件あります。例:

- [唯一のViewerウィンドウ](/Users/kni/Projects/GitHub/cooViewer/Resources/Base.lproj/MainMenu.xib:15)
- [唯一のController](/Users/kni/Projects/GitHub/cooViewer/Resources/Base.lproj/MainMenu.xib:1895)
- [BookmarkController → Controller](/Users/kni/Projects/GitHub/cooViewer/Resources/Base.lproj/MainMenu.xib:2161)
- [ThumbnailController → Controller](/Users/kni/Projects/GitHub/cooViewer/Resources/Base.lproj/MainMenu.xib:2674)
- [PreferenceController → Controller](/Users/kni/Projects/GitHub/cooViewer/Resources/Base.lproj/MainMenu.xib:2863)
- [AccessoryView → Controller](/Users/kni/Projects/GitHub/cooViewer/Resources/Base.lproj/MainMenu.xib:3322)

過去のFinderダブルクリック対応でも、multi-windowは明示的に対象外として扱われています。[該当記録](/Users/kni/Projects/GitHub/cooViewer/docs/tasks/2026-07-15-02-doubleclick-open-investigation.md:9)

## 単純な複製で問題になる部分

### 終了と永続化

[`windowWillClose:`](/Users/kni/Projects/GitHub/cooViewer/Sources/Controller.m:2902)が、ウィンドウ固有の後始末だけでなく以下も実行しています。

- Book Settings更新
- Recent Items更新
- Last Pages更新
- 共通メニューの内容削除
- キャッシュ・ローダー破棄

2つのウィンドウが近いタイミングで閉じると、`NSUserDefaults`のread-modify-writeが競合し、後から閉じたウィンドウが先の更新を消す可能性があります。

### 非同期処理

先読み処理は`NSThread`、共有配列、`threadStop`、`threadCount`、spin-waitを使用しています。各Controller内に閉じていれば動作する可能性はありますが、ウィンドウを閉じた後のスレッド寿命やUIコールバックが明確ではありません。

特に、ウィンドウ解放前に全処理を確実に停止する仕組みが必要です。

### アーカイブ読み込み

アーカイブ読み込みはメインスレッド上で同期的に行われ、進捗表示中に[`nextEventMatchingMask:`でアプリ全体のイベントを取り出しています](/Users/kni/Projects/GitHub/cooViewer/Sources/Controller.m:1134)。

multi-windowでは、一方のウィンドウの読み込みが以下を引き起こします。

- 他ウィンドウも操作不能になる
- 他ウィンドウ宛てイベントを読み込み側が消費する
- Escがどの読み込みをキャンセルしたのか曖昧になる

また、パスワード入力は[`NSAlert runModal`](/Users/kni/Projects/GitHub/cooViewer/Sources/Controller.m:1161)なので、対象ウィンドウのsheetではなくアプリ全体をブロックします。

### Fullscreenとウィンドウ位置

[`CustomWindow`](/Users/kni/Projects/GitHub/cooViewer/Sources/CustomWindow.m:6)は全ウィンドウ共通の`"NormalWindow"`キーを使い、メニューバー表示をプロセス全体で変更しています。

複数ウィンドウでは次が競合します。

- ウィンドウ位置・サイズ
- fullscreen状態
- メニューバーの表示
- `mainScreen`への強制配置

### Remoteと入力

`Controller`ごとにApple Remoteを初期化すると、排他デバイスの多重登録になります。Remoteはアプリ側で1つだけ所有し、イベントをkey windowへ転送する必要があります。

## 推奨アーキテクチャ

### AppController / AppDelegate

アプリ全体で1つだけ所有します。

- `NSApplicationDelegate`
- 開くファイルの振り分け
- 開いている`BookWindowController`一覧
- Preferencesウィンドウ
- Apple Remote / global keyboard
- Recent Items
- Book Settings永続化
- Dock menu
- アプリ終了処理

### BookWindowController

1ウィンドウにつき1インスタンスとします。

- `CustomWindow`
- `CustomImageView`
- `AccessoryView`
- 現在の本、ページ、表示モード
- `COImageLoader`
- 画像キャッシュ
- slideshow timer
- 先読み処理
- archive progress
- password sheet
- ウィンドウ固有メニュー検証

AppKitでも、Nibごとにウィンドウを生成・所有する用途は`NSWindowController`の担当とされています。[Apple NSWindowController](https://developer.apple.com/documentation/appkit/nswindowcontroller?language=objc)

### 補助コントローラ

| コントローラ | 推奨所有範囲 |
|---|---|
| `ThumbnailController` | ウィンドウごと |
| `FilterPanelController` | ウィンドウごと |
| `FullImagePanel` | ウィンドウごと |
| `AccessoryView/Window` | ウィンドウごと |
| `PreferenceController` | アプリ共通 |
| `BookmarkController` | 編集対象はウィンドウごと、全ブック一覧はアプリ共通 |

Preferencesから固定の`Controller`へ通知するのではなく、設定変更通知を全ウィンドウへ配信する構造が適切です。

## NSDocumentを採用しない理由

`NSDocument`は複数ドキュメント、ファイルURL、ウィンドウ、読み書き、close処理を標準化できます。[Apple NSDocument](https://developer.apple.com/documentation/appkit/nsdocument)

ただしcooViewerでは、次の追加改修が必要になります。

- 現在の独自ファイルオープン処理と`NSDocumentController`の統合
- 読み取り専用ドキュメントとしての状態設計
- AppKitのRecent Documentsと既存Recent Itemsの整理
- `readFromURL:`と現在の同期アーカイブ展開の整合
- 保存・revert・duplicate等、不要なdocument動作の抑制
- QuickLookと本体のローダー境界再整理

multi-window実現だけを目的とするなら過剰です。まず独自の`AppController + NSWindowController`構成を推奨します。将来、セッションモデルが分離された後なら`NSDocument`を再評価できます。

## 実装ステップ案

### Step 0: 動作仕様を決定

実装前に次を決める必要があります。

- Finderから開いたファイルは常に新規ウィンドウか
- 同じファイルを再度開いた場合、既存ウィンドウを前面化するか
- File > Openは現在のウィンドウを置換するか、新規ウィンドウか
- 最後のウィンドウを閉じてもアプリを残すか
- 起動時の「最後に読んだ本」は1冊だけ開くか
- fullscreenはウィンドウ単位か
- Thumbnail/Bookmarkパネルをウィンドウごとに持つか

### Step 1: AppControllerを抽出

動作を変えず、現在の1ウィンドウ構成のまま以下を`Controller`から移します。

- application delegate methods
- Remote初期化
- Dock menu
- Preferences
- Recent Items / Book Settings更新
- window registry

この段階ではmulti-windowを有効にしません。

### Step 2: BookWindowControllerを導入

- `BookWindow.xib`を新設
- Viewer本体とウィンドウ固有パネルを`MainMenu.xib`から移動
- 1つの`BookWindowController`がNibのtop-level objectsを所有
- 当面は既存`Controller`を閲覧セッションとして内包
- 既存機能が1ウィンドウで完全に維持されることを確認

`Controller`を最初から全面分割・改名する必要はありません。この方法なら機械的変更を抑えられます。

### Step 3: actionと補助パネルを分離

- メニューactionの固定target 484を解除
- First Responder経由でkey windowへ送る
- Thumbnail、Filter、Full Image、Accessoryをウィンドウ単位で生成
- Preferencesはアプリ共通化
- Bookmarkの共有データと現在ウィンドウ操作を分離

### Step 4: 複数ファイルのルーティング

現在の[`application:openFile:`](/Users/kni/Projects/GitHub/cooViewer/Sources/Controller.m:646)をAppController側へ移します。

複数ファイルを一度に受け取れる`application:openFiles:`相当で、各URLを別の`BookWindowController`へ振り分けます。AppKitには複数ファイル用のdelegate APIがあります。[Apple NSApplicationDelegate](https://developer.apple.com/documentation/appkit/nsapplicationdelegate?changes=latest_major)

### Step 5: lifecycleと並行処理を強化

- `windowWillClose:`を「セッション保存」と「破棄」に分割
- 先読み処理にキャンセルトークン／generationを導入
- ウィンドウ解放後のcallbackを禁止
- archive loadをバックグラウンド化
- progressとpassword promptを対象ウィンドウのsheetに変更
- `NSUserDefaults`の配列・辞書更新をAppController側で直列化
- Remoteイベントをkey windowへルーティング

ここが最も事故リスクの高い工程です。

### Step 6: ウィンドウ固有動作

- fullscreenを可能ならAppKit標準動作へ移行
- `"NormalWindow"`固定キーを廃止
- 新規ウィンドウをcascade配置
- window restorationはmulti-window安定後に追加

### Step 7: 回帰試験

最低限、以下の組み合わせが必要です。

- ZIPとRARを別ウィンドウで同時表示
- 異なるページ、読書方向、ズーム、回転状態
- 一方を閉じても他方が変化しない
- 2つのアーカイブを連続／同時に開く
- パスワード入力が正しいウィンドウに付く
- ThumbnailとBookmarkがkey windowを操作する
- Preferences変更が全ウィンドウへ反映される
- slideshow実行中に別ウィンドウを閉じる
- fullscreen、最小化、アプリ非アクティブ化
- Finderから複数ファイルを同時に開く
- Recent ItemsとLast Pagesの競合がない

## 規模とリスク

全体として「大」です。

概算は、専任で段階的に進めても5～8週間程度です。ただし、古いObjective-Cの手動メモリ管理、巨大なController、Nibの固定接続、GUI手動試験の量があるため不確実性は高めです。

主なリスク:

- ウィンドウclose後のthread callbackによるクラッシュ
- Recent Items / Book Settingsの更新消失
- メニューが非key windowを操作する
- panelが別ウィンドウのControllerを参照する
- fullscreenによる全ウィンドウへの副作用
- 同期アーカイブ読み込み中のイベント取りこぼし
- retain/release漏れ、Nib top-level objectの寿命管理
- 単一ウィンドウ時の既存挙動の回帰

## 最終提案

multi-windowは引き続きpendingが妥当です。ただし「全面改修が必要なので手を付けない」ではなく、次の順で準備タスクを進めれば現実的に到達できます。

1. AppController抽出
2. BookWindowController導入。ただしまだ1ウィンドウ限定
3. 補助パネルとメニューtargetの分離
4. close・永続化・非同期処理の安全化
5. 最後に複数ウィンドウ生成を有効化

特に、最初の実装タスクでmulti-windowを完成させようとしないことが重要です。まず1ウィンドウのまま所有関係を分離し、その状態で回帰確認を行うのが最も安全な実装経路です。

調査のみ実施しました。ファイル変更、依存変更、ビルド、コミットは行っておらず、worktreeはcleanです。