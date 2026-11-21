---
name: passflow-react-vite
description: Adds Passflow sign-in to a React single-page app built with Vite, using @passflow/react in the browser, and protects the existing Node API it calls (Express, Fastify or Hono) with @passflow/node access-token checks and CORS for the app's origin. Use when asked to add Passflow sign-in or login to a React + Vite app, call an API with a Passflow token from a React SPA, or protect that SPA's backend with Passflow. Applies when the root package.json depends on both vite and react, and not on next or @tanstack/react-start (those have their own Passflow skills).
compatibility: Node.js 22.12 or newer; React 18 or 19 with Vite; an existing API on Express 4 or 5, Fastify 5 or Hono 4; npm, pnpm or Yarn 1.
license: MIT
---

# Passflow for React + Vite with a Node API

## What this does

Adds sign-in to a React + Vite single-page app and protects the Node API it calls. The SPA signs in through Passflow's hosted sign-in (PKCE) with `@passflow/react`, keeps the tokens in browser storage, and sends the access token to the API's origin only. The API checks that token on every protected route with `@passflow/node`, and its CORS allows the SPA's origin and exposes the `WWW-Authenticate` challenge.

The API must exist already, on Express, Fastify or Hono. This skill never creates a server and never picks a framework. The only packages it adds are `@passflow/react` and `@passflow/node`. It never adds another dependency, never edits `package.json` scripts and never creates or edits a `.env*` file (`.env.example` included). Whatever else the developer has to do is listed in the last step.

## Where this runs

The skill runs on one of two paths. Where a step differs, it is labelled.

- **On the developer's machine** (`npx passflow integrate`, or an agent the developer runs): you have a shell. You install with the package manager and run `verify.sh` yourself.
- **In a Passflow GitHub App run**: you have no shell. Your tools are Read, Write, Edit, Glob, Grep and Skill, plus `add_passflow_package({ name })`, `run_build()` and `run_typecheck()`. The last two return an exit code and a short tail of the output. After you finish, the runner runs the install, `run_build()`, `run_typecheck()` and then `verify.sh static`. It never runs `verify.sh run`, because the issuer and the client secret stay out of the sandbox: the draft PR's description tells the developer to run `bash <skill>/scripts/verify.sh run` on their machine before merging.

Every other step uses only reading and writing files, so it is the same on both paths.

## Preconditions

Check each one before you change a file. Read the `package.json` files and look for the files named below with Glob (Grep for a line inside one). If one fails, stop and tell the user why.

1. **Stack.** The root `package.json` lists both `vite` and `react` in `dependencies` or `devDependencies`, and lists neither `next` nor `@tanstack/react-start`. If it lists `next`, or `@tanstack/react-start` together with `@tanstack/react-router`, use that stack's Passflow skill instead. If that stack's version rule fails (Next.js older than 16; TanStack Start older than 1.169.5 or TanStack Router older than 1.170.46; or a range that cannot be compared), stop: the project is refused, not handled as a React + Vite app.
2. **A single-page app.** If the root `package.json` lists a framework that renders React on a server (`@tanstack/react-start` without `@tanstack/react-router`, `@react-router/dev`, `@remix-run/dev`, `vike`, `vite-plugin-ssr`, `waku`, `astro`, `rakkasjs`), stop: this skill is for a single-page app only.
3. **An existing API.** The root `package.json`, or the `package.json` of an `api/` or `server/` folder, lists `express`, `fastify` or `hono`. If none does, stop and tell the user: "add an API first". Do not create one.
4. **Node.js 22.12 or newer.** On the developer's machine, check `node --version`. In a Passflow GitHub App run, the runner checks for Node.js 22.12 or newer; you do not.
5. **Package manager.** Look at the project root, which takes only `package.json` and a Glob for the lockfiles:
   - a `packageManager` field in `package.json` that names `yarn@2` or newer, or `bun`, means Yarn Berry or Bun;
   - an `npm-shrinkwrap.json`: stop. npm would write the change into it, and this skill updates `package-lock.json`, `pnpm-lock.yaml` or `yarn.lock` only;
   - otherwise the lockfiles, in this order: `pnpm-lock.yaml` → pnpm, `package-lock.json` → npm, `yarn.lock` → Yarn 1 (classic), `.yarnrc.yml` → Yarn Berry, `bun.lock` or `bun.lockb` → Bun. If any file present points to Yarn Berry or Bun, that decides; otherwise the first one present does. A `yarn.lock` with a `__metadata:` line (Grep for it) is also Yarn Berry;
   - no lockfile at all: stop. The change needs a committed lockfile. Tell the user to install once with npm, pnpm or Yarn 1 (classic) and commit the lockfile;
   - a `packageManager` field naming npm, pnpm or Yarn 1 while the lockfile belongs to another manager (`pnpm@9` beside `package-lock.json`): stop. Tell the user to make them agree.

   **Yarn Berry or Bun: stop.** Tell the user that this skill supports npm, pnpm and Yarn 1 (classic) only. If the API has its own `package.json`, decide its package manager the same way; an API folder with no lockfile of its own uses the root's.
