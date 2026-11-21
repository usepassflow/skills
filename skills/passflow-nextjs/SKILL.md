---
name: passflow-nextjs
description: Adds Passflow sign-in on the server to a Next.js 16 App Router app using @passflow/nextjs. A proxy serves /auth/login, /auth/callback and /auth/logout, the session lives in an encrypted HttpOnly cookie, and pages, layouts, server actions and route handlers check it. Use when asked to add Passflow sign-in, login or auth to a Next.js app, or to protect Next.js pages, server actions or API routes with Passflow. Applies when the root package.json depends on next 16 or newer and not on @tanstack/react-start (that has its own Passflow skill).
compatibility: Next.js 16 or newer with the App Router, React 19, Node.js 22.12 or newer; npm, pnpm or Yarn 1.
---

# Passflow for Next.js

## What this does

Adds sign-in on the server to a Next.js App Router app. `proxy.ts` serves `/auth/login`, `/auth/callback` and `/auth/logout` and refreshes the session when its access token is due. The session lives in an encrypted HttpOnly cookie, and no token reaches the browser. Pages, layouts and server actions call `requireSession()`; route handlers call `getSession()` and answer 401.

## Preconditions

Check each one before you change a file. If one fails, stop and tell the user why.

1. **Stack.** The root `package.json` lists `next` in `dependencies` or `devDependencies`, and does not list `@tanstack/react-start` (that app uses the TanStack Start Passflow skill). The `next` range must admit only Next.js 16 or newer: `^16.1.0`, `16.4.6` and `>=16` pass; `^15.3.0` fails, and so does a range that cannot be compared (a tag such as `latest`, `workspace:`, a URL, `a || b`, `a - b`). If it fails, stop: the project needs Next.js 16 or newer, written as a version range. It is not treated as another stack, even when it also lists `vite` and `react`.
2. **App Router.** The project has `app/` or `src/app/`. A Pages Router app (only `pages/`) is not supported: stop.
3. **Node.js 22.12 or newer** (`node --version`).
4. **Package manager.** Look at the project root:
   - a `packageManager` field in `package.json` that names `yarn@2` or newer, or `bun`, means Yarn Berry or Bun;
   - otherwise the lockfiles, in this order: `pnpm-lock.yaml` → pnpm, `package-lock.json` → npm, `yarn.lock` → Yarn 1 (classic), `.yarnrc.yml` → Yarn Berry, `bun.lock` or `bun.lockb` → Bun. If any file present points to Yarn Berry or Bun, that decides; otherwise the first one present does. A `yarn.lock` with a `__metadata:` line is also Yarn Berry;
   - no lockfile at all: stop. The change needs a committed lockfile. Tell the user to install once with npm, pnpm or Yarn 1 (classic) and commit the lockfile.
   - a `packageManager` field that names a manager other than the one the lockfile picks (for example `pnpm@9.0.0` beside `package-lock.json`): stop, and tell the user to make the two agree;
   - an `npm-shrinkwrap.json` at the root: stop. This skill does not support it.

   **Yarn Berry or Bun: stop.** Tell the user that this skill supports npm, pnpm and Yarn 1 (classic) only.
5. **Env files.** The app reads `PASSFLOW_ISSUER`, `PASSFLOW_CLIENT_ID`, `PASSFLOW_CLIENT_SECRET`, `PASSFLOW_SECRET` and `APP_BASE_URL` from `.env.local`.
   - **You never create or edit any `.env*` file: not `.env`, not `.env.local`, not `.env.example`.** On the developer's machine, `npx passflow integrate` writes `.env.local` and `.env.example`. In a Passflow GitHub App run, the service writes `.env.example` with the public values filled in (`PASSFLOW_ISSUER`, `PASSFLOW_CLIENT_ID`, `APP_BASE_URL`) and the secrets empty (`PASSFLOW_CLIENT_SECRET`, `PASSFLOW_SECRET`). Empty secrets there are expected, not a failed setup.
   - If `.env.local` is missing or a value is empty, do not invent values. The code changes and `verify.sh static` need no values; `verify.sh run` waits for the developer's `.env.local`.
   - If `git ls-files --error-unmatch .env.local` succeeds, git tracks the file: stop. Tell the user to run `git rm --cached .env.local`, commit, and add `.env.local` to `.gitignore`.
   - Never print the file's values.
