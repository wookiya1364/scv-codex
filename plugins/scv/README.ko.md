<div align="center">

<img src="vendor/scv-core/core/assets/scv-circle.png" width="128" height="128" alt="SCV mascot" />

# SCV for Codex

**Standard · Cowork · Verify**

모든 변경은 계획과 테스트와 함께 나가고 — 테스트는 영원히 돕니다.

[저장소 가이드](../../README.ko.md) ·
[English](./README.md) · [日本語](./README.ja.md)

</div>

## 설치

```bash
codex plugin marketplace add https://github.com/wookiya1364/scv-codex.git
codex plugin add scv@scv-codex
```

새 Codex 세션을 시작하고, **그냥 말 걸면 됩니다**:

```text
SCV로 — 결제 화면에 환불 버튼 넣고 싶어.
```

SCV는 기본으로 일반 대화에 끼어듭니다 (`scv/scv_settings.json`의
`SCV_ALWAYS_ON`; `off` = 명시적 스킬만). `$scv:help`가 명시적 선택자이고,
전체 스킬 표·설정·가드레일·멀티레포 안내는
[저장소 가이드](../../README.ko.md)에 있습니다.

## 들어 있는 것

- 루프: 자료 → 계획 + 테스트 → 구현 → 아카이브 → 쌓이는 회귀.
  `PLAN.md`가 단일 원본이고, 증적은 PR/MR에 붙습니다.
- 설정은 `scv/scv_settings.json` (자동 생성, 모든 키 설명 포함) +
  git 무시되는 비밀 파일. `.env`는 읽지 않습니다.
- 차단형 `PreToolUse` 가드 (손으로 만든 계획 파일, `scv/` 밖 쓰기) — SCV
  액션이 한 번 돌면 해제. 내부 오류에는 열리는 쪽, `scv/` 없는 곳에서는
  무반응, `SCV_GUARD=off`로 끔. Codex 훅은 핫리로드가 안 되니 업데이트 후
  재시작 + `/hooks` 재승인. 계약:
  [`core/contracts/guard.md`](vendor/scv-core/core/contracts/guard.md).
- 체크섬 고정된 [scv-core](https://github.com/wookiya1364/scv-core) 페이로드가
  `vendor/scv-core/` 아래에 — 런타임에 아무것도 내려받지 않습니다.

업데이트: `codex plugin marketplace upgrade scv-codex` →
`codex plugin add scv@scv-codex` → 새 세션. 프로젝트 템플릿 갱신은 별도로
`$scv:sync`.

MIT © [wookiya1364](https://github.com/wookiya1364)
