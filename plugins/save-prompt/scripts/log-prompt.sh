#!/usr/bin/env bash
# save-prompt: UserPromptSubmit hook. Appends each submitted prompt to a daily
# Markdown file (~/.claude/prompts/YYYY-MM-DD.md).
#
# Contract: ALWAYS exit 0 and print NOTHING to stdout (stdout of a
# UserPromptSubmit hook is added to the model's context). Never evaluate the
# prompt text; it only ever travels through quoted variables and printf '%s'.
# Must run on macOS bash 3.2.

PROMPTS_DIR="${CLAUDE_PROMPTS_DIR:-$HOME/.claude/prompts}"
LOCK_DIR="$PROMPTS_DIR/.lock"
HAVE_LOCK=0

# break_stale_lock: the lock is held for milliseconds, so one older than a
# minute was abandoned (crash, kill -9, reboot). Remove it so it cannot slow
# every later prompt.
break_stale_lock() {
  if [ -n "$(find "$LOCK_DIR" -maxdepth 0 -type d -mmin +1 2>/dev/null)" ]; then
    rmdir "$LOCK_DIR" 2>/dev/null
  fi
}

# acquire_lock: take the mkdir lock, waiting up to ~5s (50 x 0.1s). If it cannot
# be taken (a fresh orphan lock), carry on WITHOUT it rather than lose the prompt.
acquire_lock() {
  local i
  break_stale_lock
  for i in $(seq 1 50); do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      HAVE_LOCK=1
      return 0
    fi
    sleep 0.1
  done
  return 0
}

# release_lock: remove the lock only if this process took it.
release_lock() {
  if [ "$HAVE_LOCK" = "1" ]; then
    rmdir "$LOCK_DIR" 2>/dev/null
    HAVE_LOCK=0
  fi
  return 0
}

# branch_of <cwd>: print the git branch of <cwd>, "(detached <sha>)" for a
# detached HEAD, or "-" when <cwd> is not a usable git working directory.
branch_of() {
  local cwd="$1" branch
  # `git -C ""` silently means "the current directory", so reject empty/missing.
  if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
    printf '%s\n' "-"
    return
  fi
  branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)" || {
    printf '%s\n' "-"
    return
  }
  if [ "$branch" = "HEAD" ]; then
    branch="(detached $(git -C "$cwd" rev-parse --short HEAD 2>/dev/null))"
  fi
  printf '%s\n' "$branch"
}

# quote_prompt: stdin -> every line prefixed "> " (blank lines become ">")
quote_prompt() {
  sed -e 's/^/> /' -e 's/^> $/>/'
}

# append_entry <entry>: append <entry> to today's file, writing the
# "# Prompts — YYYY-MM-DD" header first when the file is new.
append_entry() {
  local file="$PROMPTS_DIR/$DAY.md" header=""
  [ -e "$file" ] || header="# Prompts — $DAY"$'\n\n'
  printf '%s%s\n\n' "$header" "$1" >>"$file"
}

main() {
  local input prompt cwd session branch stamp now quoted entry

  if ! command -v jq >/dev/null 2>&1; then
    echo "save-prompt: jq not found; this prompt was not logged (install jq)" >&2
    return 0
  fi

  input="$(cat)"
  prompt="$(printf '%s' "$input" | jq -r '.prompt // ""' 2>/dev/null)"
  # nothing to record: empty/whitespace-only prompt, or input that is not JSON
  case "$prompt" in
    *[![:space:]]*) ;;
    *) return 0 ;;
  esac
  cwd="$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)"
  session="$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)"
  [ -n "$session" ] || session="-"

  stamp="$(date '+%F %T')"
  DAY="${stamp% *}"
  now="${stamp#* }"

  branch="$(branch_of "$cwd")"
  quoted="$(printf '%s\n' "$prompt" | quote_prompt)"
  entry="$(printf '## %s\n- **Workspace:** %s\n- **Branch:** %s\n- **Session:** %s\n\n%s' \
    "$now" "$cwd" "$branch" "${session:0:8}" "$quoted")"

  umask 077
  mkdir -p "$PROMPTS_DIR" 2>/dev/null
  # an unwritable directory can never be locked or written: say so once and
  # return at once instead of waiting on a lock that cannot be taken
  if [ ! -d "$PROMPTS_DIR" ] || [ ! -w "$PROMPTS_DIR" ]; then
    echo "save-prompt: cannot write to $PROMPTS_DIR; this prompt was not logged" >&2
    return 0
  fi
  trap release_lock EXIT
  acquire_lock
  append_entry "$entry"
  release_lock
}

main
exit 0
