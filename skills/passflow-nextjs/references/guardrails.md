# Guardrails: Next.js

Read this before you edit any auth code in the app. Each rule says what to do, why, what to do instead, and whether `scripts/verify.sh` checks it. On the developer's machine you run `verify.sh`; in a Passflow GitHub App run the runner runs it after you finish, and you check your work with `run_build()` and `run_typecheck()`.

## 1. Check the session in server code, never in the proxy alone

- **Rule:** every page, layout, server action and route handler that shows or changes private data calls `passflow.requireSession()` or `passflow.getSession()` itself.
- **Why:** the proxy can be skipped. A request header once let callers bypass Next.js middleware entirely (CVE-2025-29927), and a narrow `matcher` silently leaves paths out. The proxy serves the auth routes and refreshes the cookie; it is not the security check.
- **Instead:** never add a "signed in?" redirect to `proxy.ts` and stop there. Put the call in the code that reads the data.
- **Checked:** `verify.sh run` requests the protected page and route handler with no cookie.

## 2. Close the backend, not only the page

- **Rule:** a server action or route handler that a protected page calls checks the session on its own.
- **Why:** server actions and route handlers are HTTP endpoints. Anyone can call them without loading the page that shows the button.
- **Instead:** server actions start with `const { user } = await passflow.requireSession();` (`assets/app/actions.example.ts`). Route handlers call `getSession()` and return `passflow.unauthorized()` when `session === null` (`assets/app/api/me/route.ts`). A route handler never calls `requireSession()`: it must answer 401, not redirect to an HTML page.
- **Checked:** `verify.sh run` expects 401 with `Cache-Control: no-store` from the route handler.

## 3. With cacheComponents, protected content renders only under the component that checks

- **Rule:** everything that needs a signed-in user is rendered inside the async component that calls `requireSession()`, and that component sits in `<Suspense>`.
- **Why:** with `cacheComponents: true`, the part outside `<Suspense>` is prerendered once and sent to every visitor. The redirect for a signed-out visitor can arrive in the stream after a 200, so the status code proves nothing.
- **Instead:** keep the page shell to layout, as `assets/app/account/page.tsx` does. Never call `getSession()` or `requireSession()` inside `'use cache'`. `<AuthLinks />` reads the session too, so it also renders inside `<Suspense>`.
- **Checked:** `verify.sh run` fails when the signed-out page's body contains `data-passflow-protected`. Put that attribute on the element that holds the protected content of the page you check.

## 4. No secret in a `NEXT_PUBLIC_` variable

- **Rule:** `PASSFLOW_CLIENT_SECRET` and `PASSFLOW_SECRET` keep their names. Nothing named `NEXT_PUBLIC_…SECRET` exists, and no secret's value is copied into a public variable.
- **Why:** Next.js inlines every `NEXT_PUBLIC_` value into the JavaScript sent to the browser.
- **Instead:** read secrets in server code only. The package reads them itself; the app does not need to.
- **Checked:** `verify.sh static` fails on a `NEXT_PUBLIC_…SECRET` name in the source, on either secret's name or value in the client bundle (`.next/static`), and on either secret's value in the prerendered pages (`.next/server/app`). The values come from `.env.local` and from the process environment, and are never printed.

## 5. Tokens stay on the server

- **Rule:** no access token in `localStorage`, `sessionStorage`, a non-HttpOnly cookie, a server action's return value, a client component's props or a log line. `getAccessToken()` is called only by server code that sends the token to an API.
- **Why:** anything the browser can read, an injected script can read. A `Session` holds no token for this reason; a token returned from a server action is serialized into the page.
- **Instead:** pass `session.user` (or fields of it) to client components. Call the API from server code through `fetchAsUser` in `assets/lib/call-api.example.ts`, with a URL the app chose, and return only the API's data. Never import `lib/passflow` from a `'use client'` file.
- **Checked:** `verify.sh static` fails on storage calls near the word "token", and on a `'use client'` file that imports `lib/passflow` or `@passflow/nextjs`.

## 6. Verify tokens, never decode them by hand

- **Rule:** no `jwt-decode`, `jsonwebtoken`, `atob(...)` or base64 `Buffer.from` on a token.
- **Why:** decoding is not verifying. A hand-decoded token has no signature, issuer, audience or expiry check.
- **Instead:** read the user from `session.user`. The app never reads claims from the access token: it sends the token to an API (`assets/lib/call-api.example.ts`), and the API verifies it. A Node.js API does that with the Passflow Node API skill.
- **Checked:** `verify.sh static` (guardrails).

## 7. SameSite cookies plus an Origin check on changes

