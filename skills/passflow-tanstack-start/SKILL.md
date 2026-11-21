---
name: passflow-tanstack-start
description: Adds Passflow sign-in on the server to a TanStack Start app using @passflow/tanstack-react-start. A request middleware serves /auth/login, /auth/callback and /auth/logout and checks the Origin of cookie-carrying changes, the session lives in an encrypted HttpOnly cookie, and route guards, server functions and server routes check it. Use when asked to add Passflow sign-in, login or auth to a TanStack Start app, or to protect TanStack Start routes, server functions or API routes with Passflow. Applies when the root package.json depends on @tanstack/react-start 1.169.5 or newer and @tanstack/react-router 1.170.46 or newer.
compatibility: TanStack Start 1.169.5 or newer with TanStack Router 1.170.46 or newer (React), Node.js 22.12 or newer; npm, pnpm or Yarn 1.
license: MIT
---

# Passflow for TanStack Start

## What this does

Adds sign-in on the server to a TanStack Start app. A request middleware registered in `src/start.ts` serves `/auth/login`, `/auth/callback` and `/auth/logout`, refreshes the session when its access token is due, and refuses a cross-origin change that carries cookies. The session lives in an encrypted HttpOnly cookie, `__Host-passflow_session` on https and `passflow_session` on http localhost, split into `.0`, `.1`, … chunks when it is large. Sign-in keeps its state in a `__Host-passflow_txn` cookie (`passflow_txn` on http localhost). Both cookies use `Path=/`, and no token reaches the browser. Route guards call the `requireUser` server function; server functions and server routes check the session themselves.

## Where this runs

The steps are the same in both places, except where a step is labelled.

- **On the developer's machine** (`npx passflow integrate`): you have a shell. Run the commands shown for this place.
- **In a Passflow GitHub App run**: you have no shell. Your only tools are Read, Write, Edit, Glob, Grep and Skill, plus:
  - `add_passflow_package({name})`, which adds one `@passflow/*` package with the project's package manager, scripts off;
  - `run_build()` and `run_typecheck()`, which each return the exit code and a short tail of the output.

  Never try to run `curl`, `cat`, `npx`, `node` or a script there. After you finish, the runner runs the install, `run_build()`, `run_typecheck()` and then `verify.sh static`. It never runs `verify.sh run`, because the issuer and the client secret stay out of the sandbox: the draft PR's description tells the developer to run `bash <skill>/scripts/verify.sh run` on their machine before merging.

## Preconditions

Check each one before you change a file. Every check reads files with Read, Glob or Grep, unless it is labelled. If one fails, stop and tell the user why.

1. **Stack.** Read the root `package.json`. It lists both `@tanstack/react-start` and `@tanstack/react-router` in `dependencies` or `devDependencies`.
   - The `@tanstack/react-start` range must admit only 1.169.5 or newer: `^1.169.5`, `^1.169.7` and `>=1.169.5` pass; `^1.169.0`, `>=1.169` and `^1.168.0` fail.
   - The `@tanstack/react-router` range must admit only 1.170.46 or newer: `^1.170.46` and `>=1.170.46` pass; `^1.170.0` fails.
   - A range that cannot be compared fails too: a tag such as `latest`, `workspace:`, a URL, `a || b`, `a - b`.

   If either range fails, stop: the project needs TanStack Start 1.169.5 or newer and TanStack Router 1.170.46 or newer, written as version ranges. The package was tested with exactly those versions. Do not update them yourself. If `@tanstack/react-router` is not listed at all, the project is not detected as a TanStack Start app: stop and tell the user. The React + Vite skill refuses it too, naming the missing router.
2. **Layout.** Glob for `src/routes/` (the default) or `app/routes/` (an older layout, or `srcDirectory: 'app'` in the Start plugin options in `vite.config.*`). Call the directory that holds `routes/` `<root>`: `src` or `app`, never the `routes` directory itself. So `<root>/lib/passflow.ts` is `src/lib/passflow.ts`, and `<root>/routes/api/me.ts` is `src/routes/api/me.ts`.
3. **Node.js 22.12 or newer.** *On the developer's machine:* `node --version`. *In a Passflow GitHub App run:* the runner checks for Node.js 22.12 or newer; you do not.
4. **Package manager.** Glob the project root for lockfiles and Read the `packageManager` field of `package.json`:
   - a `packageManager` field that names `yarn@2` or newer, or `bun`, means Yarn Berry or Bun;
   - otherwise the lockfiles, in this order: `pnpm-lock.yaml` → pnpm, `package-lock.json` → npm, `yarn.lock` → Yarn 1 (classic), `.yarnrc.yml` → Yarn Berry, `bun.lock` or `bun.lockb` → Bun. If any file present points to Yarn Berry or Bun, that decides; otherwise the first one present does. A `yarn.lock` with a `__metadata:` line (Grep for it) is also Yarn Berry;
   - no lockfile at all: stop. The change needs a committed lockfile. Tell the user to install once with npm, pnpm or Yarn 1 (classic) and commit the lockfile;
   - a `packageManager` field that names a manager other than the one the lockfile picks (for example `pnpm@9.0.0` beside `package-lock.json`): stop, and tell the user to make the two agree;
   - an `npm-shrinkwrap.json` at the root: stop. This skill does not support it.

   **Yarn Berry or Bun: stop.** Tell the user that this skill supports npm, pnpm and Yarn 1 (classic) only.
