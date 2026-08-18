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

15개 skill 모두 자연어로 호출할 수 있습니다. `$scv:help`는 정확한 skill을
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
| `$scv:routine <name>` | `scv/routines/`에 정의된 유지보수 루틴 1개 실행, 목록(`--list`), 검사(`--lint <file>`). 스케줄 등록은 host 소유. |
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

## 워크스페이스 가드 (0.25.0-codex.2+)

`hooks/hooks.json`이 일부러 차단하는 `PreToolUse` 가드를 등록합니다. 거부하는 건
둘입니다. `scv/promote/<slug>/`의 `PLAN.md`, `TESTS.md`,
`FEATURE_ARCHITECTURE.md`를 손으로 새로 만드는 것, 그리고 `scv/` 밖 어디든 쓰는
것. 이미 있는 계획 파일 수정은 언제나 허용합니다. `*.md`, `.gitignore`,
`.gitattributes`, `LICENSE`, `.codex/config.toml`은 면제이고 `.env`는 아닙니다 —
허용된 `.env` 쓰기는 `vendor/scv-core/core/scripts/env-set.sh`를 거치기
때문입니다.

두 차단 모두 세션에 영수증이 생기는 순간 그 세션 동안 풀립니다. 여기서 등록하는
항목은 둘입니다 — `Bash`, `shell`, `local_shell`용 `gate-bash`, 그리고
`apply_patch`, `Write`, `Edit`, `MultiEdit`용 `gate-write`. 별도의 mint 항목은
없습니다. Codex에는 발급 근거로 삼을 skill 호출 이벤트가 없기 때문입니다. 영수증은
gate-bash 쪽에서, 명령이 벤더링된 `core/scripts/` 디렉터리를 가리킬 때 발급됩니다.
Core 프로토콜은 전부 무언가를 쓰기 전에 그 호출을 합니다. 다만 `$scv:update`,
`$scv:set-models`, `$scv:sync`는 `adapter/scripts/`로 돌아 아무것도 발급하지
않습니다. 두 명령 모두 plugin
디렉터리를 `${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}`로 찾습니다. `CODEX_PLUGIN_ROOT`
같은 변수는 없고, 그 이름을 쓴 것이 `0.25.0-codex.1`에서 가드가 죽은 채로 나간
이유입니다. 이 파일이 plugin 루트의 기본 경로에 있으므로
`.codex-plugin/plugin.json`은 여전히 `hooks` 키를 선언하지 않습니다.

가드는 **열린 채로** 실패합니다 — 내부 오류가 나면 stderr에 한 줄 적고 동작을
허용합니다 — 그리고 `scv/` 디렉터리가 없는 프로젝트에서는 아무 일도 하지 않습니다.
완전히 끄려면 `SCV_GUARD=off`를 export하세요. 파일이 아니라 프로세스 환경에서만
읽으므로 저장소 안의 무언가가 스스로를 면제할 수 없습니다.
`SCV_GUARD_RULE_B=off`는 계획 규칙만 남깁니다. 계약은
[`vendor/scv-core/core/contracts/guard.md`](vendor/scv-core/core/contracts/guard.md)입니다.

Codex 훅에 대한 운영 메모 둘. 훅은 hot-reload되지 않으므로 plugin을 갱신한 뒤에는
Codex를 다시 시작하세요. 그리고 신뢰는 훅의 내용에 묶입니다 — `guard.sh`가 바뀐
릴리스는 `/hooks`에서 다시 승인할 때까지 아무것도 강제하지 않습니다.

## Journal 훅 seam (Core 0.22.0+)

Core 0.22.0은 자유대화를 커밋되는 팀 journal(`scv/journal/`)로 캡처하는
훅 템플릿 2종(`vendor/scv-core/core/template/hooks/on-user-prompt.sh`,
`on-stop.sh`)을 포함합니다. 훅 등록은 wrapper/host 소유입니다. 위의 가드는
등록된 채로 배포되지만 journal 짝은 아닙니다. Codex plugin 표면이 프롬프트
원문이나 JSONL transcript 경로를 plugin 명령에 전달하지 않으므로, Codex
host에서의 등록은 문서화된 사용자 행동입니다 — 이벤트
매핑, stdin JSON 계약, `SCV_CORE_ROOT` export, non-blocking·redaction
보장은 [`references/journal-hooks.md`](references/journal-hooks.md)를
참조하세요. host가 JSONL transcript를 제공하지 않으면 turn-end 등록은
생략합니다. seam 계약은 이 부분 구현을 허용하며, 현재 이 wrapper가 그
격차에 해당합니다.

## 안전과 업데이트

archive 전에는 테스트 통과와 승인이 필요합니다. push, PR/MR 생성, 알림,
dependency 설치, 영구 Codex config 변경은 consent gate를 유지합니다.
`$scv:update`와 model-policy 검사는 read-only입니다.

Deck dependency, build, 생성된 deck JSON은 고정된 Core payload를 key로
하는 외부 cache에 둡니다. maintainer update에서는 이전 vendor나 legacy
plugin-root `DeckUI`의 알려진 runtime만 stable snapshot에서 additive하게
복사하고, 어느 원본도 수정하거나 삭제하지 않습니다. 검증된 Core tree는
owner lock 아래에서 교체하며 catchable failure에는 이전 tree를 정확히
복구합니다.

```bash
codex plugin marketplace upgrade scv-codex
codex plugin add scv@scv-codex
```

갱신 후 새 Codex 세션을 시작하세요. 프로젝트 template까지 병합하려면
`$scv:sync`를 별도로 실행합니다.

프로젝트 `.env`의 `SCV_LANG=en|ko|ja`로 생성 언어를 고정할 수 있습니다.
없으면 최신 사용자 메시지의 언어를 따르고, 판단할 수 없으면 영어를 씁니다.

MIT © [wookiya1364](https://github.com/wookiya1364)
