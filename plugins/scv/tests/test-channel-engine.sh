#!/usr/bin/env bash
# test-channel-engine.sh — $scv:channel 의 엔진 adapter/scripts/channel.sh (0.71.0).
#
# 가짜 codex · git 으로 본다 — 설정 파일(CODEX_HOME/config.toml)의 [marketplaces.scv-codex] ref 와 설치된 버전을 파일로 들고,
# 받은 plugin 명령을 기록하고 상태를 바꾼다. 실제 마켓 · 네트워크 · 설치본은 건드리지 않는다.
# Run: bash plugins/scv/tests/test-channel-engine.sh
set -uo pipefail
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
C="$PLUGIN_ROOT/adapter/scripts/channel.sh"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
[[ -f "$C" ]] || { echo "✖ 없음: $C"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }
W="$(mktemp -d "${TMPDIR:-/tmp}/scv-codex-channel-test.XXXXXX")"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin"

# 가짜 codex — $CODEX_HOME/config.toml 에 마켓 절을 쓰고 지운다(실제 CLI 와 같은 모양). $FC_DIR/ver = 설치된 버전.
cat > "$W/bin/codex" <<'FC'
#!/usr/bin/env bash
[[ "$1" == plugin ]] || exit 9; shift
echo "$*" >> "$FC_DIR/calls"
if [[ -f "$FC_DIR/failon" ]] && [[ "$*" == "$(cat "$FC_DIR/failon")"* ]]; then echo "Error: failed" >&2; exit 1; fi
cfg="$CODEX_HOME/config.toml"
case "$*" in
  "list --json")
    if [[ -f "$FC_DIR/ver" ]]; then echo '{"installed":[{"name":"scv","marketplaceName":"scv-codex","version":"'"$(cat "$FC_DIR/ver")"'","installed":true}]}'
    else echo '{"installed":[]}'; fi ;;
  "marketplace remove scv-codex") : > "$cfg"; rm -f "$FC_DIR/ver" ;;
  "marketplace add "*)
    { echo '[marketplaces.scv-codex]'; echo 'source_type = "git"'; echo 'source = "x"'
      a="$*"; case "$a" in *' --ref '*) echo "ref = \"${a##* --ref }\"" ;; esac; } > "$cfg" ;;
  "add scv@scv-codex")
    r="$(awk -F'"' '/^ref/ { print $2 }' "$cfg")"
    case "$r" in channel/dev) echo 0.70.5-dev.abc1234 ;; channel/stage) echo 0.70.5-stage.def5678 ;; *) echo 0.70.4-codex.1 ;; esac > "$FC_DIR/ver" ;;
  *) exit 8 ;;
esac
exit 0
FC
cat > "$W/bin/git" <<'FG'
#!/usr/bin/env bash
[[ "$1" == ls-remote ]] || exit 9
grep -qxF "${@: -1}" "$FC_DIR/branches" 2>/dev/null
FG
chmod +x "$W/bin/codex" "$W/bin/git"

case_dir() {
  rm -rf "$W/fc" "$W/home"; mkdir -p "$W/fc" "$W/home"; : > "$W/fc/calls"
  printf '%s\n' channel/dev channel/stage > "$W/fc/branches"
  printf '[marketplaces.scv-codex]\nsource_type = "git"\nsource = "x"\n' > "$W/home/config.toml"; echo 0.70.4-codex.1 > "$W/fc/ver"
}
run() { FC_DIR="$W/fc" CODEX_HOME="$W/home" SCV_CODEX_BIN="$W/bin/codex" SCV_CHANNEL_GIT_BIN="$W/bin/git" bash "$C" "$@" 2>&1; }
calls() { grep -v '^list --json' "$W/fc/calls" | tr '\n' '|'; }
U=https://github.com/wookiya1364/scv-codex.git

echo "── [T0] 인자 없이 — 지금 채널만 ──"
case_dir; OUT="$(run)"; rc=$?
[[ $rc -eq 0 && "$OUT" == "CHANNEL: prod 0.70.4-codex.1" && -z "$(calls)" ]] && ok "운영, 명령 없음" || fail "rc=$rc $OUT / $(calls)"

echo "── [T5] 운영 → 개발 ──"
OUT="$(run dev)"; rc=$?
[[ "$(calls)" == "marketplace remove scv-codex|marketplace add $U --ref channel/dev|add scv@scv-codex|" ]] && ok "remove → add --ref channel/dev → add" || fail "순서: $(calls)"
[[ $rc -eq 0 && "$OUT" == *"RESULT: switched prod 0.70.4-codex.1 -> dev 0.70.5-dev.abc1234"* && "$OUT" == *"NEXT: "* ]] && ok "결과 + 새 세션 안내" || fail "rc=$rc $OUT"

echo "── [T6] 개발 → 운영, [T3] 같은 채널 ──"
: > "$W/fc/calls"; OUT="$(run prod)"; rc=$?
[[ "$(calls)" == "marketplace remove scv-codex|marketplace add $U|add scv@scv-codex|" && "$OUT" == *"-> prod 0.70.4-codex.1"* ]] && ok "운영으로 돌아옴" || fail "rc=$rc $OUT / $(calls)"
: > "$W/fc/calls"; OUT="$(run prod)"; rc=$?
[[ $rc -eq 0 && "$OUT" == *"RESULT: already prod"* && -z "$(calls)" ]] && ok "이미 운영 — 명령 없음" || fail "rc=$rc $OUT"

echo "── [T7] 실패 ──"
case_dir; : > "$W/fc/branches"; OUT="$(run stage)"; rc=$?
[[ $rc -eq 1 && "$OUT" == *"branch-missing channel/stage"* && -z "$(calls)" ]] && ok "branch-missing, 아무것도 안 바뀜" || fail "rc=$rc $OUT"
case_dir; echo "marketplace add $U --ref" > "$W/fc/failon"; OUT="$(run dev)"; rc=$?
[[ $rc -eq 1 && "$OUT" == *"RESULT: failed marketplace add"* && "$OUT" == *"RESULT: restored prod"* && "$(cat "$W/fc/ver")" == 0.70.4-codex.1 ]] \
  && ok "실패 단계 + 운영으로 되돌림" || fail "rc=$rc $OUT"
case_dir; OUT="$(run nightly)"; rc=$?
[[ $rc -eq 2 ]] && ok "모르는 채널 rc=2" || fail "rc=$rc"

echo; echo "test-channel-engine: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
