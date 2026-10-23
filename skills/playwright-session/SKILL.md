---
description: Set up a Playwright auth session for the logged-in Vue SPA. Use before any Playwright visual test against localhost:3001 — creates a throwaway account, confirms it, logs in, and injects auth cookies into the browser.
---

# /playwright-session — Project Playwright Auth Setup

Before running any Playwright visual test against the logged-in Vue SPA (`localhost:3001`), you need a valid auth session. This skill creates a throwaway account via the dev API, confirms it, logs in, and injects the resulting tokens into the Playwright browser as cookies.

This skill is **dev-only** — it depends on `debug.token`/`debug.hash` which the JS API exposes only in non-production environments.

---

## Prerequisites

Both dev servers must be running:
- `public-app`: `npm run dev` → `localhost:3000` (auth API)
- `logged-app`: `npm run dev` → `localhost:3001` (Vue SPA)

---

## Step 1 — Generate credentials

Run this in Bash before the curl chain:

```bash
EMAIL="$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 16)@mailinator.com"
PASSWORD='Pa$$123456'
DEVICE_ID="$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 10)"
```

---

## Step 2 — Register

```bash
curl -s -X POST http://localhost:3000/api/v1/auth/register \
  -H 'Content-Type: application/json' \
  -H "X-Device-Id: $DEVICE_ID" \
  -H 'Accept-Language: en' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"confirmPassword\":\"$PASSWORD\",\"acceptTerms\":true}"
```

Expected: HTTP 201. The response includes:
```json
{
  "success": true,
  "status": 201,
  "message": "Created",
  "debug": {
    "token": "<emailToken>",
    "hash": "<emailHash>"
  }
}
```

Save `debug.token` and `debug.hash`.

---

## Step 3 — Confirm email

```bash
curl -s -X POST http://localhost:3000/api/v1/auth/confirm \
  -H 'Content-Type: application/json' \
  -H "X-Device-Id: $DEVICE_ID" \
  -H 'Accept-Language: en' \
  -d "{\"token\":\"<debug.token>\",\"hash\":\"<debug.hash>\"}"
```

Expected: HTTP 201.

---

## Step 4 — Login

```bash
curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -H "X-Device-Id: $DEVICE_ID" \
  -H 'Accept-Language: en' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}"
```

Expected: HTTP 201. Save `element.accessToken` and `element.refreshToken`:
```json
{
  "success": true,
  "status": 201,
  "message": "success",
  "element": {
    "accessToken": "eyJ...",
    "refreshToken": "eyJ..."
  }
}
```

---

## Step 5 — Inject tokens into the Playwright browser

The Vue SPA reads auth from cookies (`accessToken`, `refreshToken`, `deviceId`) on mount and immediately redirects to logout if they are missing or invalid. Cookies **must** be injected at the browser context level **before** navigating to `localhost:3001`, otherwise the redirect fires before any `evaluate` can run.

Use `mcp__playwright__browser_run_code_unsafe`:

```js
async (page) => {
  // Playwright cookies take `expires` (Unix seconds); without it they're session cookies and a
  // browser restart logs the session out.
  const expires = Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 180
  await page.context().addCookies([
    { name: 'accessToken',  value: '<accessToken>',  domain: 'localhost', path: '/', expires },
    { name: 'refreshToken', value: '<refreshToken>', domain: 'localhost', path: '/', expires },
    { name: 'deviceId',     value: '<DEVICE_ID>',    domain: 'localhost', path: '/', expires },
  ])
  return 'cookies injected'
}
```

Then navigate to the protected route:

```
mcp__playwright__browser_navigate → http://localhost:3001
```

The app shell (nav, avatar) should be visible — not the login page.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Register returns 403 | `acceptTerms` missing or false | Ensure `"acceptTerms":true` in body |
| Register returns 422 | Password too weak or fields mismatch | Use exactly `Pa$$123456` |
| Confirm returns 401 | Wrong token/hash or token already used | Re-register (tokens are single-use) |
| Login returns 401 | Email not confirmed | Re-run Step 3 |
| Logged out after a while; only `deviceId` cookie left | Cookies were set without `expires` (session cookies), and the MCP browser restarted | Re-run Step 4–5; the snippet sets `expires` |
| App redirects to logout even with no cookies | `authFetch` fires on mount with no token | Use `page.context().addCookies()` BEFORE navigating (see Step 5) |
| `debug` field absent from register response | Running against production | Skill only works on dev (`localhost:3000`) |