5. **Env files.** The app reads `PASSFLOW_ISSUER`, `PASSFLOW_CLIENT_ID`, `PASSFLOW_CLIENT_SECRET`, `PASSFLOW_SECRET` and `APP_BASE_URL` from `.env.local`.
   - **You never create or edit any `.env*` file: not `.env`, not `.env.local`, not `.env.example`.** On the developer's machine, `npx passflow integrate` writes `.env.local` and `.env.example`. In a Passflow GitHub App run, the service writes `.env.example` with the public values filled in (`PASSFLOW_ISSUER`, `PASSFLOW_CLIENT_ID`, `APP_BASE_URL`) and the secrets empty (`PASSFLOW_CLIENT_SECRET`, `PASSFLOW_SECRET`). Empty secrets there are expected, not a failed setup.
   - If `.env.local` is missing or a value is empty, do not invent values. The code changes, the build and the type check need no values.
   - *On the developer's machine:* if `git ls-files --error-unmatch .env.local` succeeds, git tracks the file: stop. Tell the user to run `git rm --cached .env.local`, commit, and add `.env.local` to `.gitignore`.
   - *In a Passflow GitHub App run:* the service refuses a repository with a committed `.env`, `.env.local` or `.env.*.local` before you start, so there is nothing to check.
   - Never read out, print or repeat a value from an env file.
6. **What you may change in `package.json`.** Only add `@passflow/tanstack-react-start` to `dependencies`, through step 1. Never add any other dependency, and never edit `scripts`. If a step seems to need either, stop and put it in the message to the developer (step 8).

## Steps

1. **Install the package.**
   - *On the developer's machine:* use the project's package manager. The version comes from `PASSFLOW_TANSTACK_REACT_START_VERSION`; unset means the latest release. Run the line as it is:

     ```sh
     npm install "@passflow/tanstack-react-start${PASSFLOW_TANSTACK_REACT_START_VERSION:+@$PASSFLOW_TANSTACK_REACT_START_VERSION}"
     pnpm add "@passflow/tanstack-react-start${PASSFLOW_TANSTACK_REACT_START_VERSION:+@$PASSFLOW_TANSTACK_REACT_START_VERSION}"
     yarn add "@passflow/tanstack-react-start${PASSFLOW_TANSTACK_REACT_START_VERSION:+@$PASSFLOW_TANSTACK_REACT_START_VERSION}"
     ```

   - *In a Passflow GitHub App run:* call `add_passflow_package({name: "@passflow/tanstack-react-start"})`. The service pins the version, and the tool adds that exact version. Never edit `package.json` or the lockfile by hand.

