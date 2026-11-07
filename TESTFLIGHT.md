# TestFlight（Macなしで配布）

アプリのBundle IDは `io.github.quad18.kunitori`。既存のブラウザ版の進行は、設定 → データ引き継ぎでコピーし、iOS版へ貼り付けて取り込めます。

## 初回にApple側で行うこと

1. [Apple DeveloperのIdentifiers](https://developer.apple.com/account/resources/identifiers/list)で、App ID（App、Explicit）`io.github.quad18.kunitori` を登録。
2. [App Store Connect](https://appstoreconnect.apple.com/apps)の「マイApp」→「＋」→「新規App」。iOSを選び、名前・主言語（日本語）・上記Bundle ID・任意のSKU（例 `kunitori-ios`）を登録。
3. 作成したAppの「一般 → App情報」の数値の「Apple ID」を控える。Apple IDのメールアドレスやBundle IDとは異なります。
4. [ユーザとアクセス → 統合 → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)でチームAPIキーを作成。アクセス権は **Admin**（配布証明書・プロファイルを自動作成するため）。初回はアカウントホルダーによるAPIアクセス有効化が必要な場合があります。
5. Key IDとIssuer IDを控え、秘密鍵 `.p8` をダウンロード。Appleの秘密鍵は一度しかダウンロードできないので、手元にも保管します。

Apple Developerの契約更新など、Apple側の画面に必須手続きが出ている場合は完了させてください。

## GitHubに設定するもの

[このリポジトリのActions Secrets](https://github.com/18QUAD/kunitori-nara/settings/secrets/actions)で、次の4件を **Repository secrets** として登録。

| Secret名 | 登録する値 |
| --- | --- |
| `ASC_KEY_ID` | Appleで作成したチームAPIキーのKey ID |
| `ASC_ISSUER_ID` | そのIssuer ID |
| `ASC_PRIVATE_KEY` | `.p8`ファイルの全文（BEGIN/END行を含む） |
| `IOS_CERTIFICATE_PRIVATE_KEY` | 初回に用意した配布証明書用RSA秘密鍵ファイルの全文（BEGIN/END行を含む） |

続いて同じ画面の **Variables** タブで、Repository variable `ASC_APP_ID` にApp情報の数値Apple IDを登録。

秘密鍵をチャット、公開リポジトリ、Issue、実行ログへ貼り付けないでください。APIキーと証明書用RSA鍵は別物です。RSA鍵は更新時も同じものを使い、毎回作り直さないでください。作り直すと別の配布証明書が必要になり、Appleの発行上限に達する場合があります。

## ビルドとアップロード

初回の [iOS TestFlightワークフロー](https://github.com/18QUAD/kunitori-nara/actions/workflows/testflight.yml) は、設定不足なら不足した項目名を表示して署名・アップロードの前に停止します。上記を登録した後、その実行画面の **Re-run all jobs** を押してください。

新しいソースを配布する時は `attackable-place-search` ブランチの `.github/testflight-trigger.txt` を編集してコミットすると、そのコミットからビルドします。再実行は前回と同じソースを対象とします。`workflow_dispatch` はワークフローをデフォルトブランチにも配置した後で利用できます。

処理内容：

- 登録項目と秘密鍵形式の確認。
- Xcode 26以上を選択し、固定したFlutterと署名ツールをインストール。
- 進行データ互換性とタップ入力のテスト。
- 固定RSA鍵に対応するApple配布証明書とApp Storeプロファイルを取得。存在しなければ作成。
- ワークフローの実行番号と再実行回数から`7.1`の形式で番号を割り当て、署名済みIPAを生成。Apple側の最新番号より大きいことを検証する。Appleが処理中で古い番号を返す場合も、後続ビルドや再実行で同じ番号を使わない。
- App Store Connectへアップロード。署名ファイル・秘密鍵は成果物に含めず、一時キーチェーンを削除。

署名済みIPAの保存期間は7日です。Appleの認証・アプリ登録が未完了なら、署名済みビルドとアップロードは実行できません。

## iPhoneにインストール

1. Appleの処理完了後、App Store Connectの該当App → **TestFlight** を開く。
2. **内部テスト**のグループを作成し、自分のApp Store Connectアカウントを追加。アップロードしたビルドをグループに追加。
3. iPhoneにAppleの [TestFlight](https://apps.apple.com/jp/app/testflight/id899247664) を入れ、自分への案内からインストール。
4. ブラウザ版で引き継ぎコードをコピーし、アプリ版の設定から取り込む。ブラウザ側の保存データは削除されません。

このワークフローは内部テスト用にバイナリをアップロードします。外部テスターの招待やベータ審査、App Store一般公開は別操作です。TestFlightのビルドは原則90日間有効です。

2026年11月7日：太さ修正のアップロードは、直前に送信したビルド3がAppleで処理中のため最新番号の取得結果が古く、同じ3を割り当てたことで拒否された。以後は実行番号・再実行回数で番号を分ける。ビルド成功とアップロード成功を区別し、送信完了後にTestFlightで確認する。
