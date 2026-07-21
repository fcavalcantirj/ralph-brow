#!/bin/bash
set -eu

# ─────────────────────────────────────────────────────────────────────────────
# smoke.sh — self-test for the ralph-brow templates. Run from anywhere:
#   bash tests/smoke.sh          → ... SMOKE OK
#
# Renders the templates with dummy tokens into a temp dir, syntax-checks them,
# then drives ralph.sh/ralph-continuous.sh with a FAKE claude engine (no
# network, never touches .git — simulating a sandbox-blocked engine) to assert
# the host-side backstops: git auto-init, per-iteration auto-commit, VERIFY_CMD
# veto + URGENT injection + dedupe + recovery, supervisor completion, UAT meter.
# Deps: bash, jq, git, sed. Runs in seconds; everything stays in $WORK.
# ─────────────────────────────────────────────────────────────────────────────

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT/skills/ralph-brow/templates"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Full isolation: no real ~/.openclaw (Telegram fallback), no ~/.gitconfig.
export HOME="$WORK"
export GIT_AUTHOR_NAME=ralph GIT_AUTHOR_EMAIL=ralph@smoke.local
export GIT_COMMITTER_NAME=ralph GIT_COMMITTER_EMAIL=ralph@smoke.local

fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }
note() { echo "  ✓ $*"; }

# ── Render templates with dummy tokens ──────────────────────────────────────
render() {
  sed \
    -e 's|{{PROJECT_NAME}}|Smoke Test|g' \
    -e 's|{{PROJECT_SLUG}}|smoke-test|g' \
    -e 's|{{BANNER_EMOJI}}|🧪|g' \
    -e 's|{{PRD_FILE}}|prd.json|g' \
    -e 's|{{GOLDEN_RULES}}|Keep it simple. This is a smoke-test project.|g' \
    -e 's|{{COMPLETE_TAGLINE}}|Smoke cleared.|g' \
    -e 's|{{CUSTOM_ENGINE}}|smokey|g' \
    -e 's|{{CUSTOM_PROVIDER}}|smokeprov|g' \
    -e 's|{{CUSTOM_MODEL}}|smoke-1|g' \
    -e 's|{{CUSTOM_ENV_KEY}}|SMOKE_API_KEY|g' \
    -e 's|{{ENGINE}}|claude|g' \
    -e 's|{{ENGINE_LABEL}}|Claude Code|g' \
    -e 's|{{DATE}}|2026-01-01|g' \
    -e 's|{{TASK_COUNT}}|1|g' \
    -e 's|{{ENGINE_LIST}}|ralph-claude.sh|g' \
    "$1" > "$2"
}