2. **Copy the assets.** Read each asset and Write it to its target. Asset paths start with `src/`, which stands for `<root>`: when `<root>` is `app`, `assets/src/lib/passflow.ts` goes to `app/lib/passflow.ts`. The assets import each other with relative paths. Do not change the Passflow calls in them.

   | Asset | Target | Adapt |
   |---|---|---|
   | `assets/src/lib/passflow.ts` | `<root>/lib/passflow.ts` | Nothing. |
   | `assets/src/start.ts` | `<root>/start.ts` | If the file exists, merge instead: step 3. |
   | `assets/src/routes/api/me.ts` | `<root>/routes/api/me.ts`, or the path chosen below | Keep it: `verify.sh run` calls it. Check the app's routes first, below. |
   | `assets/src/routes/account.tsx` | `<root>/routes/account.tsx` | An example protected page. If the app has its own route to protect, apply the pattern there (step 4) and skip this file. |
   | `assets/src/components/auth-links.tsx` | `<root>/components/auth-links.tsx` | Render `<AuthLinks user={user} />` where the app shows its navigation (step 6). |
   | `assets/src/lib/server-functions.example.ts` | not copied | The pattern for server functions (step 4). |
   | `assets/src/lib/call-api.example.ts` | `<root>/lib/call-api.ts`, only if server code calls an API as the user | The pattern for sending the access token to an API (step 7). |

   **Before you add `/api/me`,** look for an existing route at that path. Glob for `<root>/routes/api/me.ts` or `.tsx`, `<root>/routes/api.me.ts` and `<root>/routes/api/me/index.ts`, and Grep `<root>/routes` for `createFileRoute('/api/me')`. If one exists, never overwrite it or add a second. Either protect that handler in place with the server-route pattern from step 4, or copy the asset to an unused path such as `<root>/routes/api/passflow/me.ts` and change its `createFileRoute('/api/me')` to `createFileRoute('/api/passflow/me')`. Name the path you used in the message to the developer (step 8), because `verify.sh run` then needs `--api /api/passflow/me`. In a Passflow GitHub App run, name it in your final summary: the summary goes into the draft PR's description, which tells the developer to run `verify.sh run --api <path>` before merging.

   The router plugin regenerates `routeTree.gen.ts` on the next `dev` or `build`; do not edit it by hand.

3. **Merge an existing `start.ts`.** Never overwrite it. Keep every item and option it has, and make its `requestMiddleware` list start with these two, as the asset does:

   ```ts
   createCsrfMiddleware({ filter: (ctx) => ctx.handlerType === 'serverFn' }),
   passflow.middleware(),
   ```

   with `import { createCsrfMiddleware } from '@tanstack/react-start';` and `import { passflow } from './lib/passflow';`. If the file has no `requestMiddleware` yet, add the key. If it already has a `createCsrfMiddleware(...)` with this filter, keep that one instead of adding a second.

   Copy the `createCsrfMiddleware` line exactly, filter included, and never call `createCsrfMiddleware()` bare. Setting `requestMiddleware` turns off Start's default check on server-function calls, so the line puts it back, limited to server functions as Start's default is. Bare, it checks every request: it refuses page loads that come from another site, including the return from sign-in to `/auth/callback`, and every request that carries no `Origin`, `Referer` or `Sec-Fetch-Site`, such as webhooks.

   Sign-in is served by `passflow.middleware()` alone. Do not add a server route for `/auth/login`, `/auth/callback` or `/auth/logout`.

4. **Protect each place that shows or changes private data.** Public routes get nothing. `getSession()` and `requireSession()` read the server's request, so they run only inside a server function or a server route. `beforeLoad` and loaders also run in the browser, so a route guard calls a server function.

   | Place | Call | Signed out |
   |---|---|---|
   | Route guard | `beforeLoad: async ({ location }) => ({ user: await requireUser({ data: { returnTo: location.href } }) }),` | The whole page goes to `/auth/login`, then back to this page |
   | A page that shows the user when there is one | `getUser()` from `lib/passflow`, in `beforeLoad` or a loader | `null` |
   | Server function that reads or changes data | `const { user } = await passflow.requireSession();` as the first line of its `.handler` | The rest of the function never runs; the page goes to sign-in |
   | Server route | `const session = await passflow.getSession();` then `if (session === null) { return passflow.unauthorized(); }` | 401 with `Cache-Control: no-store`, never a redirect |

   `assets/src/routes/account.tsx`, `assets/src/lib/server-functions.example.ts` and `assets/src/routes/api/me.ts` show each one in full. Read the guard's user in the component with `Route.useRouteContext()`. A guard protects navigation, not data: every server function and server route that returns private data checks the session itself.

5. **Origin checks.** A `start.ts` that registers request middleware turns off Start's default protection for server functions, so the asset lists Start's `createCsrfMiddleware` again, limited to server-function calls. Passflow's middleware adds the check for everything else: it refuses with 403 every request other than GET, HEAD and OPTIONS that carries a `Cookie` header and comes from another origin. That covers any cookie, whatever its name, not only Passflow's, so the app's own cookie-based endpoints are covered too. Requests without cookies, such as webhooks and bearer-token APIs, pass it. Keep both in the list, and do not add another Origin check for the same routes.

