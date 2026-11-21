#!/usr/bin/env bash
# Checks a TanStack Start app that signs users in with @passflow/tanstack-react-start.
#
#   bash verify.sh static [--dir DIR]
#   bash verify.sh run    [--dir DIR] [--port N] [--page PATH] [--api PATH]
#
# Exit 0: every check passed. 1: a check failed. 2: refused or usage error.
# Prints one "PASS <check>", "FAIL <check>: <reason>" or "SKIP <check>: <reason>" line per check,
# then "RESULT pass|fail".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/lib.sh
. "$SCRIPT_DIR/lib.sh"

STACK_ID='tanstack-start'
PACKAGE='@passflow/tanstack-react-start'
ENV_FILE_NAME='.env.local'
ENV_KEYS='PASSFLOW_ISSUER PASSFLOW_CLIENT_ID PASSFLOW_CLIENT_SECRET PASSFLOW_SECRET APP_BASE_URL'
SECRET_KEYS='PASSFLOW_CLIENT_SECRET PASSFLOW_SECRET'
NODE_MIN='22.12'
DEFAULT_PORT='3101'
DEFAULT_PAGE='/account'
DEFAULT_API='/api/me'
# Where the build puts the files the browser loads: Nitro output, then the default Start output.
CLIENT_BUNDLE_DIRS='.output/public dist/client'

usage() {
  cat >&2 <<'EOF'
Usage:
  bash verify.sh static [--dir DIR]
      Install with lifecycle scripts off, type-check, build, search the client bundle for the
      secrets' names and values and for server-only code, and scan the source for guardrail breaks.
      Needs no env values and no network beyond the install.

  bash verify.sh run [--dir DIR] [--port N] [--page PATH] [--api PATH]
      Build, start the app with .env.local, and check its answers while signed out.
      --port  port for the built app (default 3101)
      --page  a protected page (default /account)
      --api   a protected server route (default /api/me)

DIR defaults to the current directory.
Exit 0 pass, 1 a check failed, 2 refused or usage error.
EOF
}

MODE="${1:-}"
if [ "$MODE" != static ] && [ "$MODE" != run ]; then
  usage
  exit 2
fi
shift

