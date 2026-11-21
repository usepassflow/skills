# Guardrails: TanStack Start

Read this before you edit any auth code in the app. Each rule says what to do, why, what to do instead, and whether `scripts/verify.sh` checks it. On the developer's machine you run `verify.sh`; in a Passflow GitHub App run the runner runs it after you finish, and you check your work with `run_build()` and `run_typecheck()`.

## 1. A route guard calls a server function; session reads stay on the server

- **Rule:** `passflow.getSession()`, `passflow.requireSession()` and `passflow.getAccessToken()` are called only inside a `createServerFn(...).handler(...)`, a server route's `server.handlers`, or a helper module that only those call, such as `fetchAsUser` in `assets/src/lib/call-api.example.ts`. A route's `beforeLoad` calls `requireUser` (or `getUser`) from `lib/passflow`.
- **Why:** `beforeLoad` and loaders run on the server for a document request and in the browser for a client-side navigation. In the browser there is no request to read, so a direct call fails, or protects only the first page load.
- **Instead:** copy the `beforeLoad` line of `assets/src/routes/account.tsx`. It passes `location.href` as `returnTo`, so sign-in returns to the page that was navigated to.
- **Checked:** `verify.sh static` fails on a route file that calls one of the three outside a server function's handler and outside a server route. A helper module outside `routes/` that is called only from server code, such as `call-api.example.ts`, is not flagged; keeping it server-only is your job.

## 2. Close the backend, not only the route

- **Rule:** every server function and server route that returns or changes private data checks the session itself.
- **Why:** a route guard protects navigation. Server functions and server routes are HTTP endpoints that anyone can call without loading the route.
- **Instead:** server functions start their handler with `const { user } = await passflow.requireSession();` (`assets/src/lib/server-functions.example.ts`). Server routes call `getSession()` and return `passflow.unauthorized()` when `session === null` (`assets/src/routes/api/me.ts`); they never redirect.
- **Checked:** `verify.sh run` expects 401 with `Cache-Control: no-store` from the server route, and a signed-out `/account` that leads to sign-in with no `data-passflow-protected` content.

## 3. No secret in a `VITE_` variable

- **Rule:** `PASSFLOW_CLIENT_SECRET` and `PASSFLOW_SECRET` keep their names. Nothing named `VITE_…SECRET` exists, and no secret's value is copied into a `VITE_` variable.
- **Why:** Vite inlines every `VITE_` value into the JavaScript sent to the browser.
- **Instead:** read secrets in server code only. The package reads them itself; the app does not need to.
- **Checked:** `verify.sh static` fails on a `VITE_…SECRET` name in the source, and on either secret's name or value in the client bundle. The values come from `.env.local` and from the process environment, and are never printed.

## 4. Tokens stay on the server

- **Rule:** no access token in `localStorage`, `sessionStorage`, a non-HttpOnly cookie, a server function's or loader's result, or a log line. `getAccessToken()` is called only by server code that sends the token to an API.
- **Why:** a server function's result is serialized into the page or the client's response. Anything the browser can read, an injected script can read.
- **Instead:** return the session's user, which holds no token, as `requireUser` and `getUser` in `assets/src/lib/passflow.ts` do. Call the API inside a server function's handler or a server route through `fetchAsUser` in `assets/src/lib/call-api.example.ts`, with a URL the app chose, and return only the API's data.
- **Checked:** `verify.sh static` fails on storage calls near the word "token", and on `node:async_hooks` in the client bundle, which means server-only code was bundled for the browser.

## 5. Verify tokens, never decode them by hand

- **Rule:** no `jwt-decode`, `jsonwebtoken`, `atob(...)` or base64 `Buffer.from` on a token.
- **Why:** decoding is not verifying. A hand-decoded token has no signature, issuer, audience or expiry check.
- **Instead:** read the user from the session, through `requireUser` or `getUser`. The app never reads claims from the access token: it sends the token to an API (`assets/src/lib/call-api.example.ts`), and the API verifies it. A Node.js API does that with the Passflow Node API skill.
- **Checked:** `verify.sh static` (guardrails).

## 6. SameSite cookies plus two Origin checks

