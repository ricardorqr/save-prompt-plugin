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

# ---------------------------------------------------------------- summary

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
