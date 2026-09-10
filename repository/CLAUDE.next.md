<!--
  BOOTSTRAP: CLAUDE.md for a Next.js marketing site + API backend.
  This is a pre-filled starting point (not a blank template) — the sections below reflect common,
  reusable Next.js conventions (Pages Router API routes, response-envelope pattern). Adjust the
  {{PLACEHOLDER}}s to your project, drop any `OPTIONAL` block that doesn't apply, and edit
  any convention that doesn't match how this repo actually works. Delete all HTML comments
  (including this one) from the final output.
-->

# CLAUDE.md — {{REPO_NAME}}

Next.js {{NEXT_VERSION}} marketing site and API backend, deployed to {{DEPLOY_TARGET}}.

---

## Router

{{ROUTER_MODE}} <!-- e.g. "Pages Router only. `appDir` is not enabled. All pages live under
     pages/. Do not create files in an app/ directory." — or the App Router equivalent if that's
     what this repo uses. -->

---

<!-- OPTIONAL: include when this repo pins a fast-moving framework major whose APIs and file
     conventions may differ from an agent's training data. Delete for a stable/older pin. -->
## Framework version — check the installed docs first

This repo is on {{FRAMEWORK}} {{MAJOR_VERSION}} — treat your prior knowledge of it as
potentially stale. Before writing framework code, read the relevant guide under
`node_modules/{{FRAMEWORK_PACKAGE}}/dist/docs/` (resolved from this file's directory; in a
monorepo the package may not be visible from the repo root) and heed any deprecation notices.

If the dev server auto-writes an agent-rules block into this file, commit it with your work —
deleting it from the diff only makes the tool re-create the uncommitted change.

---

## Dev & build

```bash
{{NODE_VERSION_PIN}}      # e.g. nvm use
npm install
npm run dev                # dev server, http://localhost:{{DEV_PORT}}
npm run build               # production build
npm run start                # serve the production build
```

---

## Quality checks

```bash
npm run lint    # ESLint
npm run test    # Test runner — check package.json for a combined gate/watch-mode variant
```

---

<!-- OPTIONAL: only if CSS is compiled in a separate step from the framework's own build (common
     with Tailwind v4's CLI, or a custom PostCSS pipeline). Delete if the framework's dev server
     handles it natively with no gotcha. -->
## {{CSS_TOOL}}

{{CSS_BUILD_NOTE}} <!-- e.g. "compiled separately: public/styles/globals.css →
     public/styles/tailwind.css. Never edit the compiled output directly." -->

---

<!-- OPTIONAL: only if there's a second ORM/schema mirror alongside the "real" schema owner (a
     common gotcha in workspaces where a Node app and a backend app share one database). Delete
     if this repo owns its own schema outright. -->
## Database — schema ownership

{{SCHEMA_OWNERSHIP_NOTE}} <!-- e.g. "a typed ORM mirror exists here, but <other-repo>'s migrations
     own the live schema — this repo and <other-repo> target the same database. Never run
     generate/migrate commands from this repo against the real database; read-only inspection
     tools are safe." -->

---

<!-- OPTIONAL: only if content is CMS-backed. Delete for a pure API/no-CMS repo. -->
## CMS

{{CMS_NAME}} content lives under `{{CMS_CONTENT_DIR}}`.

- **Production deploy**: {{CMS_PROD_DEPLOY_NOTE}}
- **Staging deploy**: {{CMS_STAGING_DEPLOY_NOTE}}

---

## API Conventions

All API routes under `{{API_ROUTE_PREFIX}}` follow this standard:

### Response envelopes

```json
// GET / POST returning a resource → 200 or 201
{ "success": true, "status": 200, "message": "success", "element": { ... } }

// GET returning a collection → 200
{ "success": true, "status": 200, "message": "success", "collection": [ ... ] }

// POST creating a resource → 201 + Location header
{ "success": true, "status": 201, "message": "success", "element": { ... } }

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

### 405 Method Not Allowed

JSON body (not plain text): `{ "success": false, "status": 405, "message": "Method not allowed" }`,
plus an `Allow: <methods>` header. Handle centrally in a shared route wrapper/middleware rather
than per-route.

### Route pattern

Wrap every API route with a shared handler rather than raw `try/catch` per file:

```ts
// ✅ Correct
export default apiHandler({
  post: async (req, res) => {
    const { parsedBody } = await parseRequest(req)
    // ... logic
    sendJson(res, 200, { success: true, status: 200, message: 'success', element })
  }
})

// ❌ Wrong: raw try/catch, manual auth check per route
export default async function handler(req, res) {
  try {
    if (!req.headers.authorization) return res.status(401).end(...)
    // ...
  } catch (e) { res.status(500).end(...) }
}
```

`apiHandler` (or your equivalent) should own: method dispatch (404/405 with `Allow` header), CORS,
auth, and error formatting — keep that logic in one place, not duplicated per route.

<!-- OPTIONAL: include if this repo rate-limits any routes. Delete otherwise. -->
### Rate limiting

<!-- {{RATE_LIMIT_LOCATION}}: e.g. "proxy.ts (repo root, Node runtime) rate-limits
     /api/v1/auth/* by client IP before the route runs." -->
{{RATE_LIMIT_LOCATION}}. Follows the workspace `CLAUDE.md`'s "Rate limiting" section: env-var
thresholds (`RL_*`), a global multiplier + on/off switch, an `X-RateLimit-Bypass` secret
honoured only in non-prod, the standard 429 error envelope + `Retry-After`/`X-RateLimit-*`,
**fail open** on limiter/store failure for auth endpoints, and debounced fire-and-forget
recording of rejections.

---

## Pages / API structure

```
pages/
  api/{{API_VERSION_SEGMENT}}/   # one file per resource/action
  {{CONTENT_SECTION}}/            # e.g. blog/, account/ — page routes
components/                       # organised by domain, not by type
config/                           # navigation, site config
lib/                              # pure utilities, no framework imports
```

---

## Design system packages

{{DESIGN_SYSTEM_NOTE}} <!-- shared component package name(s), install/versioning process -->

---

<!-- OPTIONAL: only if translations are generated from a source-of-truth outside this repo -->
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
| {{HOSTING_SERVICE}} | Hosting + deployment |
| {{DB_SERVICE}} | Primary database |
| {{CACHE_SERVICE}} | Caching |
| {{EMAIL_SERVICE}} | Transactional email |
| {{CMS_NAME}} | Content management |

---

<!-- OPTIONAL: only if this workspace has a shared /api-review skill (check the monorepo root
     CLAUDE.md before including). -->
## API Review

Run `/api-review` after any change to:
- `pages/api/{{API_VERSION_SEGMENT}}/` — new or modified routes
- The shared fetch wrapper used by page-level API consumers
- Page-level API consumers where response fields are read

---

<!-- OPTIONAL: only if this workspace has a shared /playwright-session skill and this repo hosts
     the auth API a frontend app depends on for testing. -->
## Playwright Visual Testing

If a sibling app's `/playwright-session` skill calls this server's auth endpoints to bootstrap a
test session, make sure `npm run dev` is running here before invoking that skill.
