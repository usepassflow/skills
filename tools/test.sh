#!/usr/bin/env bash
# Black-box tests for the detection stage and the scans of skills/<name>/scripts/verify.sh
# and for the index.json copies.
#
# Each detection case copies a fixture from tools/fixtures/ into a temp dir and runs
# `verify.sh static --dir <copy>`. Refused cases expect exit 2 and a REFUSED line
# naming the reason. Accepted cases run with stub npm, pnpm, yarn and bun on PATH:
# the stubs log their arguments and fail without touching the network, so an
# accepted project shows up as "no REFUSED line, exit not 2, and the detected
# manager was asked to install".
#
# Usage: bash tools/test.sh
# Bash 3.2 compatible.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
FIXTURES="$HERE/fixtures"
CASE_TIMEOUT=${CASE_TIMEOUT:-60}

PASSED=0
FAILED=0
FAILED_NAMES=""

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t pftest)
trap 'rm -rf "$WORK"' EXIT

# Stub package managers: answer a version query, log anything else and fail.
STUBS="$WORK/stubs"
mkdir -p "$STUBS"
for tool in npm pnpm yarn bun npx; do
  case "$tool" in
    npm|npx) ver="10.9.0" ;;
    pnpm) ver="9.15.0" ;;
    yarn) ver="1.22.22" ;;
    bun) ver="1.1.0" ;;
  esac
  cat >"$STUBS/$tool" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  --version|-v|-version) echo "$ver"; exit 0 ;;
esac
echo "$tool \$*" >>"\${PF_TEST_STUB_LOG:-/dev/null}"
echo "stub $tool: no network in tests" >&2
exit 1
EOF
  chmod +x "$STUBS/$tool"
done

TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN=timeout
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN=gtimeout
fi

pass() {
  PASSED=$((PASSED + 1))
  echo "PASS $1"
}

fail() {
  FAILED=$((FAILED + 1))
  FAILED_NAMES="$FAILED_NAMES
  - $1"
  echo "FAIL $1: $2"
}

# run_verify SKILL FIXTURE -> sets OUT, CODE, STUB_LOG
N=0
run_verify() {
  skill=$1
  fixture=$2
  N=$((N + 1))
  dir="$WORK/case$N"
  mkdir -p "$dir"
  # Copy including dotfiles.
  (cd "$FIXTURES/$fixture" && tar cf - .) | (cd "$dir" && tar xf -)
  STUB_LOG="$WORK/case$N.stub.log"
  : >"$STUB_LOG"
  script="$ROOT/skills/$skill/scripts/verify.sh"
  if [ -n "$TIMEOUT_BIN" ]; then
    OUT=$(cd "$WORK" && PATH="$STUBS:$PATH" PF_TEST_STUB_LOG="$STUB_LOG" \
      npm_config_offline=true \
      "$TIMEOUT_BIN" "$CASE_TIMEOUT" bash "$script" static --dir "$dir" 2>&1 </dev/null)
    CODE=$?
  else
    OUT=$(cd "$WORK" && PATH="$STUBS:$PATH" PF_TEST_STUB_LOG="$STUB_LOG" \
      npm_config_offline=true \
      bash "$script" static --dir "$dir" 2>&1 </dev/null)
    CODE=$?
  fi
}

refused_lines() {
  printf '%s\n' "$OUT" | grep '^REFUSED:'
}

# expect_refused NAME SKILL FIXTURE PATTERN
# PATTERN is a case-insensitive extended regex the REFUSED line must match.
expect_refused() {
  name=$1
  run_verify "$2" "$3"
  pattern=$4
  lines=$(refused_lines)
  if [ "$CODE" -ne 2 ]; then
    fail "$name" "expected exit 2, got $CODE; output: $(printf '%s' "$OUT" | head -5 | tr '\n' '|')"
  elif [ -z "$lines" ]; then
    fail "$name" "exit 2 but no REFUSED line; output: $(printf '%s' "$OUT" | head -5 | tr '\n' '|')"
  elif ! printf '%s\n' "$lines" | grep -Eiq -- "$pattern"; then
    fail "$name" "REFUSED line does not match /$pattern/: $(printf '%s' "$lines" | tr '\n' '|')"
  elif [ -s "$STUB_LOG" ]; then
    fail "$name" "refused, but a package manager was run first: $(tr '\n' '|' <"$STUB_LOG")"
  else
    pass "$name"
  fi
}

