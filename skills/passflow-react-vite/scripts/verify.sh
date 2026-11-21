#!/usr/bin/env bash
# Checks a React + Vite app signed in with @passflow/react, and its Node API protected with @passflow/node.
#
#   bash verify.sh static [--dir DIR] [--api-dir DIR]
#   bash verify.sh run    [--dir DIR] [--api-dir DIR] [--port N] [--api PATH] [--entry FILE] [--no-cors]
#
# Exit 0: every check passed. 1: a check failed. 2: refused or usage error.
# Prints one "PASS <check>", "FAIL <check>: <reason>" or "SKIP <check>: <reason>" line per check,
# then "RESULT pass|fail".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/lib.sh
. "$SCRIPT_DIR/lib.sh"

STACK_ID='react-vite'
SPA_PACKAGE='@passflow/react'
API_PACKAGE='@passflow/node'
ENV_FILE_NAME='.env.local'
SPA_KEYS='VITE_PASSFLOW_URL VITE_PASSFLOW_APP_ID VITE_API_URL'
API_KEYS='PASSFLOW_ISSUER PASSFLOW_AUDIENCE APP_BASE_URL'
# Secrets of other Passflow stacks. None belongs in an SPA, so none may be in its bundle.
FOREIGN_SECRET_KEYS='PASSFLOW_CLIENT_SECRET PASSFLOW_SECRET'
NODE_MIN='22.12'
DEFAULT_PORT='8086'
DEFAULT_API='/api/me'
# Where `vite build` puts the files the browser loads.
CLIENT_BUNDLE_DIRS='dist'
# The API must already use one of these.
API_FRAMEWORKS='express fastify hono'
# React frameworks that render on a server; they list vite and react too, but are not single-page apps.
SSR_FRAMEWORKS='@tanstack/react-start @react-router/dev @remix-run/dev vike vite-plugin-ssr waku astro rakkasjs'

usage() {
  cat >&2 <<'EOF'
Usage:
  bash verify.sh static [--dir DIR] [--api-dir DIR]
      Install with lifecycle scripts off, type-check the SPA and the API, build the SPA, scan dist/ for
      secrets and server code, and scan the source for guardrail breaks. Needs no env file and no network
      beyond the install. A VITE_ name that neither the environment nor .env, .env.local, .env.production
      or .env.production.local sets is built with a placeholder; that build is removed after the scans.

  bash verify.sh run [--dir DIR] [--api-dir DIR] [--port N] [--api PATH] [--entry FILE] [--no-cors]
      Start the API and check the protected route's answers and its CORS. The API gets PASSFLOW_ISSUER,
      PASSFLOW_AUDIENCE and APP_BASE_URL from the env file, and PORT. Refused when something already
      listens on the port: only an API this script starts is tested.
      --port    port for the API, passed as PORT (default 8086)
      --api     protected route to call (default /api/me)
      --entry   the API's entry file, run with node. Default: the API's api script; in a separate API
                folder its start or dev script; else server/index.ts (or .js, .mjs) or api/index.ts.
                A separate API folder with a start script and a build script is built first.
      --no-cors skip the CORS checks: the SPA calls the API on its own origin (a Vite proxy, for example).
                They are also skipped when the API lacks its CORS package (cors, @fastify/cors).

DIR is the SPA's project root and defaults to the current directory.
--api-dir is the API's folder when it has its own package.json (for example DIR/api). By default it is
DIR when DIR's package.json lists express, fastify or hono, else DIR/api or DIR/server when that one does.
Without an API on one of the three, both modes refuse: add an API first.
Exit 0 pass, 1 a check failed, 2 refused or usage error.
EOF
}

MODE="${1:-}"
if [ "$MODE" != static ] && [ "$MODE" != run ]; then
  usage
  exit 2
fi
shift