6. **What you may change in `package.json`.** Only add `@passflow/nextjs` to `dependencies`, through the install line in step 1. Never add any other dependency, and never edit `scripts`. If a step seems to need either, stop and put it in the message to the developer (step 11).

## Steps

1. **Install the package** with the project's package manager. The version comes from `PASSFLOW_NEXTJS_VERSION`; unset means the latest release. Run the line as it is:

   ```sh
   npm install "@passflow/nextjs${PASSFLOW_NEXTJS_VERSION:+@$PASSFLOW_NEXTJS_VERSION}"
   pnpm add "@passflow/nextjs${PASSFLOW_NEXTJS_VERSION:+@$PASSFLOW_NEXTJS_VERSION}"
   yarn add "@passflow/nextjs${PASSFLOW_NEXTJS_VERSION:+@$PASSFLOW_NEXTJS_VERSION}"
   ```

2. **Pick the root.** If the project has `src/app/`, every target below goes under `src/` (`src/lib/passflow.ts`, `src/proxy.ts`, `src/app/…`). Otherwise it goes under the project root. `proxy.ts` always sits beside `app/`.

3. **Check the import alias.** The assets import with the `@/` alias (`import { passflow } from '@/lib/passflow';`), which `create-next-app` sets up by default. Look for `"@/*"` under `compilerOptions.paths` in `tsconfig.json` (or `jsconfig.json`). It must point at `<root>`: `["./*"]` for a root layout, `["./src/*"]` for a `src/` layout.
   - If it is there, copy the assets unchanged.
   - If it is missing or points elsewhere, change only the import specifiers in the copied files to relative paths (for example `'@/lib/passflow'` in `app/account/page.tsx` becomes `'../../lib/passflow'`). Never change the calls, and do not add the alias to the project's config.

   `proxy.ts` imports `'./lib/passflow'` relatively, which works in both layouts.

   The package is ESM-only: import it as the assets do, never with `require()`.

4. **Copy the assets.** Do not change the Passflow calls in them.

   | Asset | Target | Adapt |
   |---|---|---|
   | `assets/lib/passflow.ts` | `<root>/lib/passflow.ts` | Nothing. |
   | `assets/proxy.ts` | `<root>/proxy.ts` | If a proxy or middleware file exists, merge into it instead and add no file: step 5. |
   | `assets/app/api/me/route.ts` | `<root>/app/api/me/route.ts`, or the path chosen below | Keep it: `verify.sh run` calls it. Check the app's routes first, below. |

   **Before you add `/api/me`,** look for an existing route at that path: `<root>/app/api/me/route.ts` or `route.js`, or a route group or rewrite that serves `/api/me`. If one exists, never overwrite it or add a second. Either protect that handler in place with the route-handler pattern from step 6, or copy the asset to an unused path such as `<root>/app/api/passflow/me/route.ts` and run `verify.sh run --api /api/passflow/me`. Name the path you used in the message to the developer.
   | `assets/app/account/page.tsx` | `<root>/app/account/page.tsx` | An example protected page. If the app has its own page to protect, apply the pattern there (step 6) and skip this file. |
   | `assets/components/auth-links.tsx` | `<root>/components/auth-links.tsx` | Render `<AuthLinks />` where the app shows its navigation, inside `<Suspense>` (step 8). |
   | `assets/app/actions.example.ts` | not copied | The pattern for server actions (step 6). |
   | `assets/lib/call-api.example.ts` | `<root>/lib/call-api.ts`, only if server code calls an API as the user | The pattern for sending the access token to an API (step 10). |

