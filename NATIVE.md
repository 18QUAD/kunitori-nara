# Android / iOS ネイティブ版

Flutter 3.29.3 の描画・入力を使用します。WebViewで公開サイトを表示する構成ではありません。

## データ引き継ぎ

1. 公開ブラウザ版の設定 →「データ引き継ぎ」→「現在のデータをコピー」。
2. アプリ版の設定 →「データ引き継ぎ」に貼り付け、「内容を確認して取り込む」。
3. 本拠地・領土数・累計タップ数を確認し、取り込みを実行。

領土、進行中のタップ数、戦績、称号、クイズ状態、tips履歴、地図位置、キャラ設定を引き継ぎます。チェックサムでコピー漏れを検出します。取り込み前に旧データを1件バックアップし、同じ画面から復元できます。コードは暗号化されていないため、他人に渡さず保管してください。自動同期はありません。ブラウザ側の元データは削除しません。アプリ版からブラウザ版への逆方向も同じ手順です。

## 地図

全国の地図画像を初回表示時にHTTPSで取得し、サイズとSHA-256を検証して端末内に保存します。画像ディスクキャッシュは最大512MiB、メモリ内の画像保持量は32MiBの予算から分配します。未訪問の地域には通信が必要です。進行データと地図キャッシュは別管理です。

## ビルド

```
flutter pub get --enforce-lockfile
flutter test test/save_transfer_test.dart test/game_test.dart
flutter build apk --release
flutter build ios --release --no-codesign
```

AndroidにはJava17とAndroid SDK、iOSにはmacOS・Xcode・CocoaPodsが必要です。
`.github/workflows/native.yml` はAndroidとiOSをGitHub Actions上でビルドし、成果物を保存します。

生成されるAndroid APKは開発用鍵で署名したテスト配布用です。Google Play向けの正式署名は別途設定してください。iOSの成果物は未署名の実機用.appとシミュレータ用.appです。実機へのインストール／TestFlight配布にはApple Developerの署名設定が必要です。Safariでのクラッシュが解消されたことは、実機での連続プレイ試験で確認する必要があります。