# expect_accepted NAME SKILL FIXTURE MANAGER_COMMAND
expect_accepted() {
  name=$1
  run_verify "$2" "$3"
  manager=$4
  lines=$(refused_lines)
  if [ "$CODE" -eq 124 ]; then
    fail "$name" "timed out after ${CASE_TIMEOUT}s"
  elif [ -n "$lines" ]; then
    fail "$name" "refused: $(printf '%s' "$lines" | tr '\n' '|')"
  elif [ "$CODE" -eq 2 ]; then
    fail "$name" "exit 2 without a REFUSED line; output: $(printf '%s' "$OUT" | head -5 | tr '\n' '|')"
  elif ! grep -Eq "^$manager .*install" "$STUB_LOG"; then
    fail "$name" "expected '$manager ... install' to run; stub log: $(tr '\n' '|' <"$STUB_LOG")"
  else
    pass "$name"
  fi
}

# Source and bundle scans: these runs go on in the background while the detection cases run. They run every check of `static`: the npm stub's build step writes the browser files.
# With PF_TEST_BREAK, grep exits 2 from the build step on.
SCAN="$WORK/scan"
mkdir -p "$SCAN/stubs"
cat >"$SCAN/stubs/npm" <<'EOF'
#!/bin/sh
case "$*" in
  *run*build*)
    mkdir -p .next/static .next/server/app dist/client
    echo "${PF_TEST_PAGE:-ok}" >.next/server/app/x.html
    echo "${PF_TEST_JS:-ok}" | tee .next/server/app/x.js >/dev/null
    echo "${PF_TEST_BUNDLE:-ok}" | tee .next/static/a.js >dist/client/a.js
    : >"$PF_TEST_BUILT"
    ;;