5. **Merge an existing proxy or middleware.** Before copying `assets/proxy.ts`, look for `proxy.ts`, `proxy.js`, `middleware.ts` and `middleware.js`, both in the project root and in `src/`.
   - **None exists:** copy the asset to `<root>/proxy.ts`.
   - **One exists beside `app/`** (in `<root>`): merge into that file. Never overwrite it and never add a second file: Next.js refuses to start with both a proxy and a middleware file. Keep its name, its extension and its function (`proxy` or `middleware`); do not rename, convert or delete it. `middleware` is the older name, which Next.js 16 still runs.
   - **One exists only in the other place** (the project root of a `src/app/` project, or `src/` of a root `app/` project): Next.js does not run it. Do not merge into it or move it; stop and tell the user.
   - **More than one exists:** stop and tell the user; the project must pick one.
   - **The three sign-in routes go to Passflow first.** Make this the function's first statement, before any redirect, rewrite, locale handling or "signed in?" check the project already has. Otherwise an existing redirect can catch `/auth/callback`, and the user finishes sign-in on the Passflow page but never gets a session:

     ```ts
     const { pathname } = request.nextUrl;
     if (pathname === '/auth/login' || pathname === '/auth/callback' || pathname === '/auth/logout') {
       return passflow.proxy(request);
     }
     ```

   - **Then keep the project's branches as they are.** A branch that returns its own redirect or rewrite keeps doing so, and does not call `passflow.proxy(request)`.
   - **Wherever the function would return `NextResponse.next()`**, return Passflow's response instead, unchanged: it carries the refreshed session cookie and the request headers forwarded to the page.

     ```ts
     return passflow.proxy(request);
     ```

     To add a response header, set it on the response `passflow.proxy(request)` returns. Never build a new `NextResponse.next()` or `NextResponse.rewrite()` from it: either drops the refreshed cookie and the forwarded headers. A page reached through a rewrite branch still reads the session, but its access token is not refreshed on that request; if such a page calls an API with `getAccessToken()`, say so in the message to the developer.
   - The `matcher` must cover `/auth/:path*` and every page and route handler that reads the session. If the project's matcher is narrower, widen it to the asset's matcher or add those paths.
   - Import `passflow` as `proxy.ts` does: `import { passflow } from './lib/passflow';`. The snippets above have no type syntax, so they fit a `.js` file as they are.

6. **Protect each place that shows or changes private data.** Public pages get nothing.

   | Place | Call | Signed out |
   |---|---|---|
   | Page or layout | `const { user } = await passflow.requireSession();` in an async component inside `<Suspense>` | Redirect to `/auth/login`, back to this page after sign-in |
   | Server action | `const { user } = await passflow.requireSession();` as its first line | The rest of the action never runs; redirect to sign-in |
   | Route handler | `const session = await passflow.getSession();` then `if (session === null) { return passflow.unauthorized(); }` | 401 with `Cache-Control: no-store`, never a redirect |
   | Route handler that changes data | `if (!passflow.isSameOrigin(request)) { return new Response(null, { status: 403 }); }` before anything else, then the session check | 403 cross-origin |

   `assets/app/account/page.tsx`, `assets/app/actions.example.ts` and `assets/app/api/me/route.ts` show each one in full; the `POST` handler answers 204 with no body where the app's own change would go. Import `passflow` from `@/lib/passflow`.

7. **cacheComponents.** Next.js 16 apps often set `cacheComponents: true` in `next.config.*`. Then the part of a page outside `<Suspense>` is prerendered and sent to every visitor, signed in or not, and the sign-in redirect can arrive in the stream after a 200. So:
   - Render everything that needs a signed-in user inside the async component that calls `requireSession()`, as `Account` does in the asset. The page shell keeps layout only.
   - Do not put `requireSession()` or `getSession()` in a `'use cache'` function or component.

