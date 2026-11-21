---
name: passflow-node-api
description: Protects a Node.js HTTP API with Passflow access tokens using @passflow/node, on Express, Fastify or Hono. Use when asked to add Passflow auth to a Node backend, verify Passflow bearer tokens, or protect API routes with Passflow. Applies when the root package.json depends on express, fastify or hono, and not on next, @tanstack/react-start, or vite together with react (those have their own Passflow skills).
compatibility: Node.js 22.12 or newer; Express 4 or 5, Fastify 5, Hono 4; npm, pnpm or Yarn 1.
license: MIT
---

# Passflow for a Node API

## What this does

Adds Passflow access-token checks to an existing Node API. One verifier is built at startup from two env vars. Protected routes answer 401 with a `WWW-Authenticate` challenge when the token is missing or invalid. Routes get the verified claims. No app is created and no sign-in page is added: the API accepts tokens that a Passflow app issued.

The only package this skill adds is `@passflow/node`. It never adds another dependency, never edits `package.json` scripts and never creates or edits a `.env*` file (`.env.example` included). Whatever else the developer has to do is listed in the last step.

## Where this runs

The skill runs on one of two paths. Where a step differs, it is labelled.

- **On the developer's machine** (`npx passflow integrate`, or an agent the developer runs): you have a shell. You install with the package manager and run `verify.sh` yourself.
- **In a Passflow GitHub App run**: you have no shell. Your tools are Read, Write, Edit, Glob, Grep and Skill, plus `add_passflow_package({ name })`, `run_build()` and `run_typecheck()`. The last two return an exit code and a short tail of the output. After you finish, the runner runs the install, `run_build()`, `run_typecheck()` and then `verify.sh static`. It never runs `verify.sh run`, because the issuer and the client secret stay out of the sandbox: the draft PR's description tells the developer to run `bash <skill>/scripts/verify.sh run` on their machine before merging.

Every other step uses only reading and writing files, so it is the same on both paths.

## Preconditions

Check each one before you change a file. Read `package.json` and look for the files named below with Glob (Grep for a line inside one). If one fails, stop and tell the user why.

1. **Stack.** The root `package.json` lists `express`, `fastify` or `hono` in `dependencies` or `devDependencies`. If it lists `@tanstack/react-start` with `@tanstack/react-router`, `next`, or both `vite` and `react`, use that stack's Passflow skill instead. Stacks are tried in this order, by package names, and the first match wins: TanStack Start, Next.js, React + Vite, Node API. If the first match fails its version rule, the project is refused; it never falls through to a later stack.
2. **Node.js 22.12 or newer.** On the developer's machine, check `node --version`. In a Passflow GitHub App run, the runner checks for Node.js 22.12 or newer; you do not.
3. **Package manager.** Look at the project root, which takes only `package.json` and a Glob for the lockfiles:
   - a `packageManager` field in `package.json` that names `yarn@2` or newer, or `bun`, means Yarn Berry or Bun;
   - an `npm-shrinkwrap.json`: stop. npm would write the change into it, and this skill updates `package-lock.json`, `pnpm-lock.yaml` or `yarn.lock` only;
   - otherwise the lockfiles, in this order: `pnpm-lock.yaml` → pnpm, `package-lock.json` → npm, `yarn.lock` → Yarn 1 (classic), `.yarnrc.yml` → Yarn Berry, `bun.lock` or `bun.lockb` → Bun. If any file present points to Yarn Berry or Bun, that decides; otherwise the first one present does. A `yarn.lock` with a `__metadata:` line (Grep for it) is also Yarn Berry;
   - no lockfile at all: stop. The change needs a committed lockfile. Tell the user to install once with npm, pnpm or Yarn 1 (classic) and commit the lockfile;
   - a `packageManager` field naming npm, pnpm or Yarn 1 while the lockfile belongs to another manager (`pnpm@9` beside `package-lock.json`): stop. Tell the user to make them agree.

   **Yarn Berry or Bun: stop.** Tell the user that this skill supports npm, pnpm and Yarn 1 only.