- **Rule:** `requestMiddleware` in `start.ts` starts with `createCsrfMiddleware({ filter: (ctx) => ctx.handlerType === 'serverFn' })` and `passflow.middleware()`.
- **Why:** registering any request middleware turns off Start's default protection for server functions, so Start's own CSRF middleware is listed again, limited to server-function calls as Start's default is. Without the filter it refuses every page load that comes from another site, including the return from sign-in, and every request with no `Origin`, `Referer` or `Sec-Fetch-Site`. The session cookie (`__Host-passflow_session` on https, `passflow_session` on http localhost) is `SameSite=Lax`, which still lets a same-site page on another origin send it. Passflow's middleware refuses with 403 every request other than GET, HEAD and OPTIONS that carries any `Cookie` header and comes from another origin, whatever the cookie's name, so the app's other cookie-based endpoints keep that protection too. Requests without cookies, such as webhooks, pass.
- **Instead:** copy the two lines from `assets/src/start.ts` exactly, filter included, and keep the project's own items after them. Never call `createCsrfMiddleware()` bare. Do not add CORS for the app's own routes.
- **Checked:** `verify.sh static` fails when `start.ts` does not register Passflow's middleware, or lacks `createCsrfMiddleware` with the server-function filter. `verify.sh run` sends cross-site `POST`s to the server route: one carrying only `passflow_session.0` and one carrying an ordinary cookie each expect 403; one with no cookie expects exactly 401, the route's own signed-out answer. A same-origin `POST` also expects exactly 401. When the route answers the no-cookie `POST` with 405 (it has no `POST` handler), the no-cookie and same-origin checks are skipped with a reason; the two 403 checks still run, because the middleware answers them before the route.

## 7. Copy SDK calls from `assets/`, never from memory

- **Rule:** every `@passflow/tanstack-react-start` import and call in the app matches an asset file.
- **Why:** the package has a small, exact surface, and Start's builder names change between releases. A remembered name compiles badly or, worse, compiles and checks nothing.
- **Instead:** copy the asset, then adapt only what `SKILL.md` allows (target root, the route to protect).
- **Checked:** `verify.sh static` builds and type-checks the app.

## 8. Sign-in and sign-out links are plain `<a href>`

- **Rule:** links to `/auth/login` and `/auth/logout` are `<a href>`, never the router's `<Link>`.
- **Why:** these paths are served by the middleware, not by a route, and act on GET, and `<Link>` preloads on intent. `/auth/logout` ignores a preload and a request another site starts, so a preload never signs the user out, but a preload of `/auth/login` can still start a sign-in before anyone clicks. A plain `<a href>` keeps sign-in and sign-out working.
- **Instead:** render `<AuthLinks user={user} />` from `assets/src/components/auth-links.tsx`, with the user from `requireUser` or `getUser`, as `assets/src/routes/account.tsx` does. Pass `returnTo` to come back to a page after sign-in. A component that needs its own link writes a plain `<a href="/auth/login?returnTo=…">` or `<a href="/auth/logout">`.
- **Checked:** `verify.sh static` fails on a `<Link` whose `href` or `to` starts with `/auth/`.

## 9. Never write an env file, `package.json` scripts or another dependency

- **Rule:** never create or edit any `.env*` file: `.env`, `.env.local` and `.env.example` alike. In `package.json`, only add `@passflow/tanstack-react-start`; never edit `scripts` and never add another dependency.
- **Why:** the env file holds the developer's secrets. `npx passflow integrate` writes `.env.local` and `.env.example` on the developer's machine, and the Passflow service writes `.env.example` in a GitHub App run, with the public values filled in and the secrets empty. The service refuses a change to any `.env*` file, to `scripts`, or to a dependency other than `@passflow/*`.
- **Instead:** the last message to the developer lists what they do: `cp .env.example .env.local` and fill in the values, any name `.env.example` lacks, and any script or dependency the app would need.
- **Checked:** no.

## 10. The env file stays out of git

- **Rule:** `.env.local` is never committed. On the developer's machine, if `git ls-files --error-unmatch .env.local` succeeds, stop and tell the user. In a Passflow GitHub App run, which has no shell, the checkout holds only committed files, so a `.env.local` that Glob finds is tracked: stop and tell the user.
- **Why:** a `.gitignore` line does not cover a file git already tracks.
- **Instead:** tell the user to run `git rm --cached .env.local`, commit, and add `.env.local` to `.gitignore`.
- **Checked:** no.