esac
EOF
cat >"$SCAN/stubs/grep" <<EOF
#!/bin/sh
if [ -n "\${PF_TEST_BREAK:-}" ] && [ -e "\$PF_TEST_BUILT" ]; then exit 2; fi
exec "$(command -v grep)" "\$@"
EOF
chmod +x "$SCAN"/stubs/*
SECRET_VALUE='fixture-value-1'

# put FILE LINE...: writes a file of $APP.
put() {
  mkdir -p "$(dirname "$APP/$1")"
  file="$APP/$1"
  shift
  printf '%s\n' "$@" >"$file"
}

# new_app NAME SKILL: a clean app for SKILL in $APP.
new_app() {
  APP="$SCAN/$1"
  SKILL=$2
  SCRIPT="$ROOT/skills/$2/scripts/verify.sh"
  case "$SKILL" in
    passflow-nextjs)
      deps='"next": "^16.0.0", "@passflow/nextjs": "^0.1.0"'
      put proxy.ts 'export const proxy = (r) => passflow.proxy(r);'
      put lib/passflow.ts "import { createPassflow } from '@passflow/nextjs';"
      put app/page.tsx 'export default 1;'
      ;;
    passflow-tanstack-start)
      deps='"@tanstack/react-start": "^1.169.5", "@tanstack/react-router": "^1.170.46", "@passflow/tanstack-react-start": "^0.1.0"'
      put src/start.ts "requestMiddleware: [createCsrfMiddleware({ filter: (ctx) => ctx.handlerType === 'serverFn' }), passflow.middleware()]"
      put src/routes/index.tsx 'export default 1;'
      ;;
    passflow-react-vite)
      deps='"react": "19", "vite": "^7.0.0", "express": "^5.0.0", "@passflow/react": "^0.1.0", "@passflow/node": "^0.1.0"'
      put src/main.tsx "import './style.css';"
      put server/index.ts "import express from 'express';"
      ;;
    passflow-node-api)
      deps='"express": "^5.0.0", "@passflow/node": "^0.1.0"'
      put src/index.ts "import express from 'express';"
      ;;
  esac
  put package.json "{ \"scripts\": { \"build\": \"build\" }, \"dependencies\": { $deps } }"
  put package-lock.json '{ "lockfileVersion": 3 }'
  put .env.local "PASSFLOW_SECRET=$SECRET_VALUE"
}

# start_scan RUN [VAR=VALUE...]: runs $SCRIPT on $APP in the background; the output goes to $SCAN/RUN.out.
start_scan() {
  run=$1
  shift
  env PATH="$SCAN/stubs:$PATH" PF_TEST_BUILT="$SCAN/$run.built" "$@" \
    "$BASH" "$SCRIPT" static --dir "$APP" >"$SCAN/$run.out" 2>&1 </dev/null &
}

# expect_line RUN NAME LINE_REGEX: RUN printed the line, and no secret value.
expect_line() {
  OUT=$(cat "$SCAN/$1.out")
  if ! printf '%s\n' "$OUT" | grep -Eq -- "$3"; then
    fail "$2" "no line matches /$3/: $(printf '%s' "$OUT" | tr '\n' '|')"
  elif printf '%s\n' "$OUT" | grep -Fq "$SECRET_VALUE"; then
    fail "$2" "the output holds a secret's value"
  else
    pass "$2"
  fi
}

client="'use client';"
for s in nextjs tanstack-start react-vite node-api; do
  new_app "clean-$s" "passflow-$s"
  case "$s" in
    nextjs)
      put components/w.tsx "$client" "import x from './passflow';"
      put components/passflow.tsx "$client" 'export default 1;'
      put lib/ui/w.tsx "$client" "import x from './passflow';"
      put lib/ui/forms/w.tsx "$client" "import x from '../passflow';"
      ;;
  esac
  # A server file may hold the value; it is not sent to browsers.
  start_scan "clean-$s" PF_TEST_JS="$SECRET_VALUE"
  case "$s" in node-api) continue ;; esac

  # A copied verify.sh whose loops read a path that does not exist, and a grep that fails.
  new_app "break-$s" "passflow-$s"
  mkdir "$SCAN/scripts-$s"
  cp "$ROOT/skills/$SKILL/scripts/"* "$SCAN/scripts-$s"
  SCRIPT="$SCAN/scripts-$s/verify.sh"
  # shellcheck disable=SC2016
  sed 's|< <(printf .*"$files")|</nonexistent/input|' "$ROOT/skills/$SKILL/scripts/verify.sh" >"$SCRIPT"
  start_scan "break-$s" PF_TEST_BREAK=1

  new_app "leak-$s" "passflow-$s"
  if [ "$s" = nextjs ]; then
    put components/alias.tsx "$client" "import { passflow } from '@/lib/passflow';"
    put lib/sibling.tsx "$client" "import { passflow } from './passflow';"
    put lib/suffix.tsx "$client" "import { passflow } from './passflow.js';"
    put lib/ui/parent.tsx "$client" "import { passflow } from '../passflow';"
    put lib/ui/forms/deep.tsx "$client" "import { passflow } from '../../passflow';"
    put lib/help.ts "import { passflow } from './passflow';"
    put components/hop.tsx "$client" "import { x } from '@/lib/help';"
  fi
  start_scan "leak-$s" PF_TEST_BUNDLE="$SECRET_VALUE" PF_TEST_PAGE="$SECRET_VALUE"

  # An app folder with a build folder's name or behind a symlink, and a symlinked bundle folder.
  case "$s" in
    nextjs) new_app root/app "passflow-$s"; ln -s root/app "$SCAN/link"; APP="$SCAN/link"; bundle=.next/static ;;
    tanstack-start) new_app root/build "passflow-$s"; bundle=dist/client ;;
    react-vite) new_app root/dist "passflow-$s"; bundle=dist ;;
  esac
  put src/v.ts 'jwtDecode(t);'
  if [ "$s" = nextjs ]; then put lib/w.tsx "$client" "import { passflow } from './passflow';"; fi
  mkdir -p "$SCAN/out-$s" "$(dirname "$APP/$bundle")"
  ln -s "$SCAN/out-$s" "$APP/$bundle"
  start_scan "root-$s" PF_TEST_BUNDLE="PASSFLOW_SECRET node:async_hooks $SECRET_VALUE"
done

echo "# Package managers"
# REQ-1: no lockfile at all is refused.
expect_refused "REQ-1 no lockfile is refused" passflow-nextjs pm-none 'lockfile'
# REQ-2: bun.lock is refused.
expect_refused "REQ-2 bun.lock is refused" passflow-nextjs pm-bun-lock 'bun'
# REQ-3: bun.lockb is refused.
expect_refused "REQ-3 bun.lockb is refused" passflow-nextjs pm-bun-lockb 'bun'
# REQ-4: .yarnrc.yml next to yarn.lock means Yarn Berry, refused.
expect_refused "REQ-4 .yarnrc.yml + yarn.lock is refused as yarn-berry" passflow-nextjs pm-yarnrc-berry 'berry'
# REQ-5: a yarn.lock with a __metadata: line is Yarn Berry, refused.
expect_refused "REQ-5 yarn.lock with __metadata: is refused as yarn-berry" passflow-nextjs pm-yarn-metadata 'berry'
# REQ-6: packageManager yarn@2 or newer is refused.
expect_refused "REQ-6 packageManager yarn@4.1.0 is refused" passflow-nextjs pm-field-yarn4 'berry'
# REQ-7: packageManager bun is refused.
expect_refused "REQ-7 packageManager bun@1.1.0 is refused" passflow-nextjs pm-field-bun 'bun'
# REQ-14: a packageManager field naming a supported manager other than the lockfile's is refused.
expect_refused "REQ-14 packageManager pnpm@9.0.0 beside package-lock.json is refused" passflow-nextjs pm-field-pnpm-npm-lock 'pnpm'
# REQ-15: a root npm-shrinkwrap.json is refused.
expect_refused "REQ-15 root npm-shrinkwrap.json is refused" passflow-nextjs pm-shrinkwrap 'shrinkwrap'
# REQ-8: pnpm-lock.yaml, package-lock.json and a Yarn 1 yarn.lock are accepted.
expect_accepted "REQ-8 pnpm-lock.yaml is accepted (pnpm install)" passflow-nextjs pm-pnpm pnpm
expect_accepted "REQ-8 package-lock.json is accepted (npm install)" passflow-nextjs pm-npm npm
expect_accepted "REQ-8 plain yarn.lock is accepted (yarn install)" passflow-nextjs pm-yarn-classic yarn

echo "# Stacks"
# REQ-9: next <16 is selected as nextjs (first in array order) and refused, no fall-through to react-vite.
expect_refused "REQ-9 next ^15 + vite + react is refused via passflow-nextjs" passflow-nextjs stack-next15-vite 'Next\.js 16 or newer'
expect_refused "REQ-9 next ^15 + vite + react is refused via passflow-react-vite" passflow-react-vite stack-next15-vite 'Next\.js 16 or newer'
# REQ-10: @tanstack/react-start <1.169 is refused (the fixture lists @tanstack/react-router too, so the stack is chosen).
expect_refused "REQ-10 @tanstack/react-start ^1.168.0 is refused via passflow-tanstack-start" passflow-tanstack-start stack-start-1168 'TanStack Start 1\.169\.5 or newer'
expect_refused "REQ-10 @tanstack/react-start ^1.168.0 is refused via passflow-react-vite" passflow-react-vite stack-start-1168 'TanStack Start 1\.169\.5 or newer'
# REQ-11: a range that cannot be compared (workspace:*) counts as failing.
expect_refused "REQ-11 next workspace:* is refused" passflow-nextjs stack-next-workspace 'Next\.js 16 or newer'
# REQ-16: prereleases follow npm semver; 16.0.0-rc.1 does not satisfy >=16.
expect_refused "REQ-16 next 16.0.0-rc.1 is refused as an unsupported version" passflow-nextjs stack-next-rc 'Next\.js 16 or newer'
# REQ-12: no supported framework is refused.
expect_refused "REQ-12 no supported framework is refused via passflow-nextjs" passflow-nextjs stack-none 'unsupported|not supported|no supported|does not describe'
expect_refused "REQ-12 no supported framework is refused via passflow-node-api" passflow-node-api stack-none 'unsupported|not supported|no supported|does not describe'

echo "# Empty version spec"
# REQ-17: an empty version spec ("next": "") still selects the stack, which is then refused for its version;
# it never falls through to a later stack.
expect_refused "REQ-17 next \"\" + vite + react is refused via passflow-nextjs" passflow-nextjs stack-next-empty 'Next\.js 16 or newer'
expect_refused "REQ-17 next \"\" + vite + react is refused via passflow-react-vite" passflow-react-vite stack-next-empty 'Next\.js 16 or newer'

echo "# Prerelease above the floor"
# REQ-18: a prerelease above the floor's version (16.1.0-rc.1) still does not satisfy >=16, as in npm.
expect_refused "REQ-18 next 16.1.0-rc.1 is refused as an unsupported version" passflow-nextjs stack-next-rc-minor 'Next\.js 16 or newer'

echo "# TanStack Start and Router versions"
# REQ-19: @tanstack/react-start 1.169.4 (below 1.169.5) is refused; the message names both packages.
expect_refused "REQ-19 @tanstack/react-start 1.169.4 is refused" passflow-tanstack-start stack-start-1169-4 'TanStack Start 1\.169\.5 or newer with TanStack Router 1\.170\.46 or newer'
# REQ-20: @tanstack/react-router 1.170.45 (below 1.170.46) is refused.
expect_refused "REQ-20 @tanstack/react-router 1.170.45 is refused" passflow-tanstack-start stack-router-1170-45 'react-router.*1\.170\.45.*>=1\.170\.46'
# REQ-21: @tanstack/react-start without @tanstack/react-router is not detected as tanstack-start, and the
# React + Vite skill refuses it too.
expect_refused "REQ-21 @tanstack/react-start without the router is not tanstack-start" passflow-tanstack-start stack-start-no-router 'does not describe a TanStack Start app \(detected: react-vite\)'
expect_refused "REQ-21 @tanstack/react-start without the router is refused via passflow-react-vite" passflow-react-vite stack-start-no-router 'not @tanstack/react-router'
# REQ-22: Start ^1.169.5 with Router ^1.170.46 is accepted.
expect_accepted "REQ-22 @tanstack/react-start ^1.169.5 + @tanstack/react-router ^1.170.46 is accepted (npm install)" passflow-tanstack-start stack-start-ok npm

echo "# Source and bundle scans"
wait
# REQ-23: a clean app passes. REQ-24: a scan that cannot run fails its check. REQ-25: a secret's value is found.
# REQ-27: the app folder may be a symlink or have a build folder's name, and the bundle folder may be a symlink.
for s in nextjs tanstack-start react-vite node-api; do
  expect_line "clean-$s" "REQ-23 $s: a clean app passes" '^RESULT pass'
  case "$s" in node-api) continue ;; esac
  expect_line "break-$s" "REQ-24 $s: secret search cannot run" '^  could not search for the value of PASSFLOW_SECRET'
  expect_line "leak-$s" "REQ-25 $s: secret's value in the bundle" 'a\.js: value of PASSFLOW_SECRET'
  expect_line "root-$s" "REQ-27 $s: source files of the app" 'hand-decoded token .*/src/v\.ts:1'
  expect_line "root-$s" "REQ-27 $s: value in a symlinked bundle" 'a\.js: value of PASSFLOW_SECRET'
  expect_line "root-$s" "REQ-27 $s: name in a symlinked bundle" 'a\.js: PASSFLOW_SECRET$'