4. **Env file `.env`** at the project root, with `PASSFLOW_ISSUER` and `PASSFLOW_AUDIENCE`. You never create or edit it, and you never print its values.
   - `npx passflow integrate` writes it. In a Passflow GitHub App run, the service writes `.env.example` with the public values filled in (`PASSFLOW_ISSUER`, `PASSFLOW_AUDIENCE`) and any secret empty; this stack has no secret. Leave that file as it is. If `.env` is missing or a value is empty, do not invent values: carry on with the code, and the last step tells the developer how to get them (the issuer URL and the client ID of the Passflow app whose tokens this API accepts).
   - In a Passflow GitHub App run there is no `.env`: that is expected. Do not look for its values.
   - A committed `.env`: on the developer's machine, check with `git ls-files --error-unmatch .env`. If it succeeds, git tracks the file: stop. Tell the user to run `git rm --cached .env`, commit, and add `.env` to `.gitignore`. In a Passflow GitHub App run, the service refuses a repository with a committed `.env`, `.env.local` or `.env.*.local` before you start, so there is nothing to check.

## Steps

1. **Install the package.** Install nothing else.

   On the developer's machine, use the project's package manager. The version comes from `PASSFLOW_NODE_VERSION`; unset means the latest release. Run the line as it is:

   ```sh
   npm install "@passflow/node${PASSFLOW_NODE_VERSION:+@$PASSFLOW_NODE_VERSION}"
   pnpm add "@passflow/node${PASSFLOW_NODE_VERSION:+@$PASSFLOW_NODE_VERSION}"
   yarn add "@passflow/node${PASSFLOW_NODE_VERSION:+@$PASSFLOW_NODE_VERSION}"
   ```

   In a Passflow GitHub App run, call `add_passflow_package({ name: "@passflow/node" })`. It runs the detected package manager's add with lifecycle scripts off. The service pins the version, and the tool adds that exact version. Do not edit `package.json` or the lockfile by hand. If it returns a non-zero exit code, stop and report its tail.

2. **Copy the assets.** Copy `assets/src/passflow.ts` and the file for the framework the project uses. Do not change the Passflow calls in them.

   | Asset | Target | When |
   |---|---|---|
   | `assets/src/passflow.ts` | `src/passflow.ts` | Always. |
   | `assets/src/express.ts` | `src/passflow-express.ts` | Express. |
   | `assets/src/fastify.ts` | `src/passflow-fastify.ts` | Fastify. |
   | `assets/src/hono.ts` | `src/passflow-hono.ts` | Hono. |
   | `assets/src/express-cors.ts` | `src/passflow-express-cors.ts` | Express, called from a browser on another origin, and `cors` is already a dependency. See step 3. |
   | `assets/src/fastify-cors.ts` | `src/passflow-fastify-cors.ts` | Fastify, called from a browser on another origin, and `@fastify/cors` is already a dependency. See step 3. |
   | `assets/src/hono-cors.ts` | `src/passflow-hono-cors.ts` | Hono, called from a browser on another origin (`hono/cors` ships with `hono`). |
   | `assets/src/fetch-handler.ts` | `src/passflow-fetch.ts` | A handler in the same app that receives a web `Request` and returns a `Response` (a Hono `c.req.raw` handler, for example). |

   - The project has no `src/` folder (the entry is `server.js` or `index.ts` at the root, for example): put every target in `lib/` instead, as `lib/passflow.ts`, `lib/passflow-express.ts` and so on, and import them from the entry as `./lib/passflow-express.js`. Write nowhere else.
   - **`/api/me`.** The framework assets add `GET /api/me`, which `verify.sh run` calls. Look at the app's routes first (Grep for `/api/me`). If the app already has `/api/me`, do not add a second one: protect its handler in place (step 4), or change only the path string in the copied asset to an unused one such as `/api/passflow/me`, and pass that path to `verify.sh run --api`.
   - `assets/examples/` holds the patterns for the app's own routes (step 4) and for debugging a rejection. They import from the target names above. Copy single lines from them; do not copy the files as a whole.
   - Imports use `./passflow.js`. If the project's own relative imports have no extension, drop `.js` to match.
   - JavaScript project (no `tsconfig.json`): save the files as `.js` and remove everything that is TypeScript only: type annotations (`: Promise<void>`, `: RequestHandler`), type arguments (`new Hono<PassflowEnv>()` becomes `new Hono()`), `import type ...` lines, `type` names inside an import list, and `export type ...` declarations.
   - CommonJS project (no `"type": "module"` and the code uses `require`): after that, turn each `import { a } from 'x'` into `const { a } = require('x')`, a default import `import cors from 'cors'` into `const cors = require('cors')`, and each `export` into a `module.exports` entry. The package ships CommonJS too. The Fastify assets use `await` inside async functions only, so they need no other change; a CommonJS file has no top-level `await`, so wire them as step 3 shows for CommonJS.

