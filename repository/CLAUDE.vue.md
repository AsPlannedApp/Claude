<!--
  BOOTSTRAP: CLAUDE.md for a Vue 3 SPA.
  This is a pre-filled starting point (not a blank template) — the sections below reflect common,
  reusable Vue 3 SPA conventions (no-Pinia provide()-based state, Vite, Vitest). Adjust the
  {{PLACEHOLDER}}s to your project, drop any `OPTIONAL` block that doesn't apply, and edit
  any convention that doesn't match how this repo actually works. Delete all HTML comments
  (including this one) from the final output.
-->

# CLAUDE.md — {{REPO_NAME}}

Vue 3 SPA ({{JS_OR_TS}}). Deployed to {{DEPLOY_TARGET}}.

<!-- OPTIONAL: include if this repo has separate staging/production URLs -->
**Staging:** `{{STAGING_URL}}` | **Production:** `{{PRODUCTION_URL}}`

---

## Dev & build

```bash
npm install
npm run dev             # Vite dev server at http://localhost:{{DEV_PORT}}
npm run build           # Production build
npm run lint            # ESLint
npm run test            # Vitest (single run)
```

<!-- OPTIONAL: include if deploy is a manual/CLI step from this repo -->
```bash
{{DEPLOY_COMMAND}}
```

---

## Environment variables (`{{ENV_PREFIX}}_*` prefix)

| Variable | Default (dev) |
|---|---|
| `{{ENV_PREFIX}}_API_URL` | `{{API_DEV_URL}}` — backend API |
| `{{ENV_PREFIX}}_BASE_URL` | `{{APP_DEV_URL}}` — this app |

---

## Structure

Full layering rules (View/Feature/Composable/Service responsibilities) live in `ARCHITECTURE.md`
— this section is just a file-finder:

```
src/
├── views/            Page-level coordinators
├── features/         Vertical slices — one folder per domain feature (components/, composables/,
│                     services/*Api.js)
├── components/
│   ├── ui/           Design-system / component-library primitives — no domain logic
│   └── blocks/       Reusable layout-only building blocks
├── composables/       App-wide only (feature-local composables live under features/*/composables/)
├── lib/               Pure utility functions, no Vue imports — safe to unit-test without mounting
├── router/            Vue Router — routes + guard policy
└── assets/
```

---

## Auth & state

<!-- This pattern (no Pinia, root-component provide()) is worth keeping as a real starting point
     if your app follows it — replace with your actual store approach (Pinia, etc.) otherwise. -->
No global store. `App.vue` is the central state holder:

- Tokens stored in cookies; an `authFetch()` wrapper adds the `Authorization` header, retries on
  401, and redirects to logout on failure.
- State shared via `provide()`: `user`, `authFetch`, plus any app-wide reference data.
- Views/components consume shared state via a thin composable (e.g. `useAuthFetch()`) that wraps
  `inject('authFetch')` with a standard loading/error/request lifecycle — don't `inject()` directly
  in components.

---

## Design system integration

{{DESIGN_SYSTEM_NOTE}} <!-- shared component package name, import pattern, font-loading approach -->

---

<!-- OPTIONAL: only if the app shell has responsive breakpoint behaviour worth documenting once
     rather than rediscovering per-component. Delete if the app doesn't have a nonstandard
     responsive shell. -->
## Responsive layout

Document the breakpoint table and behaviour here once it's settled, e.g.:

| Viewport | Behaviour |
|---|---|
| `< {{BREAKPOINT_SM}}px` | {{BEHAVIOUR_SM}} |
| `{{BREAKPOINT_SM}}–{{BREAKPOINT_MD}}px` | {{BEHAVIOUR_MD}} |
| `≥ {{BREAKPOINT_LG}}px` | {{BEHAVIOUR_LG}} |

Any feature-specific breakpoints should build on these same numbers rather than inventing new
ones.

---

## Testing

Vitest + `@vue/test-utils` + `happy-dom`. Tests live alongside source in `__tests__/`
subdirectories.

```bash
npm run test   # Vitest — check package.json for a watch-mode variant
```

---

<!-- OPTIONAL: only if translations are generated from a source-of-truth outside this repo -->
## i18n

`{{GENERATED_I18N_FILE}}` is a **generated file** — never hand-edit it. Source of truth:
`{{I18N_SOURCE}}`. Regenerate via:
```bash
{{I18N_BUILD_COMMAND}}
```

---

## Router

`src/router/index.js` — Vue Router 4, routes lazy-loaded.

| Path | Name | View |
|---|---|---|
| `{{ROUTE_PATH}}` | `{{ROUTE_NAME}}` | `{{VIEW_NAME}}` |

{{ROUTE_GUARD_POLICY}} <!-- e.g. "No route guards — auth is enforced at the API level." -->

---

<!-- OPTIONAL: only if the repo intentionally stops short of full TS migration -->
## TypeScript

`tsconfig.json` is present with `allowJs: true` and `checkJs: false` — IDE inference only, no TS
migration. No `vue-tsc` in the build pipeline unless you add one.

---

<!-- OPTIONAL: only if this workspace has a shared /api-review skill (check the monorepo root
     CLAUDE.md before including). -->
## API Review

Run `/api-review` after modifying any `src/views/` or `App.vue` code that reads API responses —
particularly where response data is destructured, or after changes to `authFetch()`.

---

<!-- OPTIONAL: only if this workspace has a shared /playwright-session skill. -->
## Playwright Visual Testing

Before any Playwright MCP test against the logged-in app, run `/playwright-session` to bootstrap
an authenticated browser session. Requires the backend API dev server and this app's dev server
both running.