6. **Env file `.env.local`** at the project root. You never create or edit it (nor `.env`, nor `.env.example`), and you never print its values. The values come from the env file `npx passflow integrate` writes, or from the run page in the Passflow portal; `.env.example` is written by the CLI or, in a Passflow GitHub App run, by the service, which fills in the public values and leaves any secret empty (this stack has none). Leave it as it is. `.env.local` holds six names:

   | Name | Read by | Value |
   |---|---|---|
   | `VITE_PASSFLOW_URL` | SPA | The Passflow issuer URL. Public. |
   | `VITE_PASSFLOW_APP_ID` | SPA | The SPA app's client ID. Public. |
   | `VITE_API_URL` | SPA | The API's origin as the browser calls it. |
   | `PASSFLOW_ISSUER` | API | The same issuer URL as `VITE_PASSFLOW_URL`. |
   | `PASSFLOW_AUDIENCE` | API | The SPA app's client ID: the same value as `VITE_PASSFLOW_APP_ID`. |
   | `APP_BASE_URL` | API | The SPA's origin, for example `http://localhost:5173`, with no path, query or fragment: an SPA served under a sub-path is not supported, and `npx passflow integrate` refuses a `--base-url` with a path. It is the origin the API's CORS allows. |

   - `PASSFLOW_AUDIENCE` is the SPA app's client ID, because the access tokens the SPA gets carry `aud = [app ID]`. Never invent an audience string such as `api` or a URL: every token would then get 401.
   - `VITE_API_URL` is not provisioned. When it is absent, the CLI writes `http://localhost:8086`, or the origin given to its `--api-url` flag. The developer sets it to the real API origin in each environment.
   - Nothing secret goes in a `VITE_` variable. Vite puts every `VITE_` value into the browser bundle. The SPA needs no secret, and this stack has none.
   - If `.env.local` is missing or a value is empty, do not invent values: carry on with the code, and the last step tells the developer how to get them.
   - In a Passflow GitHub App run there is no `.env.local`: that is expected. Do not look for its values.
   - A committed `.env.local`: on the developer's machine, check with `git ls-files --error-unmatch .env.local`. If it succeeds, git tracks the file: stop. Tell the user to run `git rm --cached .env.local`, commit, and add `.env.local` to `.gitignore`. In a Passflow GitHub App run, the service refuses a repository with a committed `.env`, `.env.local` or `.env.*.local` before you start, so there is nothing to check.
7. **App settings in Passflow.** The SPA app is of type `spa` with PKCE. Its redirect URLs include the SPA's root URL (`APP_BASE_URL` followed by `/`), and its allowed origins include the SPA's origin. An app the Passflow CLI or service created has both. For an app made by hand, the last step tells the developer to add them; sign-in fails with "redirect_uri not registered" without the first and at the token call without the second.

## Steps

