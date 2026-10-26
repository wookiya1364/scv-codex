#!/usr/bin/env bash
# channel.sh — $scv:channel 의 엔진: 설치된 SCV 를 개발 · 스테이징 · 운영 채널 사이에서 바꿔 끼운다 (0.71.0+).
#
# 규칙 전문은 코어 protocols/channel.md, 순수부는 코어 lib/channel.sh(채널 → 브랜치, 바꿔 끼우기 단계). 여기는 양 끝의 부수효과:
# 지금 상태 읽기와 Codex CLI(`codex plugin …`) 실행. ~/.codex 의 플러그인 폴더 · 설정을 직접 고치지 않고(읽기만), 프로젝트 파일은
# 건드리지 않는다. Codex 의 목록 JSON 에는 브랜치가 없어 설정 파일([marketplaces.scv-codex] ref)에서 읽는다.
#
# Usage:
#   channel.sh                 # 지금 채널만 보인다 (아무것도 바꾸지 않음)
#   channel.sh dev|stage|prod  # 그 채널로 바꿔 끼운다
#
# Env (시험용): SCV_CODEX_BIN (기본 codex) · SCV_CHANNEL_GIT_BIN (기본 git) · SCV_CHANNEL_URL · CODEX_HOME
#
# Output: CHANNEL: · STEP: · RESULT: · NEXT: 줄 (Claude 래퍼의 channel.sh 와 같은 모양).
# Exit: 0 성공 · 이미 그 채널, 1 실패, 2 사용법 오류.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../vendor/scv-core/core/scripts/lib/channel.sh
source "$HERE/../../vendor/scv-core/core/scripts/lib/channel.sh"

CODEX_BIN="${SCV_CODEX_BIN:-codex}"
GIT_BIN="${SCV_CHANNEL_GIT_BIN:-git}"
URL="${SCV_CHANNEL_URL:-https://github.com/wookiya1364/scv-codex.git}"
CONFIG="${CODEX_HOME:-$HOME/.codex}/config.toml"
NAME=scv-codex
PLUGIN=scv

usage() { echo 'usage: channel.sh [dev | stage | prod]' >&2; exit 2; }

# step_args <단계 줄> → codex plugin 인자
step_args() {
  case "$1" in
    remove) echo "marketplace remove $NAME" ;;
    'add -') echo "marketplace add $URL" ;;
    add\ *) echo "marketplace add $URL --ref ${1#add }" ;;
    install) echo "add $PLUGIN@$NAME" ;;
  esac
}

# read_state → "present ref version" 한 줄 (ref 없음은 '-', 버전 없음은 not-installed). 못 읽으면 1.
read_state() {
  local inst present=0 ref=- ver
  inst="$("$CODEX_BIN" plugin list --json 2>/dev/null)" || return 1
  if [[ -f "$CONFIG" ]]; then
    read -r present ref <<<"$(awk -v sec="[marketplaces.$NAME]" '
      $0 == sec { in_sec = 1; found = 1; next }
      /^\[/ { in_sec = 0 }
      in_sec && $1 == "ref" { v = $0; sub(/^[^=]*=[ \t]*"?/, "", v); sub(/"?[ \t]*$/, "", v); ref = v }
      END { print (found ? 1 : 0), (ref == "" ? "-" : ref) }' "$CONFIG")"
  fi
  ver="$(printf '%s' "$inst" | jq -r --arg n "$PLUGIN" --arg m "$NAME" '
    (.installed // [])[] | select(.name == $n and (.marketplaceName // $m) == $m and (.installed // true)) | .version // "unknown"' 2>/dev/null | head -1)"
  echo "$present $ref ${ver:-not-installed}"
}

branch_exists() {
  [[ -z "$1" ]] && return 0
  "$GIT_BIN" ls-remote --exit-code --heads "$URL" "$1" >/dev/null 2>&1
}

run_steps() {
  local step args out
  while IFS= read -r step; do
    [[ -n "$step" ]] || continue
    args="$(step_args "$step")"
    # shellcheck disable=SC2086 # 단계는 공백으로 나뉜 인자다(값에 공백 없음).
    if out="$("$CODEX_BIN" plugin $args 2>&1)"; then echo "STEP: $args ok"
    else echo "STEP: $args fail"; echo "FAILED $args"; return 1; fi
  done <<<"$1"
}

main() {
  local target=${1:-}
  [[ $# -le 1 ]] || usage
  command -v jq >/dev/null 2>&1 || { echo "RESULT: failed jq-missing"; echo "NEXT: jq 를 설치한다 (\$scv:install-deps)"; return 1; }
  command -v "$CODEX_BIN" >/dev/null 2>&1 || { echo "RESULT: failed codex-cli-missing"; return 1; }

  local state present ref ver from
  state="$(read_state)" || { echo "RESULT: failed state-unreadable"; echo "NEXT: codex plugin list --json 이 읽히지 않는다 — Codex 버전을 확인한다"; return 1; }
  read -r present ref ver <<<"$state"
  [[ "$ref" == - ]] && ref=''
  from="$(scv_channel_of_ref "$ref")"
  echo "CHANNEL: $from $ver"
  [[ -n "$target" ]] || return 0

  local want steps out
  want="$(scv_channel_ref "$target")" || usage
  steps="$(scv_channel_plan "$present" "$ref" "$want")"
  if [[ -z "$steps" && "$ver" != not-installed ]]; then echo "RESULT: already $target $ver"; return 0; fi
  [[ -n "$steps" ]] || steps=install
  if ! branch_exists "$want"; then
    echo "RESULT: failed branch-missing $want"
    echo "NEXT: $want 브랜치가 아직 없다 — 래퍼의 채널 동기화가 처음 돈 뒤 다시 실행한다. 지금 설치는 그대로다"
    return 1
  fi

  if ! out="$(run_steps "$steps")"; then
    printf '%s\n' "$out" | grep -v '^FAILED '
    echo "RESULT: failed $(printf '%s\n' "$out" | sed -n 's/^FAILED //p')"
    if [[ $present -eq 1 ]] && printf '%s\n' "$out" | grep -q '^STEP: marketplace remove .* ok'; then
      if run_steps "$(scv_channel_plan 0 '' "$ref")" >/dev/null; then echo "RESULT: restored $from"
      else echo "NEXT: 원래 채널로 되돌리지 못했다 — codex plugin marketplace add $URL 다음 codex plugin add $PLUGIN@$NAME"; fi
    fi
    return 1
  fi
  printf '%s\n' "$out"

  local after aver
  after="$(read_state)" || after="0 - not-installed"
  read -r _ _ aver <<<"$after"
  echo "RESULT: switched $from $ver -> $target $aver"
  echo "NEXT: 새 Codex 대화(또는 CLI 세션)를 연다 — 그래야 바뀐 채널이 돈다"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; exit $?; fi
