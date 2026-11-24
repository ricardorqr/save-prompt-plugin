#!/usr/bin/env bash
# Tests for plugins/save-prompt/scripts/log-prompt.sh
# Run: bash tests/log-prompt.test.sh   (needs bash, jq, git)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/plugins/save-prompt/scripts/log-prompt.sh"
PASS=0
FAIL=0
TEST_ROOT="$(mktemp -d)" || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$TEST_ROOT"' EXIT

TMP=""
OUT=""
ERR=""
RC=0

# setup: fresh sandbox; the hook writes under $CLAUDE_PROMPTS_DIR
setup() {
  TMP="$(mktemp -d "$TEST_ROOT/t.XXXXXX")" || exit 1
  export CLAUDE_PROMPTS_DIR="$TMP/prompts"
  mkdir -p "$TMP/ws"
}

# payload <prompt> <cwd> <session_id>: hook input JSON
payload() {
  jq -n --arg p "$1" --arg c "$2" --arg s "$3" '{prompt: $p, cwd: $c, session_id: $s}'
}

# run_hook <json>: feed the hook on stdin; sets OUT, ERR, RC
run_hook() {
  OUT="$(printf '%s' "$1" | bash "$HOOK" 2>"$TMP/stderr")"
  RC=$?
  ERR="$(cat "$TMP/stderr")"
}

today_file() { printf '%s/%s.md' "$CLAUDE_PROMPTS_DIR" "$(date +%F)"; }

mode_of() {
  if [ "$(uname)" = "Darwin" ]; then stat -f %Lp "$1"; else stat -c %a "$1"; fi
}

# has_line <exact line>: today's file contains that whole line
has_line() { grep -qxF -- "$1" "$(today_file)" 2>/dev/null; }

# check <name> <command...>: run a test function, count the result
check() {
  local name="$1"
  shift
  if "$@"; then
    PASS=$((PASS + 1))
    echo "ok   $name"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL $name"
  fi
}

# ---------------------------------------------------------------- Task 2

t_creates_file_with_header_and_entry() {
  setup
  run_hook "$(payload "hello" "$TMP/ws" "abcd1234-5678")"
  local f
  f="$(today_file)"
  [ "$(head -n1 "$f" 2>/dev/null)" = "# Prompts — $(date +%F)" ] &&
    grep -qE '^## [0-9]{2}:[0-9]{2}:[0-9]{2}$' "$f" &&
    has_line "- **Workspace:** $TMP/ws" &&
    has_line "- **Session:** abcd1234" &&
    has_line "> hello"
}

t_multiline_prompt_is_blockquoted() {
  setup
  run_hook "$(payload $'line1\n\nline3' "$TMP/ws" "s1")"
  [ "$(grep '^>' "$(today_file)" 2>/dev/null)" = "$(printf '> line1\n>\n> line3')" ]
}

t_stdout_empty_and_exit_zero() {
  setup
  run_hook "$(payload "hello" "$TMP/ws" "s1")"
  [ -z "$OUT" ] && [ "$RC" -eq 0 ] && [ -f "$(today_file)" ]
}

t_permissions_are_private() {
  setup
  run_hook "$(payload "hello" "$TMP/ws" "s1")"
  [ "$(mode_of "$CLAUDE_PROMPTS_DIR" 2>/dev/null)" = "700" ] &&
    [ "$(mode_of "$(today_file)" 2>/dev/null)" = "600" ]
}

t_content_is_literal() {
  setup
  local p
  p="\$(touch $TMP/pwned) \`id\` \\n \$HOME"
  run_hook "$(payload "$p" "$TMP/ws" "s1")"
  has_line "> $p" && [ ! -e "$TMP/pwned" ]
}

check creates_file_with_header_and_entry t_creates_file_with_header_and_entry
check multiline_prompt_is_blockquoted t_multiline_prompt_is_blockquoted
check stdout_empty_and_exit_zero t_stdout_empty_and_exit_zero
check permissions_are_private t_permissions_are_private
check content_is_literal t_content_is_literal

# ---------------------------------------------------------------- Task 3

# make_repo <dir>: git repo on branch feature/x with one empty commit
make_repo() {
  mkdir -p "$1" &&
    git -C "$1" init -q -b feature/x &&
    git -C "$1" -c user.name=t -c user.email=t@t -c commit.gpgsign=false \
      commit -q --allow-empty -m init
}

t_branch_in_repo() {
  setup
  make_repo "$TMP/repo"
  run_hook "$(payload "hi" "$TMP/repo" "s1")"
  has_line "- **Branch:** feature/x"
}