1. **Install the packages.** `@passflow/react` goes into the SPA's `package.json`. `@passflow/node` goes into the API's: the root one when the API lives in the same package, else the API folder's. Install nothing else.

   In a Passflow GitHub App run, call `add_passflow_package({ name: "@passflow/react" })` and `add_passflow_package({ name: "@passflow/node" })`. Each runs the detected package manager's add in the project root with lifecycle scripts off. The service pins the version, and the tool adds that exact version. Do not edit a `package.json` or a lockfile by hand. If one returns a non-zero exit code, stop and report its tail. When the API has its own `package.json` in a folder (`api/` or `server/`), stop before you copy anything, and tell the user that this layout needs the developer's machine (`npx passflow integrate`): the service refuses a change to a `package.json` or lockfile that is not at the repository root.

   On the developer's machine, use the project's package manager. Versions come from `PASSFLOW_REACT_VERSION` and `PASSFLOW_NODE_VERSION`; unset means the latest release. Run the lines as they are, the `@passflow/node` one in the API's folder when it has its own `package.json`:

   ```sh
   npm install "@passflow/react${PASSFLOW_REACT_VERSION:+@$PASSFLOW_REACT_VERSION}"
   pnpm add "@passflow/react${PASSFLOW_REACT_VERSION:+@$PASSFLOW_REACT_VERSION}"
   yarn add "@passflow/react${PASSFLOW_REACT_VERSION:+@$PASSFLOW_REACT_VERSION}"
   ```

   ```sh
   npm install "@passflow/node${PASSFLOW_NODE_VERSION:+@$PASSFLOW_NODE_VERSION}"
   pnpm add "@passflow/node${PASSFLOW_NODE_VERSION:+@$PASSFLOW_NODE_VERSION}"
   yarn add "@passflow/node${PASSFLOW_NODE_VERSION:+@$PASSFLOW_NODE_VERSION}"
   ```

2. **Find the API's code.** It is the code that creates the `express()`, `Fastify()` or `new Hono()` instance, in the package that lists the framework (precondition 3). Its folder is the API folder below: usually `server/` beside `src/` in the same package, or the separate `api/` or `server/` folder, or that folder's `src/`. Do not add a second server.

3. **Copy the SPA assets.** Do not change the Passflow calls in them.

   | Asset | Target | Adapt |
   |---|---|---|
   | `assets/src/passflow.tsx` | `src/passflow.tsx` | Nothing. It also imports `@passflow/react/dist/style.css`. |
   | `assets/src/use-api.ts` | `src/use-api.ts` | Nothing. |
   | `assets/src/require-sign-in.tsx` | `src/require-sign-in.tsx` | Nothing. |

   JavaScript project (no `tsconfig.json`): save them as `.jsx` and `.js`, and remove everything that is TypeScript only: type annotations, `import type ...` lines and `type` names inside an import list.

4. **Copy the API assets** into the API folder. Do not change the Passflow calls in them.

   | Asset | Target | When |
   |---|---|---|
   | `assets/server/passflow.ts` | `passflow.ts` | Always. |
   | `assets/server/express.ts` | `passflow-express.ts` | Express. |
   | `assets/server/fastify.ts` | `passflow-fastify.ts` | Fastify. |
   | `assets/server/hono.ts` | `passflow-hono.ts` | Hono. |
   | `assets/server/express-cors.ts` | `passflow-express-cors.ts` | Express with `cors` already a dependency and no CORS middleware yet. See step 6. |
   | `assets/server/fastify-cors.ts` | `passflow-fastify-cors.ts` | Fastify with `@fastify/cors` already a dependency and no CORS registered yet. See step 6. |
   | `assets/server/hono-cors.ts` | `passflow-hono-cors.ts` | Hono with no CORS middleware yet (`hono/cors` ships with `hono`). |
   | `assets/server/tsconfig.json` | `server/tsconfig.json` | Only when the API's TypeScript files sit in the SPA's package in `server/` and nothing type-checks them yet. |

   - Imports between these files use `./passflow.js`. Match the API's own relative imports: no extension, `.js`, or `.ts` when Node runs the `.ts` files as they are (`--experimental-strip-types`).
   - JavaScript or CommonJS API: as for the SPA, remove what is TypeScript only; for CommonJS turn each `import` into `require` and each `export` into a `module.exports` entry. The package ships CommonJS too.
   - **`/api/me`.** The framework assets add `GET /api/me`, which `verify.sh run` calls. Look at the API's routes first (Grep for `/api/me`). If it already has `/api/me`, do not add a second one: protect its handler in place (step 7), or change only the path string in the copied asset to an unused one such as `/api/passflow/me`, and pass that path to `verify.sh run --api`.

