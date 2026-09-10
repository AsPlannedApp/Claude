#!/usr/bin/env bash

set -uo pipefail

# Workspace root = two levels up from this script, i.e. scripts/ is expected to live at
# <workspace-root>/<memory-repo>/scripts/ alongside the reviewed repos. Override with
# CODEX_PO_WORKSPACE_ROOT if this script sits somewhere else.
WORKSPACE_ROOT="${CODEX_PO_WORKSPACE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Repositories to review. Override with a space-separated list, e.g.
#   CODEX_PO_REPOS="public-app logged-app backend-php" ./codex-po-review.sh
read -ra REPOSITORIES <<< "${CODEX_PO_REPOS:-api-collection logged-app backend-php}"

LOG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/logs"
RUN_TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
OUTPUT_DIR="$LOG_ROOT/$RUN_TIMESTAMP-$$"
mkdir -p "$OUTPUT_DIR"
CONTEXT_FILE=""
REVIEW_TIMEOUT_SECONDS="${REVIEW_TIMEOUT_SECONDS:-180}"
MAX_REVIEW_CONTEXT_CHARS=2000

usage() {
    cat <<'EOF'
Usage: codex-po-review.sh [--context-file PATH]

Run the product-owner gate for uncommitted changes in each repository listed in
CODEX_PO_REPOS (space-separated; a sensible default is baked in — edit it for your workspace).

The complete transcript is retained in a timestamped scripts/logs directory;
the command itself prints only concise per-repository results and that directory.

Options:
  --context-file PATH  Optional Markdown brief (maximum 2000 characters) with What was
                       asked, Plan, and Implementation sections for product context.
  -h, --help           Show this help message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --context-file)
            if [[ $# -lt 2 ]]; then
                echo "--context-file requires a path." >&2
                exit 2
            fi
            CONTEXT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -n "$CONTEXT_FILE" ]]; then
    if [[ ! -r "$CONTEXT_FILE" ]]; then
        echo "Review context file is not readable: $CONTEXT_FILE" >&2
        exit 2
    fi

    if [[ ! -s "$CONTEXT_FILE" ]]; then
        echo "Review context file is empty: $CONTEXT_FILE" >&2
        exit 2
    fi

    context_char_count="$(wc -m < "$CONTEXT_FILE" | tr -d '[:space:]')"
    if (( context_char_count > MAX_REVIEW_CONTEXT_CHARS )); then
        echo "Review context is ${context_char_count} characters; the maximum is ${MAX_REVIEW_CONTEXT_CHARS}." >&2
        echo "Condense the context file to a factual brief of at most ${MAX_REVIEW_CONTEXT_CHARS} characters, then rerun the gate." >&2
        echo "Keep only the requested behavior, key product constraints, implementation summary, and verification evidence; omit ceremony, retrospectives, and repeated detail." >&2
        exit 2
    fi

    REVIEW_CONTEXT="$(<"$CONTEXT_FILE")"
else
    REVIEW_CONTEXT=""
    echo "Warning: no review context supplied; the reviewer will review the diff with reduced product context." >&2
fi

if ! command -v codex >/dev/null 2>&1; then
    echo "codex CLI is required but was not found in PATH." >&2
    exit 127
fi

overall_status=0
timed_out=0

has_uncommitted_changes() {
    local repository_path="$1"

    ! git -C "$repository_path" diff --quiet \
        || ! git -C "$repository_path" diff --cached --quiet \
        || [[ -n "$(git -C "$repository_path" ls-files --others --exclude-standard)" ]]
}

for repository in "${REPOSITORIES[@]}"; do
    repository_path="$WORKSPACE_ROOT/$repository"
    output_file="$OUTPUT_DIR/$repository.txt"

    if [[ ! -d "$repository_path/.git" ]]; then
        echo "Skipping $repository: not a git repository." >&2
        overall_status=1
        continue
    fi

    if ! has_uncommitted_changes "$repository_path"; then
        echo
        echo "===== PO review: $repository (skipped; no uncommitted changes) ====="
        continue
    fi

    echo
    echo "===== PO review: $repository ====="

    prompt_file="$OUTPUT_DIR/$repository-prompt.md"
    {
        cat <<'EOF'
Act as the product owner and senior code reviewer. Inspect all staged, unstaged, and untracked changes in this repository with git before reviewing them. Do not modify files.

Assess whether the implementation fulfills the requested product behavior and its stated plan. Identify regressions and removed existing functionality. For UI changes, check design fidelity and usability, including visible interactive affordances (such as pointer behavior), practical icon sizing, and adherence to any supplied design reference. Also check cross-repository contract compatibility, correctness, tests, error handling, and unnecessary complexity.

Report blocking issues first, then non-blocking concerns and missing tests. End with a concise technical summary in exactly this form (at most three bullets), followed by exactly one decision line:

TECHNICAL SUMMARY:
- Concrete blocker or verification result.
DECISION: PASS or DECISION: FAIL

Use DECISION: FAIL for any blocking issue, contract mismatch, regression, failing check, missing required work, or material UI/design mismatch.
EOF

        if [[ -n "$REVIEW_CONTEXT" ]]; then
            cat <<'EOF'

## Implementation context supplied by Claude

Use this as product context for the review. Verify it against the diff and repository; do not assume it is correct.

EOF
            printf '%s\n' "$REVIEW_CONTEXT"
        fi
    } > "$prompt_file"

    # macOS does not ship GNU `timeout`; Perl's alarm survives exec and terminates the
    # review process after the same fixed deadline. Normalize its SIGALRM status to 124,
    # the conventional timeout exit code Claude can recognize and retry deliberately.
    # Keep the complete transcript for this invocation's decision parsing, but never stream the
    # CLI's tool trace to Claude: a multi-repository review can otherwise consume the caller's
    # entire context before its actual findings or final decision arrive.
    perl -e 'alarm shift; exec @ARGV' "$REVIEW_TIMEOUT_SECONDS" \
        codex -C "$repository_path" exec --sandbox read-only - < "$prompt_file" \
        > "$output_file" 2>&1

    codex_status=$?
    if [[ $codex_status -eq 124 || $codex_status -eq 142 ]]; then
        echo "Review timed out for $repository after ${REVIEW_TIMEOUT_SECONDS}s; retry or ask the user how to proceed." >&2
        overall_status=1
        timed_out=1
    elif [[ $codex_status -ne 0 ]]; then
        echo "Review command failed for $repository." >&2
        tail -n 6 "$output_file" >&2
        overall_status=1
    elif ! grep -q '^DECISION: PASS$' "$output_file"; then
        echo "The reviewer did not approve $repository." >&2
        sed -n '/^TECHNICAL SUMMARY:$/,/^DECISION:/p' "$output_file" | head -n 4 >&2 || true
        grep -E '^DECISION:' "$output_file" | tail -n 1 >&2 || true
        overall_status=1
    else
        echo "PO review: $repository — PASS"
        sed -n '/^TECHNICAL SUMMARY:$/,/^DECISION:/p' "$output_file" | head -n 4
    fi
done

if [[ $timed_out -eq 1 ]]; then
    echo
    echo "PO review logs: $OUTPUT_DIR"
    echo "Codex PO review: TIMEOUT"
    exit 124
elif [[ $overall_status -eq 0 ]]; then
    echo
    echo "PO review logs: $OUTPUT_DIR"
    echo "Codex PO review: PASS"
else
    echo
    echo "PO review logs: $OUTPUT_DIR"
    echo "Codex PO review: FAIL"
fi

exit "$overall_status"
