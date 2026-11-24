#!/usr/bin/env bash
# save-prompt: UserPromptSubmit hook. Appends each submitted prompt to a daily
# Markdown file (~/.claude/prompts/YYYY-MM-DD.md).
#
# Contract: ALWAYS exit 0 and print NOTHING to stdout (stdout of a
# UserPromptSubmit hook is added to the model's context). Never evaluate the
# prompt text; it only ever travels through quoted variables and printf '%s'.
# Must run on macOS bash 3.2.

PROMPTS_DIR="${CLAUDE_PROMPTS_DIR:-$HOME/.claude/prompts}"

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
  input="$(cat)"
  prompt="$(printf '%s' "$input" | jq -r '.prompt // ""')"
  cwd="$(printf '%s' "$input" | jq -r '.cwd // ""')"
  session="$(printf '%s' "$input" | jq -r '.session_id // ""')"

  stamp="$(date '+%F %T')"
  DAY="${stamp% *}"
  now="${stamp#* }"

  branch="$(branch_of "$cwd")"
  quoted="$(printf '%s\n' "$prompt" | quote_prompt)"
  entry="$(printf '## %s\n- **Workspace:** %s\n- **Branch:** %s\n- **Session:** %s\n\n%s' \
    "$now" "$cwd" "$branch" "${session:0:8}" "$quoted")"

  umask 077
  mkdir -p "$PROMPTS_DIR"
  append_entry "$entry"
}

main
exit 0