- **Rule:** a route handler that changes data starts with `if (!passflow.isSameOrigin(request))` and answers 403.
- **Why:** the session cookie (`__Host-passflow_session` on https, `passflow_session` on http localhost) is `SameSite=Lax`, which still lets a same-site page on another origin send it. Server actions have Next.js's own Origin check; route handlers do not.
- **Instead:** copy the `POST` handler of `assets/app/api/me/route.ts`. Do not loosen the cookie or add CORS for the app's own routes.
- **Checked:** `verify.sh run` sends a `POST` from `https://evil.example` and expects 403, and from the app's own origin and expects 401.

## 8. Copy SDK calls from `assets/`, never from memory

- **Rule:** every `@passflow/nextjs` import and call in the app matches an asset file.
- **Why:** the package has a small, exact surface. A remembered name or option from another auth library compiles badly or, worse, compiles and checks nothing.
- **Instead:** copy the asset, then adapt only what `SKILL.md` allows: the target root, the page to protect, and, when the project has no `@/*` path, the import specifiers (relative paths instead of `@/`). Never the calls.
- **Checked:** `verify.sh static` type-checks and builds the app, and checks that `proxy.ts` calls `passflow.proxy`.

## 9. Sign-in and sign-out links are plain `<a href>`

- **Rule:** links to `/auth/login` and `/auth/logout` are `<a href>`, never `next/link`.
- **Why:** both routes act on GET, and `next/link` prefetches. `/auth/logout` ignores a prefetch and a request another site starts, so a prefetch never signs the user out, but a prefetch of `/auth/login` can still start a sign-in before anyone clicks. The client router also cannot render a route the proxy serves. A plain `<a href>` keeps sign-in and sign-out working.
- **Instead:** render `<AuthLinks />` from `assets/components/auth-links.tsx` inside `<Suspense>`, in a server component. Pass `returnTo` to come back to a page after sign-in: `<AuthLinks returnTo="/account" />`. A client component that needs a link writes a plain `<a href="/auth/login?returnTo=…">` or `<a href="/auth/logout">` itself.
- **Checked:** `verify.sh static` fails on a `<Link` whose `href` starts with `/auth/`.

## 10. Never write an env file, `package.json` scripts or another dependency

- **Rule:** never create or edit any `.env*` file: `.env`, `.env.local` and `.env.example` alike. In `package.json`, only add `@passflow/nextjs`; never edit `scripts` and never add another dependency.
- **Why:** the env file holds the developer's secrets. `npx passflow integrate` writes `.env.local` and `.env.example` on the developer's machine, and the Passflow service writes `.env.example` in a GitHub App run, with the public values filled in and the secrets empty. The service refuses a change to any `.env*` file, to `scripts`, or to a dependency other than `@passflow/*`.
- **Instead:** the last message to the developer lists what they do: `cp .env.example .env.local` and fill in the values, any name `.env.example` lacks, and any script or dependency the app would need.
- **Checked:** no.

## 11. The env file stays out of git

- **Rule:** `.env.local` is never committed. On the developer's machine, if `git ls-files --error-unmatch .env.local` succeeds, stop and tell the user. In a Passflow GitHub App run, which has no shell, the checkout holds only committed files, so a `.env.local` that Glob finds is tracked: stop and tell the user.
- **Why:** a `.gitignore` line does not cover a file git already tracks.
- **Instead:** tell the user to run `git rm --cached .env.local`, commit, and add `.env.local` to `.gitignore`.
- **Checked:** no.

## 12. In an existing proxy or middleware, Passflow handles the sign-in routes first

- **Rule:** when the project already has `proxy.ts` or `middleware.ts`, its function sends `/auth/login`, `/auth/callback` and `/auth/logout` to `passflow.proxy(request)` before any of its own redirects or rewrites, and returns Passflow's response unchanged where it would return `NextResponse.next()`.
- **Why:** a locale redirect or a "signed in?" redirect that runs first catches `/auth/callback`, so the user signs in on the Passflow page and comes back without a session. A new `NextResponse.next()` built after Passflow's response drops the refreshed session cookie and the request headers Passflow forwards to the page.
- **Instead:** follow step 5 of `SKILL.md`. Look for `proxy` and `middleware` files, `.ts` or `.js`, in the project root and in `src/` before adding one. Keep the existing file's name, extension and other branches; never add a second file.
- **Checked:** partly. `verify.sh static` checks that the file calls `passflow.proxy` and that only one proxy or middleware file exists beside `app/`; `verify.sh run` checks that `/auth/login` reaches the issuer. The order of the branches is not checked.
