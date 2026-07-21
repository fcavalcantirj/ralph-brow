# Overnight runs — tmux, pacing, and the smoke-first rule

Read this when the user wants the loop running unattended — overnight, all
weekend, "leave it going", "run it in tmux". Relay the relevant parts; don't
start the loop yourself unless explicitly asked.

## Detach or die

Never launch `ralph-continuous.sh` as a child of an agent session or a
terminal that will close: when the parent tears down, the loop takes a SIGHUP
and dies mid-run — typically discovered the next morning at task 1 of 40.
(Lived experience: the first agent-faces overnight run died exactly this way
after one task.)

Run it in a detached tmux session instead — it survives any teardown:

```bash
tmux new-session -d -s ralph './ralph-continuous.sh claude >> ralph-continuous.log 2>&1'

tmux ls                        # liveness — is the session still there?
tail -f ralph-continuous.log   # watch it work
./progress.sh                  # ledger progress any time
tmux kill-session -t ralph     # stop — prefer during a pause countdown
```

Keep every knob in `.env.ralph.local` (the scripts source it), so the tmux
command stays a bare script invocation — no env-var prefix to forget on
relaunch. The supervisor detects it's not on a TTY and logs one line per
pause instead of animated countdowns.

## Pace for the usage windows

Claude subscriptions meter TWO budgets: a **5-hour rolling window** and a
**7-day weekly cap**. An unpaced loop hammers iteration after iteration,
exhausts the 5-hour window before midnight, spends the rest of the night in
rate-limit backoff, and eats a chunk of the week's cap for one project.

The pacing knobs are `BATCH_SIZE` (tasks per burst) and `BATCH_PAUSE_MINS`
(rest between bursts). The arithmetic, so you can retune instead of guess:

    tasks/hour ≈ BATCH_SIZE × 60 / (BATCH_SIZE × avg_task_mins + BATCH_PAUSE_MINS)

Overnight starting point — `BATCH_SIZE=2`, `BATCH_PAUSE_MINS=30`, with a
typical ~10-min task: 2×60/(20+30) ≈ **2.4 tasks/hour, ~19 tasks across 8
hours** — steady progress spread across the night instead of slammed into the
first window. Tune from the first batch's actual task times: long build/test
tasks (15–20 min) can take shorter pauses; quick doc tasks deserve longer
ones.

The supervisor's rate-limit backoff is *reactive* protection — it stops the
hammering after the window is already gone. Proactive pauses are what
preserve the weekly cap. Codex and custom providers have their own
provider-side limits and per-request costs; the same pacing logic applies.

## Smoke before you sleep — non-negotiable

Before ANY unattended run: execute 1–2 attended iterations and actually read
the results —

```bash
./ralph-claude.sh 1     # or 2, on the engine you'll run overnight
git log -1 --stat       # what did it commit?
tail -30 progress.txt   # does the journal entry make sense?
./progress.sh
```

One supervised iteration catches a broken Verify step, a missing API key, a
sandbox/network refusal, or a mis-ordered ledger while it costs ten minutes.
Discovering the same thing at 7am costs the whole night AND the quota it
burned failing repeatedly.

## Clean cut-overs

To retune mid-run (pause length, batch size, engine): kill the tmux session
**during a pause countdown** — never mid-iteration — adjust
`.env.ralph.local`, relaunch the same tmux one-liner. Statelessness makes
this safe: the next iteration re-reads the ledger and continues exactly where
the loop stopped. A morning-after check is: `tmux ls`, `./progress.sh`,
`tail -50 ralph-continuous.log`, then `git log --oneline` to review the
night's commits.
