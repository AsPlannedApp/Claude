# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

**Project** is a SaaS application. The workspace contains these codebases:

| Directory         | Tech                                | Purpose                                 | URL                                 |
|-------------------|-------------------------------------|-----------------------------------------|-------------------------------------|
| `claude-memory/`  | Claude KB and Plans                 | Keep Claude Code updated and consistent | -                                   |
| `public-app/`     | Next.js 16, TypeScript, Tailwind v4 | Marketing site + API backend            | project.app (Vercel)                |
| `logged-app/`     | Vue 3, JavaScript, Tailwind v4      | Logged-in SPA                           | me.project.app (Cloudflare Workers) |
| `backend-php/`    | Laravel 13, PHP 8.4                 | Backend API (iCal, data processing)     | Docker, port 4000                   |
| `api-collection/` | Bruno API Collection                | Centralized API endpints for test       | —                                   |
| `project-ui/`     | npm workspaces                      | Shared design-system component library  | localhost playgrounds               |
| `project-design/` | Static reference                    | Design tokens, fonts, preview HTML      | Claude Design                       |

Each sub-repo has its own `CLAUDE.md` with repo-specific detail, and an `ARCHITECTURE.md` with structural rules and agent constraints. **Read `ARCHITECTURE.md` before writing any new code in a sub-repo.** This root file covers cross-repo conventions only.

---

## claude-memory/ — Self-Memory Layer

`claude-memory/` is the cross-repo planning and memory layer for this project. It is **not** a deployable codebase — it is Claude's persistent working memory for the Project: `knowledge/` holds domain rules/facts/hypotheses (routed via its own `INDEX.md`), `plans/` holds the active feature plans as numbered step folders, each with its own `README.md` spec.

**Before starting any  work:** read `claude-memory/plans/INDEX.md` to check step status and dependencies. Each step folder has its own `README.md` with the full spec for that step.

---

## Basic Knowledgebase

- Before starting a task/plan, review existing rules and hypotheses for that domain (`claude-memory/knowledge/<domain>/`). Apply rules by default; check if a hypothesis can be tested with today's work.
- At the end of each task, extract insights into the domain folder: `knowledge.md` (facts/patterns), `hypotheses.md` (needs more data), `rules.md` (confirmed — apply by default). Create the folder if it doesn't exist.
- Promote a hypothesis to a rule after 3+ confirmations; demote a rule back to hypothesis if later contradicted.
- Keep `claude-memory/knowledge/INDEX.md` routing to every domain folder.
- Every plan's last step should update the knowledgebase, unless told not to.

---

## API Review

Whenever code in any codebase that touches the API contract changes — new routes, modified response shapes, new client-side consumers — run `/api-review` against the affected endpoint and consumer.

The skill covers: response envelope shape, HTTP verb/status rules, 204 empty-body handling, pagination shape, Bruno collection sync, and JS/Vue consumer alignment.

Trigger points by codebase:
- **backend-php**: any new/modified controller, route in `routes/api.php`, or `ApiResponse` usage
- **public-app**: any new/modified route in `pages/api/v1/`, changes to `helpers/api/api-util.ts`, or page code that destructures API responses
- **logged-app**: any `src/views/` or `App.vue` code that reads `element`, `collection`, or `pagination` from API data

---

## Playwright Visual Testing

Before any Playwright MCP test against the logged-in Vue SPA, run `/playwright-session` to create a throwaway account, confirm it, log in, and inject the auth cookies into the browser. Without this step, protected routes immediately redirect to login.

Requires both dev servers running:
- `localhost:3000` — `public-app` (hosts the auth API)
- `localhost:3001` — `logged-app` (the Vue SPA under test)

Trigger points:
- **logged-app**: any time you want to visually test a feature in the logged-in SPA
- **public-app**: if you need to verify API-backed browser flows end-to-end

---

## public-app/ (Next.js marketing + API)

```bash
cd public-app
nvm use v22.22.3 && npm install
npm run serve       # http://localhost:3000 + Tailwind watch
npm run ci:check    # prettier:fix + tsc + jest — use before committing
```

Pages Router only (`appDir` disabled). See `public-app/CLAUDE.md` for Contentful CMS release
flow, Tailwind build details, and the full API route structure.

---

## logged-app (Vue 3 SPA)

```bash
cd logged-app
npm install
npm run serve       # Vite dev server at http://localhost:3001
npm run test        # Vitest
```

Deployed to Cloudflare Workers via `wrangler.toml`. See `logged-app/CLAUDE.md` for structure
(`src/views/`, `src/components/`), state management (no Pinia — `App.vue` via `provide()`), and
testing details.

---

## backend-php (Laravel API)

```bash
cd backend-php
npm run serve       # Docker services, port 4000
docker-compose exec php-fpm php artisan test
```

All routes under `/api/v1/`. See `backend-php/CLAUDE.md` for structure, Pint/PHPStan config,
and IDE-helper regeneration after migrations.

---


## project-ui (shared design system)

```bash
cd project-ui
npm install
npm run build --workspace @ProjectApp/tokens           # rebuild order: tokens → css → vue → web/react
npm run dev --workspace @ProjectApp/playground-design  # http://localhost:5173
```

npm workspaces monorepo: `@ProjectApp/{tokens,css,vue,web,react,fonts,email}`. See
`project-ui/CLAUDE.md` for full design-system details, token values, and component specs.

**Architectural rule:** `tokens → CSS variables / @theme → Vue components`. Lower layers must
never import higher layers.

---

## Design System Quick Reference

Brand colors (canonical values, used across all codebases):

| Role | Token | Hex |
|---|---|---|
| Brand primary | `--brand` | `#000000` (example) |
| Brand secondary | `--brand-light` | `#000000` (example) |
| CTA / accent | `--brand-opposite` | `#000000` (example) |
| Fill / accent 2 | `--brand-fill` | `#000000` (example) |

Fonts: **{{Heading font}}** (headings h1–h4), **{{Body font}}** (body/UI), **{{Wordmark font}}** (logo wordmark), **{{Display font}}** (display accent). Served from `fonts.project.app` via Cloudflare Worker (or your own font host).

Icons: pick one icon library and stick to it across every codebase (e.g. `@tabler/icons-vue` / `@tabler/icons-react`) — outline style, consistent stroke width. Never use emoji as icons in the app UI.

Buttons: pick one border-radius convention for the app shell (e.g. `14px`, not pill) and one for the marketing site (e.g. pill). No gradients in production UI unless that's a deliberate brand choice.

---

## External services

- **CMS:** Contentful (blog/marketing content)
- **DB:** PostgreSQL via Docker (backend-php)
- **Cache:** Redis
- **Storage:** Amazon S3
- **Email:** Amazon SES + Nodemailer
- **Deploy:** Vercel (public-app), Cloudflare Workers (logged-app, project-ui/fonts)