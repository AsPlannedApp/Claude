---
description: Run the Codex product-owner / code-quality gate on uncommitted cross-repo changes before declaring a multi-repository implementation complete. Use for any larger change (new feature, multi-file implementation, design-facing change); small scoped fixes skip it. Also covers the per-repo focused review and the visual-fidelity gate.
---

# Codex product-owner gate

Claude is the implementation agent; a second agent (Codex) is the independent product-owner and
code-quality gate. Adapt the CLI name/flags below to whatever second agent your workspace uses.

## Size gate

The gate is **not** mandatory for every change. Small, scoped fixes (a targeted bug fix, a
single review comment addressed, a one-file correction) may skip it entirely — lint/tests green
is enough. For anything larger (a new feature, a multi-file implementation, a design-facing
change), write the What-was-asked / Plan / Implementation brief below, and **ask the user to
confirm the plan before running the gate** — not just before merging. Do not assume a large
change qualifies as "small" on your own judgment.

## Running the gate

Before declaring a multi-repository implementation complete, run the workspace review script
from the workspace root:

```bash
review_context="$(mktemp "${TMPDIR:-/tmp}/codex-review-context.XXXXXX.md")"
trap 'rm -f "$review_context"' EXIT

cat > "$review_context" <<'EOF'
# What was asked
- Concise requested behavior, acceptance criteria, and affected repositories.

# Plan
- The intended approach and any explicit product or design decisions.

# Implementation
- What changed, intentionally preserved behavior, tests run, and any relevant design references or visual checks.
EOF

./claude-memory/scripts/codex-po-review.sh --context-file "$review_context"
```

Before invoking the gate, replace the template text with a factual brief of **at most 2,000
characters** (including headings and whitespace). The script rejects an oversized file with an
actionable retry message, so condense it rather than truncating it. The three sections are
deliberately required whenever that information is available: they let the reviewer check the
diff against the request and plan, rather than only against generic code-quality expectations.
Include only affected repositories, requested behavior and key constraints, intentional
preservation, implementation, tests, and design/visual evidence when relevant. Use short
bullets; omit ceremony, retrospectives, repeated detail, and prose that does not affect the
review. Do not conceal known gaps; the reviewer will verify the brief against the repository.

The `--context-file` argument is optional so the gate can still be run manually when no task
brief exists; the script prints a reduced-context warning in that case. The script runs the
reviewer in read-only mode against each configured repository (`CODEX_PO_REPOS`, see the
script), explicitly directing it to inspect that repository's uncommitted changes. Repositories
with no staged, unstaged, or untracked changes are explicitly skipped. It fails unless the
reviewer explicitly returns `DECISION: PASS` for every reviewed repository. A review has a fixed
per-repo deadline; a timeout exits with status 124 and prints `Codex PO review: TIMEOUT`, so
Claude must retry deliberately or ask the user how to proceed rather than reporting a false
pass.

Every invocation stores the complete, timestamped per-repository transcript in
`claude-memory/scripts/logs/` (the directory is kept in Git while log files are ignored). The
command prints only each repository's decision and a maximum-three-bullet `TECHNICAL SUMMARY`,
then prints the log directory path. On a failure, first use that summary to decide whether the
cause is actionable; if it needs evidence, open the corresponding saved `<repo>.txt` log rather
than rerunning blindly or pasting the full transcript into the conversation. Do not claim the
implementation is complete when this gate fails; address the reported blockers and run it again.

## Focused single-repository review

For a focused review of one repository, run the reviewer directly from that repository:

```bash
codex exec --sandbox read-only "Inspect and review all uncommitted changes. Do not modify files."
```

## Visual-fidelity gate (any step with a design reference file)

The plain-diff review above only ever checks correctness, tests, and contracts — it cannot see
whether a UI change actually matches a design mockup. For any step whose folder contains a
design reference (an `.html` mockup, a `DESIGN-handoff.md`, a Figma/image export, etc.), before
declaring the step done: screenshot the implementation and the reference at matched container
widths, save both to disk, and look at them side by side yourself — do not rely on the diff
review to catch a visual mismatch, since it isn't given the screenshots and isn't asked the
question. Record any matched-width screenshot convention your workspace settles on in
`knowledge/<domain>/`.
