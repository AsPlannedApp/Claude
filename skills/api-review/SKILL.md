---
description: Review an API endpoint or consumer for REST convention compliance. Use when code touches an API route, response shape, controller, Bruno collection, or Vue consumer that reads API data.
---

# /api-review — Project API Review Skill

You are performing an API review for the Project platform. This skill is self-contained: all conventions are embedded below. Do not rely on CLAUDE.md to run this review.

---

## Project REST API Standard

### Response Envelopes

```json
// GET or POST returning a single resource → HTTP 200 or 201
{
  "success": true,
  "status": 200,
  "message": "success",
  "element": { "id": "...", ... },
  "includes": { "timezones": [...] }   // optional — sideloaded lookup data only
}

// GET returning multiple resources → HTTP 200
{
  "success": true,
  "status": 200,
  "message": "success",
  "collection": [ {...}, {...} ]
}

// GET returning a paginated collection → HTTP 200
// pagination object is present alongside collection; absent on non-paginated endpoints
{
  "success": true,
  "status": 200,
  "message": "success",
  "collection": [ {...}, {...} ],
  "pagination": {
    "currentPage": 1,
    "totalPages": 4,
    "totalItems": 37,
    "perPage": 10,
    "hasNext": true,
    "hasPrev": false
  }
}
// No results: currentPage:1, totalPages:1, totalItems:0, hasNext:false, hasPrev:false
// ?page defaults to 1 if omitted

// POST creating a resource → HTTP 201 + Location header
{
  "success": true,
  "status": 201,
  "message": "success",
  "element": { ... }
}

// PUT or DELETE success → HTTP 204, EMPTY BODY (no JSON at all)

// Validation error → HTTP 422
{
  "success": false,
  "status": 422,
  "message": "Validation errors",
  "errors": [
    { "message": "Email is invalid" },
    { "message": "Password too short" }
  ]
}

// Method not allowed → HTTP 405 + Allow header
{
  "success": false,
  "status": 405,
  "message": "Method not allowed"
}

// Single error (401, 404, 409, 500…) → no errors array
{
  "success": false,
  "status": 401,
  "message": "Invalid JWT token"
}
```

### HTTP Verb → Status Code Rules

| Verb   | Used on               | Success code    | Notes            |
|--------|-----------------------|-----------------|------------------|
| GET    | element or collection | 200             | Safe, idempotent |
| POST   | collection (creates)  | 201 + Location  | Not idempotent   |
| PUT    | element (full update) | 204, empty body | Idempotent       |
| DELETE | element               | 204, empty body | Idempotent       |

### Status Codes

| Code | When                                     |
|------|------------------------------------------|
| 200  | GET success                              |
| 201  | POST success (resource created)          |
| 204  | PUT / DELETE success — empty body        |
| 400  | Generic bad request / malformed input    |
| 401  | Missing or invalid JWT — unauthenticated |
| 403  | Authenticated but not authorized         |
| 404  | Resource not found                       |
| 405  | Method not allowed                       |
| 409  | Conflict (e.g. duplicate resource)       |
| 422  | Validation failed (NEVER use 406)        |
| 500  | Unhandled server exception               |
| 501  | Not implemented (stub routes)            |

### URL Rules

- Collections end with `/`: `/users/`, `/newsletters/subscribers/`
- Elements do NOT: `/users/{id}`, `/newsletters/subscription`
- No verbs in URLs: ❌ `/auth/delete`, ❌ `/newsletter/remove`
- Exception: `/newsletter/subscribe` — pragmatic POST kept (not a collection URL)

### Content-Type

**PHP responses** (`backend-php`): `application/vnd.project.{resource}.v1+json`
- user: `application/vnd.project.user.v1+json`
- avatar: `application/vnd.project.avatar.v1+json`
- error: `application/vnd.project.error.v1+json`

**JS responses** (`public-app`): `application/vnd.project.{resource}+json` (no `.v1`, uses existing constants)

### Auth Token Shape

Login and refresh both return tokens wrapped in `element`:
```json
{ "success": true, "status": 201, "message": "success", "element": { "accessToken": "...", "refreshToken": "..." } }
```

