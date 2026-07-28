<div align="center">

<img src="assets/scv-circle.png" width="128" height="128" alt="SCV マスコット" />

# SCV for Codex

**Standard · Cowork · Verify**

元資料を承認可能なプランと実行可能テストへ精製し、プランを実装した後、
承認済みテストを累積回帰 suite に残すプロセス中心の Codex plugin です。

[リポジトリガイド](../../README.ja.md) ·
[English](./README.md) · [한국어](./README.ko.md)

</div>

## インストール

```bash
codex plugin marketplace add https://github.com/wookiya1364/scv-codex.git
codex plugin add scv@scv-codex
```

新しい Codex chat または CLI session を開始し、literal skill 名を
呼び出します。

```text
$scv:help
```

SCV は slash command ではなく、明示的に呼び出す Codex skill です。

## スキル

| スキル | 動作 |
|---|---|
| **`$scv:help`** | 状態診断、アイデア具体化、archive 検索、次の操作案内。 |
| `$scv:status` | raw input、active plan、epic、workspace mode、handoff を要約。 |
| `$scv:promote` | `scv/raw/` を PLAN、TESTS、feature architecture へ変換。 |
| `$scv:work <slug>` | 実装、テスト、証拠収集、承認、archive、PR/MR 準備。 |
| `$scv:codegen <slug>` | 実験的 TESTS-driven Red → Green loop。完了処理は `$scv:work` へ引き継ぐ。 |
| `$scv:deck [<md>]` | Markdown を企画文書または DeckUI slide deck として render。 |
| `$scv:update` | read-only version check と Codex marketplace 更新案内。 |
| `$scv:regression` | 有効な全 archive のテスト手順を実行。 |
| `$scv:report` | 設定済み Slack または Discord へフェーズ結果を報告。 |
| `$scv:sync` | template merge と active plan・code scope・test 間の drift 検出。 |
| `$scv:install-deps` | CLI 検出と同意ベースの install 支援。 |
| `$scv:workspace` | nested umbrella workspace の作成、参加、確認、分離。 |
| `$scv:handoff` | cross-repo 作業と文脈を記録。push と通知には同意が必要。 |
| `$scv:set-models` | インストール済み skill を変更せず、legacy model-policy の意図と実際の Codex config を診断。 |

## Codex 互換性

workflow、repository layout、Bash helper、plan、test、archive、regression、
deck 生成、multi-repo 調整は SCV for Claude Code から port しました。

host の差が一つあります。Codex plugin skill は skill ごとに異なる model
を pin できません。そのため `$scv:set-models` は旧
`SCV_MODEL_POLICY` のための read-only migration 診断です。Anthropic
model 名を推測で変換したり、インストール済み `SKILL.md` を変更したり
しません。永続的な `.codex/config.toml` 変更には明示的依頼、対応確認、
preview、確認が必要です。

## 安全性と更新

archive の前にテスト合格と承認が必要です。push、PR/MR 作成、通知、
dependency install、永続 Codex config 変更は consent gate を保ちます。
`$scv:update` と model-policy 検査は read-only です。

```bash
codex plugin marketplace upgrade scv-codex
codex plugin add scv@scv-codex
```

更新後、新しい Codex session を開始してください。project template も
merge する場合は `$scv:sync` を別途実行します。

project `.env` の `SCV_LANG=en|ko|ja` で生成言語を固定できます。未指定
なら最新のユーザーメッセージに従い、判定できなければ英語を使用します。

MIT © [wookiya1364](https://github.com/wookiya1364)
