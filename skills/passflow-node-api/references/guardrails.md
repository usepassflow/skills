# Guardrails: Node API

Read this before you edit any auth code in the API. Each rule says what to do, why, what to do instead, and whether `scripts/verify.sh` checks it.

## 1. Verify tokens with `createVerifier`, never by hand

- **Rule:** every access token is checked by a verifier from `createVerifier`, through an adapter (`passflowExpress`, `passflowFastify`, `passflowHono`) or `authenticateRequest`.
- **Why:** decoding a token is not verifying it. A hand-decoded token has no signature check, no issuer or audience check and no expiry check. Anyone can write a token that decodes.
- **Instead:** no `jwt-decode`, no `jsonwebtoken`, no `atob(...)` or `Buffer.from(..., 'base64')` on a token. Read claims with `getAuth(...)` after the middleware ran, or from `result.claims` of `authenticateRequest`.
- **Checked:** `verify.sh static` (guardrails) fails on `jwt-decode`, `jsonwebtoken`, `jwtDecode(`, and on `atob(` or a base64 `Buffer.from` in files that handle tokens.

## 2. Check the token on every protected route, on the server

- **Rule:** each route that returns or changes private data has `authenticate`, `requireACR(...)` or `requireFresh(...)` on it, or calls `authenticateRequest` first.
- **Why:** hiding a button in the browser protects nothing. The API is reachable without the browser.
- **Instead:** put the middleware on the route itself, or on a router or Fastify scope that holds only protected routes. A public route stays outside that scope.
- **Checked:** `verify.sh run` calls the protected route with no token and with an invalid token, and expects 401 both times.

## 3. Return the library's rejection unchanged

- **Rule:** a 401 or 503 from the adapter goes to the client as it is: status, `WWW-Authenticate` and `Cache-Control: no-store`.
- **Why:** the browser SDK starts a step-up only from the exact challenge. A custom error handler or a rewritten body drops it.
- **Instead:** do not wrap the middleware in `try`/`catch`, do not call `next(err)` with it, and return `result.response` from `authenticateRequest` as it is. A missing role is your decision: answer 403 with no `WWW-Authenticate`.
- **Checked:** `verify.sh run` reads `WWW-Authenticate` and `Cache-Control` on the 401.

## 4. Expose `WWW-Authenticate` when a browser calls the API

- **Rule:** when a page on another origin calls the API, CORS is mounted before every route and its options are wrapped in `exposeChallengeHeader`.
- **Why:** a browser hides `WWW-Authenticate` from a cross-origin page unless `Access-Control-Expose-Headers` names it. `*` does not count on a credentialed request.
- **Instead:** wrap the existing CORS options in `exposeChallengeHeader`, or use `passflowCors(...)` from the CORS asset when the CORS package is already a dependency, with the origins the API already allows. Do not hard-code a new origin. Keep the existing `credentials` setting and never turn it on: a bearer token needs no credentials, and credentials with an origin that reflects every site lets any site read the answers.
- **Checked:** `verify.sh run --origin <origin>` checks that the 401 carries `Access-Control-Allow-Origin` for that origin and `Access-Control-Expose-Headers` with `WWW-Authenticate`.

## 5. Configuration comes from the environment

- **Rule:** the issuer and the audience come from `PASSFLOW_ISSUER` and `PASSFLOW_AUDIENCE`. Nothing Passflow-specific is hard-coded.
- **Why:** each environment (local, staging, production) has its own issuer and app. A hard-coded value ships the wrong one, or mixes them.
- **Instead:** keep `src/passflow.ts` as the asset has it. Build one verifier at startup and share it.
- **Checked:** no.

## 6. Copy SDK calls from `assets/`, never from memory

- **Rule:** every `@passflow/node` import and call in the app matches an asset file.
- **Why:** the package has a small, exact surface. A remembered name, option or import path from another library compiles badly or, worse, compiles and checks nothing.
- **Instead:** copy the asset, then adapt only what its comment allows (file location, import style, the route list). For the app's own routes, copy the lines in `assets/examples/`.
- **Checked:** `verify.sh static` type-checks and builds the app.

## 7. Never print or log a token

- **Rule:** no `console.log`, logger call, error message or response body contains a token, an `Authorization` header or an env value.
- **Why:** logs are copied, shipped and kept. A logged token is a stolen session.
- **Instead:** to debug a rejection, log `error.code` and `error.reason` of a `PassflowAuthError`, nothing else, as `assets/examples/explain-rejection.ts` does.
- **Checked:** no.

## 8. Add only `@passflow/node`; leave scripts and env files alone

- **Rule:** the only dependency you add is `@passflow/node`. You never edit `package.json` scripts and never create or edit a `.env*` file, `.env.example` included.
- **Why:** the choice of server packages belongs to the project, and a change through the Passflow service that adds another dependency, touches a script or writes an env file is refused as a whole. The CLI and the service write the env files themselves.
- **Instead:** when the project needs another package (a CORS package), a script change (`--env-file=.env`) or env values, list the exact command or line in the final message to the developer.
- **Checked:** no.

## 9. The env file stays out of git

- **Rule:** `.env` holds the real values and is never committed. On the developer's machine, if `git ls-files --error-unmatch .env` succeeds, stop and tell the user. A Passflow GitHub App run never starts on such a repository: the service refuses a committed `.env`, `.env.local` or `.env.*.local` before the agent runs.
- **Why:** a `.gitignore` line does not cover a file git already tracks.
- **Instead:** tell the user to run `git rm --cached .env`, commit, and add `.env` to `.gitignore`. Do not edit `.env` yourself.
- **Checked:** no.
