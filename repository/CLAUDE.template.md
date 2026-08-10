<!--
  TEMPLATE: CLAUDE.md for a single repo in a multi-repo project.
  This is a dev-facing operational doc: what to run, how it's conventionally built, what to
  watch out for. It should stay short enough to scan. Deep structural rules belong in
  ARCHITECTURE.md instead — this file should point there, not duplicate it.

  Fill every {{PLACEHOLDER}}. Delete any block wrapped in `OPTIONAL` whose condition doesn't 
  apply to this repo. Delete all HTML comments (including this one) from the final output — 
  they are authoring guidance only, not content.
-->

# CLAUDE.md — {{REPO_NAME}}

{{ONE_LINE_DESCRIPTION}} <!-- e.g. "Next.js 16 marketing site and API backend, deployed to Vercel at example.app." -->

<!-- OPTIONAL: include if this repo has separate staging/production URLs -->
**Staging:** `{{STAGING_URL}}` | **Production:** `{{PRODUCTION_URL}}`

---

<!-- OPTIONAL: include if the framework has a routing mode decision that agents could get wrong
     (e.g. Next.js Pages Router vs App Router, Vue Router history mode, etc.) -->
## Router

{{ROUTER_MODE_NOTE}} <!-- state which mode is in use and what NOT to create (e.g. "Do not create files in an app/ directory") -->

---

## Dev & build

<!-- Copy these from the actual package.json/composer.json scripts. Never invent a command that
     isn't defined — if a step normally requires two commands, show both. -->
```bash
{{DEV_SETUP_COMMANDS}}       # e.g. nvm use, npm install / composer install
{{DEV_SERVER_COMMAND}}       # local dev server, with port
{{BUILD_COMMAND}}            # production build
```

<!-- OPTIONAL: include if deploy is a manual/CLI step from this repo (not just CI) -->
Deploy:
```bash
{{DEPLOY_COMMANDS}}
```

---

## Quality checks

<!-- List the actual gate command(s) a dev/agent must run before committing, and what each one
     bundles. Match the granularity of the real scripts — one combined "ci:check" style command
     plus the individual pieces it's made of, if useful to run in isolation. -->
```bash
{{QUALITY_GATE_COMMAND}}     # e.g. format + typecheck + test — run before every commit
{{LINT_COMMAND}}
{{TYPECHECK_COMMAND}}
{{TEST_COMMAND}}
{{TEST_WATCH_COMMAND}}
```

---

<!-- OPTIONAL: repeat this kind of section for each framework-specific gotcha worth flagging —
     a generated-output file that must never be hand-edited, a build pipeline quirk, a stale/
     abandoned tool that looks live but isn't, etc. One heading per gotcha, short and specific. -->
## {{FRAMEWORK_GOTCHA_HEADING}}

{{FRAMEWORK_GOTCHA_DETAIL}}

---

<!-- OPTIONAL: include only if this repo serves or consumes an HTTP API. Delete entirely for a
     pure frontend-only repo with no API surface, or a library with no HTTP layer. -->
## API Conventions

All API routes under `{{API_ROUTE_PREFIX}}` follow this standard:

### Response envelopes

```json
// GET / POST returning a resource → 200 or 201
{ "success": true, "status": 200, "message": "success", "element": { ... } }

// GET returning a collection → 200
{ "success": true, "status": 200, "message": "success", "collection": [ ... ] }

// DELETE / PUT success → 204, empty body (no JSON)

// Validation error → 422
{ "success": false, "status": 422, "message": "Validation errors", "errors": [{ "message": "..." }] }

// Single error (401, 404, 409, 500…)
{ "success": false, "status": 401, "message": "..." }
```

### Status codes

| Code | When |
|---|---|
| 200 | GET success |
| 201 | POST creates a resource |
| 204 | DELETE / PUT (empty body) |
| 401 | Invalid or missing auth |
| 404 | Resource not found |
| 409 | Conflict (duplicate) |
| 422 | Validation failed |
| 500 | Unhandled exception |

<!-- OPTIONAL: include only if this repo returns paginated collections -->
### Pagination

```json
{
  "success": true, "status": 200, "message": "success",
  "collection": [...],
  "pagination": {
    "currentPage": 1, "totalPages": 4, "totalItems": 37, "perPage": 10,
    "hasNext": true, "hasPrev": false
  }
}
```

---

## Structure

Full layering rules live in `ARCHITECTURE.md` — this file is just a dev-command reference, not
a structure map. See `ARCHITECTURE.md`'s folder tree and responsibility rules before adding new
code.

---

<!-- OPTIONAL: frontend-only. Delete for a pure backend/API repo. -->
## Design system integration

{{DESIGN_SYSTEM_NOTE}} <!-- shared component package name, import pattern, font-loading approach -->

---

<!-- OPTIONAL: frontend-only, and only if there's a generated/synced translation file with a
     source-of-truth elsewhere. Delete otherwise. -->
## i18n

`{{GENERATED_I18N_FILE}}` is a **generated file** — never hand-edit it. Source of truth:
`{{I18N_SOURCE}}`. Regenerate via:
```bash
{{I18N_BUILD_COMMAND}}
```

---

## External services

| Service | Purpose |
|---|---|
| {{SERVICE_1}} | {{SERVICE_1_PURPOSE}} |
| {{SERVICE_2}} | {{SERVICE_2_PURPOSE}} |

---

<!-- OPTIONAL: only if this workspace has a shared /api-review skill (check the monorepo root
     CLAUDE.md for a skill by this name before including). -->
## API Review

Run `/api-review` after any change to:
- {{API_REVIEW_TRIGGER_1}}
- {{API_REVIEW_TRIGGER_2}}

---

<!-- OPTIONAL: only if this workspace has a shared /playwright-session skill and this repo is a
     browser-testable frontend. -->
## Playwright Visual Testing

Before any Playwright MCP test against this app, run `/playwright-session` to bootstrap an
authenticated browser session. Requires `{{DEV_SERVER_DEPENDENCIES}}` running.
