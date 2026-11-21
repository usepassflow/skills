# SDK surface

Every package export that the skills' assets and `SKILL.md` files call, per package, with its status and the files that use it. When a package changes, this is the list to check.

Status:

- **released**: on npm in the version named.
- **designed, not released**: specified for the next release; not on npm yet.
- **built, tested in acceptance, not published**: the package is built and its skill's assets passed the browser checks against a real Passflow; not on npm yet.

Asset paths are relative to `skills/`.

## `@passflow/node`

Released: 0.1.3. Designed: 0.2.0. Node.js 22.12 or newer. Install variable: `PASSFLOW_NODE_VERSION`.

| Export | Import path | Signature or shape | Status | Used by |
|---|---|---|---|---|
| `createVerifier` | `@passflow/node` | `createVerifier({ issuer, audience, ...options }): Verifier` | released (0.1.3) | `passflow-node-api/assets/src/passflow.ts`; `passflow-react-vite/assets/server/passflow.ts` |
| `createVerifier` with `issuer: string \| undefined` and `audience: string \| string[] \| undefined` | `@passflow/node` | a missing value throws `TypeError` when called | designed, not released (0.2.0) | `passflow-node-api/assets/src/passflow.ts`; `passflow-react-vite/assets/server/passflow.ts` |
| `.verify` | method of `Verifier` | `verify(token: string): Promise<PassflowClaims>`; rejects with a `PassflowAuthError` | released (0.1.3) | `passflow-node-api/assets/examples/explain-rejection.ts` |
| `extractBearer` | `@passflow/node` | `extractBearer(authorization: string \| undefined \| null): string \| undefined` | released (0.1.3) | `passflow-node-api/assets/examples/explain-rejection.ts` |
| `isPassflowAuthError` | `@passflow/node` | `isPassflowAuthError(e: unknown): e is PassflowAuthError`; the error has `code` (`missing_token`, `invalid_token`, `jwks_unavailable`) and `reason?` | released (0.1.3) | `passflow-node-api/assets/examples/explain-rejection.ts` |
| `authenticateRequest` | `@passflow/node` | `authenticateRequest(verifier, request: Request, requirement?): Promise<{ claims: PassflowClaims } \| { response: Response }>` | designed, not released (0.2.0) | `passflow-node-api/assets/src/fetch-handler.ts` |
| `AAL2` | `@passflow/node` | the level `'2'`, for `requireACR` | released (0.1.3) | `passflow-node-api/assets/examples/express-routes.ts`, `fastify-routes.ts`, `hono-routes.ts` |
| `passflowExpress` | `@passflow/node/express` | `passflowExpress(verifier): { authenticate, requireACR(min), requireFresh(seconds) }` | released (0.1.3) | `passflow-node-api/assets/src/express.ts`; `passflow-react-vite/assets/server/express.ts`; `requireACR(AAL2)` and `requireFresh(300)` in `passflow-node-api/assets/examples/express-routes.ts` |
| `getAuth` | `@passflow/node/express` | `getAuth(req): PassflowClaims` | released (0.1.3) | `passflow-node-api/assets/src/express.ts`, `assets/examples/express-routes.ts`; `passflow-react-vite/assets/server/express.ts` |
| `exposeChallengeHeader` | `@passflow/node/express` | adds `WWW-Authenticate` to `cors`'s `exposedHeaders`; 0.2.0 takes `exposedHeaders?: string \| readonly string[] \| undefined`, so the framework's own options type passes with `exactOptionalPropertyTypes` | released (0.1.3) | `passflow-node-api/assets/src/express-cors.ts`; `passflow-react-vite/assets/server/express-cors.ts` |
| `passflowFastify` | `@passflow/node/fastify` | plugin, `{ verifier }`; decorates `app.passflow` with `authenticate`, `requireACR`, `requireFresh` | released (0.1.3) | `passflow-node-api/assets/src/fastify.ts`; `passflow-react-vite/assets/server/fastify.ts`; `app.passflow.requireACR(AAL2)` and `requireFresh(300)` in `passflow-node-api/assets/examples/fastify-routes.ts` |
| `getAuth` | `@passflow/node/fastify` | `getAuth(request): PassflowClaims` | released (0.1.3) | `passflow-node-api/assets/src/fastify.ts`, `assets/examples/fastify-routes.ts`; `passflow-react-vite/assets/server/fastify.ts` |
| `exposeChallengeHeader` | `@passflow/node/fastify` | adds `WWW-Authenticate` to `@fastify/cors`'s `exposedHeaders`; 0.2.0 takes `exposedHeaders?: string \| readonly string[] \| undefined`, so the framework's own options type passes with `exactOptionalPropertyTypes` | released (0.1.3) | `passflow-node-api/assets/src/fastify-cors.ts`; `passflow-react-vite/assets/server/fastify-cors.ts` |
| `createFastifyHooks` | `@passflow/node/fastify` | `createFastifyHooks(verifier)`: the same three hooks, no plugin | released (0.1.3) | `passflow-node-api/assets/examples/fastify-routes.ts` |
| `passflowHono` | `@passflow/node/hono` | `passflowHono(verifier): { authenticate, requireACR(min), requireFresh(seconds) }` | released (0.1.3) | `passflow-node-api/assets/src/hono.ts`; `passflow-react-vite/assets/server/hono.ts`; `requireACR(AAL2)` and `requireFresh(300)` in `passflow-node-api/assets/examples/hono-routes.ts` |
| `getAuth` | `@passflow/node/hono` | `getAuth(c): PassflowClaims` | released (0.1.3) | `passflow-node-api/assets/src/hono.ts`, `assets/examples/hono-routes.ts`; `passflow-react-vite/assets/server/hono.ts` |
| `exposeChallengeHeader` | `@passflow/node/hono` | adds `WWW-Authenticate` to `hono/cors`'s `exposeHeaders`; 0.2.0 takes `exposeHeaders?: readonly string[] \| undefined`, so the framework's own options type passes with `exactOptionalPropertyTypes` | released (0.1.3) | `passflow-node-api/assets/src/hono-cors.ts`; `passflow-react-vite/assets/server/hono-cors.ts` |
| `PassflowVariables` (type) | `@passflow/node/hono` | `{ passflow: PassflowClaims }` | released (0.1.3) | `passflow-node-api/assets/src/hono.ts`; `passflow-react-vite/assets/server/hono.ts` |