DIR="$PWD"
API_DIR_ARG=''
PORT_ARG="$DEFAULT_PORT"
API_PATH="$DEFAULT_API"
ENTRY_ARG=''
NO_CORS=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir) DIR="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --api-dir) API_DIR_ARG="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --entry) ENTRY_ARG="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --no-cors) NO_CORS=1; shift ;;
    --port) PORT_ARG="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --api) API_PATH="${2:-}"; shift 2 || { usage; exit 2; } ;;
    -h | --help) usage; exit 2 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$DIR" ] || [ ! -f "$DIR/package.json" ]; then
  printf 'REFUSED: no package.json in %s\n' "${DIR:-<empty>}" >&2
  exit 2
fi
DIR="$(cd "$DIR" && pwd)"
case "$PORT_ARG" in
  '' | *[!0-9]*) printf 'REFUSED: --port must be a number\n' >&2; exit 2 ;;
esac
case "$API_PATH" in
  /*) ;;
  *) printf 'REFUSED: --api must start with /\n' >&2; exit 2 ;;
esac

case "$ENTRY_ARG" in
  '' | /*) ;;
  *) ENTRY_ARG="$DIR/$ENTRY_ARG" ;;
esac

# 0 when DIR's package.json lists a server framework the skill supports.
has_api_framework() {
  local fw
  for fw in $API_FRAMEWORKS; do
    if pf_has_dep "$1" "$fw"; then return 0; fi
  done
  return 1
}

pf_require_tool node || exit 2
if ! pf_node_at_least "$NODE_MIN"; then
  printf 'REFUSED: Node.js %s or newer is required\n' "$NODE_MIN" >&2
  exit 2
fi

STACK="$(pf_detect_stack "$DIR" "$(pf_index_file)")"
case "$STACK" in
  "$STACK_ID") ;;
  refused:*) printf 'REFUSED: %s\n' "$(pf_stack_refusal "$DIR" "$(pf_index_file)" "${STACK#refused:}")" >&2; exit 2 ;;
  *) printf 'REFUSED: package.json does not describe a React + Vite app (detected: %s)\n' "$STACK" >&2; exit 2 ;;
esac

# Frameworks that render React on a server also list vite and react. This skill is for a single-page app.
# A TanStack Start app is detected as tanstack-start only when it also lists @tanstack/react-router.
if pf_has_dep "$DIR" @tanstack/react-start; then
  printf 'REFUSED: package.json lists @tanstack/react-start but not @tanstack/react-router. The TanStack Start skill needs %s; this skill is for a React + Vite single-page app only.\n' \
    "$(pf_stack_version_message tanstack-start)" >&2
  exit 2
fi
for fw in $SSR_FRAMEWORKS; do
  if pf_has_dep "$DIR" "$fw"; then
    printf 'REFUSED: package.json lists %s, which renders on a server. This skill is for a React + Vite single-page app only.\n' "$fw" >&2
    exit 2
  fi
done

check_pm() {
  local dir="$1" pm="$2"
  if ! pf_pm_supported "$pm"; then
    printf 'REFUSED: %s: %s\n' "$dir" "$(pf_pm_refusal "$pm")" >&2
    exit 2
  fi
  pf_require_tool "$(pf_pm_tool "$pm")" || exit 2
}

PM="$(pf_detect_pm "$DIR")"
check_pm "$DIR" "$PM"

# The API's folder: --api-dir (relative to DIR or absolute); else DIR when its package.json lists Express,
# Fastify or Hono; else DIR/api or DIR/server when that folder's package.json does. The skill adds Passflow
# to an existing API and never creates one.
API_DIR=''
if [ -n "$API_DIR_ARG" ]; then
  case "$API_DIR_ARG" in
    /*) API_DIR="$API_DIR_ARG" ;;
    *) API_DIR="$DIR/$API_DIR_ARG" ;;
  esac
  if [ ! -f "$API_DIR/package.json" ]; then
    printf 'REFUSED: no package.json in --api-dir %s\n' "$API_DIR" >&2
    exit 2
  fi
  API_DIR="$(cd "$API_DIR" && pwd)"
elif has_api_framework "$DIR"; then
  API_DIR="$DIR"
else
  for candidate in api server; do
    if [ -f "$DIR/$candidate/package.json" ] && has_api_framework "$DIR/$candidate"; then
      API_DIR="$DIR/$candidate"
      break
    fi
  done
fi
if [ -z "$API_DIR" ] || ! has_api_framework "$API_DIR"; then
  printf 'REFUSED: no API found: neither %s nor its api/ or server/ folder lists express, fastify or hono. This skill protects an existing API and never creates one: add an API first, then run again.\n' \
    "${API_DIR:-$DIR}/package.json" >&2
  exit 2
fi

API_PM="$PM"
if [ "$API_DIR" != "$DIR" ]; then
  API_PM="$(pf_detect_pm "$API_DIR")"
  # An API folder with no lockfile of its own installs with the root's manager.
  [ "$API_PM" != none ] || API_PM="$PM"
  check_pm "$API_DIR" "$API_PM"
fi

ENV_FILE="$DIR/$ENV_FILE_NAME"

# ---------------------------------------------------------------- static

# Env names that look secret, from the env file. Names only.
secret_looking_names() {
  [ -f "$ENV_FILE" ] || return 0
  sed -n 's/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}\([A-Za-z_][A-Za-z0-9_]*\)[[:space:]]*=.*/\2/p' "$ENV_FILE" |
    grep -E 'SECRET|PASSWORD|PRIVATE' | LC_ALL=C sort -u || true
}

