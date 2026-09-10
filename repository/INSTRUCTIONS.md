# INSTRUCTIONS.md — generate CLAUDE.md and ARCHITECTURE.md for this repo

You are Claude Code, dropped into a repo alongside two templates: `CLAUDE.template.md` and
`ARCHITECTURE.template.md` (plus this file, and possibly framework-specific `CLAUDE.php.md` /
`CLAUDE.vue.md` / `CLAUDE.next.md` bootstraps). Your job: produce a real `CLAUDE.md` and
`ARCHITECTURE.md` at this repo's root, filled in from the actual codebase — not from guesses.

Do not start writing prose until you've done the exploration below. Every `{{PLACEHOLDER}}` you
fill must trace back to something you actually read (a script in `package.json`/`composer.json`,
a real file path, a real code snippet). If you can't find a fact, ask rather than invent it.

## 1. Detect the stack

- Read the manifest: `package.json` (Node), `composer.json` (PHP), or the equivalent for the
  language present (`Cargo.toml`, `pyproject.toml`, `go.mod`, …).
- Identify the framework from dependencies + config files present (e.g. `next.config.*`,
  `vite.config.*`, Laravel's `bootstrap/app.php`, `artisan`, a Vue `main.js` + `App.vue`, etc.).
- If a matching bootstrap exists alongside this file — `CLAUDE.php.md` for Laravel, `CLAUDE.vue.md`
  for a Vue 3 SPA, `CLAUDE.next.md` for Next.js — start from that instead of the blank
  `CLAUDE.template.md`; it's already seeded with framework-standard conventions (response
  envelope, dev commands, folder roles) and only needs the `{{PLACEHOLDER}}`s and any
  repo-specific deviations filled in. Fall back to `CLAUDE.template.md` for any other stack.
- Read the **scripts** section of the manifest in full. These become `{{DEV_SETUP_COMMANDS}}`,
  `{{DEV_SERVER_COMMAND}}`, `{{BUILD_COMMAND}}`, `{{QUALITY_GATE_COMMAND}}` and friends —
  copy them verbatim, don't paraphrase into a command that doesn't exist.
- Note the dev server port(s) from config (vite.config, next.config, docker-compose, etc.).
- Check for a lockfile / version pin (`.nvmrc`, `composer.lock` PHP version, engines field) —
  include it in the setup command if the sibling repos in this workspace show that convention.

## 2. Determine repo "shape"

Decide which optional blocks in `CLAUDE.template.md` and `ARCHITECTURE.template.md` apply:

| Signal                                                       | Shape                                  | Template blocks to keep                                                                                              |
|--------------------------------------------------------------|----------------------------------------|----------------------------------------------------------------------------------------------------------------------|
| Has HTTP route handlers/controllers that return JSON         | API backend (fully or partially)       | API Conventions, response envelope, status codes                                                                     |
| Has views/components rendered in a browser, no server routes | Frontend SPA                           | Design system integration, State management, Design conventions                                                      |
| Both                                                         | Marketing/hybrid site with API backend | Keep both sets                                                                                                       |
| No HTTP surface, imported as a package/library               | Library                                | Drop API Conventions and frontend blocks; keep folder structure, responsibility rules, quality commands, Agent rules |

Drop every block whose condition doesn't hold. Don't leave a block in "for completeness" if it's
empty or fabricated.

## 3. Look for monorepo context

If this repo lives inside a multi-repo workspace with its own root `CLAUDE.md` (check the parent
directory and one level up), read it. Reuse rather than restate:

- If the root file defines shared design tokens, brand colors, or fonts — reference them, don't
  copy the values into this repo's file, unless this repo has repo-specific overrides.
- If the root file documents a shared skill (e.g. an API-review or visual-testing skill) with
  trigger points per codebase — check whether this repo is listed as a trigger point. If so, keep
  the corresponding optional block in `CLAUDE.template.md`; if this repo isn't a fit for that
  skill (e.g. it's a library with no API and no browser UI), drop the block instead of including
  it speculatively.
- Do not duplicate cross-repo conventions verbatim into this repo's file — link to the root file's
  section by name instead.
- If the root file has a "Codex product-owner gate", a "Verification & Working Discipline", or a
  "Rate limiting" section, add a one-line pointer to it from this repo's `CLAUDE.md` (near the
  top) rather than restating the rules — an agent working only in this repo should still be sent
  to the gate and the discipline rules.

If there's no monorepo root context, skip this step — the repo stands alone.

## 4. Populate ARCHITECTURE.md first

`ARCHITECTURE.md` is the harder, higher-value file — do it before `CLAUDE.md` since parts of
`CLAUDE.md` (the Structure section) just point back to it.

- **Folder tree**: walk actual top-level source folders 2-3 levels deep. Annotate each with what
  it's for, using real filenames you saw, not generic placeholders like "components go here".
- **Responsibility rules table**: one row per folder/layer with a genuinely distinct
  responsibility. If two folders serve the same purpose, merge them into one row rather than
  padding the table.
- **Canonical pattern section**: find one real, representative request/data-flow example in the
  code (a controller + its action/service, or a view + its composable + its API-calling service,
  or a route handler + its response helper) and show it — trimmed for length but not invented.
  Only add a ❌ "wrong" counter-example if you can find (or the codebase's git history/comments
  suggest) a real anti-pattern worth warning against; don't manufacture a strawman.
- **State management**: only include if state genuinely lives somewhere non-obvious (a root
  component's `provide()`, a global store, a singleton) — skip for stateless backends.
- **Agent rules**: write 4-8 rules, following the priority order commented in the template. Every
  rule must be something you could point to a violation of in a code review — no vague "write
  clean code" filler. Always end with the "run the quality gate after every step" rule using the
  real command name.

## 5. Populate CLAUDE.md

- Keep it scannable — command blocks and short prose, not restated architecture.
- Copy commands from what you verified in step 1; don't add commands you haven't confirmed exist.
- The API Conventions block (if kept) should describe the *actual* envelope shape used in this
  codebase's responses — read at least one real handler/controller to confirm the shape rather
  than assuming the generic example in the template is correct for this repo.
- External services table: only list integrations you found evidence of (a client library in the
  manifest, an env var, a config file) — don't guess.

## 6. Ask before inventing

Use a clarifying question (don't just pick a default silently) only for things you genuinely
cannot infer from the repo:

- The deploy target/URL, if it's not in any config file and not documented anywhere.
- Whether a monorepo root convention (shared skill, shared design tokens) should be referenced,
  when it's ambiguous whether this repo participates.

Everything else — commands, folder structure, patterns — should come from reading the repo, not
from asking the user to restate what's already there.

## 7. Clean up

Once `CLAUDE.md` and `ARCHITECTURE.md` are written and you've confirmed every placeholder was
replaced (grep for `{{` and `<!--` — there should be none left), ask the user whether to delete
`CLAUDE.template.md`, `ARCHITECTURE.template.md`, and this `INSTRUCTIONS.md` from the repo. They're
bootstrapping-only inputs, not meant to ship alongside the generated docs — but don't delete
without confirming, in case the user wants to keep them for re-runs on other repos.
