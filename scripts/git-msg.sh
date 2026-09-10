#!/usr/bin/env bash

set -euo pipefail

if ! command -v codex >/dev/null 2>&1; then
    echo "codex CLI is required but was not found in PATH." >&2
    exit 127
fi

output_file="$(mktemp "${TMPDIR:-/tmp}/git-msg.XXXXXX")"
trap 'rm -f "$output_file"' EXIT

if ! codex exec --sandbox read-only --output-last-message "$output_file" \
    'Review the current uncommitted git changes. Output exactly one concise Conventional Commit subject line, with no Markdown, explanation, quotes, or surrounding text.' \
    > /dev/null 2>&1; then
    echo "Codex could not generate a commit message." >&2
    exit 1
fi

# The CLI writes only its final assistant message to --output-last-message.
message="$(<"$output_file")"
if [[ -z "$message" ]]; then
    echo "Codex did not return a Conventional Commit subject." >&2
    exit 1
fi

printf '%s\n' "$message"
