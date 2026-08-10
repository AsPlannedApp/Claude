# Claude

A reusable Claude Code setup for a multi-repo SaaS project (marketing site + logged-in app +
backend API + shared design system, etc.). Drop this repo at the root of your workspace, rename
the placeholders, and Claude Code will have consistent cross-repo context from day one.

## What's in here

- **`CLAUDE.md`** — the root-level guidance file: lists every codebase in the workspace, cross-repo
  conventions (design tokens, external services), and trigger points for the bundled skills. This
  is what Claude Code reads first when working anywhere in the workspace.
- **`skills/`** — two example Claude Code skills:
  - `api-review` — reviews an API endpoint/consumer for REST convention compliance.
  - `playwright-session` — bootstraps an authenticated browser session before visual testing.
- **`repository/`** — a template kit for generating a `CLAUDE.md` + `ARCHITECTURE.md` pair *inside*
  each individual sub-repo. Contains `CLAUDE.template.md`, `ARCHITECTURE.template.md`, and
  `INSTRUCTIONS.md`.

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
   `/api-review` and `/playwright-session` available, and adjust their `SKILL.md` content to match
   your actual endpoints/ports.

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
grep -rniE "your-project-name" --include="*.md" .
```
