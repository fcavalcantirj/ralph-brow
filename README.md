# ralph-brow 🤖🔁

A [Claude Code skill](https://docs.claude.com/en/docs/claude-code/skills) that scaffolds the **Ralph autonomous build loop** into any project — ask a few questions, get a complete self-driving harness that builds your product task by task from a `prd.json` ledger.

Inspired by the "Ralph Wiggum" technique: run a stateless coding agent in a loop against a task ledger until everything passes.

## The loop

```
┌─────────────────────────────────────────────────────┐
│  ralph-continuous.sh  (supervisor: batches forever) │
│    └── ralph.sh N  (bounded loop)                   │
│          each iteration, a FRESH headless agent:    │
│          1. reads prd.json + progress.txt           │
│          2. picks FIRST task with passes=false      │
│          3. does ONLY that task (tests-first)       │
│          4. runs the task's own Verify steps        │
│          5. journals to progress.txt                │
│          6. flips passes → true                     │
│          7. commits · stops                         │
└─────────────────────────────────────────────────────┘
```

Statelessness is the trick: no conversation memory, no drift — every run re-reads the ledger and picks up exactly where the last one stopped. `progress.txt` is the durable memory; `prd.json` is the single source of truth. When every task passes, the loop emits `<promise>COMPLETE</promise>` and shuts itself down.

## Engines

The scaffolded harness is engine-agnostic — pick per run:

| Wrapper | Engine | Notes |
|---|---|---|
| `./ralph-claude.sh N` | Claude Code CLI (headless `claude -p`) | per-iteration token + cost accounting |
| `./ralph-codex.sh N` | Codex CLI (`gpt-5.6-sol`, reasoning max) | `codex exec`, sandboxed with network |
| `./ralph-<custom>.sh N` | Any Codex `model_provider` (e.g. Sakana fugu) | provider from `~/.codex/config.toml` |

`./ralph-continuous.sh <engine>` supervises: fixed-size batches, pauses between batches, automatic backoff on rate limits / 429 / 503, optional Telegram notifications, stops at 100%.

## Install (as a Claude Code skill)

```bash
git clone https://github.com/fcavalcantirj/ralph-brow.git ~/dev/ralph-brow
ln -s ~/dev/ralph-brow ~/.claude/skills/ralph-brow
```

## Use

In any project, inside Claude Code:

```
/ralph-brow
```

The skill checks your prerequisites (a valid `prd.json` ledger, installed CLIs, git state), asks 1–2 rounds of questions (project name, engines, golden rules, notifications), renders the harness from `templates/`, and verifies everything — without ever starting the loop itself. Then:

```bash
./ralph-claude.sh 1          # one task, watch it work
./ralph-continuous.sh codex  # hands off, go to sleep
```

## Spec mode — no PRD? It builds one with you

The skill auto-detects where your project stands:

- **`prd.json` exists** → straight to scaffolding.
- **Requirements doc exists** (`REQUIREMENTS.md`, `PRD.md`, `SPEC.md`…) but no ledger → it offers to translate your requirements into `prd.json`, asking only about genuine gaps.
- **Nothing yet** → **spec mode**: a real product interview (it mines your repo and conversation first — no obvious questions), writes `REQUIREMENTS.md`, waits for your sign-off, then translates it into the ledger.

Generated ledgers follow [Anthropic's guidance for long-running agent harnesses](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents): a strictly 4-field task schema (validated with `jq` before hand-off), end-to-end user-verifiable steps, initializer tasks first, one-session granularity (err toward more, smaller tasks), every task starting `passes: false`, and an immutable-ledger rule — the loop only ever flips `passes`.

## The ledger format

`prd.json` is a JSON array, ordered by priority:

```json
[
  {
    "category": "infra",
    "description": "Initialize the repository and toolchain",
    "steps": [
      "Run git init with main as default branch.",
      "…",
      "Verify: npm ci succeeds from a clean checkout."
    ],
    "passes": false
  }
]
```

Conventions the harness understands: an `URGENT` prefix jumps the queue, `DEPENDS ON:` notes gate ordering, every task carries its own `Verify:` steps, and tasks whose verification is human-only get a `UAT:` line in the journal instead of being skipped.

## What gets scaffolded

| File | Role |
|---|---|
| `ralph.sh` | engine-agnostic core loop |
| `ralph-<engine>.sh` | one thin wrapper per engine you chose |
| `ralph-continuous.sh` | forever-supervisor (batches, backoff, Telegram) |
| `progress.sh` | `12/45 (26%)` progress meter |
| `progress.txt` | append-only build journal (the loop's memory) |
| `.env.ralph.local` | git-ignored knobs + provider API key (only if needed) |

## Battle-tested details

Lessons already baked into the templates so you don't rediscover them:

- **macOS bash 3.2** cannot parse a heredoc inside `$(...)` when the body contains an apostrophe — prompts are assigned with `read -r -d ''` instead.
- `codex exec` needs `--skip-git-repo-check` before your first task git-inits the repo, and `workspace-write` sandboxing blocks network unless you pass `-c 'sandbox_workspace_write.network_access=true'` (`npm install` needs it).
- Custom Codex providers authenticate via `env_key` in `~/.codex/config.toml` — it must hold the env var *name*, never the key itself.
- The harness tolerates repos that aren't git-initialized yet (commits start once your first infra task creates `.git`).

## License

[MIT](LICENSE) — Felipe Cavalcanti
