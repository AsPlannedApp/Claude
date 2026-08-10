<!--
  BOOTSTRAP: CLAUDE.md for a Laravel/PHP API backend.
  This is a pre-filled starting point (not a blank template) — the sections below reflect common,
  reusable Laravel API conventions. Adjust the {{PLACEHOLDER}}s to your project, drop any
  `OPTIONAL` block that doesn't apply, and edit any convention that doesn't match how this
  repo actually works. Delete all HTML comments (including this one) from the final output.
-->

# CLAUDE.md — {{REPO_NAME}}

Laravel {{LARAVEL_VERSION}} / PHP {{PHP_VERSION}} API backend. Runs in Docker
({{DOCKER_SERVICES}}) on port `{{PORT}}`. All routes under `{{API_ROUTE_PREFIX}}`.

**Read `ARCHITECTURE.md` before writing any new code here** — it owns the folder structure,
Controller/Action/Resource pattern, and Agent rules (controllers must delegate to an Action, never
contain business logic). This file covers dev commands, packages, and gotchas.

---

## Dev setup

```bash
composer install
docker-compose up -d      # start services, port {{PORT}}
docker-compose down       # stop services
```

```bash
# Inside the container (or locally, if not using Docker)
php artisan migrate:fresh --seed
php artisan test
php artisan tinker
php artisan pint          # format code
```

See `ARCHITECTURE.md`'s "Quality commands" for the full lint/test/static-analysis command list.

---

## Key packages

<!-- Keep only the packages actually installed. This is a starting checklist, not a mandate. -->
| Package | Purpose |
|---|---|
| `spatie/laravel-data` | DTOs and validation |
| `firebase/php-jwt` | JWT auth |
| `aws/aws-sdk-php` | S3 file storage |
| `predis/predis` | Redis client |
| `barryvdh/laravel-ide-helper` | IDE stubs — run after schema/model changes |
| `laravel/pint` | Code formatter |
| `{{ADDITIONAL_PACKAGE}}` | {{ADDITIONAL_PACKAGE_PURPOSE}} |

---

## Code formatter

Pint with the Laravel preset (`pint.json`). {{PINT_CUSTOM_RULES_NOTE}}

Run: `php artisan pint`

---

<!-- OPTIONAL: include if seeders have a required run order (FK dependencies, lookup tables) -->
## Migrations & seeders

Migrations live in `database/migrations/`, named `YYYY_MM_DD_HHMMSS_description.php`.

Seeder order (`DatabaseSeeder.php`):
```
{{SEEDER_ORDER}}
```

{{SEEDER_ORDER_NOTE}} <!-- e.g. "X must run before Y because Y derives rows via INSERT…SELECT from X" -->

---

## API Conventions

All PHP responses go through `{{API_RESPONSE_HELPER}}` (e.g. `app/Http/Responses/ApiResponse.php`).
Never build a raw `JsonResponse` directly in controllers.

### Response methods

```php
// Single resource (GET 200, POST 201)
ApiResponse::element($data, $includes = [], $status = 200, $resource = 'generic')
// → { success: true, status: 200, message: "success", element: {...}, includes: {...} }

// Collection (GET 200)
ApiResponse::collection($data, $status = 200, $resource = 'generic')
// → { success: true, status: 200, message: "success", collection: [...] }

// No content (DELETE / PUT success)
ApiResponse::noContent()
// → HTTP 204, empty body — NO JSON

// Server / unhandled error
ApiResponse::error(Exception $exception, $status = 500)
// → { success: false, status: 500, message: "..." }

// Validation / client error
ApiResponse::invalid($message, $status = 422)
// → { success: false, status: 422, message: "Validation errors", errors: [{ message: "..." }] }
```

### Status code rules

| Code | When |
|---|---|
| 200 | GET success |
| 201 | POST creates a resource — add Location header |
| 204 | PUT / DELETE success — empty body |
| 401 | Auth invalid/missing |
| 409 | Conflict (duplicate, etc.) |
| 422 | Validation failed |
| 500 | Unhandled exception |

### Content-Type per resource

<!-- OPTIONAL: only if this repo uses vendor content-types. Drop this subsection if not. -->
`{{VENDOR_CONTENT_TYPE_PATTERN}}` (e.g. `application/vnd.{{PROJECT}}.{resource}.v1+json`) where
resource maps to the domain object returned (`user`, `error`, etc.).

### 204 rule

`ApiResponse::noContent()` returns an empty body. Never pass a 204 status into `element()` — that
would return a JSON body on a 204, violating HTTP spec.

### 405 Method Not Allowed

Handle centrally in `bootstrap/app.php` via `withExceptions()` (routing exceptions fire before
middleware): `{ "success": false, "status": 405, "message": "Method not allowed" }`, plus an
`Allow: <methods>` header.

### 422 Validation (FormRequest failures)

Also rendered globally in `bootstrap/app.php` via `withExceptions()` so the standard envelope is
guaranteed regardless of `Accept` header: one entry per failed rule, flattened from Laravel's
`field => [messages]` shape into `errors: [{ message }, ...]`.

---

## IDE helpers

Run after any schema or model change:
```bash
php artisan ide-helper:models --write --no-interaction
```

Writes `@property` docblocks directly into each model file — commit the modified model files
themselves, there's no separate stub file.

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
| {{DB_SERVICE}} | Primary database |
| Redis | Caching |
| {{STORAGE_SERVICE}} | File storage |
| {{EMAIL_SERVICE}} | Transactional email |

---

<!-- OPTIONAL: only if this workspace has a shared /api-review skill (check the monorepo root
     CLAUDE.md before including). -->
## API Review

Run `/api-review` after adding or modifying:
- Any controller in `app/Http/Controllers/`
- Routes in `routes/api.php`
- `{{API_RESPONSE_HELPER}}` usage (key rule: use `ApiResponse::noContent()` for 204 — never pass a
  204 status to `element()`, which would return a JSON body on a 204)
