# save-prompt Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Claude Code plugin whose `UserPromptSubmit` hook appends every prompt (time, workspace, branch, session) to `~/.claude/prompts/YYYY-MM-DD.md`.

**Architecture:** One bash script (`log-prompt.sh`) reads the hook JSON from stdin with `jq` and appends a Markdown entry under a `mkdir` lock. The repo mirrors `~/Repositories/read-aloud-plugin`: marketplace at the root, plugin under `plugins/save-prompt/`, bash tests under `tests/`, CI that runs every `tests/*.test.sh`.

**Tech Stack:** bash (must run on macOS bash 3.2 and Linux), `jq`, `git`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-24-save-prompt-design.md`

## Global Constraints

- Output file: `~/.claude/prompts/YYYY-MM-DD.md`, local date; directory mode `700`, file mode `600`; `CLAUDE_PROMPTS_DIR` overrides the directory.
- The hook always exits 0 and prints NOTHING to stdout (stdout of a `UserPromptSubmit` hook is added to the model's context). Warnings go to stderr.
- No network access.
- Entry format exactly: `## HH:MM:SS`, then `- **Workspace:** <cwd>`, `- **Branch:** <branch>`, `- **Session:** <first 8 chars of session_id>`, a blank line, then the prompt with every line prefixed `> ` (blank lines become `>`), then a blank line. A new file starts with `# Prompts — YYYY-MM-DD` and a blank line.
- Branch: `git -C "$cwd" rev-parse --abbrev-ref HEAD`; detached HEAD → `(detached <short-sha>)`; not a repo or missing cwd → `-`.
- Missing `jq`: one line on stderr, exit 0.
- Names: plugin `save-prompt`, marketplace `save-prompt-marketplace`, GitHub `ricardorqr/save-prompt-plugin`, branch `master`, version `0.1.0`, author `ricardorqr`, license MIT "Ricardo Ribeiro".
- Commit messages are conventional (`feat:`, `test:`, `docs:`, `ci:`, `chore:`) and end with the line `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Do not push, do not create the GitHub repo, do not install the plugin into the real `~/.claude`.

## Review Focus

- Prompt text containing `$(cmd)`, backticks, backslashes, `$HOME` must be stored literally and never executed (Task 2).
- Empty or whitespace-only prompt: no entry and no file created, exit 0 (Task 4).
- Two sessions submitting at the same instant: every entry intact, none interleaved (Task 4).
- A 200 KB prompt, and Unicode/emoji, are stored intact (Task 4).
- Missing `session_id`, or a `cwd` that does not exist or contains spaces, still logs with `-` / the literal path (Tasks 3 and 4).

## File Structure

| File | Responsibility |
|---|---|
| `plugins/save-prompt/scripts/log-prompt.sh` | the whole logger |
| `plugins/save-prompt/hooks/hooks.json` | registers the script for `UserPromptSubmit` |
| `plugins/save-prompt/.claude-plugin/plugin.json` | plugin manifest |
| `.claude-plugin/marketplace.json` | marketplace manifest |
| `tests/log-prompt.test.sh` | all tests plus a tiny harness |
| `.github/workflows/ci.yml` | runs the tests |
| `README.md`, `LICENSE`, `CITATION.cff`, `CHANGELOG.md`, `.gitignore`, `.gitattributes` | repo metadata and docs |

---

### Task 1: Repo scaffold and manifests

**Files:**
- Create: `.gitignore` (`.DS_Store`), `.gitattributes` (copy from `~/Repositories/improve-prompt-plugin/.gitattributes`), `LICENSE` (copy from `~/Repositories/read-aloud-plugin/LICENSE`), `CITATION.cff` (modeled on read-aloud's; title `save-prompt — Claude Code Plugin`, version `0.1.0`, date-released `2026-11-24`, urls point to `ricardorqr/save-prompt-plugin`), `CHANGELOG.md` (`# Changelog` plus `## [0.1.0] - 2026-11-24` with one "Initial release" bullet)
- Create: `.claude-plugin/marketplace.json`, `plugins/save-prompt/.claude-plugin/plugin.json`, `plugins/save-prompt/hooks/hooks.json`