# The env files `vite build` reads (production mode), in Vite's order.
VITE_BUILD_ENV_FILES='.env .env.local .env.production .env.production.local'

# vite_env_sets NAME: 0 when one of the env files a production build reads gives NAME a non-empty value.
vite_env_sets() {
  local f
  for f in $VITE_BUILD_ENV_FILES; do
    [ -f "$DIR/$f" ] || continue
    if [ -z "$(pf_env_missing_keys "$DIR/$f" "$1")" ]; then return 0; fi
  done
  return 1
}

# The folders that hold the API's code: the API folder when it is separate, else DIR/server and DIR/api.
api_code_dirs() {
  local sub
  if [ "$API_DIR" != "$DIR" ]; then
    printf '%s\n' "$API_DIR"
    return 0
  fi
  for sub in server api; do
    if [ -d "$DIR/$sub" ]; then printf '%s\n' "$DIR/$sub"; fi
  done
}

# resolve_import FILE SPEC: the absolute path a relative import SPEC in FILE points at (without checking that
# a file is there), or nothing when its folder does not exist.
resolve_import() {
  local base parent leaf
  base="$(dirname "$1")/$2"
  parent="$(dirname "$base")"
  leaf="$(basename "$base")"
  parent="$(cd "$parent" 2>/dev/null && pwd -P)" || return 0
  printf '%s/%s\n' "$parent" "$leaf"
}