### Known Endpoints

| Method | Path                            | API | Auth | Success                                             |
|--------|---------------------------------|-----|------|-----------------------------------------------------|
| POST   | /api/v1/auth/login              | JS  | No   | 201 + element.{accessToken,refreshToken}            |
| POST   | /api/v1/auth/refresh            | JS  | No   | 201 + element.{accessToken,refreshToken}            |
| POST   | /api/v1/auth/logout             | JS  | Yes  | 200                                                 |
| GET    | /api/v1/users/me                | JS  | Yes  | 200 + element.{userId,settings}                     |
| GET    | /api/v1/users/me/profile        | PHP | Yes  | 200 + element + includes                            |
| PUT    | /api/v1/users/me/profile        | PHP | Yes  | 204 empty                                           |
| POST   | /api/v1/users/me/avatar         | PHP | Yes  | 201 + element.avatar + Location header              |
| DELETE | /api/v1/users/me/avatar         | PHP | Yes  | 204 empty                                           |
| GET    | /api/v1/blog/posts?page=N       | JS  | No   | 200 + collection                                    |
| GET    | /api/v1/blog/article?slug=...   | JS  | No   | 200 + element                                       |
| GET    | /api/v1/blog/category?id=...    | JS  | No   | 200 + collection                                    |
| GET    | /api/v1/blog/label?id=...       | JS  | No   | 200 + collection                                    |
| GET    | /api/v1/blog/search?q=...       | JS  | No   | 200 + collection (empty collection when no results) |
| POST   | /api/v1/newsletter/subscribe    | JS  | No   | 201                                                 |
| POST   | /api/v1/newsletter/confirm      | JS  | No   | 201                                                 |
| DELETE | /api/v1/newsletter/subscription | JS  | No   | 204 empty                                           |

### PHP — ApiResponse helper

Always use `ApiResponse` (never raw `JsonResponse`) in controllers:

```php
ApiResponse::element($data, $includes = [], $status = 200, $resource = 'generic')
ApiResponse::collection($data, $status = 200, $resource = 'generic')
ApiResponse::noContent()          // HTTP 204, empty body — never pass NO_CONTENT to element()
ApiResponse::error($exception, $status = 500)
ApiResponse::invalid($message, $status = 422)
```

### JS — API constants (`helpers/api/api-constants.mjs`)

```js
apiConst.VALIDATION_ERROR = 422   // NOT 406
apiConst.NOT_FOUND = 404
apiConst.AUTH_ERROR = 401
apiConst.SUCCESS = 200
apiConst.CREATED = 201
apiConst.NO_CONTENT = 204
```

---

## Review Checklist

When reviewing an endpoint, verify each category and mark ✅ or ❌:

### 1. HTTP Verb
- [ ] Correct verb for the operation (GET=read, POST=create, PUT=update, DELETE=remove)
- [ ] No verbs in the URL path
- [ ] Logout is POST (not GET)
- [ ] Newsletter unsubscribe is DELETE on `/subscription` (not POST on `/remove`)

### 2. URL Structure
- [ ] Collections end with `/` if applicable
- [ ] No verbs in path segments
- [ ] Resource naming is consistent with existing endpoints

### 3. Auth
- [ ] Protected endpoints require `Authorization: Bearer <token>`
- [ ] Public endpoints are in `endpointNoAuth` (JS) or not behind `verify.jwt` (PHP)
- [ ] 401 response includes `status: 401` field

### 4. Request Payload
- [ ] Validated before processing
- [ ] Validation errors return 422 with `errors` array (not 406, not 400)
- [ ] No extra fields accepted/leaked in response

### 5. Response Code
- [ ] GET → 200
- [ ] POST (creates) → 201 + Location header
- [ ] PUT → 204 empty body
- [ ] DELETE → 204 empty body
- [ ] Not found → 404 (not 401)
- [ ] Validation → 422 (not 406)