done
for s in nextjs tanstack-start; do
  expect_line "break-$s" "REQ-24 $s: source list cannot be read" '^  could not read the list of source files'
done
expect_line clean-nextjs "REQ-25 nextjs: server files are not prerendered pages" '^PASS client bundle'
expect_line leak-nextjs "REQ-25 nextjs: secret's value in a prerendered page" 'x\.html: value of PASSFLOW_SECRET'
expect_line root-nextjs "REQ-27 nextjs: import scan" 'server-only Passflow module: .*/lib/w\.tsx'
expect_line root-tanstack-start "REQ-27 tanstack-start: server code in a symlinked bundle" '^FAIL client bundle: server-only code'
# REQ-26: a client component must not import the server module, by any path.
for f in components/alias lib/sibling lib/suffix lib/ui/parent lib/ui/forms/deep; do
  expect_line leak-nextjs "REQ-26 nextjs: $f.tsx" "server-only Passflow module: .*/$f\.tsx"
done
expect_line leak-nextjs "REQ-26 nextjs: import through a helper in lib/" 'uses the server-only Passflow module: .*/hop\.tsx'
expect_line clean-nextjs "REQ-26 nextjs: unrelated passflow modules pass" '^PASS guardrails'

echo "# Repo structure"
# REQ-13: every skills/<name>/scripts/index.json is byte-identical to skills/index.json.
found=0
for d in "$ROOT"/skills/*/; do
  [ -d "$d" ] || continue
  found=1
  name=$(basename "$d")
  copy="$d/scripts/index.json"
  if [ ! -f "$copy" ]; then
    fail "REQ-13 $name/scripts/index.json exists" "missing"
  elif cmp -s "$ROOT/skills/index.json" "$copy"; then
    pass "REQ-13 $name/scripts/index.json is byte-identical to skills/index.json"
  else
    fail "REQ-13 $name/scripts/index.json is byte-identical to skills/index.json" "differs"
  fi
done
if [ "$found" -eq 0 ]; then
  fail "REQ-13 skill folders exist" "no skills/<name>/ folders found"
fi

echo
echo "SUMMARY: $PASSED passed, $FAILED failed, $((PASSED + FAILED)) total"
if [ "$FAILED" -ne 0 ]; then
  echo "Failed:$FAILED_NAMES"
  exit 1
fi
exit 0