5. **Wire the SPA.** In `src/main.tsx`, wrap the root component in `PassflowRoot`:

   ```tsx
   import { PassflowRoot } from './passflow';

   createRoot(document.getElementById('root')!).render(
     <StrictMode>
       <PassflowRoot>
         <App />
       </PassflowRoot>
     </StrictMode>,
   );
   ```

   Then use the three pieces where the app needs them:

   | Place | Use |
   |---|---|
   | The header or nav: sign-in and sign-out | `<AccountButton />` from `./passflow` |
   | A page or part only a signed-in user sees | `<RequireSignIn>…</RequireSignIn>` from `./require-sign-in` |
   | A component that calls the API | `const api = useApi();` then `await api(apiUrl('/api/me'))`, both from `./use-api` |

   `RequireSignIn` renders nothing until the first session check ends, then its children when a user is signed in, else the sign-in button. `useApi()` adds the token for `VITE_API_URL`'s origin only: it returns `passflow.withAuth(fetch, { origins: [apiOrigin] })`, where `passflow` is `usePassflow()`. Never add an `Authorization` header by hand, and never read the token yourself.

   Sign-in and sign-out return to the app's root URL, because that is the redirect URL the app has registered. A user who signs in from a deeper page lands on the root.

6. **Wire the API.** CORS first, then the routes, on the existing instance (`app`).

   **CORS.** Pick the first case that fits:
   - The API already mounts a CORS middleware: keep it where it is, before the routes. Add `appOrigin` (from `./passflow.js`) to the origins it allows, or set its origin to it, and wrap its options in `exposeChallengeHeader` from `@passflow/node/express`, `/fastify` or `/hono`: `cors(exposeChallengeHeader({ origin: appOrigin }))`. Keep its `credentials` setting; never turn `credentials` on, since the API takes a bearer token and needs none.
   - The CORS package is a dependency (Express: `cors`; Fastify: `@fastify/cors`; Hono: always) but nothing is mounted: mount the CORS asset before every route:
     ```ts
     app.use(passflowCors);          // Express, from ./passflow-express-cors.js
     await passflowCors(app);        // Fastify, from ./passflow-fastify-cors.js
     app.use(passflowCors);          // Hono, from ./passflow-hono-cors.js
     ```
   - Express without `cors`, or Fastify without `@fastify/cors`: change nothing for CORS. The last step tells the developer what to add.

   **Routes.** Mount the protected route after CORS:
   ```ts
   app.use(passflowRoutes);              // Express, from ./passflow-express.js
   await passflowPlugin(app);            // Fastify, from ./passflow-fastify.js
   app.route('/', passflowRoutes);       // Hono, from ./passflow-hono.js; give the app the PassflowEnv type
   ```

   A CommonJS Fastify API has no top-level `await`: put both `await` lines in the async function that starts the server, before `app.listen`, or add one if there is none:
   ```js
   async function start() {
     await passflowCors(app);
     await passflowPlugin(app);
     await app.listen({ port: Number(process.env.PORT ?? 3000) });
   }
   start();
   ```

7. **Protect every API route that returns or changes private data.** Hiding a page in the SPA protects nothing: anyone can call the API without the SPA. So the API checks the token on each protected route, and a public route gets nothing.

   | Place | Call | Signed out or invalid token |
   |---|---|---|
   | Express route | `app.get('/path', passflow.authenticate, handler)` | 401, `WWW-Authenticate: Bearer` |
   | Fastify route | `{ preHandler: app.passflow.authenticate }` | same |
   | Hono route | `passflow.authenticate` | same |

   `passflow` is exported by `passflow-express.ts` and `passflow-hono.ts`. Read the claims in a handler with `getAuth(req)` (Express), `getAuth(request)` (Fastify) or `getAuth(c)` (Hono), each imported from the same adapter path. A missing role is a plain 403 with no `WWW-Authenticate`.

