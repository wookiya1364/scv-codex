<div align="center">

<img src="vendor/scv-core/core/assets/scv-circle.png" width="128" height="128" alt="SCV 마스코트" />

# SCV for Codex

**Standard · Cowork · Verify**

원본 자료를 승인 가능한 계획과 실행 가능한 테스트로 정제하고, 계획을
구현한 뒤 승인된 모든 테스트를 누적 회귀 suite에 남기는 프로세스 중심
Codex 플러그인입니다.

[저장소 가이드](../../README.ko.md) ·
[English](./README.md) · [日本語](./README.ja.md)

</div>

## 설치

```bash
codex plugin marketplace add https://github.com/wookiya1364/scv-codex.git
codex plugin add scv@scv-codex
```

새 Codex 채팅 또는 CLI 세션을 시작한 다음 자연어로 요청합니다.

```text
SCV로 이 프로젝트 상태를 진단하고 다음 할 일을 알려줘.
```

14개 skill 모두 자연어로 호출할 수 있습니다. `$scv:help`는 정확한 skill을
고르는 선택적 selector이고, `/scv:help`는 Claude Code slash command라서
여기서는 사용하지 않습니다.

## 스킬

| 스킬 | 동작 |
|---|---|
| **`$scv:help`** | 상태 진단, 아이디어 구체화, archive 검색, 다음 행동 안내. |
| `$scv:status` | raw 입력, active plan, epic, workspace mode, handoff 요약. |
| `$scv:promote` | `scv/raw/`를 PLAN, TESTS, feature architecture로 변환. |
| `$scv:work <slug>` | 구현, 테스트, 증거 수집, 승인, archive, PR/MR 준비. |
| `$scv:codegen <slug>` | 실험적 TESTS-driven Red → Green loop; 완료 단계는 `$scv:work`에 인계. |
| `$scv:deck [<md>]` | Markdown을 기획 문서 또는 DeckUI slide deck으로 렌더링. |
| `$scv:update` | read-only 버전 검사와 Codex marketplace 갱신 안내. |
| `$scv:regression` | 유효한 모든 archive의 테스트 지시 실행. |
| `$scv:report` | 설정된 Slack 또는 Discord에 단계 결과 보고. |
| `$scv:sync` | template 병합과 active plan·code scope·test 사이 drift 탐지. |
| `$scv:install-deps` | CLI 탐지와 동의 기반 설치 지원. |
| `$scv:workspace` | nested umbrella workspace 생성, 참가, 점검, 분리. |
| `$scv:handoff` | cross-repo 작업과 맥락 기록. push와 알림은 동의가 있어야 실행. |
| `$scv:set-models` | 설치된 skill을 고치지 않고 legacy model-policy 의도와 실제 Codex config를 진단. |

## Codex 호환성

workflow, repository layout, Bash helper, plan, test, archive, regression,
deck 생성, multi-repo 조정 동작은 Claude Code wrapper와 함께 사용하는
고정된 `vendor/scv-core` payload에서 옵니다. 설치된 plugin은 self-contained
형태이며 runtime에 core를 network로 받지 않습니다.

wrapper, core, template version은 따로 추적합니다. core lock은 source와
payload checksum, 해당되는 경우 검증된 release artifact SHA-256을
기록합니다. `scv/SCV.md`가 canonical이며, 기존 `CLAUDE.md` 또는
`CODEX.md` state는 변경 없이 읽고 승인된 sync에서만 migration합니다.

host 차이 하나는 명시적으로 남습니다. Codex plugin skill은 skill별로 다른
model을 pin할 수 없습니다. 따라서 `$scv:set-models`는 이전
`SCV_MODEL_POLICY` 값을 위한 read-only migration 진단입니다. Anthropic
model 이름을 추측으로 치환하거나 설치된 `SKILL.md`를 수정하지 않습니다.
영구 `.codex/config.toml` 변경에는 명시적 요청, 지원 여부 확인, preview,
확인이 필요합니다.

## 안전과 업데이트

archive 전에는 테스트 통과와 승인이 필요합니다. push, PR/MR 생성, 알림,
dependency 설치, 영구 Codex config 변경은 consent gate를 유지합니다.
`$scv:update`와 model-policy 검사는 read-only입니다.

```bash
codex plugin marketplace upgrade scv-codex
codex plugin add scv@scv-codex
```

갱신 후 새 Codex 세션을 시작하세요. 프로젝트 template까지 병합하려면
`$scv:sync`를 별도로 실행합니다.

프로젝트 `.env`의 `SCV_LANG=en|ko|ja`로 생성 언어를 고정할 수 있습니다.
없으면 최신 사용자 메시지의 언어를 따르고, 판단할 수 없으면 영어를 씁니다.

MIT © [wookiya1364](https://github.com/wookiya1364)
