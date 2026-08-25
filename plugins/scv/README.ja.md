<div align="center">

<img src="vendor/scv-core/core/assets/scv-circle.png" width="128" height="128" alt="SCV mascot" />

# SCV for Codex

**Standard · Cowork · Verify**

すべての変更は計画とテストとともに出荷され — テストは永遠に回り続けます。

[リポジトリガイド](../../README.ja.md) ·
[English](./README.md) · [한국어](./README.ko.md)

</div>

## インストール

```bash
codex plugin marketplace add https://github.com/wookiya1364/scv-codex.git
codex plugin add scv@scv-codex
```

新しい Codex セッションを開始して、**普通に話しかけるだけ**:

```text
SCV で — 決済画面に払い戻しボタンを付けたい。
```

SCV は既定で自由会話に加わります (`scv/scv_settings.json` の
`SCV_ALWAYS_ON`; `off` = 明示的スキルのみ)。`$scv:help` が明示的なセレクター
で、スキル表・設定・ガードレール・マルチレポの全ガイドは
[リポジトリガイド](../../README.ja.md) にあります。

## 入っているもの

- ループ: 資料 → 計画 + テスト → 実装 → アーカイブ → 蓄積される回帰。
  `PLAN.md` が単一の原本で、証跡は PR/MR に付きます。
- 設定は `scv/scv_settings.json` (自動生成、全キー説明つき) +
  git-ignore される secret ファイル。`.env` は読みません。
- ブロッキングな `PreToolUse` ガード (手作りの計画ファイル、`scv/` 外への
  書き込み) — SCV アクションが一度動けば解除。内部エラー時は開く側、`scv/` の
  ない場所では不活性、`SCV_GUARD=off` で停止。Codex フックはホットリロード
  されないため、更新後は再起動 + `/hooks` で再承認。契約:
  [`core/contracts/guard.md`](vendor/scv-core/core/contracts/guard.md)。
- チェックサム固定の [scv-core](https://github.com/wookiya1364/scv-core)
  ペイロードが `vendor/scv-core/` 配下に — 実行時に何も取得しません。

更新: `codex plugin marketplace upgrade scv-codex` →
`codex plugin add scv@scv-codex` → 新セッション。プロジェクトテンプレートの
更新は別途 `$scv:sync`。

MIT © [wookiya1364](https://github.com/wookiya1364)