**Interfaces:**
- Produces: hook command string `"${CLAUDE_PLUGIN_ROOT}"/scripts/log-prompt.sh` (Task 2 creates that file); plugin `name` = `save-prompt`.

- [ ] **Step 1: Initialise the repo.** In `~/Repositories/save-prompt-plugin` run `git init -b master`. Existing `docs/` stays untracked until the first commit.
- [ ] **Step 2: Write the manifests.** `plugin.json` mirrors read-aloud's fields (`name`, `displayName` "Save Prompt", `description`, `version` "0.1.0", `author.name`, `homepage`, `repository`, `keywords`). `marketplace.json` mirrors read-aloud's, with `name` `save-prompt-marketplace`, one plugin, `source` `./plugins/save-prompt`, `category` `productivity`. `hooks.json` has a single `UserPromptSubmit` entry (`matcher` `""`, one `command` hook) using the command string above.
- [ ] **Step 3: Write the remaining metadata files** listed above.
- [ ] **Step 4: Validate JSON.** Run `for f in .claude-plugin/marketplace.json plugins/save-prompt/.claude-plugin/plugin.json plugins/save-prompt/hooks/hooks.json; do jq empty "$f" && echo ok; done`. Expected: `ok` three times. If the `claude` CLI is available, also run `claude plugin validate .`; expected: no errors (a warning about the missing script is acceptable until Task 2).
- [ ] **Step 5: Commit.** `git add -A && git commit -m "chore: scaffold save-prompt plugin"`

---

### Task 2: Core logger and test harness

**Files:**
- Create: `plugins/save-prompt/scripts/log-prompt.sh` (mode `755`), `tests/log-prompt.test.sh`

**Interfaces:**
- Consumes: hook JSON on stdin: `{"prompt": "...", "cwd": "...", "session_id": "..."}`.
- Produces in the script: `branch_of() { ... }` taking a cwd and printing the branch string (stub returning `-` in this task; Task 3 implements it), `quote_prompt() { ... }` reading stdin and printing each line prefixed `> ` or `>` for blank lines, `append_entry() { ... }` taking the full entry text as `$1` and appending it to today's file (no lock yet; Task 4 adds it).
- Produces in the test file: `setup()` (fresh temp dir `$TMP`, exports `CLAUDE_PROMPTS_DIR=$TMP/prompts`), `payload() { prompt cwd session }` printing hook JSON built with `jq -n`, `run_hook() { json }` running the script with that JSON on stdin and setting `OUT`, `ERR`, `RC`, `today_file()` printing `$CLAUDE_PROMPTS_DIR/$(date +%F).md`, `mode_of() { path }` (use `stat -f %Lp` on Darwin, `stat -c %a` otherwise), `check() { name condition-command... }` counting passes and failures, and a final `exit` that is non-zero if any check failed.

- [ ] **Step 1: Write the failing tests** in `tests/log-prompt.test.sh` (harness above, then):
  - `creates_file_with_header_and_entry`: `payload "hello" "$TMP/ws" "abcd1234-5678"`; assert first line is `# Prompts — $(date +%F)`, a line matches `^## [0-9]{2}:[0-9]{2}:[0-9]{2}$`, and the file contains `- **Workspace:** $TMP/ws`, `- **Session:** abcd1234`, and `> hello`.
  - `multiline_prompt_is_blockquoted`: prompt `$'line1\n\nline3'` yields consecutive lines `> line1`, `>`, `> line3`.
  - `stdout_empty_and_exit_zero`: `OUT` is empty and `RC` is `0`.
  - `permissions_are_private`: `mode_of "$CLAUDE_PROMPTS_DIR"` is `700` and `mode_of "$(today_file)"` is `600`.
  - `content_is_literal`: prompt `'$(touch '"$TMP"'/pwned) `id` \n $HOME'` is stored verbatim after `> `, and `$TMP/pwned` does not exist.