Behaviour the skills' checks rely on (released, 0.1.3): a missing token answers 401 with `WWW-Authenticate: Bearer`; an invalid token answers 401 with `Bearer error="invalid_token"`; every rejection has `Cache-Control: no-store` and an empty body.

With 0.1.3 installed, `passflow-node-api` fails its type-check in two places only: `createVerifier` rejects `string | undefined`, and `authenticateRequest` is not exported. `passflow-react-vite` fails in one place only: `createVerifier` rejects `string | undefined` in `assets/server/passflow.ts`.

## `@passflow/react`

Released: 0.26.2 (with `@passflow/core` 0.32.1, whose exports it re-exports). Install variable: `PASSFLOW_REACT_VERSION`. Read from the published type declarations.

| Export | Import path | Signature or shape | Status | Used by |
|---|---|---|---|---|
| `PassflowProvider` | `@passflow/react` | component; props include `url`, `appId`, `scopes` (all optional; with no `url` the SDK falls back to Passflow's cloud, so the asset throws when a value is missing) | released (0.26.2) | `passflow-react-vite/assets/src/passflow.tsx` |
| `LoginButton` | `@passflow/react` | component; props include `authRedirectOptions: { redirectUrl }` and `postLogoutRedirectUri`. Default redirect URL: the current page's origin and path | released (0.26.2) | `passflow-react-vite/assets/src/passflow.tsx` |
| `useAuth` | `@passflow/react` | `useAuth(): { isSignedIn: boolean; isLoading: boolean; ... }`. `isLoading` is true only while `getTokens` runs; `isSignedIn` is read from storage on the first render | released (0.26.2) | `passflow-react-vite/assets/src/require-sign-in.tsx` |
| `usePassflow` | `@passflow/react` | `usePassflow(): Passflow`, the provider's core instance | released (0.26.2) | `passflow-react-vite/assets/src/use-api.ts`; `passflow-react-vite/assets/src/require-sign-in.tsx` |
| `.withAuth` | method of `Passflow` (`usePassflow()`) | `withAuth(next?: FetchLike, options?: { origins?: readonly string[] }): FetchLike`; adds `Bearer <access token>` (refreshed first when expired) only for the page's own origin and `origins`, and only when the request has no `Authorization` header | released (0.26.2) | `passflow-react-vite/assets/src/use-api.ts` |
| `.subscribe`, `.unsubscribe` | methods of `Passflow` | `subscribe(subscriber: PassflowSubscriber, events?: PassflowEvent[])` | released (0.26.2) | `passflow-react-vite/assets/src/require-sign-in.tsx` |
| `PassflowEvent` | `@passflow/react` | enum; `SignIn`, `Error` used | released (0.26.2) | `passflow-react-vite/assets/src/require-sign-in.tsx` |
| `PassflowSubscriber` (type) | `@passflow/react` | `{ onAuthChange(eventType, payload?): void }` | released (0.26.2) | `passflow-react-vite/assets/src/require-sign-in.tsx` |
| `FetchLike` (type) | `@passflow/react` | the `fetch` signature | released (0.26.2) | `passflow-react-vite/assets/src/use-api.ts` |
| `withAuth` | `@passflow/react` | free function, same signature as `.withAuth`; binds to the mounted provider's instance when called and throws outside one | released (0.26.2) | not used by an asset |
| style sheet | `@passflow/react/dist/style.css` | CSS import | released (0.26.2) | `passflow-react-vite/assets/src/passflow.tsx` |

Both forms of `withAuth` exist in 0.26.2: the method `usePassflow().withAuth(fetch, { origins })`, which the React getting-started page documents, and a free `withAuth` export. The asset uses the method inside `useMemo`, so it is bound to the provider's instance through React context and never runs before the provider mounts.

## `@passflow/nextjs`

Built, tested in acceptance, not published (0.1.0). Next.js 16 or newer, React 19 or newer, Node.js 22.12 or newer. ESM only, with a `browser` export condition that resolves to a stub. Depends on `@passflow/node` ^0.2.0. Install variable: `PASSFLOW_NEXTJS_VERSION`. Reads `PASSFLOW_ISSUER`, `PASSFLOW_CLIENT_ID`, `PASSFLOW_CLIENT_SECRET`, `PASSFLOW_SECRET` and `APP_BASE_URL` on first use. Redirects are absolute URLs built on `APP_BASE_URL`, because the Next.js proxy refuses a relative `Location`. `APP_BASE_URL` is an origin only; `npx passflow integrate` refuses a `--base-url` with a path, query or fragment.

Session behaviour, from `@passflow/node/session` and shared with `@passflow/tanstack-react-start`:

- Cookies: `__Host-passflow_session` (chunks `__Host-passflow_session.0`, `.1`, …) and `__Host-passflow_txn` on https; `passflow_session` and `passflow_txn` on http loopback. All use `Path=/`, the transaction cookie included.
- `GET /auth/logout` does nothing for a prefetch (`Sec-Purpose`, `Purpose` or `Next-Router-Prefetch`) or a request another site started (`Sec-Fetch-Site` other than `same-origin` or `none`).
- Issuer calls time out after 10 seconds. When the issuer gives no answer (timeout, refused connection, unknown host) or answers with a 5xx, `/auth/login` and `/auth/callback` answer 503 `text/plain` with `Sign-in is unavailable: the Passflow issuer could not be reached. Try again later.`, and nothing retries.

The assets are byte-identical to the ones the acceptance suite ran, except `app/actions.example.ts` and `lib/call-api.example.ts`, which were type-checked against the built package.

| Export | Import path | Signature or shape | Status | Used by |
|---|---|---|---|---|
| `createPassflow` | `@passflow/nextjs` | `createPassflow(config?: Partial<SessionConfig>): Passflow`; config is read from env on first use | built, tested in acceptance, not published | `passflow-nextjs/assets/lib/passflow.ts` |
| `.proxy` | method of `createPassflow()` | `proxy(request: NextRequest): Promise<NextResponse>`; serves `/auth/login`, `/auth/callback`, `/auth/logout` and refreshes the session | built, tested in acceptance, not published | `passflow-nextjs/assets/proxy.ts`; `passflow-nextjs/SKILL.md` |
| `.getSession` | method | `getSession(): Promise<Session \| null>`; `Session` is `{ user: PassflowUser; expiresAt: number }` and holds no token | built, tested in acceptance, not published | `passflow-nextjs/assets/app/api/me/route.ts`; `passflow-nextjs/assets/components/auth-links.tsx`; `passflow-nextjs/SKILL.md` |
| `.requireSession` | method | `requireSession(o?: { returnTo?: string }): Promise<Session>`; signed out: redirects to sign-in | built, tested in acceptance, not published | `passflow-nextjs/assets/app/account/page.tsx`; `passflow-nextjs/assets/app/actions.example.ts`; `passflow-nextjs/SKILL.md` |
| `.getAccessToken` | method | `getAccessToken(): Promise<string \| null>`; server code that calls an API | built, tested in acceptance, not published | `passflow-nextjs/assets/lib/call-api.example.ts`; `passflow-nextjs/SKILL.md` |
| `.unauthorized` | method | `unauthorized(): Response`; 401 with `Cache-Control: no-store` | built, tested in acceptance, not published | `passflow-nextjs/assets/app/api/me/route.ts`; `passflow-nextjs/SKILL.md` |
| `.isSameOrigin` | method | `isSameOrigin(request: Request): boolean` | built, tested in acceptance, not published | `passflow-nextjs/assets/app/api/me/route.ts`; `passflow-nextjs/SKILL.md` |

## `@passflow/tanstack-react-start`

Built, tested in acceptance, not published (0.1.0). Peer ranges: `@tanstack/react-start` >=1.169.5 <2 and `@tanstack/react-router` >=1.170.46 <2; tested with Start 1.169.5 and Router 1.170.46. Detection asks for the same floors: `@tanstack/react-start` >=1.169.5 and `@tanstack/react-router` >=1.170.46, both listed. ESM only, with a `browser` export condition that resolves to a stub. Depends on `@passflow/node` ^0.2.0. Install variable: `PASSFLOW_TANSTACK_REACT_START_VERSION`. Reads the same five env vars as `@passflow/nextjs`, with the same cookies, sign-out and issuer behaviour (see the session behaviour list above). The middleware's Origin check applies to any request with a `Cookie` header, whatever the cookie's name. The assets are byte-identical to the ones the acceptance suite ran, except `src/lib/server-functions.example.ts` and `src/lib/call-api.example.ts`, which were built and type-checked against the built package.

| Export | Import path | Signature or shape | Status | Used by |
|---|---|---|---|---|
| `createPassflow` | `@passflow/tanstack-react-start` | `createPassflow(config?: Partial<SessionConfig>): Passflow`; config is read from env on first use | built, tested in acceptance, not published | `passflow-tanstack-start/assets/src/lib/passflow.ts` |
| `.middleware` | method of `createPassflow()` | `middleware(): PassflowMiddleware`, the value `createMiddleware().server(...)` returns; auth routes, refresh, Origin check | built, tested in acceptance, not published | `passflow-tanstack-start/assets/src/start.ts`; `passflow-tanstack-start/SKILL.md` |
| `.handler` | method | `handler(): (context: { request: Request }) => Promise<Response>`; the three sign-in routes from a server route, with no refresh | built, not used by the assets | none: the skill serves sign-in from the middleware only |
| `.getSession` | method | `getSession(): Promise<Session \| null>`; server only, inside a server function or server route | built, tested in acceptance, not published | `passflow-tanstack-start/assets/src/lib/passflow.ts`; `passflow-tanstack-start/assets/src/routes/api/me.ts`; `passflow-tanstack-start/SKILL.md` |
| `.requireSession` | method | `requireSession(o?: { returnTo?: string }): Promise<Session>`; signed out: throws a redirect to sign-in | built, tested in acceptance, not published | `passflow-tanstack-start/assets/src/lib/passflow.ts`; `passflow-tanstack-start/assets/src/lib/server-functions.example.ts`; `passflow-tanstack-start/SKILL.md` |
| `.getAccessToken` | method | `getAccessToken(): Promise<string \| null>`; server code that calls an API | built, tested in acceptance, not published | `passflow-tanstack-start/assets/src/lib/call-api.example.ts`; `passflow-tanstack-start/SKILL.md` |
| `.unauthorized` | method | `unauthorized(): Response`; 401 with `Cache-Control: no-store` | built, tested in acceptance, not published | `passflow-tanstack-start/assets/src/routes/api/me.ts`; `passflow-tanstack-start/SKILL.md` |
| `PassflowUser` | `@passflow/tanstack-react-start` (type) | re-exported from `@passflow/node/session` | built, tested in acceptance, not published | `passflow-tanstack-start/assets/src/components/auth-links.tsx` |

The assets also rely on these, from the design:

- `requireSession` signed out throws `redirect({ href, reloadDocument: true })`, so a client-side navigation leaves the router for `/auth/login`.
- `middleware()` returns a value that `createStart`'s `requestMiddleware` accepts (`AnyRequestMiddleware` in Start 1.169). It refuses with 403 every request other than GET, HEAD and OPTIONS that carries any `Cookie` header from another origin.
- The server functions in `assets/src/lib/passflow.ts` use Start's `.validator()` builder (Start 1.169).
- `requireUser` and `getUser` return `session.user` as it is. A server function's result must be serializable, so `PassflowUser` has no index signature (see "Shared types"); with `[k: string]: unknown` it fails Start's type check.
- `src/start.ts` lists Start's `createCsrfMiddleware({ filter: (ctx) => ctx.handlerType === 'serverFn' })` (from `@tanstack/react-start`, Start 1.169) before `passflow.middleware()`. A `start.ts` with request middleware turns off Start's default server-function CSRF check, and Start warns in development until one is registered. The filter is Start's own default; without it, the middleware refuses cross-site page loads, including the return from sign-in to `/auth/callback`, and requests with no `Origin`, `Referer` or `Sec-Fetch-Site`.
- The package's `browser` export condition resolves to a stub, because `src/lib/passflow.ts` is also bundled for the browser. The stub holds no server code and no env names, and its methods throw if called.

## Shared types

| Type | From | Shape |
|---|---|---|
| `PassflowClaims` | `@passflow/node` | `sub`, `iss`, `aud`, `exp`, `acr`, `amr`, `scopes`, `tenants`, `authTime?`, `raw`, and more |
| `Session` | `@passflow/node/session` (0.2.0, built); re-exported as a type by `@passflow/nextjs` | `{ user: PassflowUser; expiresAt: number }` |
| `PassflowUser` | `@passflow/node/session` (0.2.0, built); re-exported as a type by `@passflow/nextjs` | exactly `{ sub: string; email?: string; emailVerified?: boolean; name?: string; picture?: string }`, with no index signature, so a TanStack Start server function can return it. UserInfo fills `sub`, `email` and `email_verified` only, so `name` and `picture` are usually absent |

## Workarounds in the assets

Each line is a gap in a package that an asset covers today. When the package closes it, drop the workaround from the asset and from this list.

| Workaround | Asset | Why | Drop when |
|---|---|---|---|
| `LoginButton` gets `authRedirectOptions={{ redirectUrl: appRoot }}` and `postLogoutRedirectUri={appRoot}`, where `appRoot` is the app's root URL | `passflow-react-vite/assets/src/passflow.tsx` | The button's default is the current page's URL, which is a registered redirect URL of the app only on the root page | `@passflow/react` defaults both to a URL that provisioning registers |
| The module throws at load when `VITE_PASSFLOW_URL` or `VITE_PASSFLOW_APP_ID` is missing | `passflow-react-vite/assets/src/passflow.tsx` | `PassflowProvider` takes both as optional, and with no `url` it falls back to Passflow's cloud instead of failing | `PassflowProvider` refuses a missing `url` or `appId` itself |

Dropped: the `cors` options parameter of `passflowCors` in `passflow-node-api/assets/src/express-cors.ts`, `fastify-cors.ts` and `hono-cors.ts` was widened with `& { exposedHeaders?: … }`. `@passflow/node` 0.2.0's `exposeChallengeHeader` accepts `CorsOptions`, `FastifyCorsOptions` and Hono's options as they are, including `undefined` and read-only lists, so the assets now take the plain options type.
