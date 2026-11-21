# Passflow skills

Agent skills that add Passflow sign-in to an app. A coding agent reads a skill, copies its files into the app, wires them in and runs the skill's checks. The same skills work as a Claude Code plugin and through `npx skills`.

**Not released yet:** `@passflow/nextjs`, `@passflow/tanstack-react-start` and `@passflow/node` 0.2.0 are not on npm yet. Until they are, the Next.js and TanStack Start skills cannot install their package, and the Node API and React + Vite skills type-check only against `@passflow/node` 0.2.0. [SDK-SURFACE.md](SDK-SURFACE.md) lists every package call the skills use and its status.

## The skills

| Skill | For | Package |
|---|---|---|
| `passflow-node-api` | A Node API on Express, Fastify or Hono that accepts Passflow access tokens | `@passflow/node` |
| `passflow-nextjs` | A Next.js 16 App Router app with server-side sign-in | `@passflow/nextjs` |
| `passflow-react-vite` | A React + Vite single-page app that calls an existing Node API on Express, Fastify or Hono | `@passflow/react`, `@passflow/node` |
| `passflow-tanstack-start` | A TanStack Start app with server-side sign-in | `@passflow/tanstack-react-start` |

Each skill has:

- `SKILL.md`: what it does, preconditions, steps, guardrails, verification and troubleshooting.
- `assets/`: the exact files to copy into the app.
- `references/guardrails.md`: the rules for auth code, and why.
- `scripts/verify.sh`: `static` mode (install, type-check, build, scans) and `run` mode (starts the app on a free port and checks its answers; it refuses a port something already listens on).

`verify.sh` is a build and wiring check, not a security gate. Its scans catch common mistakes in the files it reads; any lockfile check in it is advisory, and it never trusts a lockfile's own dependency edges.

A skill adds only `@passflow/*` packages. It never adds another dependency, never edits `package.json` scripts and never creates or edits a `.env*` file: the Passflow CLI writes `.env.local` and `.env.example`, and the Passflow service writes `.env.example`. Anything else the app needs (a CORS package, a start flag that loads the env file, the env values) is listed in the agent's final message for the developer. The React + Vite skill needs an existing API on Express, Fastify or Hono; without one it stops and asks for one.

A skill runs on two paths. On the developer's machine (`npx passflow integrate`, or an agent the developer runs) the agent has a shell: it installs with the package manager and runs `verify.sh` itself. In a Passflow GitHub App run the agent has no shell, only file tools plus `add_passflow_package`, `run_build` and `run_typecheck`, and the runner starts `verify.sh`.

`skills/index.json` holds the detection rules: which stack an app is, its env file and keys, its package manager, and the paths a change may touch. The Passflow CLI and the Passflow GitHub App read it, and they refuse a field they do not know. Each skill carries a byte-identical copy in `scripts/index.json`, which its `verify.sh` reads.

## Install

As a Claude Code plugin:

```text
/plugin marketplace add usepassflow/skills
/plugin install passflow@passflow
```

For other agents, with the `skills` CLI:

```sh
npx skills add usepassflow/skills
```

Then ask your agent to add Passflow sign-in. It picks the skill for your stack.

`npx passflow integrate` records the skill copies it installs in `.passflow-skill.json` and replaces a copy only while it is unchanged. A skill folder you changed is not overwritten: delete it to get the new version.

## Package versions

The skills install each package with a line like this one:

```sh
npm install "@passflow/node${PASSFLOW_NODE_VERSION:+@$PASSFLOW_NODE_VERSION}"
```

With the variable unset, it installs the latest release. Set it to install an exact version, for example `PASSFLOW_NODE_VERSION=0.2.0`.

| Package | Variable |
|---|---|
| `@passflow/node` | `PASSFLOW_NODE_VERSION` |
| `@passflow/nextjs` | `PASSFLOW_NEXTJS_VERSION` |
| `@passflow/tanstack-react-start` | `PASSFLOW_TANSTACK_REACT_START_VERSION` |
| `@passflow/react` | `PASSFLOW_REACT_VERSION` |

The skills support npm, pnpm and Yarn 1. They stop on Yarn Berry and Bun.

## index.json

`skills/index.json` is schema 1. Readers refuse a field they do not know, so it has exactly these:

- Top level: `schema` (1), `package_managers`, `stacks`.
- `package_managers`: `supported` (npm, pnpm, yarn-classic), `refused` (yarn-berry, bun), and `detect`, a list of `{file, manager}`.
- Each stack: `id`, `skill`, `detect`, `app_type`, `default_base_url`, `env_file`, `env_keys`, `secret_env_keys`, `not_provisioned_env_keys`, `packages` (`{name, version_env, env_keys}`), `allowed_paths`, `denied_paths`.
- `detect` is `{all: [{package, range?}], any: [{package, range?}]}`. A range is written `>=16` or `>=1.169.5`.
- `allowed_paths` and `denied_paths` are globs matched against the path from the repository root: `src/**` covers everything under the root's `src/` and nothing under `packages/web/src/`. `*` matches within one folder, `**` across folders, and `**/` at the start matches at any depth (`**/.env*`). A plain name such as `proxy.ts` is that file at the root only.

**Choosing a stack.** Read `dependencies` and `devDependencies` of the root `package.json`. Try the stacks in array order. A stack is chosen by package names alone: every `all` package is present and, when there is an `any` list, at least one `any` package is. The first stack chosen wins. Its range rules must then hold, or the project is refused: "Next.js 16 or newer", "TanStack Start 1.169.5 or newer with TanStack Router 1.170.46 or newer". TanStack Start lists both `@tanstack/react-start` and `@tanstack/react-router` under `all`, so a project without the router is not a TanStack Start app here (the React + Vite skill refuses it too). It never falls through to a later stack. A range that cannot be compared counts as failing: a tag such as `latest`, `workspace:`, a URL, `a || b`, `a - b`, and an empty version (`"next": ""`), which still chooses the stack. A prerelease never meets a rule, as in npm: `16.1.0-rc.1` fails "16 or newer".

**Choosing a package manager.**

- A `packageManager` field naming `yarn@2` or newer, or `bun`, is refused.
- A root `npm-shrinkwrap.json` is refused: npm would write the change into it, and a change may touch `package-lock.json`, `pnpm-lock.yaml` or `yarn.lock` only.
- Otherwise look for each `detect` file in the project root. If any file found belongs to a refused manager, refuse. Otherwise the first file found decides.
- A `yarn.lock` with a `__metadata:` line is a Yarn Berry lockfile, so it is refused.
- No lockfile at all is refused: a change needs a committed lockfile.
- A `packageManager` field naming a supported manager other than the one the lockfile chose (`pnpm@9` beside `package-lock.json`) is refused.

**Where it is read.** Each skill's checks are at `skills/<name>/scripts/verify.sh`. The script reads its own copy of the file at `skills/<name>/scripts/index.json`, which is byte-identical to `skills/index.json`. `tools/check.sh` fails when a copy differs.

## Checks

`bash tools/check.sh` runs the repository checks: JSON files parse, the exact fields of `skills/index.json` and its copies, skill frontmatter, `skills/index.json` against the skill folders, shellcheck, identical `scripts/lib.sh` copies, content rules, and `tools/test.sh`, the detection tests against the fixtures in `tools/fixtures/`. CI runs it on every pull request. It needs `jq` and `shellcheck`.