- [ ] **Step 2: Run to verify failure.** `bash tests/log-prompt.test.sh`. Expected: failures (script missing).
- [ ] **Step 3: Implement `plugins/save-prompt/scripts/log-prompt.sh`.** Order: `command -v jq` guard (stderr message, exit 0); read stdin once; extract `prompt`, `cwd`, `session_id` with `jq -r` (empty-string default); build the entry per Global Constraints (`date +%H:%M:%S`, `date +%F`); `umask 077` before creating the directory and file so modes are `700`/`600`; end the script with `exit 0` and send nothing to stdout. Never `eval` or expand prompt text: pass it through variables and `printf '%s\n'` only.
- [ ] **Step 4: Run to verify pass.** `bash tests/log-prompt.test.sh`. Expected: all checks pass.
- [ ] **Step 5: Commit.** `git add -A && git commit -m "feat: log each prompt to a daily markdown file"` (plus the trailer).

---

### Task 3: Branch resolution

**Files:**
- Modify: `plugins/save-prompt/scripts/log-prompt.sh` (`branch_of`)
- Test: `tests/log-prompt.test.sh`

**Interfaces:**
- Consumes: `branch_of() { cwd }` stub, `payload`, `run_hook`, `today_file` from Task 2.
- Produces: `branch_of` printing a branch name, `(detached <short-sha>)`, or `-`.

- [ ] **Step 1: Write failing tests.** Add a `make_repo() { dir }` helper (`git init -b feature/x`, one empty commit with `-c user.name=t -c user.email=t@t`). Tests: `branch_in_repo` expects `- **Branch:** feature/x`; `branch_detached` (after `git checkout --detach`) expects a line matching `^- \*\*Branch:\*\* \(detached [0-9a-f]{7,}\)$`; `branch_outside_repo` (plain temp dir) expects `- **Branch:** -`; `branch_missing_cwd` (path that does not exist) expects `- **Branch:** -`; `cwd_with_spaces` (repo in `$TMP/my work dir`) expects the literal path in the Workspace line and the correct branch.
- [ ] **Step 2: Run to verify failure.** Expected: the three branch-name checks fail against the `-` stub.
- [ ] **Step 3: Implement `branch_of`.** Use `git -C "$cwd" rev-parse --abbrev-ref HEAD` with stderr silenced; when it prints `HEAD`, use `git -C "$cwd" rev-parse --short HEAD`; on any failure print `-`. Quote `"$cwd"` everywhere.
- [ ] **Step 4: Run to verify pass.** Expected: all checks pass.
- [ ] **Step 5: Commit.** `git commit -am "feat: record the git branch of the workspace"` (plus the trailer).

---

### Task 4: Robustness (lock, bad input, large prompts)

**Files:**
- Modify: `plugins/save-prompt/scripts/log-prompt.sh` (`append_entry`, input guards)
- Test: `tests/log-prompt.test.sh`

**Interfaces:**
- Consumes: `append_entry() { entry }` from Task 2.
- Produces: lock directory `$CLAUDE_PROMPTS_DIR/.lock` (created with `mkdir`, removed after the write); wait up to 5 seconds in 0.1 s steps, then write anyway and leave a stale lock untouched. When `CLAUDE_PROMPTS_DIR` is unset the directory is `$HOME/.claude/prompts`.