8. **Tell the developer.** End with a short message that lists what they still have to do, each as a command or a line to add. Include only the items that apply:
   - **Env values.** If `.env.local` is missing or a value is empty: run `npx passflow integrate`, or copy `.env.example` to `.env.local` and fill in the names from the table in precondition 6 (from the Passflow portal). Set `VITE_API_URL` to the API's origin. Names only in your message, never values.
   - **Loading `.env.local` in the API.** If the API does not read it already (dotenv, `--env-file`, its framework): start it with `--env-file-if-exists=.env.local` (`../.env.local` from a separate API folder), for example `node --env-file-if-exists=.env.local --experimental-strip-types server/index.ts` for TypeScript run as it is. Vite reads the `VITE_` names from the same file for the SPA.
   - **CORS package.** If it is missing: `npm install cors` (plus `npm install -D @types/cors` in a TypeScript API) for Express, or `npm install @fastify/cors` for Fastify, in the API's package and written for its package manager. Then copy the CORS asset and add the one line from step 6, before the routes.
   - **App settings.** For an app made by hand: add `<APP_BASE_URL's origin>/` to its redirect URLs and the origin to its allowed origins (precondition 7).
   - **Run and check.** The SPA with `npm run dev`, the API with its own start command, side by side. Then `bash <skill>/scripts/verify.sh run` with the API stopped (it starts its own copy), plus `--api <path>` when the route is not `/api/me`.
   - In a Passflow GitHub App run, say also which of `run_typecheck()` and `run_build()` passed, and name the route path in your final summary when it is not `/api/me`. The summary goes into the draft PR's description, which tells the developer to run `verify.sh run --api <path>` before merging.

## Guardrails

Read `references/guardrails.md` before you edit auth code. In short:

- Nothing secret in a `VITE_` variable: Vite ships every one to the browser.
- The API checks the token on every protected route. Hiding a page in the SPA protects nothing.
- `PASSFLOW_AUDIENCE` is the SPA app's client ID, the same value as `VITE_PASSFLOW_APP_ID`. Never invent one.
- Tokens go to the API's origin only, through `useApi()`. Never build an `Authorization` header by hand, and never send the token to another origin.
- Verify tokens on the API with `createVerifier`; never decode one by hand, in the SPA or the API.
- CORS goes first on the API, allows the SPA's origin only, and exposes `WWW-Authenticate` through `exposeChallengeHeader`. Never turn on `credentials`.
- No server code in `src/`: the SPA never imports from the API's folder or from `@passflow/node`.
- Copy Passflow calls from `assets/`, never from memory.
- Never print or log a token, an `Authorization` header or an env value.
- Add no dependency other than `@passflow/react` and `@passflow/node`, edit no `package.json` script, and create or edit no `.env*` file.

## Verification

On the developer's machine, run these from the project root; `<skill>` is this skill's directory:

```sh
bash <skill>/scripts/verify.sh static
bash <skill>/scripts/verify.sh run
```

In a Passflow GitHub App run, call `run_typecheck()`, then `run_build()`. If one returns a non-zero exit code, read its tail and fix the copied or wired code, then call it again. The fix never touches a `package.json` script, a dependency or a config file. `run_typecheck()` runs the same checks as `verify.sh static`: for the SPA the `typecheck` script, else `tsc -b` for a `tsconfig.json` with `references`, else `tsc -p tsconfig.json`; for the API also `server/tsconfig.json` when there is one. The runner then runs `verify.sh static` itself, and its result is part of the run. It never runs `verify.sh run`; the draft PR's description tells the developer to run it on their machine before merging, with `--api <path>` when the route moved.

What `verify.sh` checks. Add `--api-dir api` when the API has its own `package.json` somewhere other than `api/` or `server/` (those are found by themselves when their `package.json` lists `express`, `fastify` or `hono`). Both modes refuse a project with no such API: add an API first.