8. **Sign-in and sign-out links.** `assets/components/auth-links.tsx` is one async server component:

   ```tsx
   export async function AuthLinks({ returnTo = '/' }: { returnTo?: string }) {
     const session = await passflow.getSession();
     if (session === null) {
       return <a href={`/auth/login?returnTo=${encodeURIComponent(returnTo)}`}>Sign in</a>;
     }
     return <a href="/auth/logout">Sign out</a>;
   }
   ```

   It reads the session, so render it inside `<Suspense>` (with cacheComponents, outside one the build fails), and only from server components: a client component cannot render it. Pass `returnTo="/some/path"` to come back to that page after sign-in; only a same-origin path is honoured. Links to `/auth/login` and `/auth/logout` are always plain `<a href>`, never `next/link`: it prefetches, and these routes act on GET. A client component that needs a link writes a plain `<a href="/auth/login?returnTo=…">` or `<a href="/auth/logout">` itself.

9. **`APP_BASE_URL` is the origin the browser uses.** The package builds its redirects as absolute URLs on `APP_BASE_URL`, because the Next.js proxy refuses a relative `Location`, and the Passflow app's callback URL is `APP_BASE_URL` plus `/auth/callback`. If the browser opens the app on another origin (`127.0.0.1` against `localhost`, another port, a preview domain), sign-in lands on the wrong host and fails. Tell the developer; do not change it yourself.

10. **Keep tokens on the server.** The `Session` that `getSession()` and `requireSession()` return holds no token, so a page may pass `session.user` to a client component. Never import `lib/passflow` from a file marked `'use client'`.

    Server code that calls an API as the signed-in user copies `assets/lib/call-api.example.ts`, which sends the access token as a bearer token:

    ```ts
    const token = await passflow.getAccessToken();
    ```

    Call `fetchAsUser` from a server component, a server action or a route handler, with a URL the app chose, and return only the API's data. Never return the token from a server action, pass it as a prop to a client component, put it in a cookie or browser storage, or log it. The app itself never reads claims from the token: it reads `session.user`. The API that receives the token verifies it; for a Node.js API that is the Passflow Node API skill.

11. **Tell the developer.** End with one message that lists what they do next, and change none of it yourself:
    - the env file: if `.env.local` is missing, `cp .env.example .env.local`, then fill in the five values from the Passflow portal or the run page (`npx passflow integrate` writes it instead). If `.env.example` lacks a name from `assets/.env.example`, list that name;
    - the Passflow app's callback URL: `APP_BASE_URL` followed by `/auth/callback`;
    - `bash <skill>/scripts/verify.sh run` once `.env.local` is filled in, with `--api <path>` when the route is not at `/api/me`;
    - anything you stopped short of: a dependency or `package.json` script the app would need, a rewrite branch from step 5, an `APP_BASE_URL` that does not match the browser's origin (step 9).

## Guardrails

Read `references/guardrails.md` before you edit auth code. In short:

- The session check is in server code: `requireSession()` or `getSession()`. The proxy alone protects nothing.
- Close the backend too: every server action and route handler that touches private data checks the session, not only the page that links to it.
- With cacheComponents, signed-in content renders only under the component that calls `requireSession()`.
- No secret in a `NEXT_PUBLIC_` variable.
- No token in browser storage, in a server action's result or in a client component's props.
- Never decode a token by hand; read the user from the session, and let the API that receives the token verify it.
- Route handlers that change data call `isSameOrigin(request)` first.
- Sign-in and sign-out links are plain `<a href>`, never `next/link`.
- In an existing proxy or middleware, `/auth/login`, `/auth/callback` and `/auth/logout` go to `passflow.proxy(request)` before any other branch.
- Copy Passflow calls from `assets/`, never from memory.
- Never create or edit any `.env*` file, `.env.example` included. Never edit `package.json` scripts or add a dependency other than `@passflow/nextjs`.

## Verification

Run from the project root; `<skill>` is this skill's directory.

```sh
bash <skill>/scripts/verify.sh static
bash <skill>/scripts/verify.sh run
```