INDEX="$(pf_index_file)"
DIR="$PWD"
PORT_ARG="$DEFAULT_PORT"
PAGE_PATH="$DEFAULT_PAGE"
API_PATH="$DEFAULT_API"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir) DIR="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --port) PORT_ARG="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --page) PAGE_PATH="${2:-}"; shift 2 || { usage; exit 2; } ;;
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
for p in "$PAGE_PATH" "$API_PATH"; do
  case "$p" in
    /*) ;;
    *) printf 'REFUSED: --page and --api must start with /\n' >&2; exit 2 ;;
  esac
done

pf_require_tool node || exit 2
if ! pf_node_at_least "$NODE_MIN"; then
  printf 'REFUSED: Node.js %s or newer is required\n' "$NODE_MIN" >&2
  exit 2
fi

STACK="$(pf_detect_stack "$DIR" "$INDEX")"
case "$STACK" in
  "$STACK_ID") ;;
  refused:*) printf 'REFUSED: %s\n' "$(pf_stack_refusal "$DIR" "$INDEX" "${STACK#refused:}")" >&2; exit 2 ;;
  *) printf 'REFUSED: package.json does not describe a TanStack Start app (detected: %s)\n' "$STACK" >&2; exit 2 ;;
esac
# The directory that holds routes/ and router.tsx: src/ by default, app/ in older layouts.
if [ -d "$DIR/src/routes" ]; then
  ROOT_NAME='src'
elif [ -d "$DIR/app/routes" ]; then
  ROOT_NAME='app'
else
  printf 'REFUSED: no src/routes/ or app/routes/ directory\n' >&2
  exit 2
fi
ROOT="$DIR/$ROOT_NAME"

PM="$(pf_detect_pm "$DIR")"
if ! pf_pm_supported "$PM"; then
  printf 'REFUSED: %s\n' "$(pf_pm_refusal "$PM")" >&2
  exit 2
fi
pf_require_tool "$(pf_pm_tool "$PM")" || exit 2

# ---------------------------------------------------------------- checks used by both modes

check_start_file() {
  local f found=''
  for f in start.ts start.tsx start.js; do
    if [ -f "$ROOT/$f" ] && grep -q 'requestMiddleware' "$ROOT/$f" && grep -q 'passflow\.middleware()' "$ROOT/$f"; then
      found="$f"
    fi
  done
  if [ -z "$found" ]; then
    pf_fail "request middleware" "no $ROOT_NAME/start.ts lists passflow.middleware() in requestMiddleware"
  elif ! grep -q 'createCsrfMiddleware(' "$ROOT/$found"; then
    # Setting requestMiddleware turns off Start's own check on server-function calls; this line restores it.
    pf_fail "request middleware" "$ROOT_NAME/$found has no createCsrfMiddleware({ filter: (ctx) => ctx.handlerType === 'serverFn' }); server functions are unprotected without it"
  elif ! grep -qE "handlerType[[:space:]]*===[[:space:]]*['\"]serverFn['\"]" "$ROOT/$found"; then
    # Unfiltered, Start's check also refuses the issuer's redirect back to /auth/callback.
    pf_fail "request middleware" "$ROOT_NAME/$found calls createCsrfMiddleware without the filter (ctx) => ctx.handlerType === 'serverFn'"
  else
    pf_pass "request middleware ($ROOT_NAME/$found registers passflow.middleware())"
  fi
}

# getSession, requireSession and getAccessToken read the server's request: each call must sit inside a server
# function or a server route. A call is flagged when the nearest line above it (or its own line) that opens
# code opens browser-side code (beforeLoad, loader, component, a component function) rather than a server
# function or server route (createServerFn, createServerOnlyFn, .handler(, server: {). A helper module with
# neither, called from server code, is not flagged.
server_only_scan() {
  local files f found hits=''
  files="$(_pf_source_files "$ROOT")"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    grep -qE 'passflow\.(getSession|requireSession|getAccessToken)\(' "$f" 2>/dev/null || continue
    found="$(awk -v file="$f" '
      /createServerFn|createServerOnlyFn|\.handler\(|server:[[:space:]]*\{/ { ctx = "server" }
      /beforeLoad|loader[[:space:]]*:|component[[:space:]]*:|function[[:space:]]+[A-Z]|=[[:space:]]*\([^)]*\)[[:space:]]*=>[[:space:]]*[(<]/ {
        if ($0 !~ /createServerFn|createServerOnlyFn|\.handler\(|server:[[:space:]]*\{/) ctx = "client"
      }
      /passflow\.(getSession|requireSession|getAccessToken)\(/ {
        if (ctx == "client") printf "  getSession, requireSession or getAccessToken outside a server function or server route: %s:%d\n", file, NR
      }' "$f" 2>/dev/null || true)"
    if [ -n "$found" ]; then
      hits="$hits$found
"
    fi
  done <<EOF
$files
EOF
  if [ -n "$hits" ]; then
    printf '%s' "$hits"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------- static

run_static() {
  local rc d scanned=0 found=0 bundle_dirs server_code='' build_failed=0

  if pf_has_dep "$DIR" "$PACKAGE"; then
    pf_pass "dependency $PACKAGE"
  else
    pf_fail "dependency $PACKAGE" "not in dependencies or devDependencies of package.json"
  fi

  check_start_file

  rc=0
  pf_install "$DIR" >"$WORK/install.log" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    pf_pass "install ($PM)"
  else
    pf_fail "install ($PM)" "exit $rc; log: $WORK/install.log"
    return 0
  fi

  # Start writes routeTree.gen.ts during the build, so a new route type-checks only after it.
  if pf_has_script "$DIR" build; then
    rc=0
    pf_run_script "$DIR" build >"$WORK/build.log" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
      pf_pass build
    else
      build_failed=1
      pf_fail build "exit $rc; log: $WORK/build.log"
    fi
  else
    pf_skip build "no build script"
  fi

  rc=0
  pf_typecheck "$DIR" >"$WORK/typecheck.log" 2>&1 || rc=$?
  case "$rc" in
    0) pf_pass typecheck ;;
    3) pf_skip typecheck "no typecheck script and no tsconfig.json" ;;
    *) pf_fail typecheck "exit $rc; log: $WORK/typecheck.log" ;;
  esac

  if [ "$build_failed" -eq 1 ]; then
    # The folders hold an older build: scanning them would prove nothing.
    pf_skip "client bundle" "the build failed"
  elif pf_has_script "$DIR" build; then
    bundle_dirs="$CLIENT_BUNDLE_DIRS"
    : >"$WORK/bundle.log"
    for d in $bundle_dirs; do
      rc=0
      # shellcheck disable=SC2086
      pf_scan_bundle "$DIR/$d" "$DIR/$ENV_FILE_NAME" $SECRET_KEYS >>"$WORK/bundle.log" 2>&1 || rc=$?
      case "$rc" in
        0) scanned=1 ;;
        1) scanned=1; found=1 ;;
      esac
      if [ -d "$DIR/$d" ]; then
        server_code="$server_code$(grep -rlF 'node:async_hooks' "$DIR/$d" 2>/dev/null || true)"
      fi
    done
    if [ "$scanned" -eq 0 ]; then
      pf_fail "client bundle" "no client bundle in: $(printf '%s' "$bundle_dirs" | tr '\n' ' ')"
    elif [ "$found" -eq 1 ]; then
      pf_fail "client bundle" "a secret's name or value is in the browser's files"
      cat "$WORK/bundle.log"
    else
      pf_pass "client bundle has no secret names or values"
    fi
    if [ "$scanned" -eq 1 ]; then
      if [ -n "$server_code" ]; then
        pf_fail "client bundle" "server-only code (node:async_hooks) is in the browser's files"
        printf '%s\n' "$server_code" | while IFS= read -r f; do printf '  %s\n' "$f"; done
      else
        pf_pass "client bundle has no server-only code"
      fi
    fi
  else
    pf_skip "client bundle" "nothing was built"
  fi

  rc=0
  pf_guardrail_scan "$DIR" server >"$WORK/guardrails.log" 2>&1 || rc=$?
  server_only_scan >>"$WORK/guardrails.log" 2>&1 || rc=1
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

# Starts the built app: the start script, else the Nitro output, else the preview script.
start_server() {
  if pf_has_script "$DIR" start; then
    SERVER_HOW='start script'
    case "$PM" in
      npm) pf_start_bg "$DIR" "$WORK/server.log" npm run start ;;
      pnpm) pf_start_bg "$DIR" "$WORK/server.log" pnpm run start ;;
      yarn-classic) pf_start_bg "$DIR" "$WORK/server.log" yarn run start ;;
    esac
  elif [ -f "$DIR/.output/server/index.mjs" ]; then
    SERVER_HOW='.output/server/index.mjs'
    pf_start_bg "$DIR" "$WORK/server.log" node .output/server/index.mjs
  elif pf_has_script "$DIR" preview; then
    SERVER_HOW='preview script'
    case "$PM" in
      npm) pf_start_bg "$DIR" "$WORK/server.log" npm run preview -- --port "$PORT_ARG" --strictPort ;;
      pnpm) pf_start_bg "$DIR" "$WORK/server.log" pnpm run preview --port "$PORT_ARG" --strictPort ;;
      yarn-classic) pf_start_bg "$DIR" "$WORK/server.log" yarn run preview --port "$PORT_ARG" --strictPort ;;
    esac
  else
    return 2
  fi
}

run_live() {
  local env_file="$DIR/$ENV_FILE_NAME" missing base status location body_has issuer rc app_origin
  if [ ! -f "$env_file" ]; then
    printf 'REFUSED: %s not found; run mode needs it\n' "$env_file" >&2
    exit 2
  fi
  # shellcheck disable=SC2086
  missing="$(pf_env_missing_keys "$env_file" $ENV_KEYS)"
  if [ -n "$missing" ]; then
    printf 'REFUSED: %s has no value for: %s\n' "$ENV_FILE_NAME" "$(printf '%s' "$missing" | tr '\n' ' ')" >&2
    exit 2
  fi
  pf_require_tool curl || exit 2
  if ! pf_has_script "$DIR" build; then
    printf 'REFUSED: package.json has no build script\n' >&2
    exit 2
  fi
  # localhost, not 127.0.0.1: `vite preview` listens on localhost only, which can be IPv6.
  base="http://localhost:$PORT_ARG"
  if ! pf_port_free "$PORT_ARG"; then
    printf 'REFUSED: %s\n' "$(pf_port_busy_refusal "$PORT_ARG")" >&2
    exit 2
  fi

  # Only the stack's own names; the app reads the rest of .env.local itself.
  # shellcheck disable=SC2086
  pf_load_env "$env_file" $ENV_KEYS

  # The build comes first: with Nitro it writes .output/server/index.mjs, one of the ways to start.
  rc=0
  pf_run_script "$DIR" build >"$WORK/build.log" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    pf_pass build
  else
    pf_fail build "exit $rc; log: $WORK/build.log"
    return 0
  fi

  export PORT="$PORT_ARG"
  pf_traps stop_server
  SERVER_HOW=''
  if ! start_server; then
    printf 'REFUSED: nothing to start: package.json has no start or preview script and the build wrote no .output/server/index.mjs\n' >&2
    exit 2
  fi

  if pf_wait_http "$base/" 90 "$PF_BG_PID"; then
    pf_pass "server starts on port $PORT_ARG ($SERVER_HOW)"
  elif pf_alive "$PF_BG_PID"; then
    pf_fail "server starts on port $PORT_ARG ($SERVER_HOW)" "no answer within 90 s; log: $WORK/server.log"
    return 0
  else
    pf_fail "server starts on port $PORT_ARG ($SERVER_HOW)" "the process exited; log: $WORK/server.log"
    return 0
  fi
  pf_check_listener "$PORT_ARG" "$PF_BG_PID"

  # 1. A protected page, signed out: no protected content, and the way out is sign-in.
  pf_http "$WORK/page" GET "$base$PAGE_PATH" || true
  status="$(cat "$WORK/page/status")"
  location="$(pf_header "$WORK/page" Location)"
  body_has=0
  if grep -q 'data-passflow-protected' "$WORK/page/body"; then body_has=1; fi
  if [ "$body_has" -eq 1 ]; then
    pf_fail "GET $PAGE_PATH signed out" "status $status; the body has data-passflow-protected content"
  else
    # Only a real redirect counts. A sign-in link in the page's navigation also names /auth/login, on an
    # unprotected page or a 404 as well, so the body's links prove nothing.
    case "$status $location" in
      30[12378]\ */auth/login*) pf_pass "GET $PAGE_PATH signed out: no protected content, $status redirect to /auth/login" ;;
      404\ *) pf_fail "GET $PAGE_PATH signed out" "status 404; --page must name a protected route that exists" ;;
      *)
        if grep -qE 'http-equiv="?refresh"?[^>]*/auth/login' "$WORK/page/body"; then
          pf_pass "GET $PAGE_PATH signed out: no protected content, a meta refresh to /auth/login ($status)"
        else
          pf_fail "GET $PAGE_PATH signed out" "status $status, Location '${location}'; want a redirect to /auth/login (is beforeLoad: requireUser on the route?)"
        fi
        ;;
    esac
  fi

  # 2. A protected server route, signed out: 401 with no-store, never a redirect.
  pf_http "$WORK/api" GET "$base$API_PATH" || true
  status="$(cat "$WORK/api/status")"
  if [ "$status" = 401 ] && pf_has_token "$(pf_header "$WORK/api" Cache-Control)" no-store; then
    pf_pass "GET $API_PATH signed out: 401, Cache-Control no-store"
  else
    pf_fail "GET $API_PATH signed out" "status $status, Cache-Control '$(pf_header "$WORK/api" Cache-Control)'; want 401 and no-store (status 000: no answer)"
  fi

  # 3. Sign-in starts at the issuer with PKCE and sets the transaction cookie.
  pf_http "$WORK/login" GET "$base/auth/login" || true
  status="$(cat "$WORK/login/status")"
  location="$(pf_header "$WORK/login" Location)"
  issuer="${PASSFLOW_ISSUER%/}"
  case "$status" in
    30[1278])
      if [ "${location#"$issuer"/oidc/authorize}" = "$location" ]; then
        pf_fail "GET /auth/login" "Location is not PASSFLOW_ISSUER/oidc/authorize"
      elif ! printf '%s' "$location" | grep -q 'code_challenge_method=S256'; then
        pf_fail "GET /auth/login" "Location has no code_challenge_method=S256"
      else
        pf_pass "GET /auth/login: $status to the issuer's /oidc/authorize with S256"
      fi
      ;;
    *) pf_fail "GET /auth/login" "status $status; want a redirect" ;;
  esac
  if tr -d '\r' <"$WORK/login/headers" | grep -iE '^set-cookie:[[:space:]]*(__Host-)?passflow_txn=' | grep -qi 'httponly'; then
    pf_pass "GET /auth/login sets an HttpOnly transaction cookie (passflow_txn, or __Host-passflow_txn on https)"
  else
    pf_fail "GET /auth/login" "no HttpOnly passflow_txn or __Host-passflow_txn cookie"
  fi
  location=''
  issuer=''

  # 4. The middleware refuses a POST from another site that carries any cookie, a session made of chunks
  # only included. A POST with no cookie (a webhook) and the app's own POST reach the route, which answers
  # its signed-out 401.
  pf_http "$WORK/cross-chunk" POST "$base$API_PATH" -H 'Cookie: passflow_session.0=x' -H 'Origin: https://evil.example' || true
  status="$(cat "$WORK/cross-chunk/status")"
  if [ "$status" = 403 ]; then
    pf_pass "cross-origin POST $API_PATH with only passflow_session.0: 403"
  else
    pf_fail "cross-origin POST $API_PATH with only passflow_session.0" "status $status; want 403"
  fi
  pf_http "$WORK/cross-cookie" POST "$base$API_PATH" -H 'Cookie: theme=dark' -H 'Origin: https://evil.example' || true
  status="$(cat "$WORK/cross-cookie/status")"
  if [ "$status" = 403 ]; then
    pf_pass "cross-origin POST $API_PATH with an ordinary cookie: 403"
  else
    pf_fail "cross-origin POST $API_PATH with an ordinary cookie" "status $status; want 403"
  fi
  pf_http "$WORK/cross-none" POST "$base$API_PATH" -H 'Origin: https://evil.example' || true
  status="$(cat "$WORK/cross-none/status")"
  if [ "$status" = 405 ]; then
    # The middleware let it through and the route has no POST handler: the route-level checks cannot run.
    pf_skip "POST $API_PATH reaching the route" "the route has no POST handler (405); the cross-origin cookie checks above still apply"
  else
    if [ "$status" = 401 ]; then
      pf_pass "cross-origin POST $API_PATH with no cookie reaches the route: 401"
    else
      pf_fail "cross-origin POST $API_PATH with no cookie" "status $status; want the route's signed-out 401"
    fi
    app_origin="$(printf '%s' "$APP_BASE_URL" | sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*://[^/?#]+).*#\1#')"
    pf_http "$WORK/same" POST "$base$API_PATH" -H 'Cookie: passflow_session.0=x' -H "Origin: $app_origin" || true
    status="$(cat "$WORK/same/status")"
    app_origin=''
    if [ "$status" = 401 ]; then
      pf_pass "same-origin POST $API_PATH passes the Origin check: 401 signed out"
    else
      pf_fail "same-origin POST $API_PATH" "status $status; want the route's signed-out 401 (the app's own origin is APP_BASE_URL's)"
    fi
  fi

  if ! pf_alive "$PF_BG_PID"; then
    pf_fail "server still running after the checks" "the process exited; log: $WORK/server.log"
  fi
  stop_server
}

WORK="$(mktemp -d "$PF_TMP/passflow-verify.XXXXXX")"
printf 'verify.sh %s: %s (%s, %s)\n' "$MODE" "$DIR" "$STACK_ID" "$PM"
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
