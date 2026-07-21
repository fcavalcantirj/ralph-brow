# Spec mode — interview → REQUIREMENTS.md → prd.json

Read this when the auto-detect router sends you here. The goal: turn a fuzzy
project idea into a validated task ledger the Ralph loop can build unattended,
following Anthropic's long-running-agent harness guidance
(anthropic.com/engineering/effective-harnesses-for-long-running-agents).

## Auto-detect: pick the entry point yourself

Run this decision on every invocation — don't ask the user "which mode":

1. **Valid `prd.json` exists** → skip spec mode entirely; go straight to the
   scaffold flow in SKILL.md.
2. **No `prd.json`, but a requirements doc exists** — check for
   `REQUIREMENTS.md`, `requirements.md`, `PRD.md`, `SPEC.md`,
   `docs/requirements*.md`, or anything similar (a Glob + a skim decides) →
   ask: "Found `<file>` — translate it into `prd.json`?" On yes: read it in
   full, apply the Translation rules below, and ask targeted questions ONLY
   about genuine gaps (missing verification strategy, unstated stack, etc.).
3. **Neither exists** → full spec mode: interview → REQUIREMENTS.md →
   sign-off → translate → scaffold.

## The interview

This is a real product interview, not a form. The user is trusting you to ask
the questions a good technical cofounder would ask.

**Mine context first.** Before asking anything, extract what the repo and the
conversation already answer: existing code and stack, README fragments, prior
discussion of the idea, installed CLIs. Never ask what you can already know —
open by confirming your inferences in one line ("Next.js + Vercel, localhost
dev, right?") instead of asking open-ended what-stack questions.

**Run it in AskUserQuestion rounds** — 2–4 questions per round, as many rounds
as the project's depth deserves. Drill until you could write the requirements
yourself. One sharp follow-up on a vague answer beats three new generic
questions.

What to dig into (skip whatever context already answered):

- **The demo journey**: the ONE end-to-end flow that must work when the loop
  finishes. "A visitor opens the site, presses talk, speaks, and the face
  answers out loud." Everything else orbits this.
- **Users**: who actually uses it, and what do they already use today?
- **Scope surgery**: what is irreducible v1 core vs nice-to-have? Actively
  challenge scope — propose cuts and make the user defend what stays.
- **Platform + deploy target**: localhost only? Vercel? A Hetzner box? Mobile?
- **Integrations and credentials**: which providers, and which keys does the
  user ACTUALLY have right now? (A task the loop can't verify for lack of a
  key becomes a UAT trap — better to know up front.)
- **Data**: what persists, where, and what must never leak client-side?
- **Done**: what does the user check to declare v1 finished?
- **Non-goals**: what is explicitly OUT, so the loop never wanders there.
- **Reference material**: existing repos/exports/designs the loop may consult —
  and their provenance/license. If ownership is undocumented, record that the
  reference is inspect-only (clean-room lesson: an autonomous agent will
  rightly refuse to copy from unlicensed sources).
- **Verification environment**: how can a HEADLESS agent verify features?
  Browser automation (Playwright/Puppeteer) available? CLI-testable? This
  decides how `steps` get written. Also capture the ONE host-side command that
  must always pass on a healthy checkout — it becomes the `VERIFY_CMD` scaffold
  knob (SKILL.md §2), the harness's ground truth outside the engine sandbox.

## REQUIREMENTS.md

Write the interview's outcome to `REQUIREMENTS.md` at the target repo root:

```markdown
# <Project> — Product Requirements
## Vision            (one paragraph)
## Users
## Core journeys     (the demo journey first, numbered steps)
## Functional requirements   (grouped; each one testable)
## Non-functional    (stack, security, deploy, performance)
## Out of scope      (explicit non-goals)
## Verification strategy     (how a headless agent proves each area works)
```

**CHECKPOINT — get the user's sign-off on REQUIREMENTS.md before generating
any JSON.** The markdown is cheap to iterate; a wrong ledger burns loop
iterations.

## Translation rules — REQUIREMENTS.md → prd.json

- **Deterministic schema. Every task has EXACTLY these four fields — no more,
  no fewer, ever**: `category`, `description`, `steps`, `passes`. No `id`, no
  `priority`, no `headless_verifiable`, no extras. The whole harness
  (progress meters, loop prompts, immutability rules) assumes this shape.

The canonical task (keep this shape exactly):

```json
{
  "category": "functional",
  "description": "New chat button creates a fresh conversation",
  "steps": [
    "Navigate to main interface",
    "Click the 'New Chat' button",
    "Verify a new conversation is created",
    "Check that chat area shows welcome state",
    "Verify conversation appears in sidebar"
  ],
  "passes": false
}
```

- **Order = build order.** JSON array, top-to-bottom priority. First tasks
  follow the initializer pattern: git init + toolchain, dev-server/init
  script, then features in dependency order. Encode dependencies in prose
  ("DEPENDS ON: …") inside `description` when ordering alone isn't enough.
- **Steps are end-to-end verification a user would perform** — "Navigate to…",
  "Click…", "Speak into…", "Verify…". Written so a human or a
  browser-automation agent can execute them literally. Unit tests support a
  task; they never replace its user-visible verification.
- **Granularity**: one loop iteration = one task. Err toward MORE, smaller
  tasks — tens to 200+ depending on scope. Big compound tasks invite
  one-shotting and half-done `passes: true`.
- **Every task starts `passes: false`.** All of them.
- **Formatting**: one `"passes"` flag per line in the file (the grep-based
  progress meter counts lines).
- **Coverage check before finishing**: walk REQUIREMENTS.md requirement by
  requirement — each maps to ≥1 task; every task traces back to a
  requirement. Fix orphans on either side.

**Mandatory validation gate** — run after writing the file, regenerate until
it passes; never hand over an unvalidated ledger:

```bash
jq -e 'type == "array" and length > 0 and all(.[];
  (keys | sort) == ["category","description","passes","steps"]
  and (.category | type) == "string"
  and (.description | type) == "string"
  and (.passes == false)
  and (.steps | type == "array" and length > 0 and all(.[]; type == "string"))
)' prd.json
```

Also verify: `grep -c '"passes"' prd.json` equals `jq length prd.json`.

## Ledger immutability (bake into the generated harness)

When you later render `{{GOLDEN_RULES}}` for this project, include: the loop
never edits, removes, or reorders ledger tasks — the ONLY field it may change
is `passes`, one task per iteration, after that task's own steps verify. This
is what keeps a 200-task overnight run honest.

## Hand-off

With `prd.json` written and validated, return to SKILL.md §2 (Ask) and
continue the normal scaffold flow — but skip every question the interview
already answered (project name, stack, reference paths, push policy are
usually all known by now).
