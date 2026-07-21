---
name: ralph-brow
description: Scaffold the Ralph autonomous PRD build loop (ralph.sh core, engine wrappers, continuous supervisor, progress meter) into any project. Use whenever Felipe says "ralph", "ralph-brow", "ralph this", "set up ralph", "add the ralph harness", "prd loop", or "ralph it" — and also when he wants an autonomous per-task agent build loop over a prd.json task ledger, an overnight/hands-off build runner, or to copy the ralph harness into another project, even if he never says the word "ralph". Also use to spec a brand-new project: "spec a new project", "write a prd", "interview me about my project", "translate my requirements into prd.json", "start a project from scratch with ralph" — spec mode interviews Felipe, writes REQUIREMENTS.md, and generates the prd.json ledger. Asks scaffolding questions first, then generates the harness; never runs the loop itself. Engines: Claude Code CLI, Codex CLI (gpt-5.6-sol), and custom Codex providers (e.g. Sakana fugu).
argument-hint: [target project path]
---

# Ralph — PRD build-loop scaffolder

Ralph is a stateless autonomous build loop: each iteration a headless coding agent
reads `prd.json` (a JSON array of tasks), does ONLY the first task with
`"passes": false`, runs that task's own Verify steps, journals to `progress.txt`,
flips `passes` to true, commits, and stops. Statelessness means every run re-reads
the ledger and picks up the next task. A supervisor runs it in batches forever.

This skill SCAFFOLDS the harness into a target project from `templates/`.
**Ask first, then scaffold. Never run the loop itself unless explicitly asked —
each iteration costs real tokens and starts building.**

## 1. Preflight (read-only)

1. Target dir = argument if given, else cwd.
2. If any of `ralph.sh`, `ralph-*.sh`, `progress.sh`, `progress.txt` already exist
   there: STOP and show what exists — overwrite only with explicit confirmation.
3. PRD router — auto-detect, don't ask which mode:
   - **Valid `prd.json` exists** → continue to §2. Valid = JSON array where
     every task has EXACTLY the four fields `{category, description, steps,
     passes}` — no extras, no omissions — with one `"passes"` per line (the
     grep meter needs it). A ledger with extra/missing fields: flag what
     deviates and ask before proceeding — meters and loop prompts assume the
     canonical shape.
   - **No `prd.json` but a requirements doc exists** (`REQUIREMENTS.md`,
     `PRD.md`, `SPEC.md`, `docs/requirements*.md`, or similar) → read
     `references/spec-mode.md` and offer to translate it into `prd.json`.
   - **Neither** → read `references/spec-mode.md` and run full spec mode:
     interview → REQUIREMENTS.md → sign-off → translate → back here.
4. `which claude codex` — only offer engines whose CLI is installed.
5. `git rev-parse --git-dir` — note whether the repo is git-initialized (affects
   codex flags and the commit step wording; the harness tolerates git-less repos).

## 2. Ask (AskUserQuestion, keep it to 1–2 rounds)

- **Project name + banner emoji** (e.g. "Fugu Faces", 🐡) and PRD filename
  (default `prd.json`).
- **Engines**: claude / codex / custom codex provider — multiSelect. For a custom
  provider also collect: engine name (e.g. `fugu`), codex `model_provider` id
  (must exist in `~/.codex/config.toml`), model id, and the env var NAME holding
  its API key (e.g. `SAKANA_API_KEY`).
- **Golden rules** for the prompt: stack/conventions, reference or clean-room
  paths (what the agent may/may not read), push policy (RALPH_PUSH default: 0
  unless a remote exists), anything project-specific.
- **Telegram notifications** for the supervisor: on/off (token via env or
  `~/.openclaw/openclaw.json`).

## 3. Scaffold

Render each template by reading it and Writing the final file with every token
replaced. Do the substitution in-context while writing — do NOT pipe through
`sed`: `{{GOLDEN_RULES}}` is a multi-line block and one-line sed replacements
mangle it (newlines, bullets, slashes).

Tokens:

| Token | Meaning |
|---|---|
| `{{PROJECT_NAME}}` / `{{PROJECT_SLUG}}` | Display name / kebab slug |
| `{{BANNER_EMOJI}}` | Supervisor banner + Telegram emoji |
| `{{PRD_FILE}}` | Ledger filename (usually `prd.json`) |
| `{{GOLDEN_RULES}}` | Project rules block inside the prompt heredoc |
| `{{COMPLETE_TAGLINE}}` | Final Telegram flourish ("The fugu has a face.") |
| `{{CUSTOM_ENGINE}}` / `{{CUSTOM_PROVIDER}}` / `{{CUSTOM_MODEL}}` / `{{CUSTOM_ENV_KEY}}` | Custom codex-provider engine |

Files: `ralph.sh` (core), `ralph-continuous.sh` (supervisor), `progress.sh`
(meter), one `ralph-<engine>.sh` per chosen engine from `wrapper.sh`,
`progress.txt` from `progress.txt.seed`, and — only if a custom provider needs a
key — `.env.ralph.local` from `env.ralph.local.example` (chmod 600; confirm the
project's `.gitignore` covers it, e.g. `.env*.local`, before writing a secret).

If NO custom engine was chosen: delete the `{{CUSTOM_ENGINE}}` branches from
`ralph.sh`/`ralph-continuous.sh` (they are clearly marked `# --custom-engine--`).

`chmod +x` every script.

## 4. Verify (always)

- `/bin/bash -n` every script — **must use /bin/bash (3.2)**: macOS's only bash.
- `./progress.sh` prints `0/N (0%)` and the ledger is untouched afterwards.
- `./ralph.sh` with no args prints usage.
- Print a cheatsheet: `./ralph-<engine>.sh 1` (one task), `./ralph-continuous.sh
  <engine>` (forever), knobs live in `.env.ralph.local`.

## Hard-won facts (do not rediscover)

- **bash 3.2 (macOS default): NEVER put a heredoc inside `$(...)`** if the body
  can contain an apostrophe — 3.2 fails to parse the file. Assign prompts with
  `read -r -d '' VAR <<'EOF' … EOF || true` (what the templates do).
- `codex exec` = non-interactive one-shot: final answer → stdout, progress →
  stderr, check the exit code. No `@file` attachments — the prompt must tell it
  to read the ledger/journal first. Text mode reports no token usage/cost.
- Codex needs `--skip-git-repo-check` in repos without `.git`, and
  `--sandbox workspace-write` blocks network unless you add
  `-c 'sandbox_workspace_write.network_access=true'` (npm install / git push
  need it). Don't use `--dangerously-bypass-approvals-and-sandbox`.
- Custom codex providers: `-c model_provider=<id>` + `-m <model>`; the provider
  block in `~/.codex/config.toml` must set `env_key` to the env var **NAME**
  (e.g. `"SAKANA_API_KEY"`) — never the literal key.
- Claude engine: `claude --dangerously-skip-permissions --no-session-persistence
  -p --output-format json "@<prd> @progress.txt <prompt>"`; jq out `.result`,
  `.total_cost_usd`, `.usage.*` for per-iteration accounting.
- The completion sentinel is the exact line `<promise>COMPLETE</promise>`,
  emitted only when every ledger task passes; the supervisor greps for
  "PRD COMPLETE" from ralph.sh's banner to stop.
- `progress.sh` counts `"passes"` vs `"passes": true` lines — the ledger must
  keep one flag per line (jq-rewriting the file preserves this).