3. **Wire it into the app.** Mount CORS first (when there is CORS), then the routes.

   Express (`app` is the existing `express()` instance):
   ```ts
   import { passflowRoutes } from './passflow-express.js';

   app.use(passflowRoutes);
   ```

   Fastify (`app` is the existing `Fastify()` instance):
   ```ts
   import { passflowPlugin } from './passflow-fastify.js';

   await passflowPlugin(app);
   ```

   In CommonJS, where top-level `await` is a syntax error, put the calls in the async function that starts the server, before `app.listen`:
   ```js
   const { passflowPlugin } = require('./passflow-fastify.js');

   async function start() {
     await passflowPlugin(app);
     await app.listen({ port: Number(process.env.PORT ?? 3000) });
   }
   start();
   ```
   If the app already has such a function, add the `await` line to it instead of adding a second one. The same goes for `await passflowCors(app, ...)` below.

   Hono (`app` is the existing `new Hono()`; give it the `PassflowEnv` type so `getAuth(c)` is typed):
   ```ts
   import { type PassflowEnv, passflowRoutes } from './passflow-hono.js';

   const app = new Hono<PassflowEnv>();
   app.route('/', passflowRoutes);
   ```

   **CORS.** Only when a browser page on another origin calls the API. Pick the first case that fits:
   - The app already mounts a CORS middleware (`cors(...)`, `app.register(cors, ...)`, `cors(...)` from `hono/cors`): keep it where it is, before the routes, and wrap its options in `exposeChallengeHeader` from `@passflow/node/express`, `/fastify` or `/hono`: `cors(exposeChallengeHeader({ origin: allowedOrigins }))`. Do not add a second one.
   - The package is a dependency but not mounted yet: copy the CORS asset and mount it before every route with the origins the API already allows (from its config or env), never a new hard-coded one:
     ```ts
     app.use(passflowCors({ origin: allowedOrigins }));        // Express, from ./passflow-express-cors.js
     await passflowCors(app, { origin: allowedOrigins });      // Fastify, from ./passflow-fastify-cors.js
     app.use(passflowCors({ origin: allowedOrigins }));        // Hono, from ./passflow-hono-cors.js
     ```
   - Express without `cors`, or Fastify without `@fastify/cors`: change nothing for CORS. The last step tells the developer what to add.

   Keep the app's existing `credentials` setting. Never turn `credentials` on yourself: a bearer token needs none, and credentials together with an origin that reflects or allows every site lets any site read the API's answers.

   Fetch-style handler: return `handleMe(request)` for `GET /api/me`, and copy its first four lines into each protected handler. This is a manual path inside an app that already uses Express, Fastify or Hono: a server with none of the three is not detected, and `verify.sh` refuses it.