### 6. Response Envelope
- [ ] Success: `{ success: true, status: N, message: "success", element/collection: ... }`
- [ ] Error: `{ success: false, status: N, message: "..." }`
- [ ] 204: empty body (no JSON)
- [ ] `content` key NOT used (legacy — should be `element`)
- [ ] `success` is `true` for 2xx (not inverted)

### 7. Pagination (collection endpoints only)
- [ ] `pagination` object present alongside `collection`
- [ ] Fields: `currentPage`, `totalPages`, `totalItems`, `perPage`, `hasNext`, `hasPrev`
- [ ] `?page` missing → defaults to page 1 (no 422)
- [ ] Empty results: `currentPage:1, totalPages:1, totalItems:0, hasNext:false, hasPrev:false`
- [ ] Non-paginated endpoints (single resource): `pagination` key absent

### 7. Method Not Allowed (405)
- [ ] Body is JSON `{ success: false, status: 405, message: "Method not allowed" }` (not plain text)
- [ ] `Allow` header lists the valid methods for the route
- [ ] JS: handled in `apiHandler` (central) or `default` case of manual switch routes
- [ ] PHP: handled in `bootstrap/app.php` `withExceptions()` — NOT middleware

### 8. Content-Type
- [ ] PHP: `application/vnd.project.{resource}.v1+json`
- [ ] JS: `application/vnd.project.{resource}+json`
- [ ] Error: `application/vnd.project.error[.v1]+json`

### 9. Bruno Collection
- [ ] Request exists in collection
- [ ] Token extraction uses `res.body.element.accessToken` (not flat `res.body.accessToken`)
- [ ] Tests check correct status code and response shape

---

## Common Violations

| Violation                                          | Fix                                                                                                                                          |
|----------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------|
| `success: false` on a 200 response                 | `ApiResponse::element()` bug — use the helper correctly                                                                                      |
| `content` key instead of `element`                 | Replace `content` with `element` in response and consumer                                                                                    |
| 406 for validation errors                          | Change `VALIDATION_ERROR` to 422                                                                                                             |
| 401 for "not found"                                | Return 404 instead                                                                                                                           |
| 400 with `success: false` for empty results        | Return 200 with `collection: []`                                                                                                             |
| GET logout                                         | Change to POST                                                                                                                               |
| POST /newsletter/remove                            | Change to DELETE /newsletter/subscription                                                                                                    |
| 204 with JSON body                                 | Use `ApiResponse::noContent()` — returns empty body                                                                                          |
| Flat `{ success, accessToken, refreshToken }`      | Wrap in `element`                                                                                                                            |
| Missing `status` field in response                 | Add `status: N` field                                                                                                                        |
| 405 body is plain text (`Method POST Not Allowed`) | Return `JSON.stringify({ success: false, status: 405, message: 'Method not allowed' })` — fix in `apiHandler` (JS) or `withExceptions` (PHP) |
| Flat `currentPage`/`totalPages` at top level       | Nest in `pagination` object; add `totalItems`, `perPage`, `hasNext`, `hasPrev`                                                               |
| `currentPage: 0` for empty search results          | Use `buildPagination(1, 0)` → `currentPage:1, totalItems:0`                                                                                  |
| Missing `?page` default → 422                      | Default `query.page ?? '1'` before validation                                                                                                |

---

## How to Run a Review

1. **Identify the endpoint**: verb, path, which API (JS/PHP), auth required?
2. **Read the route file** in `pages/api/v1/` (JS) or `routes/api.php` + controller (PHP)
3. **Check each item** in the checklist above
4. **Report findings** as a table:

```
| Category        | Status | Finding                             |
|-----------------|--------|-------------------------------------|
| Verb            | ✅     | POST ✓                             |
| Status code     | ❌     | Returns 406, should be 422          |
| Response shape  | ❌     | Uses `content`, should be `element` |
| Content-Type    | ✅     | Correct vendor type                 |
| Bruno           | ❌     | Token extraction needs update       |
```

5. **Apply fixes**: edit the relevant files, update Bruno collection
6. **Update consumers**: if JS response shape changes, update Vue SPA (`App.vue`, `ProfileView.vue`) that reads it