# save-prompt plugin — design

Status: **approved by Ricardo with changes** (2026-11-24): global location, plugin packaging (B), `git init` allowed, structure to mirror `read-aloud-plugin` and `improve-prompt-plugin`.

## Intent and why
Every prompt Ricardo submits to Claude Code is appended to a Markdown file for that day, right after submission. Each entry records the time, workspace path and git branch. Later Ricardo can ask Claude to list all prompts for a day or for a specific context (a repo, a branch). It is shipped as a Claude Code plugin so teammates can install it on their own machines.

## Goals
- One file per day: `~/.claude/prompts/YYYY-MM-DD.md`, global across all projects (decided by Ricardo).
- Each entry has time, workspace, branch, session ID and the full prompt text.
- Readable by a human and fast for Claude to read or grep (Markdown, decided by Ricardo).
- Shareable through a plugin, structured like his other two plugins (decided by Ricardo).

## Non-goals
- No search or list command now. Claude reads the files when asked.
- No secret redaction (Ricardo hasn't asked for it). Mitigation: private file permissions.
- No logging of Claude's responses, only prompts.
- No automated release pipeline in the first build (see Calls).

## Anti-goals (failure even if it "works")
- The hook must never block, delay or alter a prompt. It always exits 0, even on bad input.
- It must print nothing to stdout, because stdout from a `UserPromptSubmit` hook is added to the model's context.
- It must not touch the network.

## Approaches considered
- **A. Script plus `install.sh` that edits `settings.json`.** Matches the install-script convention but edits teammates' settings.
- **B. Claude Code plugin (chosen by Ricardo).** No `settings.json` edits and teammates can disable it from `/plugin`.
- **C. README snippet only.** Manual and error-prone.

## Design
Repo `~/Repositories/save-prompt-plugin/`, branch `master`, laid out like `read-aloud-plugin`:

```
.claude-plugin/marketplace.json            marketplace save-prompt-marketplace, plugin source "./plugins/save-prompt"
plugins/save-prompt/.claude-plugin/plugin.json
plugins/save-prompt/hooks/hooks.json       UserPromptSubmit -> "${CLAUDE_PLUGIN_ROOT}"/scripts/log-prompt.sh
plugins/save-prompt/scripts/log-prompt.sh  the logger (bash + jq)
tests/log-prompt.test.sh                   feeds sample payloads, asserts on the output file
.github/workflows/ci.yml                   runs every tests/*.test.sh (same loop as read-aloud)
README.md                                  CI badge, install, update, uninstall, usage, requirements
LICENSE (MIT), CITATION.cff, CHANGELOG.md, .gitignore (.DS_Store), .gitattributes
docs/superpowers/specs/2026-11-24-save-prompt-design.md   this file
docs/superpowers/plans/2026-11-24-save-prompt-plugin.md   implementation plan
```

**Entry format** (the file starts with `# Prompts — YYYY-MM-DD`):

```
## 14:32:07
- **Workspace:** ~/projects/foo
- **Branch:** feature/bar
- **Session:** 1bb85011

> first line of the prompt
> second line
```

**Behavior**
- Read the JSON payload from stdin. Take `prompt`, `cwd`, `session_id`.
- Branch comes from `git -C "$cwd" rev-parse --abbrev-ref HEAD`. Detached HEAD shows `(detached <short-sha>)`. Outside a repo it shows `-`.
- Time and date use the local timezone.
- Every prompt line is prefixed with `> ` (blank lines become `>`), so prompts that contain Markdown headings can't break the file structure.
- Appends are guarded by a `mkdir` lock with a short bounded wait, so two open sessions can't interleave. If the lock can't be taken, it writes anyway rather than lose the prompt.
- Directory is created `700` and files `600`.
- `CLAUDE_PROMPTS_DIR` overrides the output directory (used by tests).
- If `jq` is missing, write one line to stderr and exit 0. The README lists `jq` as a requirement.

**Distribution** (same as his other plugins)
```
/plugin marketplace add ricardorqr/save-prompt-plugin
/plugin install save-prompt@save-prompt-marketplace
```

## Calls I made (not decided by Ricardo)
- Plugin name `save-prompt`; marketplace name `save-prompt-marketplace`; GitHub path `ricardorqr/save-prompt-plugin`, following his naming. The repo may not exist on GitHub yet. I will not create or push it.
- Release automation is left out of the first build. His two repos do it differently (semantic-release in read-aloud, a version-bump workflow in improve-prompt). The CI test workflow, LICENSE, CITATION.cff and CHANGELOG are included. Starting version is `0.1.0`.
- Bash + `jq` implementation; local timezone; session ID included; file permissions `700`/`600`; `> ` blockquote for prompt text.
- Manifest author is `ricardorqr`; copyright line "Ricardo Ribeiro", as in read-aloud.
- `.idea/` and `.superpowers/` from his other repos are not copied.
- An empty or whitespace-only prompt is not logged (nothing to record).
- The session is shown as the first 8 characters of the session ID.

## Left to the builder
- Exact test cases: normal entry, multi-line prompt, non-git directory, detached HEAD, empty prompt, same-day append, malformed JSON, no stdout, exit 0 on every path.
- Verify during testing whether slash-command prompts (e.g. `/my-skill ...`) also trigger the hook, and document what actually happens.

## Open
- Whether to add release automation later, and which style.
- No commit is made until the build is verified. No push, and no local install into his real `~/.claude`, without asking.
