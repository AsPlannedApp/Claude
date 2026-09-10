# Claude

A reusable Claude Code setup for a multi-repo SaaS project (marketing site + logged-in app +
backend API + shared design system, etc.). Drop this repo at the root of your workspace, rename
the placeholders, and Claude Code will have consistent cross-repo context from day one.

## What's in here

- **`CLAUDE.md`** — the root-level guidance file: lists every codebase in the workspace, cross-repo
  conventions (design tokens, external services), and trigger points for the bundled skills. This
  is what Claude Code reads first when working anywhere in the workspace.
- **`skills/`** — three example Claude Code skills:
  - `api-review` — reviews an API endpoint/consumer for REST convention compliance.
  - `playwright-session` — bootstraps an authenticated browser session before visual testing.
  - `codex-po-gate` — runs a second agent as an independent product-owner / code-quality gate
    over uncommitted cross-repo changes before a larger implementation is declared complete.
- **`scripts/`** — helper scripts the skills call:
  - `codex-po-review.sh` — the `codex-po-gate` runner (reviews each repo in `CODEX_PO_REPOS`).
  - `git-msg.sh` — asks the second agent for a one-line Conventional Commit subject for the
    current uncommitted diff.
  - `logs/` — per-run review transcripts (kept in Git; the log files themselves are ignored).
- **`repository/`** — a template kit for generating a `CLAUDE.md` + `ARCHITECTURE.md` pair *inside*
  each individual sub-repo. Contains `CLAUDE.template.md`, `ARCHITECTURE.template.md`,
  `INSTRUCTIONS.md`, and framework bootstraps (`CLAUDE.next.md`, `CLAUDE.php.md`, `CLAUDE.vue.md`).

## Setting this up in a new workspace

1. Copy this `Claude/` folder to the root of your multi-repo workspace, alongside your other repos
   (e.g. `my-workspace/Claude/`, `my-workspace/public-app/`, `my-workspace/backend-php/`, …).
2. Symlink `CLAUDE.md` to the workspace root so Claude Code picks it up automatically:
   ```bash
   ln -s Claude/CLAUDE.md CLAUDE.md
   ```
3. Edit `CLAUDE.md`: replace the repo table, tech stack, brand tokens, and external services with
   your actual project's details. Search for `{{...}}` placeholders in the Design System section.
4. Point Claude Code at `skills/` (e.g. symlink or copy into `.claude/skills/`) if you want
   `/api-review`, `/playwright-session`, and `/codex-po-gate` available, and adjust their
   `SKILL.md` content to match your actual endpoints/ports.
   - `codex-po-gate` runs `scripts/codex-po-review.sh`, which assumes it sits at
     `<workspace-root>/<memory-repo>/scripts/` (it derives the workspace root as two levels up).
     Copy `scripts/` — including `scripts/logs/.gitignore` — into your memory repo so that holds,
     or set `CODEX_PO_WORKSPACE_ROOT` if it lives elsewhere; the skill invokes it as
     `./claude-memory/scripts/codex-po-review.sh`, so adjust that path to match. Set
     `CODEX_PO_REPOS` to your real repo list (edit the default in the script). Both `scripts/*.sh`
     need the `codex` CLI (or your second-agent CLI) on `PATH`.

## Generating per-repo docs with `repository/`

For each sub-repo that needs its own `CLAUDE.md` + `ARCHITECTURE.md`:

1. Copy `repository/CLAUDE.template.md`, `repository/ARCHITECTURE.template.md`, and
   `repository/INSTRUCTIONS.md` into that repo's root.
2. Open Claude Code in that repo and tell it: **"Follow INSTRUCTIONS.md."**
3. Claude will inspect the real codebase (framework, scripts, folder structure, patterns) and
   produce a filled-in `CLAUDE.md` and `ARCHITECTURE.md`, dropping any template sections that
   don't apply (e.g. API conventions in a repo with no API surface).
4. Once you're happy with the result, let Claude delete the three template/instruction files from
   that repo — they're bootstrapping-only and aren't meant to ship alongside the generated docs.

## Keeping it generic

If you're about to share or reuse this repo, grep for leftover project-specific names before
handing it off:

```bash
grep -rniE "your-project-name" --include="*.md" --include="*.sh" .
```