4. **Protect the existing routes.** Every route that returns or changes private data gets one of these. Public routes get none. The exact lines are in `assets/examples/express-routes.ts`, `fastify-routes.ts` and `hono-routes.ts`.

   | Place | Call | Signed out or invalid token |
   |---|---|---|
   | Express route | `app.get('/path', passflow.authenticate, handler)` | 401, `WWW-Authenticate: Bearer` |
   | Express, needs a second factor | `passflow.requireACR(AAL2)`, with `import { AAL2 } from '@passflow/node'` | 401 with `acr_values="2"` |
   | Express, needs a recent sign-in | `passflow.requireFresh(300)` | 401 with `max_age=300` |
   | Fastify route | `{ preHandler: app.passflow.authenticate }` (or `app.passflow.requireACR(AAL2)`, `app.passflow.requireFresh(300)`) | same |
   | Hono route | `passflow.authenticate` (or `passflow.requireACR(AAL2)`, `passflow.requireFresh(300)`) | same |
   | Fetch-style handler | `const result = await authenticateRequest(verifier, request); if ('response' in result) return result.response;` | same |

   `passflow` is exported by `passflow-express.ts` and `passflow-hono.ts`. Read the claims in a handler with `getAuth(req)` (Express), `getAuth(request)` (Fastify) or `getAuth(c)` (Hono), each imported from the same adapter path. A missing role is a plain 403 with no `WWW-Authenticate`. In Fastify, `passflowPlugin` is registered once per instance; a scope without it uses `createFastifyHooks(verifier)` from `@passflow/node/fastify`, as `assets/examples/fastify-routes.ts` shows.

5. **Tell the developer.** End with a short message that lists what they still have to do, each as a command or a line to add. Include only the items that apply:
   - **Env values.** If `.env` is missing or a value is empty: run `npx passflow integrate`, or create `.env` with `PASSFLOW_ISSUER=` and `PASSFLOW_AUDIENCE=` from the Passflow portal (the issuer URL, and the client ID of the app whose tokens the API accepts). Names only in your message, never values.
   - **Loading `.env`.** If the app does not load it already (dotenv, `--env-file`, its framework): start Node with `--env-file=.env`, for example `node --env-file=.env dist/server.js` in the start script.
   - **CORS package.** If a browser on another origin calls the API and the CORS package is missing: `npm install cors` (plus `npm install -D @types/cors` in a TypeScript project) for Express, or `npm install @fastify/cors` for Fastify, written for the project's package manager. Then copy the CORS asset and add the one line from step 3, before the routes.
   - **Check.** `bash <skill>/scripts/verify.sh run --port <the API's port>`, with `--origin <a browser origin it allows>` when there is CORS, and `--api <path>` when the route is not `/api/me`.
   - In a Passflow GitHub App run, say also which of `run_typecheck()` and `run_build()` passed, and name the route path in your final summary when it is not `/api/me`. The summary goes into the draft PR's description, which tells the developer to run `verify.sh run --api <path>` before merging.

## Guardrails

Read `references/guardrails.md` before you edit auth code. In short:

- Verify with `createVerifier` through the adapter or `authenticateRequest`. Never decode a token by hand (`jwt-decode`, `jsonwebtoken`, `atob`, base64 `Buffer`).
- Check the token on every protected route, on the server.
- Return the library's 401 or 503 unchanged; no `next(err)`, no rewritten body.
- When a browser calls the API, CORS goes first and exposes `WWW-Authenticate` through `exposeChallengeHeader`. Never turn on `credentials`.
- Issuer and audience come from `PASSFLOW_ISSUER` and `PASSFLOW_AUDIENCE`, never hard-coded.
- Copy Passflow calls from `assets/`, never from memory.
- Never print or log a token, an `Authorization` header or an env value.
- Add no dependency other than `@passflow/node`, edit no `package.json` script, and create or edit no `.env*` file.

## Verification

