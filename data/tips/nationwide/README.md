# 奈良県外の地域tips用・収集資料

このフォルダーには、**出典付き素材**と、短文tipsの根拠・編集記録を保存しています。
収集した長文を未確認のままゲームに表示するためのデータではありません。
奈良県の既存tips・ID・保存形式を維持し、奈良県外の短文tipsを別途生成しています。

## 収集対象

- `assets/data/japan.json` の奈良県外1,857市区町村。政令指定都市の行政区を含みます。
- 地図・自治体コードは2020年の構成です。取得した記事は取得時点の版であり、その後の区再編・改称は短文化前に確認が必要です。
- 全国ファイルには奈良県の39市町村が含まれていないため、全国ファイルの自治体数から39を引く処理は行いません。

## 日本語版Wikipedia

`01.json`〜`47.json`（奈良県の`29.json`を除く）に自治体別の資料を保存しています。

- 自治体コード・自治体名・都道府県、記事名、元記事URL、版番号・固定版URL、取得日時、取得HTMLのSHA-256。
- `materials` は概要、地理、歴史、産業、観光などの記事段落。下位見出しも親見出しとともに保持。
- 人口・世帯・推計を含む段落、人口の節、参考文献・外部リンクなどは素材候補から除外。
- 同名自治体は記事中の都道府県で照合し、行政区は区名・市名を区別。
- `reviewStatus: unreviewed_source_material` は「取得済み、短文としては未確認」を意味します。
- 日本語版Wikipedia各記事の執筆者による文章。[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)。執筆者・履歴は固定版から参照できます。
- 変更内容は段落の抽出、参照番号の削除、空白の整理、対象外の節・段落の除外です。この素材自体は長文です。表示用の短文化と根拠は別の監査ファイルに保持しています。

## 文化庁・国指定文化財等データベース

`cultural_properties.json` は奈良県外の史跡・名勝・天然記念物を所在都道府県で絞り込んだ**先頭5件までのサンプル**です。
全国の文化財を網羅した一覧ではありません。

- `https://kunishitei.bunka.go.jp/` の個別文化財ページから名称、種別、指定年月日、所在地などを記録。
- 記録上の所在都道府県と対象都道府県が一致するものだけを採用。
- 所在地に自治体名が明示される場合だけ`cityIds`へ対応付け。複数県にまたがる文化財や所在地未記載のものを、自治体へ推測で割り当てません。
- 文化財ページのURL、取得日時、HTMLのSHA-256を保持。Wikipediaのライセンスを文化庁資料に適用するものではありません。

## 今回の取得結果（2026-10-18 UTC）

- Wikipedia：奈良県外46都道府県・1,857市区町村、151,767段落。未解決・本文抽出なしは0件。
- 文化庁：46都道府県・230件の公式資料。所在地から対応が確認できた自治体は220市区町村。
- 全記事の版・自治体コード・保存HTMLのSHA-256を検証済み。この資料全体の手作業による事実確認は未実施。表示文は文脈依存の断片・年表・人口情報を除外し、短文として編集しています。

都道府県別の件数は`prefecture_summary.tsv`、全体の検証記録は`collection_report.json`を参照してください。

## 再取得・検証

Pythonの`requests`と`lxml`が必要です。環境のプロキシとCA設定を使用します。

```sh
python tools/collect_national_tip_sources.py
python tools/collect_cultural_tip_sources.py
python tools/check_national_tip_sources.py
# この作業環境に保存された生HTMLも照合する場合
python tools/check_national_tip_sources.py --snapshots
python -m unittest discover -s tools -p test_collect_national_tip_sources.py -v
```

Wikipediaは全体で毎秒2.5リクエスト以下・最大3並列、文化庁は毎秒1リクエスト以下です。
取得済みのWikipedia記事はキャッシュを再利用し、中断した自治体から再開できます。
生HTMLは`data/raw/`にgzipで保存します（Gitの管理対象外）。このフォルダーには抽出資料と出典情報を残します。

件数・未解決の自治体は`collection_report.json`を参照してください。
実装時は、伝承・諸説、現時点の営業・交通情報、地図の2020年自治体との対応を確認して40文字以内に編集し、人口情報を含めず、固定のtips IDと出典を割り当てます。奈良の既存tips IDは維持します。

## アプリ用の短文tips

`tools/build_national_tips.py` は1,857市区町村に1〜5件、合計3,582件を生成します。
全件40文字以内。本文に出典・URL・脚注は表示しません。出典URLはデータの別フィールドと設定画面の一覧に保持します。
`short_tip_audit.json` は表示文・元の文または地理一覧・固定版・ID生成根拠を対応付ける監査資料です。
`short_tip_overrides.json` は元段落に照合して編集した短文です。全件を人手で校閲した資料という意味ではありません。
参照番号の削除は後続テキストを保存する方式（parserVersion 3）で、同じ保存HTMLから再抽出しています。

出力は `assets/data/tips/index.json` と県別JSONです。本文は必要な県だけ読み込み、県が変わると前の県の本文を解放します。
小さいID一覧は常駐し、未読込の県の閲覧履歴も保存・復元できます。奈良のtips・クイズは従来データを使います。
IDは自治体コードと原文・出典の識別情報から決定し、廃止IDもindexのknownIdsに残します。

```sh
python tools/build_national_tips.py
python -m unittest discover -s tools -p test_build_national_tips.py -v
```
