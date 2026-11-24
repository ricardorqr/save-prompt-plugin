# save-prompt — Claude Code Plugin

[![CI](https://github.com/ricardorqr/save-prompt-plugin/actions/workflows/ci.yml/badge.svg)](https://github.com/ricardorqr/save-prompt-plugin/actions/workflows/ci.yml)

A Claude Code plugin that saves **every prompt you submit** to a Markdown file,
one file per day, across all your projects. Each entry records the time, the
workspace path, the git branch and the session, so you can later ask Claude to
list everything you asked on a given day, in a given repo, or on a given branch.

It is a `UserPromptSubmit` hook, so it runs the moment you press enter, outside
the model: it can't be forgotten, it costs no tokens, and it never changes or
delays your prompt.

---

## Requirements

- `bash` (macOS's built-in 3.2 is fine)
- [`jq`](https://jqlang.github.io/jq/) — `brew install jq`
- `git` (only used to read the branch name)

If `jq` is missing the hook does nothing except write one line to stderr; it
never blocks a prompt.

## Install

Add the marketplace once, then install the plugin:

```
/plugin marketplace add ricardorqr/save-prompt-plugin
/plugin install save-prompt@save-prompt-marketplace
```

Restart Claude Code (or start a new session). From then on every prompt is
logged.

## Update

```
/plugin marketplace update save-prompt-marketplace
/plugin install save-prompt@save-prompt-marketplace
```

## Uninstall

```
/plugin uninstall save-prompt@save-prompt-marketplace
```

- **Disable instead of remove:** use the `/plugin` menu to toggle it off while
  keeping it installed.
- Your saved prompts in `~/.claude/prompts/` are **not** deleted.

---

## What it writes

One file per day: `~/.claude/prompts/YYYY-MM-DD.md` (local date). Each prompt is
appended as an entry:

```
# Prompts — 2026-11-24

## 14:32:07
- **Workspace:** /Users/you/projects/foo
- **Branch:** feature/bar
- **Session:** 1bb85011

> first line of the prompt
> second line
```

- **Branch** is `-` when the workspace is not a git repo, and
  `(detached <sha>)` on a detached HEAD.
- **Session** is the first 8 characters of the session ID, so you can group the
  prompts of one conversation.
- Every prompt line is prefixed with `> `, so a prompt that contains Markdown
  headings can't break the file's structure.
- Empty or whitespace-only prompts are not logged.

Set `CLAUDE_PROMPTS_DIR` to write somewhere other than `~/.claude/prompts`.

## Using it

The files are plain Markdown; just ask Claude:

- *"List all the prompts I entered on 2026-11-24."*
- *"Show the prompts I entered in the `my-project` repo this week."*
- *"What did I ask on branch `feature/bar`?"*

## Notes

- **Slash commands.** Prompts that start with a skill or plugin command (for
  example `/improve-prompt:coding fix flaky test`) are logged as typed.
  Built-in local commands such as `/context` did **not** trigger the hook in a
  headless (`claude -p`) run; they have not been checked in an interactive
  session.
- **Several sessions at once** are safe: appends are serialised with a small
  lock, and a stale lock never causes a prompt to be lost.

## Privacy

Prompts are saved in **plain text** and may contain anything you paste, including
secrets. The folder is created with mode `700` and the files with `600`, so only
your user can read them. Nothing is sent anywhere: the hook never touches the
network.

## Testing

```
bash tests/log-prompt.test.sh
```

The suite needs `bash`, `jq` and `git`, and runs in CI on every push and pull
request.

## Repo layout

```
.claude-plugin/marketplace.json            marketplace (save-prompt-marketplace)
plugins/save-prompt/.claude-plugin/        plugin manifest
plugins/save-prompt/hooks/hooks.json       registers the UserPromptSubmit hook
plugins/save-prompt/scripts/log-prompt.sh  the logger
tests/log-prompt.test.sh                   test suite
docs/superpowers/                          design and implementation plan
```

## License

MIT — see [LICENSE](LICENSE).