6. **Sign-in and sign-out links.** `assets/src/components/auth-links.tsx` is one component that takes the user:

   ```tsx
   export function AuthLinks({ user, returnTo = '/' }: { user: PassflowUser | null; returnTo?: string }) {
     if (user === null) {
       return <a href={`/auth/login?returnTo=${encodeURIComponent(returnTo)}`}>Sign in</a>;
     }
     return <a href="/auth/logout">Sign out</a>;
   }
   ```

   Render it where the app shows its navigation, with the user from `requireUser` or `getUser`, as `assets/src/routes/account.tsx` does with `<AuthLinks user={user} />`. Pass `returnTo="/some/path"` to come back to that page after sign-in; only a same-origin path is honoured. Links to `/auth/login` and `/auth/logout` are always plain `<a href>`, never the router's `<Link>`. These paths are served by the middleware, not by a route, and act on GET. `/auth/logout` ignores preloads and requests another site starts, so a preloading `<Link>` never signs the user out by itself, but a preload of `/auth/login` can still start a sign-in before anyone clicks. A plain `<a href>` keeps sign-in and sign-out working.

7. **Keep tokens on the server.** `requireUser` and `getUser` return the session's user (`sub`, `email`, `emailVerified`, and `name` and `picture` when known), which holds no token.

   Server code that calls an API as the signed-in user copies `assets/src/lib/call-api.example.ts`, which sends the access token as a bearer token:

   ```ts
   const token = await passflow.getAccessToken();
   ```

   Call `fetchAsUser` only inside a server function's handler or a server route, with a URL the app chose, and return only the API's data. Never return the token, or a whole session, from a server function or a loader, never put it in a cookie or browser storage, and never log it. The app itself never reads claims from the token: it reads the session's user. The API that receives the token verifies it; for a Node.js API that is the Passflow Node API skill.

8. **Check your work, then tell the developer.**
   - *On the developer's machine:* run `bash <skill>/scripts/verify.sh static` (see Verification) and fix what it reports.
   - *In a Passflow GitHub App run:* call `run_build()`, then `run_typecheck()`, and fix what they report. The build also writes the route tree the type check needs. `run_typecheck()` runs the same check as `verify.sh static`: the `typecheck` script, else `tsc -b` for a `tsconfig.json` with `references`, else `tsc -p tsconfig.json`.

   End with one message that lists what the developer does next, and change none of it yourself:
   - the env file: if `.env.local` is missing, `cp .env.example .env.local`, then fill in the values from the Passflow portal or the run page (`npx passflow integrate` writes it instead). If `.env.example` lacks a name from `assets/.env.example`, list that name;
   - the Passflow app's callback URL: `APP_BASE_URL` followed by `/auth/callback`. `APP_BASE_URL` must be the origin the browser opens, `localhost` and `127.0.0.1` being different origins. It is an origin only, with no path, query or fragment; an app served under a sub-path is not supported, and `npx passflow integrate` refuses a `--base-url` with a path;
   - `bash <skill>/scripts/verify.sh run` once `.env.local` is filled in, with `--api <path>` when the route is not at `/api/me`;
   - anything you stopped short of: a dependency or `package.json` script the app would need.

## Guardrails

Read `references/guardrails.md` before you edit auth code. In short:

- The session check is in server code. A route guard calls the `requireUser` server function; `getSession()` and `requireSession()` stay inside server functions and server routes.
- Close the backend too: every server function and server route that touches private data checks the session, not only the route that shows it.
- No secret in a `VITE_` variable.
- No token in browser storage, and no token returned from a server function or a loader.
- Never decode a token by hand; read the user from the session, and let the API that receives the token verify it.
- Keep both request middlewares registered: Start's `createCsrfMiddleware` with the server-function filter, never bare, and Passflow's, which is the Origin check for cookie-carrying changes.
- Sign-in and sign-out links are plain `<a href>`, never `<Link>`.
- Copy Passflow calls from `assets/`, never from memory.
- Never create or edit any `.env*` file, `.env.example` included. Never edit `package.json` scripts or add a dependency other than `@passflow/tanstack-react-start`.

## Verification

*On the developer's machine*, run from the project root; `<skill>` is this skill's directory:

```sh
bash <skill>/scripts/verify.sh static
bash <skill>/scripts/verify.sh run
```

*In a Passflow GitHub App run*, you run `run_build()` and `run_typecheck()` only (step 8). The runner then runs `verify.sh static` itself, and its result is part of the run. It never runs `verify.sh run`; the draft PR's description tells the developer to run it on their machine before merging, with `--api <path>` when the route moved.