RENDER="$WORK/rendered"
mkdir -p "$RENDER"
render "$TPL/ralph.sh" "$RENDER/ralph.sh"
render "$TPL/ralph-continuous.sh" "$RENDER/ralph-continuous.sh"
render "$TPL/progress.sh" "$RENDER/progress.sh"
render "$TPL/wrapper.sh" "$RENDER/ralph-claude.sh"
chmod +x "$RENDER"/*.sh

# ── S1: syntax ──────────────────────────────────────────────────────────────
for script in "$RENDER"/*.sh; do
  /bin/bash -n "$script" || fail "bash -n rejected $script"
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S error "$RENDER"/*.sh || fail "shellcheck -S error rejected a rendered script"
  note "S1 syntax (bash -n + shellcheck)"
else
  note "S1 syntax (bash -n; shellcheck not installed)"
fi

# ── Fake engine: flips first open task, journals, emits claude-CLI JSON.
# Never touches .git and makes no network calls — a sandbox-blocked engine.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/claude" <<'FAKE'
#!/bin/bash
set -eu
if [ "${FAKE_MODE:-normal}" != "noop" ]; then
  t=$(mktemp)
  jq '(map(.passes == false) | index(true)) as $i
      | if $i == null then . else .[$i].passes = true end' prd.json > "$t" && mv "$t" prd.json
  printf '\n%s\n' "2026-01-01: fake engine did one task." >> progress.txt
fi
if jq -e 'all(.[]; .passes == true)' prd.json >/dev/null; then
  r="Done. <promise>COMPLETE</promise>"
else
  r="Did one task."
fi
jq -cn --arg r "$r" '{result:$r, is_error:false, subtype:"success", total_cost_usd:0.01,
  usage:{input_tokens:10, output_tokens:5, cache_read_input_tokens:0, cache_creation_input_tokens:0}}'
FAKE
chmod +x "$WORK/bin/claude"
export PATH="$WORK/bin:$PATH"

# ── Scenario helpers ────────────────────────────────────────────────────────
mkproj() { # <dir> <ntasks>
  mkdir -p "$1"
  cp "$RENDER/ralph.sh" "$RENDER/progress.sh" "$1/"
  jq -n --argjson n "$2" '[range($n) | {category:"infra",
    description:("Task \(.+1): do thing \(.+1)"),
    steps:["do the thing"], passes:false}]' > "$1/prd.json"
  printf '%s\n' "# smoke-test build journal" > "$1/progress.txt"
}
run_ralph() { # <dir> <iterations> [env pairs...] — sets rc and LOG
  local dir="$1" n="$2"; shift 2
  LOG="$WORK/run.log"; rc=0
  (cd "$dir" && env ENGINE=claude "$@" ./ralph.sh "$n") > "$LOG" 2>&1 || rc=$?
}
commits() { git -C "$1" log --oneline 2>/dev/null | wc -l | tr -d ' '; }

# ── S2: git backstop — auto-init, one commit per iteration, journal-derived
# message, COMPLETE with passing verify ─────────────────────────────────────
A="$WORK/proj-a"; mkproj "$A" 2
run_ralph "$A" 2 VERIFY_CMD=true
[ "$rc" -eq 0 ] || fail "S2 expected rc=0, got $rc ($(tail -5 "$LOG"))"
[ -d "$A/.git" ] || fail "S2 .git was not auto-created"
[ "$(commits "$A")" -eq 2 ] || fail "S2 expected exactly 2 commits, got $(commits "$A")"
git -C "$A" log -1 --format=%s | grep -q "fake engine did one task" \
  || fail "S2 commit message not derived from progress.txt"
[ -z "$(git -C "$A" status --porcelain)" ] || fail "S2 tree not clean after run"
grep -q "PRD COMPLETE" "$LOG" || fail "S2 missing PRD COMPLETE banner"
(cd "$A" && ./progress.sh) | grep -q "UAT pending" && fail "S2 UAT suffix shown with no UAT lines"
note "S2 git auto-init + per-iteration auto-commit + COMPLETE"

# ── S2b: clean tree ⇒ no new commit ─────────────────────────────────────────
run_ralph "$A" 1 VERIFY_CMD=true FAKE_MODE=noop
[ "$rc" -eq 0 ] || fail "S2b expected rc=0, got $rc"
[ "$(commits "$A")" -eq 2 ] || fail "S2b committed on a clean tree"
note "S2b clean-tree guard (no spurious commit)"

# ── S3: engine claims COMPLETE, host verify fails ⇒ veto + URGENT injection ─
B="$WORK/proj-b"; mkproj "$B" 1
run_ralph "$B" 1 VERIFY_CMD=false
[ "$rc" -eq 1 ] || fail "S3 expected rc=1 (veto), got $rc"
grep -q "PRD COMPLETE" "$LOG" && fail "S3 banner shown despite failed verify"
[ "$(jq length "$B/prd.json")" -eq 2 ] || fail "S3 expected 2 tasks after injection"
[ "$(jq '[.[] | select(.passes == false and (.description | startswith("URGENT: host verification failed")))] | length' "$B/prd.json")" -eq 1 ] \
  || fail "S3 expected exactly one open URGENT task"
grep -q "HOST VERIFY FAILED" "$B/progress.txt" || fail "S3 journal entry missing"
jq -e 'all(.[]; (keys | sort) == ["category","description","passes","steps"])' "$B/prd.json" >/dev/null \
  || fail "S3 injected task violates the 4-field schema"
[ "$(grep -c '"passes"' "$B/prd.json")" -eq "$(jq length "$B/prd.json")" ] \
  || fail "S3 broke the one-passes-per-line contract"
note "S3 COMPLETE veto + schema-clean URGENT injection"

# ── S4: verify still failing ⇒ dedupe, no second URGENT (loop-end path) ─────
run_ralph "$B" 1 VERIFY_CMD=false FAKE_MODE=noop
[ "$rc" -eq 0 ] || fail "S4 expected rc=0 (informational loop-end verify), got $rc"
[ "$(jq length "$B/prd.json")" -eq 2 ] || fail "S4 dedupe failed — task count changed"
[ "$(jq '[.[] | select(.passes == false and (.description | startswith("URGENT")))] | length' "$B/prd.json")" -eq 1 ] \
  || fail "S4 expected still exactly one open URGENT task"
note "S4 dedupe on repeated verify failure"

# ── S5: recovery — engine fixes the URGENT task, verify green ⇒ COMPLETE ────
before=$(commits "$B")
run_ralph "$B" 1 VERIFY_CMD=true
[ "$rc" -eq 0 ] || fail "S5 expected rc=0, got $rc"
grep -q "PRD COMPLETE" "$LOG" || fail "S5 missing PRD COMPLETE after recovery"
jq -e 'all(.[]; .passes == true)' "$B/prd.json" >/dev/null || fail "S5 ledger not fully passed"
[ "$(commits "$B")" -gt "$before" ] || fail "S5 recovery iteration was not committed"
note "S5 self-healing recovery to COMPLETE"

# ── S6: supervisor happy path — banner contract between the two scripts ─────
C="$WORK/proj-c"; mkproj "$C" 1
cp "$RENDER/ralph-continuous.sh" "$C/"
rc=0
(cd "$C" && env ENGINE=claude VERIFY_CMD=true BATCH_SIZE=1 BATCH_PAUSE_MINS=0 WAIT_TIME_MINS=0 \
  TELEGRAM_CHAT_ID= ./ralph-continuous.sh claude) > "$WORK/sup.log" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "S6 supervisor expected rc=0, got $rc ($(tail -5 "$WORK/sup.log"))"
grep -q "PRD COMPLETE" "$WORK/sup.log" || fail "S6 supervisor never saw the completion banner"
note "S6 supervisor stops on completion"

# ── S7: UAT meter ───────────────────────────────────────────────────────────
printf '%s\n%s\n' "UAT: confirm the face lip-syncs on real audio" \
  "UAT: confirm audible speech on real hardware" >> "$A/progress.txt"
(cd "$A" && ./progress.sh) | grep -q "2 UAT pending" || fail "S7 progress.sh did not report 2 UAT pending"
note "S7 UAT pending meter"

# ── S8: meter is formatting-immune — engines rewrite the ledger with arbitrary
# JSON spacing (a real claude run produced compact "passes":true) ────────────
D="$WORK/proj-d"; mkdir -p "$D"
cp "$RENDER/progress.sh" "$D/"
printf '%s' '[{"category":"infra","description":"t1","steps":["s"],"passes":true},{"category":"infra","description":"t2","steps":["s"],"passes":false}]' > "$D/prd.json"
(cd "$D" && ./progress.sh) | grep -q "1/2 (50%)" || fail "S8 meter miscounts compact-JSON ledger: $(cd "$D" && ./progress.sh)"
note "S8 meter immune to ledger formatting"

echo "SMOKE OK"