On the developer's machine, run these from the project root; `<skill>` is this skill's directory:

```sh
bash <skill>/scripts/verify.sh static
bash <skill>/scripts/verify.sh run --port <the API's port> [--origin <a browser origin it allows>]
```

In a Passflow GitHub App run, call `run_typecheck()`, then `run_build()` when `package.json` has a `build` script. If one returns a non-zero exit code, read its tail and fix the copied or wired code, then call it again. The fix never touches a `package.json` script, a dependency or a config file. `run_typecheck()` runs the same check as `verify.sh static`: the `typecheck` script, else `tsc -b` for a `tsconfig.json` with `references`, else `tsc -p tsconfig.json`. The runner then runs `verify.sh static` itself, and its result is part of the run. It never runs `verify.sh run`; the draft PR's description tells the developer to run it on their machine before merging, with `--api <path>` when the route moved.

What `verify.sh` checks:

- `static` needs no env values. It installs with lifecycle scripts off, type-checks (the `typecheck` script; else `tsc -b --noEmit` for a `tsconfig.json` with project references, `tsc -p tsconfig.json --noEmit` otherwise), builds if there is a `build` script, and scans the source for the guardrail breaks above. It proves the copied calls compile against the installed package.
- `run` needs `.env` with both values and a `start` (or `dev`) script that reads `PORT`. It refuses when something already listens on the port, so stop a running copy of the API first or pass another `--port`. With a `start` script and a `build` script it builds first and fails on a build error, so the run tests the current code. It starts the API, checks that the process it started is the one answering on the port (with `lsof`; skipped without it), calls `/api/me` (or the path given with `--api`, step 2) with no token and expects 401 `Bearer` with `Cache-Control: no-store`, then with an invalid token and expects 401 `invalid_token`. With `--origin`, it checks that the 401 allows that origin and exposes `WWW-Authenticate`. It fails if the API it started exits, and it stops that API at the end.

Each check prints `PASS`, `FAIL` or `SKIP` (a check that does not apply, such as CORS without `--origin` or a build without a `build` script), then `RESULT pass` or `RESULT fail`. Exit 0 is a pass, 1 a failed check, 2 a refusal (unsupported package manager, missing tool or env file, busy port).

## Troubleshooting

- **`TypeError: [passflow] issuer must be a non-empty string` at startup.** `.env` was not loaded, or `PASSFLOW_ISSUER` is empty. See step 5.
- **Type error on `createVerifier`: `string | undefined` is not assignable to `string`.** The installed `@passflow/node` is older than the one the assets need. Run the install line again.
- **Every token gets 401 `invalid_token`.** `PASSFLOW_ISSUER` differs from the token's `iss` (a trailing slash counts), or `PASSFLOW_AUDIENCE` is not the client ID of the app that issued the token. To see why, use `explainRejection` from `assets/examples/explain-rejection.ts` for a moment: it logs the error's `code` and `reason` only. Remove it afterwards.
- **Every request gets 503.** The API cannot load the issuer's key set. From the API's machine, `curl -i "$PASSFLOW_ISSUER/.well-known/jwks.json"` must answer 200.
- **The browser sees a bare 401 and the step-up dialog never opens.** CORS does not expose `WWW-Authenticate`, or it is mounted after the routes. See step 3.
- **Fastify throws `FST_ERR_DEC_ALREADY_PRESENT`.** `passflowPlugin` was registered twice on one instance. Register it once; use `createFastifyHooks(verifier)` elsewhere, as in `assets/examples/fastify-routes.ts`.
- **`verify.sh run` refuses: something already listens on the port.** A copy of the API (or another server) is running there. Stop it, or pass a free `--port`.
- **`npx passflow integrate` did not update this skill.** The CLI replaces only a skill copy it installed itself and that is unchanged, as recorded in `.passflow-skill.json`. A skill folder you changed is not overwritten: delete it to get the new version.