# One line per import in src/ that reaches server code: "FAIL<TAB><file>:<line>" for @passflow/node, a server
# framework, or a relative import that resolves into the API's code; "NOTE<TAB><file>:<line>" for an alias
# such as @/server/ or ~/api/, whose target this script cannot resolve. A relative import into src/api/ (a
# browser client) is not a hit.
server_imports_in_src() {
  local api_dirs tab f line n spec target d
  tab="$(printf '\t')"
  api_dirs="$(api_code_dirs | while IFS= read -r d; do (cd "$d" && pwd -P); done)"
  find "$DIR/src" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.mjs' \) -print 2>/dev/null |
    while IFS= read -r f; do
      { grep -noE -- "(from|import|require\\()[[:space:]]*['\"][^'\"]+['\"]" "$f" 2>/dev/null || true; } |
        while IFS= read -r line; do
          n="${line%%:*}"
          spec="$(printf '%s' "${line#*:}" | sed -E "s/^.*['\"]([^'\"]+)['\"]\$/\\1/")"
          case "$spec" in
            @passflow/node | @passflow/node/* | express | fastify | fastify/* | hono | hono/* | @hono/node-server | @hono/node-server/*)
              printf 'FAIL%s%s:%s\n' "$tab" "${f#"$DIR"/}" "$n"
              ;;
            ./* | ../*)
              target="$(resolve_import "$f" "$spec")"
              [ -n "$target" ] || continue
              printf '%s\n' "$api_dirs" | while IFS= read -r d; do
                [ -n "$d" ] || continue
                case "$target/" in
                  "$d"/*) printf 'FAIL%s%s:%s\n' "$tab" "${f#"$DIR"/}" "$n" ;;
                esac
              done
              ;;
            @/server/* | @/api/* | \~/server/* | \~/api/* | '#server/'* | '#api/'*)
              printf 'NOTE%s%s:%s\n' "$tab" "${f#"$DIR"/}" "$n"
              ;;
          esac
        done
    done
}

# The API's own type-check: its package's when it has one, else server/tsconfig.json or api/tsconfig.json.
typecheck_api() {
  local sub
  if [ "$API_DIR" != "$DIR" ]; then
    pf_typecheck "$API_DIR" "$API_PM"
    return $?
  fi
  for sub in server api; do
    if [ -f "$DIR/$sub/tsconfig.json" ]; then
      pf_exec "$DIR" tsc -p "$sub/tsconfig.json" --noEmit
      return $?
    fi
  done
  return 3
}

run_static() {
  local rc names hits notes name placeholders='' bundle any_bundle=0 secret_names build_failed=0

  if pf_has_dep "$DIR" "$SPA_PACKAGE"; then
    pf_pass "dependency $SPA_PACKAGE"
  else
    pf_fail "dependency $SPA_PACKAGE" "not in dependencies or devDependencies of $DIR/package.json"
  fi
  if pf_has_dep "$API_DIR" "$API_PACKAGE"; then
    pf_pass "dependency $API_PACKAGE ($API_DIR)"
  else
    pf_fail "dependency $API_PACKAGE" "not in dependencies or devDependencies of $API_DIR/package.json"
  fi

  if [ -f "$ENV_FILE" ]; then
    names="$(secret_looking_names | grep '^VITE_' || true)"
    if [ -z "$names" ]; then
      pf_pass "no secret-looking VITE_ name in $ENV_FILE_NAME"
    else
      pf_fail "no secret-looking VITE_ name in $ENV_FILE_NAME" "$(printf '%s' "$names" | tr '\n' ' ')"
    fi
  else
    pf_skip "VITE_ names in $ENV_FILE_NAME" "no $ENV_FILE_NAME"
  fi

  rc=0
  pf_install "$DIR" >"$WORK/install.log" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    pf_pass "install ($PM)"
  else
    pf_fail "install ($PM)" "exit $rc; log: $WORK/install.log"
    return 0
  fi
  if [ "$API_DIR" != "$DIR" ]; then
    rc=0
    pf_install "$API_DIR" "$API_PM" >"$WORK/install-api.log" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
      pf_pass "install API ($API_PM)"
    else
      pf_fail "install API ($API_PM)" "exit $rc; log: $WORK/install-api.log"
      return 0
    fi
  fi

  rc=0
  pf_typecheck "$DIR" >"$WORK/typecheck.log" 2>&1 || rc=$?
  case "$rc" in
    0) pf_pass "typecheck (SPA)" ;;
    3) pf_skip "typecheck (SPA)" "no typecheck script and no tsconfig.json" ;;
    *) pf_fail "typecheck (SPA)" "exit $rc; log: $WORK/typecheck.log" ;;
  esac

  rc=0
  typecheck_api >"$WORK/typecheck-api.log" 2>&1 || rc=$?
  case "$rc" in
    0) pf_pass "typecheck (API)" ;;
    3) pf_skip "typecheck (API)" "no tsconfig.json for the API (server/tsconfig.json from the skill's assets)" ;;
    *) pf_fail "typecheck (API)" "exit $rc; log: $WORK/typecheck-api.log" ;;
  esac

  if pf_has_script "$DIR" build; then
    # A VITE_ name with no value makes the app throw at load, and the bundler then drops the rest of it.
    # Build every missing one with a placeholder, so the bundle holds the whole app for the scans below.
    # A name counts as set when the environment or any env file Vite reads for a production build sets it;
    # a placeholder never overrides a real value.
    for name in $SPA_KEYS; do
      if [ -z "${!name:-}" ] && ! vite_env_sets "$name"; then
        placeholders="$placeholders $name"
      fi
    done
    rc=0
    (
      for name in $placeholders; do
        case "$name" in
          VITE_PASSFLOW_URL) export VITE_PASSFLOW_URL='https://passflow.invalid' ;;
          VITE_PASSFLOW_APP_ID) export VITE_PASSFLOW_APP_ID='placeholder-app-id' ;;
          VITE_API_URL) export VITE_API_URL='https://api.invalid' ;;
        esac
      done
      pf_run_script "$DIR" build
    ) >"$WORK/build.log" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
      pf_pass build
      if [ -n "$placeholders" ]; then
        pf_info "built with placeholder values for:$placeholders (no env file nor the environment sets them); the build is scanned, then removed."
      fi
    else
      build_failed=1
      pf_fail build "exit $rc; log: $WORK/build.log"
    fi
  else
    pf_skip build "no build script"
  fi

  # shellcheck disable=SC2086
  secret_names="$({
    printf '%s\n' $FOREIGN_SECRET_KEYS
    pf_stack_get "$(pf_index_file)" "$STACK_ID" secret_env_keys
    secret_looking_names
  } | LC_ALL=C sort -u)"
  for bundle in $CLIENT_BUNDLE_DIRS; do
    # After a failed build the folder holds an older build: scanning it would prove nothing.
    [ "$build_failed" -eq 0 ] || break
    [ -d "$DIR/$bundle" ] || continue
    any_bundle=1
    rc=0
    # shellcheck disable=SC2086
    pf_scan_bundle "$DIR/$bundle" "$ENV_FILE" $secret_names >"$WORK/bundle-secrets.log" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
      pf_pass "no secret in $bundle/"
    else
      pf_fail "no secret in $bundle/" "see below"
      cat "$WORK/bundle-secrets.log"
    fi
    # The API's env names appear in a bundle only when server code was imported into the SPA. Names only:
    # their values are public or equal to VITE_ values.
    rc=0
    # shellcheck disable=SC2086
    pf_scan_bundle "$DIR/$bundle" '' $API_KEYS >"$WORK/bundle-server.log" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
      pf_pass "no server code in $bundle/"
    else
      pf_fail "no server code in $bundle/" "the SPA imports API code; see below"
      cat "$WORK/bundle-server.log"
    fi
  done
  if [ "$build_failed" -eq 1 ]; then
    pf_skip "bundle scan" "the build failed"
  elif [ "$any_bundle" -eq 0 ]; then
    pf_skip "bundle scan" "no build output in $CLIENT_BUNDLE_DIRS"
  fi

  # The placeholder build must never be deployed: remove it now that it is scanned.
  if [ -n "$placeholders" ] && [ "$build_failed" -eq 0 ]; then
    for bundle in $CLIENT_BUNDLE_DIRS; do
      if [ -d "$DIR/$bundle" ]; then rm -rf "${DIR:?}/$bundle"; fi
    done
    pf_info "removed $CLIENT_BUNDLE_DIRS/: it was built with placeholder values. Build again with real values to deploy."
  fi

  if [ -d "$DIR/src" ]; then
    names="$(server_imports_in_src || true)"
    hits="$(printf '%s\n' "$names" | sed -n 's/^FAIL	//p')"
    notes="$(printf '%s\n' "$names" | sed -n 's/^NOTE	//p')"
    if [ -z "$hits" ]; then
      pf_pass "no server import in src/"
    else
      pf_fail "no server import in src/" "src/ imports @passflow/node, a server framework or the API's code:"
      printf '%s\n' "$hits" | while IFS= read -r h; do printf '  %s\n' "$h"; done
    fi
    if [ -n "$notes" ]; then
      pf_skip "server imports through an alias" "cannot tell where these point; check by hand that they are not API code:"
      printf '%s\n' "$notes" | while IFS= read -r h; do printf '  %s\n' "$h"; done
    fi
  fi

  rc=0
  pf_guardrail_scan "$DIR" spa >"$WORK/guardrails.log" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    pf_pass guardrails
  else
    pf_fail guardrails "see below"
    cat "$WORK/guardrails.log"
  fi
}

# ---------------------------------------------------------------- run

stop_server() {
  if [ -n "$PF_BG_PID" ]; then
    pf_kill_tree "$PF_BG_PID"
    PF_BG_PID=''
  fi
}

run_live() {
  local missing script entry candidate how base www cc app_origin rc
  if [ ! -f "$ENV_FILE" ]; then
    printf 'REFUSED: %s not found; run mode needs it\n' "$ENV_FILE" >&2
    exit 2
  fi
  # shellcheck disable=SC2086
  missing="$(pf_env_missing_keys "$ENV_FILE" $API_KEYS)"
  if [ -n "$missing" ]; then
    printf 'REFUSED: %s has no value for: %s\n' "$ENV_FILE_NAME" "$(printf '%s' "$missing" | tr '\n' ' ')" >&2
    exit 2
  fi
  pf_require_tool curl || exit 2

  # How the API starts: --entry, else a script, else a usual entry file. verify.sh never adds a script.
  script=''
  entry="$ENTRY_ARG"
  if [ -n "$entry" ]; then
    if [ ! -f "$entry" ]; then
      printf 'REFUSED: --entry %s not found\n' "$entry" >&2
      exit 2
    fi
  elif pf_has_script "$API_DIR" api; then
    script=api
  elif [ "$API_DIR" != "$DIR" ] && pf_has_script "$API_DIR" start; then
    script=start
  elif [ "$API_DIR" != "$DIR" ] && pf_has_script "$API_DIR" dev; then
    script=dev
  else
    for candidate in server/index.ts server/index.js server/index.mjs api/index.ts api/index.js src/index.ts src/server.ts; do
      if [ -f "$API_DIR/$candidate" ]; then
        entry="$API_DIR/$candidate"
        break
      fi
    done
    if [ -z "$entry" ]; then
      printf 'REFUSED: cannot tell how to start the API in %s: no api script and no server/index.ts. Pass its entry file with --entry.\n' "$API_DIR" >&2
      exit 2
    fi
  fi

  if ! pf_port_free "$PORT_ARG"; then
    printf 'REFUSED: %s\n' "$(pf_port_busy_refusal "$PORT_ARG")" >&2
    exit 2
  fi

  # shellcheck disable=SC2086
  pf_load_env "$ENV_FILE" $API_KEYS

  # A separate API's start script usually runs its build output: build first, so the run tests the current
  # code.
  if [ "$script" = start ] && pf_has_script "$API_DIR" build; then
    rc=0
    pf_run_script "$API_DIR" build "$API_PM" >"$WORK/build-api.log" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
      pf_pass "build (API)"
    else
      pf_fail "build (API)" "exit $rc; log: $WORK/build-api.log"
      return 0
    fi
  fi

  # APP_BASE_URL reduced to its origin, as the API's CORS allows it.
  app_origin="$(printf '%s' "$APP_BASE_URL" | sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*://[^/?#]+).*#\1#')"
  export PORT="$PORT_ARG"
  pf_traps stop_server
  if [ -n "$script" ]; then
    how="$script script"
    case "$API_PM" in
      npm) pf_start_bg "$API_DIR" "$WORK/server.log" npm run "$script" ;;
      pnpm) pf_start_bg "$API_DIR" "$WORK/server.log" pnpm run "$script" ;;
      yarn-classic) pf_start_bg "$API_DIR" "$WORK/server.log" yarn run "$script" ;;
    esac
  else
    how="node ${entry#"$DIR"/}"
    case "$entry" in
      *.ts | *.mts) pf_start_bg "$API_DIR" "$WORK/server.log" node --experimental-strip-types "$entry" ;;
      *) pf_start_bg "$API_DIR" "$WORK/server.log" node "$entry" ;;
    esac
  fi

  # localhost, not 127.0.0.1: an API bound to localhost may listen on ::1 only.
  base="http://localhost:$PORT_ARG"
  if pf_wait_http "$base$API_PATH" 60 "$PF_BG_PID"; then
    pf_pass "API starts on port $PORT_ARG ($how)"
  elif pf_alive "$PF_BG_PID"; then
    pf_fail "API starts on port $PORT_ARG ($how)" "no answer within 60 s; log: $WORK/server.log"
    return 0
  else
    pf_fail "API starts on port $PORT_ARG ($how)" "the process exited; log: $WORK/server.log"
    return 0
  fi
  pf_check_listener "$PORT_ARG" "$PF_BG_PID"

  pf_http "$WORK/no-token" GET "$base$API_PATH" || true
  www="$(pf_header "$WORK/no-token" WWW-Authenticate)"
  cc="$(pf_header "$WORK/no-token" Cache-Control)"
  if [ "$(cat "$WORK/no-token/status")" = 401 ] && [ "$www" = Bearer ]; then
    pf_pass "GET $API_PATH without a token: 401, WWW-Authenticate: Bearer"
  else
    pf_fail "GET $API_PATH without a token" "status $(cat "$WORK/no-token/status"), WWW-Authenticate '${www}'; want 401 and 'Bearer' (status 000: no answer)"
  fi
  if pf_has_token "$cc" no-store; then
    pf_pass "GET $API_PATH without a token: Cache-Control no-store"
  else
    pf_fail "GET $API_PATH without a token" "Cache-Control '${cc}' has no no-store"
  fi

  pf_http "$WORK/bogus-token" GET "$base$API_PATH" -H 'Authorization: Bearer not.a.token' || true
  www="$(pf_header "$WORK/bogus-token" WWW-Authenticate)"
  case "$(cat "$WORK/bogus-token/status") $www" in
    '401 Bearer error="invalid_token"'*) pf_pass "GET $API_PATH with an invalid token: 401 invalid_token" ;;
    *) pf_fail "GET $API_PATH with an invalid token" "status $(cat "$WORK/bogus-token/status"), WWW-Authenticate '${www}'; want 401 and error=\"invalid_token\"" ;;
  esac

  if [ "$NO_CORS" -eq 1 ]; then
    pf_skip CORS "--no-cors: the SPA calls the API on its own origin"
  elif ! api_has_cors_package; then
    pf_skip CORS "the API has no CORS package ($(api_cors_package)); the skill leaves CORS to the developer. Pass --no-cors for a same-origin setup"
  else
    check_cors "$base" "$app_origin"
  fi

  if ! pf_alive "$PF_BG_PID"; then
    pf_fail "API still running after the checks" "the process exited; log: $WORK/server.log"
  fi
  stop_server
}

# The CORS package the API's framework needs: cors (Express), @fastify/cors (Fastify), none for Hono.
api_cors_package() {
  if pf_has_dep "$API_DIR" express; then
    printf 'cors\n'
  elif pf_has_dep "$API_DIR" fastify; then
    printf '@fastify/cors\n'
  else
    printf 'hono/cors\n'
  fi
}

# 0 when the API can mount CORS: Hono always (hono/cors ships with it), Express with cors, Fastify with
# @fastify/cors.
api_has_cors_package() {
  local pkg
  pkg="$(api_cors_package)"
  [ "$pkg" = hono/cors ] && return 0
  pf_has_dep "$API_DIR" "$pkg"
}

# check_cors BASE APP_ORIGIN: the 401 to the SPA's origin allows it and exposes WWW-Authenticate, the preflight
# allows Authorization, and another origin is not allowed. Each answer must be an HTTP answer (status 000,
# no answer, is a FAIL), and header lists are matched by whole items.
check_cors() {
  local base="$1" app_origin="$2" status allow expose allow_headers
  pf_http "$WORK/origin" GET "$base$API_PATH" -H "Origin: $app_origin" || true
  status="$(cat "$WORK/origin/status")"
  allow="$(pf_header "$WORK/origin" Access-Control-Allow-Origin)"
  expose="$(pf_header "$WORK/origin" Access-Control-Expose-Headers)"
  if [ "$status" = 401 ] && [ "$allow" = "$app_origin" ] && pf_has_token "$expose" WWW-Authenticate; then
    pf_pass "CORS: the 401 to APP_BASE_URL's origin ($app_origin) exposes WWW-Authenticate"
  else
    pf_fail "CORS: the answer to $app_origin" "status $status, Access-Control-Allow-Origin '${allow}', Access-Control-Expose-Headers '${expose}'; want 401, the origin and WWW-Authenticate"
  fi

  pf_http "$WORK/preflight" OPTIONS "$base$API_PATH" -H "Origin: $app_origin" \
    -H 'Access-Control-Request-Method: GET' -H 'Access-Control-Request-Headers: authorization' || true
  status="$(cat "$WORK/preflight/status")"
  allow="$(pf_header "$WORK/preflight" Access-Control-Allow-Origin)"
  allow_headers="$(pf_header "$WORK/preflight" Access-Control-Allow-Headers)"
  case "$status" in
    2??)
      if [ "$allow" = "$app_origin" ] && pf_has_token "$allow_headers" authorization; then
        pf_pass "CORS: the preflight from $app_origin allows the Authorization header"
      else
        pf_fail "CORS: the preflight from $app_origin" "Access-Control-Allow-Origin '${allow}', Access-Control-Allow-Headers '${allow_headers}'; want the origin and authorization"
      fi
      ;;
    *) pf_fail "CORS: the preflight from $app_origin" "status $status; want 2xx (is CORS mounted before the routes?)" ;;
  esac

  pf_http "$WORK/other-origin" GET "$base$API_PATH" -H 'Origin: https://other-origin.invalid' || true
  status="$(cat "$WORK/other-origin/status")"
  allow="$(pf_header "$WORK/other-origin" Access-Control-Allow-Origin)"
  if [ "$status" != 401 ]; then
    pf_fail "CORS: another origin is refused" "status $status; want the signed-out 401 without its origin allowed"
  else
    case "$allow" in
      '*' | 'https://other-origin.invalid') pf_fail "CORS: another origin is refused" "Access-Control-Allow-Origin is '${allow}'; want only $app_origin" ;;
      *) pf_pass "CORS: another origin is refused" ;;
    esac
  fi
}


WORK="$(mktemp -d "$PF_TMP/passflow-verify.XXXXXX")"
printf 'verify.sh %s: %s (%s, %s)\n' "$MODE" "$DIR" "$STACK_ID" "$PM"
if [ "$API_DIR" != "$DIR" ]; then
  printf 'API: %s (%s)\n' "$API_DIR" "$API_PM"
fi
printf 'logs: %s\n' "$WORK"

if [ "$MODE" = static ]; then
  run_static
else
  run_live
fi

if pf_result; then
  exit 0
fi
exit 1
