---
description: Run the independent Codex product-owner gate for larger changes. Audit invariants and their sibling sites first; review all classes in parallel under one 180-second deadline; P1 blocks, P2/P3 become follow-ups, and three rounds trigger escalation.
---

# Codex product-owner gate

Codex is the independent product-owner and code-quality reviewer. Claude is a fallback only
when Codex returns a provider quota/rate-limit error in `--reviewer auto`. A fresh, read-only
Claude reviewer has no shared implementation conversation; its valid verdict counts fully.

## Size and approval gate

Small scoped fixes may skip this gate when lint/tests pass. Larger changes (new features,
multi-file implementations, design-facing changes) need a factual What-was-asked / Plan /
Implementation brief and a user-approved plan before the gate. Approval already given for the
implementation and its validation is sufficient; do not ask again before each review round.

## Before round 1: audit invariants, not individual examples

For **every non-trivial logic change**, write a checklist of **5–15 one-line invariants** that
must hold at every relevant site. Derive these from the actual behavior and approved decisions.
Examples: every input loop charges its budget; all time arithmetic follows the same semantics;
no early stop assumes generated instants are ordered; data failures preserve incomplete signals.

For **each** invariant:

1. Search/list **all** relevant implementation sites, including preprocessing, callers,
   alternate input sources, fallback paths, and exits. Record the search and its evidence with
   repository-relative file:line references. Do not present a sample as an exhaustive list.
2. Inspect every listed site and fix violations before launching the gate.
3. Add at least one meaningful test per invariant. A parameterized test may cover sibling sites;
   a test of one happy-path instance is insufficient for a class-wide claim. Run the tests and
   record the actual outcomes, including gaps or untested paths.
4. Write the checklist and evidence to an **audit sidecar** supplied through `--audit-file`.
   Reviewers receive the complete checklist, assigned evidence, and bounded source context.
   Keep it factual: reviewers must verify it, not trust the implementer's conclusions.

The JSON sidecar has this shape (repeat the invariant object to reach 5–15):

```json
{
  "invariants": [{
    "id": "budget",
    "statement": "Every input-dependent loop respects the shared deadline and work budget.",
    "search": "rg -n 'foreach|while|array_map|usort' app/Services/Example",
    "evidence": "Full matched-site list below; inspected loops and called helpers, including preprocessing.",
    "sites": [{"repo": "backend-php", "path": "app/Services/Example/Expand.php", "line": 42}],
    "tests": [{"repo": "backend-php", "path": "tests/Unit/ExampleTest.php", "line": 31,
               "name": "test_every_source_respects_budget", "result": "PASS; command and relevant cases"}]
  }]
}
```

Use stable IDs across rounds. `search` and `evidence` must show how the complete site list was
obtained; they are not attestations of semantic correctness. Each site needs a positive line;
each test needs a name and actual result. Do not invent passing tests. Sidecars are limited to
64,000 characters and are separate from the brief limit. Omission is allowed for manual/simple
reviews with a warning, **not** for the non-trivial workflow above.

## Launch and scope

Use one stable `--session` task ID for the whole implementation. Commit the reviewable snapshot
on its feature branch first so the next round has an unambiguous base; do not commit unrelated
user changes. Keep the brief ≤2,000 characters; **launch only behind a ≤1,900-character guard**.
Rewrite the current fix summary rather than appending round history to the brief.

```bash
# B = existing brief; A = existing audit JSON. Keep both outside the reviewed product diff.
n=$(wc -m < "$B")
if [ "$n" -le 1900 ]; then
    ./claude-memory/scripts/codex-po-review.sh \
        --context-file "$B" --audit-file "$A" \
        --session feature-task-id --repos backend-php --base staging
else
    echo "Condense the brief to at most 1900 characters before launching." >&2
fi
```

The entrypoint requires Python 3.9+ (standard library only). The script's own guard rejects empty or >2,000-character briefs. Context is optional for manual
use; the normal workflow requires it. Include approved product exceptions, tests actually run,
and material gaps. Do not ask reviewers to read the entire planning history.

Existing options remain: `--repos a,b`, `--base REF`, `--effort low|medium|high`,
`--reviewer codex|claude|auto` (default auto, also `PO_REVIEWER`). Repositories without the base
ref fall back to uncommitted changes with a warning on round 1. For a previously reviewed repository, later rounds reject an unavailable ref or one that does not resolve to its previous reviewed HEAD. Verify first-round fallback warnings are intended.
`--repos` rejects unknown/duplicate names. Generated files are listed instead of diffed.

Other repositories can use the same bounded gate through `CODEX_PO_REPOS` and
`CODEX_PO_WORKSPACE_ROOT`; do not bypass the timing/session controls with an unbounded direct
`codex exec`. Git worktrees are supported. `PO_LOG_ROOT` redirects artifacts for isolated tests.

## Reviewer contract and stop rule

Reviewers sweep **all assigned classes before drilling deeply into one**, and do not stop at
the first blocker. Each finding includes its class, every substantiated instance in the part,
file:line, concrete input/impact, and severity:

- **P1:** wrong results or data loss on realistic inputs, including concrete user-visible regressions.
- **P2:** wrong only on rare/exotic inputs, or a guarantee violated without user-visible harm.
- **P3:** test/documentation gaps.

Strict wording alone does not turn an exotic issue or missing test into P1. Reviewers explicitly
mark assigned invariants **confirmed**, **violated** (with sites), or **unverifiable** (with reason).
A violated invariant must also have the appropriately graded finding; inspect unverifiable
entries and do not describe them as verified. An unfinished sweep is incomplete coverage.