- [ ] **Step 1: Write failing tests:**
  - `second_entry_appends`: two runs on the same day give one `# Prompts` header and two `## ` entries.
  - `empty_prompt_is_skipped`: prompts `""` and `"   "` leave no file, `RC` 0.
  - `malformed_json_is_ignored`: stdin `not json` gives `RC` 0, empty `OUT`, no file.
  - `missing_jq_warns_and_exits_zero`: run `env PATH="$TMP/emptybin" /bin/bash "$HOOK"` (empty directory on PATH); `ERR` mentions `jq`, `RC` 0, empty `OUT`.
  - `missing_session_id_uses_dash`: payload without `session_id` gives `- **Session:** -`.
  - `unicode_roundtrip`: prompt `héllo 日本語 🎉` appears intact.
  - `large_prompt_intact`: a 200 KB prompt (`head -c 200000 /dev/zero | tr '\0' 'x'` followed by `END`) ends with a `> ...END` line and the file size is at least 200000 bytes.
  - `concurrent_runs_do_not_interleave`: start 20 hook runs in the background with prompts `msg-1` to `msg-20`, `wait`, expect 20 `## ` entries and each `> msg-N` line present exactly once, with every entry's four metadata lines directly above its quote.
  - `stale_lock_does_not_lose_prompt`: pre-create `$CLAUDE_PROMPTS_DIR/.lock`; the entry is still written, `RC` 0, finishes in under 10 seconds.
  - `default_dir_is_home`: unset `CLAUDE_PROMPTS_DIR`, set `HOME=$TMP/home`; file appears at `$TMP/home/.claude/prompts/<date>.md`.
- [ ] **Step 2: Run to verify failure.** Expected: the lock, empty-prompt, malformed-JSON and concurrency checks fail.
- [ ] **Step 3: Implement.** Guard: if `jq` fails to parse stdin, or the trimmed prompt is empty, exit 0 before touching the filesystem. Lock: loop `mkdir "$lockdir" 2>/dev/null` up to 50 times with `sleep 0.1`; if acquired, remove it with `rmdir` after the write (use a `trap` for `EXIT`); otherwise write anyway. Do the append as one `printf '%s'` redirect so a single entry is one write.
- [ ] **Step 4: Run to verify pass.** Expected: all checks pass, run it three times in a row to catch flakiness in the concurrency test.
- [ ] **Step 5: Commit.** `git commit -am "feat: lock appends and ignore empty or malformed input"` (plus the trailer).

---

### Task 5: CI, README, and real-world verification

**Files:**
- Create: `.github/workflows/ci.yml`, `README.md`
- Modify: `CHANGELOG.md` only if the slash-command finding needs a note

**Interfaces:**
- Consumes: the finished script and test file.

- [ ] **Step 1: Write `.github/workflows/ci.yml`** as a copy of read-aloud's (`name: CI`, triggers on push to `master` and on pull requests, `actions/checkout@v5`, the `for t in tests/*.test.sh` loop). The README badge points at it.
- [ ] **Step 2: Write `README.md`** in the style of improve-prompt's: title `save-prompt — Claude Code Plugin`, CI badge, one-paragraph overview, Requirements (`bash`, `jq`, `git`), Install (`/plugin marketplace add ricardorqr/save-prompt-plugin` then `/plugin install save-prompt@save-prompt-marketplace`), Update, Uninstall, an entry-format example copied from the spec, how to ask Claude to list prompts for a day or context, and a Privacy note (plain text, mode 600, may contain pasted secrets, nothing leaves the machine).
- [ ] **Step 3: Verify the whole suite.** `bash tests/log-prompt.test.sh`. Expected: all pass. If the `claude` CLI is available, `claude plugin validate .` reports no errors.
- [ ] **Step 4: Check slash-command behavior.** With the CLI available, run `CLAUDE_PROMPTS_DIR="$(mktemp -d)" claude -p "reply with ok" --plugin-dir ./plugins/save-prompt` and confirm one entry appears in that directory (this makes one small model call). Then ask Ricardo to confirm, in an interactive session with the plugin loaded, whether a `/command` prompt is logged; record the answer in the README under "Notes". Do not install the plugin into the real `~/.claude`.
- [ ] **Step 5: Commit.** `git add -A && git commit -m "docs: add README and CI workflow"` (plus the trailer). Stop there: no push.

---

## Self-review notes
- Spec coverage: format, branch rules, lock, permissions, env override, jq-missing, exit-0/no-stdout, distribution, tests list, slash-command check, files list — each maps to a task above.
- Decision added beyond the spec: empty or whitespace-only prompts are not logged; session shown as first 8 characters.