- `static` needs no env values. It installs with lifecycle scripts off (the SPA, and the API folder when it is separate), type-checks the SPA (the `typecheck` script; else `tsc -b --noEmit` for a `tsconfig.json` with project references, as Vite's has, `tsc -p tsconfig.json --noEmit` otherwise) and the API (`server/tsconfig.json`, or the API folder's own check), and builds the SPA. A `VITE_` name that neither the environment nor `.env`, `.env.local`, `.env.production` or `.env.production.local` sets is built with a placeholder, so the bundle holds the whole app; the output says so, and that `dist/` is removed after the scans, so build again before you deploy. Then it scans `dist/` for the names and values of secrets (from `.env.local` and from the environment) and for the API's env names (which appear only when server code reached the bundle), checks that nothing in `src/` imports `@passflow/node`, a server framework or the API's code (relative imports are resolved to real paths, so a browser client in `src/api/` is fine; an alias such as `@/server/` is listed as a `SKIP` to check by hand), checks the env file has no secret-looking `VITE_` name, and scans the source for the guardrail breaks above.
- `run` needs `.env.local` with `PASSFLOW_ISSUER`, `PASSFLOW_AUDIENCE` and `APP_BASE_URL`. It refuses when something already listens on the port (8086, or `--port`): stop the API you run yourself first. It starts the API with those three names and `PORT` set: the API's `api` script, a separate API folder's `start` or `dev` script, else `server/index.ts` with Node, or the file given with `--entry`; a separate API folder with `start` and `build` scripts is built first, and a build error fails the run. It checks that the process it started is the one answering on the port (with `lsof`; skipped without it). It calls `/api/me` (`--api`) with no token and expects 401 `Bearer` with `Cache-Control: no-store`, then with an invalid token and expects 401 `invalid_token`. With `Origin` set to `APP_BASE_URL`'s origin it checks that the 401 allows that origin and exposes `WWW-Authenticate`, and that a preflight allows the `Authorization` header; another origin gets the 401 without being allowed. The CORS checks are skipped, with the reason, when the API lacks its CORS package (`cors`, `@fastify/cors`) or with `--no-cors` (the SPA calls the API on its own origin, through a Vite proxy for example). A transport failure (no answer) is a `FAIL`. It fails if the API it started exits, and it stops that API at the end. It does not sign in: that takes a browser.

Each check prints `PASS`, `FAIL` or `SKIP` (a check that does not apply, such as a bundle scan after a failed build), then `RESULT pass` or `RESULT fail`. Exit 0 is a pass, 1 a failed check, 2 a refusal (unsupported package manager or framework, no API, missing tool or env file, busy port).

## Troubleshooting

- **The page is blank and the console says `VITE_PASSFLOW_URL and VITE_PASSFLOW_APP_ID must be set in .env.local`** (or `VITE_API_URL`). The value was missing when Vite started or built. Fill in `.env.local`, then restart `npm run dev` or build again.
- **Passflow shows "redirect_uri not registered for this client".** The app's redirect URLs lack the SPA's root URL, or the SPA runs on another origin or port than `APP_BASE_URL`. Add `<origin>/` to the app's redirect URLs, or open the SPA on the registered origin.
- **Every API call gets 401 `invalid_token`.** `PASSFLOW_AUDIENCE` is not the SPA app's client ID, or `PASSFLOW_ISSUER` differs from the token's `iss` (a trailing slash counts). Both must equal `VITE_PASSFLOW_APP_ID` and `VITE_PASSFLOW_URL`.
- **The API call has no `Authorization` header.** The request did not go through `useApi()`, its URL is not on `VITE_API_URL`'s origin, or no user is signed in.
- **The browser reports a CORS error.** `APP_BASE_URL` does not match the origin the SPA runs on, CORS is mounted after the routes, or the API has no CORS at all. See step 6.
- **`TypeError: [passflow] issuer must be a non-empty string` when the API starts.** The API did not load `.env.local`. See step 8.
- **`verify.sh run` refuses: something already listens on the port.** The API (or another server) is running there. Stop it, or pass a free `--port`.
- **`npx passflow integrate` did not update this skill.** The CLI replaces only a skill copy it installed itself and that is unchanged, as recorded in `.passflow-skill.json`. A skill folder you changed is not overwritten: delete it to get the new version.