The reviewer returns structured JSON; the script prints `DECISION: PASS|FAIL` and concise
summaries. **Only P1 findings block product approval.** Invalid/missing output, incomplete
coverage, command errors and timeouts are unsuccessful reviews, never PASS. Codex's final answer
is captured separately; echoed prompts or intermediate PASS text cannot approve the change.

P2/P3 automatically accumulate in the run's **`follow-ups.md`**, with source round/log and sites.
Link this file in the completion report and copy material follow-ups into the task's durable
tracking notes. Do not loop merely to clear P2/P3. Fix a trivial one if useful, but include that
change in the next required delta; do not silently expand scope.

After **any finding**, name its class and enumerate **all sibling sites**. Fix all P1 instances
of that class in the same round, update the invariant evidence, and test the class. For deferred
P2/P3, record the sibling audit in follow-ups instead of starting an unnecessary fix round.

There are at most **three rounds per session**, including reviewer-error/timeout rounds.
Preflight failures without reviewer launch do not consume a round. A successful third round
passes. An unsuccessful third round prints **ESCALATE**; a fourth invocation refuses to launch
models. Present unresolved P1s, uncertainty, timings and options to the user. Do not change the
session ID to evade the cap. User-approved continuation starts a new session and explicitly
carries forward unresolved findings/context. Explicit risk acceptance is a user decision, not
a reviewer PASS.

## Fix rounds: delta plus class siblings

Keep the same session, commit the fixes, and use:

```bash
# Use the same 1900-character launch guard as above.
./claude-memory/scripts/codex-po-review.sh \
    --context-file "$B" --audit-file "$A" --session feature-task-id \
    --repos backend-php --base PREVIOUS_REVIEWED_COMMIT
```

Only touched sites, previous P1 findings and class siblings are reviewed. New areas are opened
only for concrete P1 impact. Do not repeatedly run a full-branch “final review” after delta fixes.
Unresolved P1s persist even if a repo is omitted from `--repos`; a missing delta cannot erase
one. Reviewers must provide specific code evidence when resolving a prior P1.

When omitted, the session ID is derived from workspace and configured repository branches,
not the selected subset or changing base. Prefer explicit task IDs to avoid mixing unrelated
work on the same branch. Session metadata lives in ignored `scripts/logs/sessions/` and is
locked against concurrent rounds. Unfinished original scope persists across empty deltas and repository subsets; its base is frozen to a commit SHA. Legacy saved symbolic bases fail preflight: restore their original immutable review base from evidence rather than guessing a moving HEAD. Completed worker findings survive cancellation: the next invocation recovers valid P1/P2/P3 artifacts from interrupted rounds before it can approve a delta.

## Hard speed budget

**Every invocation, including round 1, has one ≤180-second wall-clock deadline.** Preparation,
queueing, parallel reviews, fallback and reporting all share it. `REVIEW_TIMEOUT_SECONDS`
defaults to 180; higher values are rejected. Review workers stop with five seconds reserved for
cleanup/reporting. The supervisor terminates process groups and returns timeout status 124; SIGTERM/SIGINT also terminate reviewer groups and record interruption;
completed part artifacts remain available. An operating-system suspension is outside the
script's scheduling control; never promise provider completion merely because a timer exists.

- With an audit, assign each invariant class an explicit owner across whole sibling files, grouping more than five classes into at most five implementation parts per repository. Test files get explicit test parts. This avoids every file reviewer re-auditing every class.
- Without an audit, pack whole files using a **400-changed-line target**. The same target packs test parts; large files remain intact. Class parts may exceed it to preserve sibling context. Every site remains enumerated in the prompt; long prose evidence is explicitly excerpted with a path to the full sidecar.
- Default maximum concurrency: **six** (`PO_MAX_PARALLEL`, 1–6). Six is an observed operating
  point, not a guaranteed provider quota. Queue time consumes the same deadline.
- Diffs and bounded sibling context are attached. Omitted excerpts are named. Reviewers may
  read missing context but must not run git, suites, builds or servers, or reread skill files.
- `--effort low` is for small follow-ups. Default effort comes from the installed configuration.
- `--first-round-model MODEL` is an explicit, measured opt-in: only the largest first-round
  part uses it. Later rounds use the configured default. Do not enable a stronger model merely
  on reputation; check availability, coverage and latency on a representative part first.
- No Ollama pre-filter: use deterministic searches/site inventories. The ICS Qwen campaign
  repeatedly produced incorrect or unusable diagnoses; local-model output has no gate authority.
- Auto fallback runs once, **only** on a Codex quota/rate-limit diagnostic, within the remaining
  deadline. A real FAIL, malformed response, timeout, missing CLI, or auth error never triggers it.
  Explicit `--reviewer claude` remains available when Codex is known unavailable.

Each run saves prompts, diffs, final responses, full transcripts, per-part results,
`findings.json`, `follow-ups.md`, and **`metrics.json`** (preparation, queue, attempts, total time,
part sizes and model calls). Inspect those artifacts instead of rerunning blindly.
Exit codes: 0 pass; 1 review/error failure; 2 invalid invocation; 3 round-cap escalation;
124 timeout; 127 required CLI missing. A third-round timeout remains 124 and also escalates.

## Visual fidelity

When a design reference exists, compare screenshots of the implementation and reference at
matched widths yourself, including the complete computed style of changed interactive elements.
Record what was checked in the brief. A text diff review cannot establish visual fidelity.