t_branch_detached() {
  setup
  make_repo "$TMP/repo"
  git -C "$TMP/repo" checkout -q --detach
  run_hook "$(payload "hi" "$TMP/repo" "s1")"
  grep -qE '^- \*\*Branch:\*\* \(detached [0-9a-f]{7,}\)$' "$(today_file)"
}

t_branch_outside_repo() {
  setup
  run_hook "$(payload "hi" "$TMP/ws" "s1")"
  has_line "- **Branch:** -"
}

t_branch_missing_cwd() {
  setup
  run_hook "$(payload "hi" "$TMP/does-not-exist" "s1")"
  has_line "- **Branch:** -"
}

t_branch_empty_cwd_ignores_hook_directory() {
  setup
  make_repo "$TMP/repo"
  (cd "$TMP/repo" && printf '%s' "$(payload "hi" "" "s1")" | bash "$HOOK" >/dev/null 2>&1)
  has_line "- **Branch:** -"
}

t_cwd_with_spaces() {
  setup
  make_repo "$TMP/my work dir"
  run_hook "$(payload "hi" "$TMP/my work dir" "s1")"
  has_line "- **Workspace:** $TMP/my work dir" && has_line "- **Branch:** feature/x"
}

check branch_in_repo t_branch_in_repo
check branch_detached t_branch_detached
check branch_outside_repo t_branch_outside_repo
check branch_missing_cwd t_branch_missing_cwd
check branch_empty_cwd_ignores_hook_directory t_branch_empty_cwd_ignores_hook_directory
check cwd_with_spaces t_cwd_with_spaces

# ---------------------------------------------------------------- Task 4

t_second_entry_appends() {
  setup
  run_hook "$(payload "one" "$TMP/ws" "s1")"
  run_hook "$(payload "two" "$TMP/ws" "s1")"
  local f
  f="$(today_file)"
  [ "$(grep -c '^# Prompts' "$f")" = "1" ] && [ "$(grep -c '^## ' "$f")" = "2" ] &&
    has_line "> one" && has_line "> two"
}

t_empty_prompt_is_skipped() {
  setup
  run_hook "$(payload "" "$TMP/ws" "s1")"
  local rc1=$RC
  run_hook "$(payload "   " "$TMP/ws" "s1")"
  [ "$rc1" -eq 0 ] && [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ ! -e "$CLAUDE_PROMPTS_DIR" ]
}

t_malformed_json_is_ignored() {
  setup
  run_hook "not json"
  [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ ! -e "$CLAUDE_PROMPTS_DIR" ]
}

t_missing_jq_warns_and_exits_zero() {
  setup
  # a PATH holding every tool the hook needs EXCEPT jq, so only the jq guard
  # (not an accidental "mkdir: command not found") can stop it from writing
  local t
  mkdir -p "$TMP/nojqbin"
  for t in cat date sed mkdir rmdir sleep git; do
    ln -s "$(command -v "$t")" "$TMP/nojqbin/$t"
  done
  OUT="$(printf '%s' "$(payload "hi" "$TMP/ws" "s1")" |
    env PATH="$TMP/nojqbin" /bin/bash "$HOOK" 2>"$TMP/stderr")"
  RC=$?
  ERR="$(cat "$TMP/stderr")"
  [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [[ "$ERR" == *"save-prompt: jq not found"* ]] &&
    [ ! -e "$CLAUDE_PROMPTS_DIR" ]
}

t_missing_session_id_uses_dash() {
  setup
  run_hook "$(jq -n --arg p "hi" --arg c "$TMP/ws" '{prompt: $p, cwd: $c}')"
  has_line "- **Session:** -"
}

t_unicode_roundtrip() {
  setup
  run_hook "$(payload "héllo 日本語 🎉" "$TMP/ws" "s1")"
  has_line "> héllo 日本語 🎉"
}

t_large_prompt_intact() {
  setup
  # build via files: a 200 KB value is too big for one argv entry on Linux
  { head -c 200000 /dev/zero | tr '\0' 'x'; printf 'END'; } >"$TMP/big.txt"
  jq -n --rawfile p "$TMP/big.txt" --arg c "$TMP/ws" --arg s "s1" \
    '{prompt: $p, cwd: $c, session_id: $s}' >"$TMP/big.json"
  run_hook "$(cat "$TMP/big.json")"
  local f
  f="$(today_file)"
  [ "$RC" -eq 0 ] && grep -q 'xEND$' "$f" && [ "$(wc -c <"$f")" -ge 200000 ]
}

