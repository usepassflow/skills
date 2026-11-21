# Guardrails: React + Vite with a Node API

Read this before you edit any auth code in the SPA or its API. Each rule says what to do, why, what to do instead, and whether `scripts/verify.sh` checks it.

This stack keeps the user's tokens in browser storage. That is how `@passflow/react` works for a single-page app, and it is allowed here. The rules below are about secrets in the bundle, where the token goes, and what the API checks.

## 1. Nothing secret in a `VITE_` variable

- **Rule:** a `VITE_` variable holds only public values: the issuer URL, the app's client ID, the API's URL.
- **Why:** Vite writes every `VITE_` value into the JavaScript it ships. Anyone who opens the app can read it.
- **Instead:** a secret belongs to a server and is read there from a name without the `VITE_` prefix. This stack needs none: the SPA is a public client with PKCE, and the API verifies tokens with public keys.
- **Checked:** `verify.sh static` fails on a `VITE_` name containing `SECRET` in the source or a secret-looking `VITE_` name in `.env.local`, and searches `dist/` for the names and values of secrets.

## 2. The API checks the token on every protected route

- **Rule:** each API route that returns or changes private data has `authenticate` on it (Express, Hono) or a `preHandler` of `app.passflow.authenticate` (Fastify).
- **Why:** `RequireSignIn` only hides part of a page. The API is reachable without the SPA, by anyone with `curl`.
- **Instead:** put the check on the route itself, or on a router or Fastify scope that holds only protected routes. Treat `RequireSignIn` as layout, never as access control.
- **Checked:** `verify.sh run` calls the protected route with no token and with an invalid token, and expects 401 both times.

## 3. `PASSFLOW_AUDIENCE` is the SPA app's client ID

- **Rule:** the API's `PASSFLOW_AUDIENCE` has the same value as `VITE_PASSFLOW_APP_ID`, and `PASSFLOW_ISSUER` the same as `VITE_PASSFLOW_URL`.
- **Why:** the access tokens the SPA gets carry `aud = [app ID]`. An invented audience (`api`, a URL) matches no token, so every call gets 401.
- **Instead:** take both values from the env file the developer filled in. If one is missing, tell the developer; never make one up.
- **Checked:** no. A wrong value shows as 401 `invalid_token` on every signed-in call.

## 4. The token goes to the API's origin only, through `useApi()`

- **Rule:** the SPA calls the API with the fetch from `useApi()`. Nothing builds an `Authorization` header by hand or reads the token.
- **Why:** `withAuth` adds the token only for the page's own origin and the origins listed, and refreshes it first when it has expired. A hand-made header leaks the token to whatever URL the code calls, and goes stale.
- **Instead:** `const api = useApi();` then `api(apiUrl('/path'))`. Set `VITE_API_URL` to the API's real origin in each environment.
- **Checked:** no.

## 5. Verify tokens with `createVerifier`, never by hand

- **Rule:** the API checks every access token with the verifier from `createVerifier`, through the framework adapter. The SPA never decodes a token to decide anything.
- **Why:** decoding is not verifying. A decoded token has no signature, issuer, audience or expiry check, and anyone can write one that decodes.
- **Instead:** no `jwt-decode`, no `jsonwebtoken`, no `atob(...)` or base64 `Buffer.from` on a token. In the SPA use `useAuth().isSignedIn`; in the API read claims with `getAuth(...)` after the middleware ran.
- **Checked:** `verify.sh static` (guardrails) fails on `jwt-decode`, `jsonwebtoken`, `jwtDecode(`, and on `atob(` or a base64 `Buffer.from` in files that handle tokens.

## 6. CORS first, the SPA's origin only, `WWW-Authenticate` exposed

- **Rule:** the API mounts CORS before every route, allows only `APP_BASE_URL`'s origin, and wraps its options in `exposeChallengeHeader`.
- **Why:** a preflight that reaches authentication fails, and a 401 without CORS headers is unreadable to the SPA. A browser hides `WWW-Authenticate` from a cross-origin page unless `Access-Control-Expose-Headers` names it. Allowing every origin lets any site call the API from a user's browser.
- **Instead:** if the API already has CORS, set its origin to `appOrigin` (or add it to its list) and wrap its options in `exposeChallengeHeader`. Otherwise mount the CORS asset, when the CORS package is already a dependency. Keep the existing `credentials` setting and never turn it on: a bearer token needs no credentials.
- **Checked:** `verify.sh run` checks the 401 to the SPA's origin allows that origin and exposes `WWW-Authenticate`, the preflight allows `Authorization`, and another origin is not allowed.

## 7. No server code in the SPA

- **Rule:** nothing in `src/` imports from the API's folder, from `@passflow/node` or from a server framework.
- **Why:** an import pulls the API's code and env names into the browser bundle, and server code does not run there.
- **Instead:** the SPA talks to the API over HTTP only.
- **Checked:** `verify.sh static` searches `src/` for imports of `@passflow/node`, `express`, `fastify`, `hono` or a `../server/` or `../api/` path, and searches `dist/` for the API's env names (`PASSFLOW_ISSUER`, `PASSFLOW_AUDIENCE`, `APP_BASE_URL`).

## 8. Copy SDK calls from `assets/`, never from memory

- **Rule:** every `@passflow/react` and `@passflow/node` import and call in the app matches an asset file.
- **Why:** the packages have a small, exact surface. A remembered name, prop or import path compiles badly or, worse, compiles and checks nothing.
- **Instead:** copy the asset, then adapt only what `SKILL.md` allows (file location, the routes, the API's existing CORS).
- **Checked:** `verify.sh static` type-checks the SPA and the API and builds the SPA.

## 9. Never print or log a token

- **Rule:** no `console.log`, logger call, error message or response body contains a token, an `Authorization` header or an env value.
- **Why:** logs and browser consoles are copied, shared and kept. A logged token is a stolen session.
- **Instead:** to debug a rejection on the API, log `error.code` and `error.reason` of a `PassflowAuthError`, nothing else.
- **Checked:** no.

## 10. Add only the Passflow packages; leave scripts and env files alone

- **Rule:** the only dependencies you add are `@passflow/react` and `@passflow/node`. You never create a server, never edit `package.json` scripts, and never create or edit a `.env*` file: `.env.local`, `.env` and `.env.example` included.
- **Why:** the choice of server packages belongs to the project, and a change through the Passflow service that adds another dependency, touches a script or writes an env file is refused as a whole. The env file holds the developer's real values; the CLI and the service write `.env.example` themselves.
- **Instead:** when the project needs another package (a CORS package), a start command that loads `.env.local`, or env values, list the exact command or line in the final message to the developer. With no API at all, stop: "add an API first".
- **Checked:** `verify.sh` refuses a project whose API does not list `express`, `fastify` or `hono`.

## 11. The env file stays out of git

- **Rule:** `.env.local` is never committed. On the developer's machine, if `git ls-files --error-unmatch .env.local` succeeds, stop and tell the user. A Passflow GitHub App run never starts on such a repository: the service refuses a committed `.env`, `.env.local` or `.env.*.local` before the agent runs.
- **Why:** a `.gitignore` line does not cover a file git already tracks.
- **Instead:** tell the user to run `git rm --cached .env.local`, commit, and add `.env.local` to `.gitignore`.
- **Checked:** no.