- `static` needs no env values. It checks that `@passflow/tanstack-react-start` is a dependency and that `start.ts` registers `passflow.middleware()`, and lists `createCsrfMiddleware` with the server-function filter, installs with lifecycle scripts off, runs `build` (which also writes the route tree), then type-checks: the `typecheck` script when there is one, else `tsc -b --noEmit` for a solution-style `tsconfig.json`, else `tsc -p tsconfig.json --noEmit`. It searches `.output/public` and `dist/client` for the names `PASSFLOW_CLIENT_SECRET` and `PASSFLOW_SECRET`, for their values (from `.env.local` and from the process environment, never printed), and for `node:async_hooks`. It scans the source for the guardrail breaks above, including a `getSession`, `requireSession` or `getAccessToken` call in a route file outside a server function's handler and outside a server route. A helper module such as `call-api.example.ts` is not flagged; keep it called from server code only. It proves the copied calls compile and nothing secret or server-only reaches the browser.
- `run` needs the developer's `.env.local` with all five values, a `build` script, and a `start` script, Nitro output or a `preview` script, on a free port (default 3101, `--port` to change), and a reachable `PASSFLOW_ISSUER`: `/auth/login` reads the issuer's discovery document before it redirects, and answers 503 when the issuer gives no answer within 10 seconds or answers with a 5xx. It builds, starts the app and checks, signed out: `/account` (change with `--page`) has no `data-passflow-protected` content and redirects to `/auth/login`, by a redirect status or a meta refresh, never only a sign-in link in the page; `/api/me` (change with `--api`) answers 401 with `Cache-Control: no-store`; `/auth/login` redirects to the issuer's `/oidc/authorize` with `code_challenge_method=S256` and sets an HttpOnly transaction cookie (`passflow_txn` over http, `__Host-passflow_txn` over https). Then it sends four `POST`s to `/api/me`: from `https://evil.example` carrying only `Cookie: passflow_session.0=x`, and carrying an ordinary cookie, each expecting 403; from `https://evil.example` with no cookie, expecting exactly 401, because the route answers it; and from `APP_BASE_URL`'s origin, expecting exactly 401. When the route answers the no-cookie `POST` with 405 (it has no `POST` handler), the no-cookie and same-origin checks are skipped with a reason; the two 403 checks still run, because the middleware answers them before the route. It stops the server it started.

Each check prints `PASS`, `FAIL` or `SKIP`, then `RESULT pass` or `RESULT fail`. Exit 0 is a pass, 1 a failed check, 2 a refusal (unsupported stack or package manager, missing tool or env file).

## Troubleshooting

- **`TypeError` naming a `PASSFLOW_` variable or `APP_BASE_URL` on the first request.** `.env.local` is missing that value. The developer fills it in; you do not.
- **`/auth/login` answers 404.** `start.ts` does not register `passflow.middleware()`, or it is in the wrong directory. See step 3.
- **A route guard throws in the browser, or every client-side navigation ends on sign-in.** `beforeLoad` or a loader calls `passflow.getSession()` or `passflow.requireSession()` directly. Call `requireUser` or `getUser` instead (step 4).
- **Type error: a server function's result "may not be serializable".** It returns something with a value of type `unknown`, a class instance or a function. Return plain data, as `requireUser` and `getUser` in `lib/passflow.ts` do.
- **The dev server warns that server functions are not protected by the CSRF middleware.** `start.ts` lacks the `createCsrfMiddleware(...)` line. Add it as in step 3.
- **Every page answers 403 `Forbidden`, or sign-in fails on the way back.** `createCsrfMiddleware()` is called without the server-function filter. Add the filter (step 3).
- **`/auth/login` or the return to `/auth/callback` answers 503 `Sign-in is unavailable: the Passflow issuer could not be reached. Try again later.`** The app could not reach `PASSFLOW_ISSUER`: no answer within 10 seconds, a refused connection or an unknown host, or a 5xx from the issuer. Nothing retries; the user tries again later. Check the value for a typo and for a proxy or firewall in between. *On the developer's machine*, `curl -i "$PASSFLOW_ISSUER/.well-known/openid-configuration"` from the app's machine must answer 200.
- **Sign-in works on http localhost but not on the deployed https site, or the browser drops the session cookie.** On https the cookies are named `__Host-passflow_session` and `__Host-passflow_txn`, and the browser takes them only over https with `Path=/`. `APP_BASE_URL` must use `https://` there, and a proxy in front of the app must not rewrite the cookie's path or domain.
- **A webhook or another site's legitimate POST gets 403.** It sends cookies from another origin. Webhooks normally send none; if a trusted caller must send cookies cross-origin, ask the user before changing anything.
- **`npx passflow integrate` did not update this skill.** The CLI replaces only a skill folder it installed and that is still unchanged; a skill folder you changed is not overwritten. Delete the folder to get the new version.