t_concurrent_runs_do_not_interleave() {
  setup
  local i f
  for i in $(seq 1 20); do
    (printf '%s' "$(payload "msg-$i" "$TMP/ws" "s$i")" | bash "$HOOK" >/dev/null 2>&1) &
  done
  wait
  f="$(today_file)"
  [ "$(grep -c '^# Prompts' "$f")" = "1" ] && [ "$(grep -c '^## ' "$f")" = "20" ] || return 1
  for i in $(seq 1 20); do
    [ "$(grep -cxF "> msg-$i" "$f")" = "1" ] || return 1
  done
  # each quote line sits two lines below its own Session line (blank line between)
  awk '{ if ($0 ~ /^> msg-/) { n=$0; sub(/^> msg-/, "", n)
           if (p2 != "- **Session:** s" n || p1 != "") bad=1 }
         p2=p1; p1=$0 }
       END { exit bad }' "$f"
}

t_waits_for_held_lock() {
  setup
  mkdir -p "$CLAUDE_PROMPTS_DIR/.lock"
  (printf '%s' "$(payload "hello" "$TMP/ws" "s1")" | bash "$HOOK" >/dev/null 2>&1) &
  local pid=$!
  sleep 0.5
  [ ! -e "$(today_file)" ] || { wait "$pid"; return 1; } # must still be waiting
  rmdir "$CLAUDE_PROMPTS_DIR/.lock"
  wait "$pid"
  has_line "> hello" && [ ! -e "$CLAUDE_PROMPTS_DIR/.lock" ]
}

t_stale_lock_does_not_lose_prompt() {
  setup
  mkdir -p "$CLAUDE_PROMPTS_DIR/.lock"
  local start end
  start="$(date +%s)"
  run_hook "$(payload "hello" "$TMP/ws" "s1")"
  end="$(date +%s)"
  [ "$RC" -eq 0 ] && has_line "> hello" && [ $((end - start)) -lt 20 ]
}

t_default_dir_is_home() {
  setup
  mkdir -p "$TMP/home"
  printf '%s' "$(payload "hello" "$TMP/ws" "s1")" |
    env -u CLAUDE_PROMPTS_DIR HOME="$TMP/home" bash "$HOOK" >/dev/null 2>&1
  [ -f "$TMP/home/.claude/prompts/$(date +%F).md" ]
}

check second_entry_appends t_second_entry_appends
check empty_prompt_is_skipped t_empty_prompt_is_skipped
check malformed_json_is_ignored t_malformed_json_is_ignored
check missing_jq_warns_and_exits_zero t_missing_jq_warns_and_exits_zero
check missing_session_id_uses_dash t_missing_session_id_uses_dash
check unicode_roundtrip t_unicode_roundtrip
check large_prompt_intact t_large_prompt_intact
check concurrent_runs_do_not_interleave t_concurrent_runs_do_not_interleave
check waits_for_held_lock t_waits_for_held_lock
check stale_lock_does_not_lose_prompt t_stale_lock_does_not_lose_prompt
check default_dir_is_home t_default_dir_is_home

# ---------------------------------------------------------------- Final review fixes

# An abandoned lock (crash, kill -9, reboot) must heal, not slow every prompt.
t_old_stale_lock_is_broken_quickly() {
  setup
  mkdir -p "$CLAUDE_PROMPTS_DIR/.lock"
  touch -t 202001010000 "$CLAUDE_PROMPTS_DIR/.lock"
  local start end
  start="$(date +%s)"
  run_hook "$(payload "first" "$TMP/ws" "s1")"
  run_hook "$(payload "second" "$TMP/ws" "s1")"
  end="$(date +%s)"
  has_line "> first" && has_line "> second" && [ "$RC" -eq 0 ] &&
    [ ! -e "$CLAUDE_PROMPTS_DIR/.lock" ] && [ $((end - start)) -lt 3 ]
}

# A directory that cannot be written must not make every prompt wait.
t_unwritable_dir_returns_quickly() {
  setup
  if [ "$(id -u)" = "0" ]; then return 0; fi # root ignores chmod; nothing to test
  mkdir -p "$TMP/ro"
  chmod 500 "$TMP/ro"
  export CLAUDE_PROMPTS_DIR="$TMP/ro/prompts"
  local start end
  start="$(date +%s)"
  run_hook "$(payload "hello" "$TMP/ws" "s1")"
  end="$(date +%s)"
  chmod 700 "$TMP/ro"
  [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [[ "$ERR" == *"save-prompt: cannot write"* ]] &&
    [ $((end - start)) -lt 3 ]
}

check old_stale_lock_is_broken_quickly t_old_stale_lock_is_broken_quickly
check unwritable_dir_returns_quickly t_unwritable_dir_returns_quickly

# ---------------------------------------------------------------- summary

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