- `static` needs no env values. It checks that `@passflow/nextjs` is a dependency and that exactly one proxy or middleware file (`.ts` or `.js`) beside `app/` calls `passflow.proxy`, and installs with lifecycle scripts off. It runs `build` first, because the build writes `next-env.d.ts`, and then type-checks: the `typecheck` script when there is one, else `tsc -b --noEmit` for a solution-style `tsconfig.json` (one with `references`), else `tsc -p tsconfig.json --noEmit`. It searches the client bundle in `.next/static` for the names `PASSFLOW_CLIENT_SECRET` and `PASSFLOW_SECRET` and for their values, and the prerendered pages in `.next/server/app` (`.html`, `.rsc`, `.body`, `.meta`) for their values. The values come from `.env.local` and from the process environment, such as a CI secret, and are never printed. It also scans the source for the guardrail breaks above, including a `'use client'` file that imports `lib/passflow`. It proves the copied calls compile and no secret reaches the browser.
- `run` needs the developer's `.env.local` with all five values, a `build` and a `start` script, a free port (default 3100, `--port` to change), and a reachable `PASSFLOW_ISSUER`: `/auth/login` reads the issuer's discovery document before it redirects. It builds, starts the app and checks, signed out: `/account` (change with `--page`) has no `data-passflow-protected` content and redirects to `/auth/login`, in `Location` or in the stream; `/api/me` (change with `--api`) answers 401 with `Cache-Control: no-store`; `/auth/login` redirects to the issuer's `/oidc/authorize` with `code_challenge_method=S256` and sets an HttpOnly `passflow_txn` cookie; a `POST` to `/api/me` from `https://evil.example` gets 403, and from `APP_BASE_URL`'s origin gets 401 (skipped when the route has no `POST`). It stops the server it started. It never signs in.

Each check prints `PASS`, `FAIL` or `SKIP`, then `RESULT pass` or `RESULT fail`. Exit 0 is a pass, 1 a failed check, 2 a refusal (unsupported stack or package manager, missing tool or env file).

## Troubleshooting

- **`TypeError` naming a `PASSFLOW_` variable or `APP_BASE_URL` on the first request.** `.env.local` is missing that value. The build passes without it, because config is read on first use. The developer fills it in; you do not.
- **`Cannot find module '@/lib/passflow'`.** The project has no `@/*` path, or it points at another directory. Change the import specifiers to relative paths (step 3).
- **Build error about uncached data or `cookies()` outside `<Suspense>`.** `<AuthLinks />` or a component that calls `getSession()` or `requireSession()` renders outside `<Suspense>`. Wrap it (steps 7 and 8).
- **Next.js refuses to start, or `verify.sh static` fails, because both a middleware and a proxy file exist.** The project had `middleware.ts` and `proxy.ts` was added beside it. Move the Passflow call into `middleware.ts` and remove the `proxy.ts` you added (step 5).
- **The signed-out page shows its content for a moment, or `verify.sh run` finds `data-passflow-protected`.** Signed-in content sits outside the component that calls `requireSession()`. Move it inside (step 7).
- **Sign-in loops back to the sign-in page, or ends on another page with no session.** The proxy's `matcher` skips the page or `/auth/callback`, or an existing redirect runs before Passflow sees `/auth/callback`. Use the asset's matcher and send the three sign-in routes to Passflow first (step 5).
- **A route handler answers with the sign-in page's HTML instead of 401.** It calls `requireSession()`. Route handlers use `getSession()` and `passflow.unauthorized()`.
- **`/auth/login` answers 500 and the server log shows `fetch failed`.** The app cannot reach `PASSFLOW_ISSUER` for its discovery document. From the app's machine, `curl -i "$PASSFLOW_ISSUER/.well-known/openid-configuration"` must answer 200.
- **`Sign-in failed. Try again.` after the Passflow page, or sign-in ends on another host.** The browser uses an origin other than `APP_BASE_URL` (step 9). Open the app at exactly `APP_BASE_URL`, or have the developer correct it.
