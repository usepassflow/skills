#!/usr/bin/env bash
# Checks a Next.js 16 App Router app that signs users in with @passflow/nextjs.
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

STACK_ID='nextjs'
PACKAGE='@passflow/nextjs'
ENV_FILE_NAME='.env.local'
ENV_KEYS='PASSFLOW_ISSUER PASSFLOW_CLIENT_ID PASSFLOW_CLIENT_SECRET PASSFLOW_SECRET APP_BASE_URL'
SECRET_KEYS='PASSFLOW_CLIENT_SECRET PASSFLOW_SECRET'
NODE_MIN='22.12'
DEFAULT_PORT='3100'
DEFAULT_PAGE='/account'
DEFAULT_API='/api/me'
# Where the build puts the files the browser loads.
CLIENT_BUNDLE_DIRS='.next/static'
# Prerendered output that is also sent to browsers.
PRERENDER_DIR='.next/server/app'
PRERENDER_GLOBS='*.html *.rsc *.body *.meta'

usage() {
  cat >&2 <<'EOF'
Usage:
  bash verify.sh static [--dir DIR]
      Install with lifecycle scripts off, type-check, build, search the client bundle for the
      secrets' names and values, and scan the source for guardrail breaks.
      Needs no env values and no network beyond the install.

  bash verify.sh run [--dir DIR] [--port N] [--page PATH] [--api PATH]
      Build, start the app with .env.local, and check its answers while signed out.
      --port  port for `next start`, passed as PORT (default 3100)
      --page  a protected page (default /account)
      --api   a protected route handler (default /api/me)

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
  *) printf 'REFUSED: package.json does not describe a Next.js app (detected: %s)\n' "$STACK" >&2; exit 2 ;;
esac
if [ -d "$DIR/src/app" ]; then
  ROOT="$DIR/src"
elif [ -d "$DIR/app" ]; then
  ROOT="$DIR"
else
  printf 'REFUSED: no app/ or src/app/ directory; this skill needs the App Router\n' >&2
  exit 2
fi
# "src/" or "" (the project root), for messages.
REL_ROOT="${ROOT#"$DIR"}"
REL_ROOT="${REL_ROOT#/}"
REL_ROOT="${REL_ROOT:+$REL_ROOT/}"

PM="$(pf_detect_pm "$DIR")"
if ! pf_pm_supported "$PM"; then
  printf 'REFUSED: %s\n' "$(pf_pm_refusal "$PM")" >&2
  exit 2
fi
pf_require_tool "$(pf_pm_tool "$PM")" || exit 2

# ---------------------------------------------------------------- checks used by both modes

# Names Next.js reads the proxy from: proxy (Next.js 16) or the older middleware, in TypeScript or JavaScript.
PROXY_FILES='proxy.ts proxy.js middleware.ts middleware.js'

# The proxy file sits beside app/: one of PROXY_FILES, which an existing project may already have in any of
# its forms. Exactly one may exist there, and it must call passflow.proxy.
check_proxy() {
  local f found='' present='' other_root='' other='' rel
  for f in $PROXY_FILES; do
    if [ -f "$ROOT/$f" ]; then
      present="$present ${REL_ROOT}$f"
      if grep -q 'passflow\.proxy(' "$ROOT/$f"; then found="$f"; fi
    fi
  done
  # With src/app, Next.js reads src/proxy.*; a proxy file at the project root is ignored (and the other way round).
  if [ "$ROOT" = "$DIR/src" ]; then other_root="$DIR"; rel=''; else other_root="$DIR/src"; rel='src/'; fi
  for f in $PROXY_FILES; do
    if [ -f "$other_root/$f" ]; then other="$other $rel$f"; fi
  done
  # shellcheck disable=SC2086
  set -- $present
  if [ "$#" -gt 1 ]; then
    pf_fail proxy "more than one proxy file:$present; Next.js reads only one, so merge them into the existing one"
  elif [ -n "$other" ]; then
    pf_fail proxy "Next.js ignores$other here; the proxy file belongs in ${REL_ROOT:-the project root} beside app/"
  elif [ -n "$found" ]; then
    pf_pass "proxy (${REL_ROOT}$found calls passflow.proxy)"
  elif [ -n "$present" ]; then
    pf_fail proxy "${present# } does not call passflow.proxy(request); merge it into that file"
  else
    pf_fail proxy "no ${REL_ROOT}proxy.ts calls passflow.proxy(request)"
  fi
}

# has_directive FILE 'use client': 0 when the directive is FILE's first statement, after any comments and
# blank lines.
has_directive() {
  awk -v d="$2" '
    BEGIN { found = 1 }
    inblock { if (index($0, "*/")) { inblock = 0 } ; next }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*\/\// { next }
    /^[[:space:]]*\/\*/ { if (!index($0, "*/")) inblock = 1; next }
    {
      s = $0; sub(/^[[:space:]]+/, "", s); sub(/[[:space:]\r]+$/, "", s)
      if (s == "\"" d "\"" || s == "\"" d "\";" || s == "'\''" d "'\''" || s == "'\''" d "'\'';") found = 0
      exit
    }
    END { exit found }' "$1" 2>/dev/null
}

is_client_file() { has_directive "$1" 'use client'; }

SERVER_MODULE_IMPORT="from[[:space:]]*['\"]([^'\"]*/)?(lib/passflow|@passflow/nextjs)(\\.[jt]sx?)?['\"]"

# A client component must not import the server module, directly or through a module of the app that imports
# it: it would ship to the browser and fail there.
client_import_scan() {
  local files f stem stems='' hits=''
  files="$(_pf_source_files "$DIR")"
  # Server-side modules of the app that import the Passflow server module, by file name without extension.
  # A 'use server' file is left out: a client component may import server actions.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if ! is_client_file "$f" && ! has_directive "$f" 'use server' && grep -qE "$SERVER_MODULE_IMPORT" "$f"; then
      stem="$(basename "$f")"
      stem="${stem%.*}"
      case "$stem" in
        index | page | layout | route | passflow | proxy | middleware | *[!A-Za-z0-9_-]*) ;;
        *) stems="$stems|$stem" ;;
      esac
    fi
  done <<EOF
$files
EOF
  stems="${stems#|}"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    is_client_file "$f" || continue
    if grep -qE "$SERVER_MODULE_IMPORT" "$f"; then
      hits="$hits  client component imports the server-only Passflow module: $f
"
    elif [ -n "$stems" ] && grep -qE "from[[:space:]]*['\"]([^'\"]*/)?($stems)(\\.[jt]sx?)?['\"]" "$f"; then
      hits="$hits  client component imports a module that uses the server-only Passflow module: $f
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
  local rc d scanned=0 found=0 bundle_dirs

  if pf_has_dep "$DIR" "$PACKAGE"; then
    pf_pass "dependency $PACKAGE"
  else
    pf_fail "dependency $PACKAGE" "not in dependencies or devDependencies of package.json"
  fi

  check_proxy

  rc=0
  pf_install "$DIR" >"$WORK/install.log" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    pf_pass "install ($PM)"
  else
    pf_fail "install ($PM)" "exit $rc; log: $WORK/install.log"
    return 0
  fi

  # The build comes first: next build writes next-env.d.ts (git-ignored in a fresh clone), which the
  # type-check needs for CSS-module and image imports.
  if pf_has_script "$DIR" build; then
    rc=0
    pf_run_script "$DIR" build >"$WORK/build.log" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
      pf_pass build
    else
      pf_fail build "exit $rc; log: $WORK/build.log"
    fi

    if [ "$rc" -ne 0 ]; then
      # The folders hold an older build: scanning them would prove nothing.
      pf_skip "client bundle" "the build failed"
    else
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
      done
      # Prerendered pages and RSC payloads are sent to every visitor too. Server code there names the
      # secrets legitimately, so only their values are searched.
      rc=0
      # shellcheck disable=SC2086
      pf_scan_values "$DIR/$PRERENDER_DIR" "$DIR/$ENV_FILE_NAME" "$PRERENDER_GLOBS" $SECRET_KEYS >>"$WORK/bundle.log" 2>&1 || rc=$?
      [ "$rc" -ne 1 ] || found=1
      if [ "$scanned" -eq 0 ]; then
        pf_fail "client bundle" "no client bundle in: $(printf '%s' "$bundle_dirs" | tr '\n' ' ')"
      elif [ "$found" -eq 1 ]; then
        pf_fail "client bundle" "a secret's name or value is in the files sent to the browser"
        cat "$WORK/bundle.log"
      else
        pf_pass "client bundle has no secret names or values; prerendered pages have no secret values"
      fi
    fi
  else
    pf_skip build "no build script"
    pf_skip "client bundle" "nothing was built"
  fi

  rc=0
  pf_typecheck "$DIR" >"$WORK/typecheck.log" 2>&1 || rc=$?
  case "$rc" in
    0) pf_pass typecheck ;;
    3) pf_skip typecheck "no typecheck script and no tsconfig.json" ;;
    *) pf_fail typecheck "exit $rc; log: $WORK/typecheck.log" ;;
  esac

  rc=0
  pf_guardrail_scan "$DIR" server >"$WORK/guardrails.log" 2>&1 || rc=$?
  client_import_scan >>"$WORK/guardrails.log" 2>&1 || rc=1
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
  if ! pf_has_script "$DIR" build || ! pf_has_script "$DIR" start; then
    printf 'REFUSED: package.json needs a build and a start script (next build, next start)\n' >&2
    exit 2
  fi
  base="http://localhost:$PORT_ARG"
  if ! pf_port_free "$PORT_ARG"; then
    printf 'REFUSED: %s\n' "$(pf_port_busy_refusal "$PORT_ARG")" >&2
    exit 2
  fi

  # Only the stack's own names; next build and next start read the rest of .env.local themselves.
  # shellcheck disable=SC2086
  pf_load_env "$env_file" $ENV_KEYS

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
  case "$PM" in
    npm) pf_start_bg "$DIR" "$WORK/server.log" npm run start ;;
    pnpm) pf_start_bg "$DIR" "$WORK/server.log" pnpm run start ;;
    yarn-classic) pf_start_bg "$DIR" "$WORK/server.log" yarn run start ;;
  esac

  if pf_wait_http "$base/" 90 "$PF_BG_PID"; then
    pf_pass "server starts on port $PORT_ARG (start script)"
  elif pf_alive "$PF_BG_PID"; then
    pf_fail "server starts on port $PORT_ARG (start script)" "no answer within 90 s; log: $WORK/server.log"
    return 0
  else
    pf_fail "server starts on port $PORT_ARG (start script)" "the process exited; log: $WORK/server.log"
    return 0
  fi
  pf_check_listener "$PORT_ARG" "$PF_BG_PID"

  # 1. A protected page, signed out: no protected content, and the way out is sign-in. With
  # cacheComponents the redirect can arrive in the stream after a 200, so the status is not checked.
  pf_http "$WORK/page" GET "$base$PAGE_PATH" || true
  status="$(cat "$WORK/page/status")"
  location="$(pf_header "$WORK/page" Location)"
  body_has=0
  if grep -q 'data-passflow-protected' "$WORK/page/body"; then body_has=1; fi
  if [ "$body_has" -eq 1 ]; then
    pf_fail "GET $PAGE_PATH signed out" "status $status; the body has data-passflow-protected content"
  else
    case "$location" in
      */auth/login*) pf_pass "GET $PAGE_PATH signed out: no protected content, redirect to /auth/login ($status)" ;;
      *)
        # A streamed redirect, not a sign-in link in the page's navigation.
        if grep -qE 'NEXT_REDIRECT;[a-z]+;[^;]*/auth/login|http-equiv="refresh"[^>]*/auth/login' "$WORK/page/body"; then
          pf_pass "GET $PAGE_PATH signed out: no protected content, the stream redirects to /auth/login ($status)"
        else
          pf_fail "GET $PAGE_PATH signed out" "status $status; no redirect to /auth/login in Location or in the stream"
        fi
        ;;
    esac
  fi

  # 2. A protected route handler, signed out: 401 with no-store, never a redirect.
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
    5??) pf_fail "GET /auth/login" "status $status; the app could not read the issuer's discovery document (PASSFLOW_ISSUER/.well-known/openid-configuration); log: $WORK/server.log" ;;
    *) pf_fail "GET /auth/login" "status $status; want a redirect" ;;
  esac
  if tr -d '\r' <"$WORK/login/headers" | grep -iE '^set-cookie:[[:space:]]*(__Host-)?passflow_txn=' | grep -qi 'httponly'; then
    pf_pass "GET /auth/login sets an HttpOnly transaction cookie (passflow_txn, or __Host-passflow_txn on https)"
  else
    pf_fail "GET /auth/login" "no HttpOnly passflow_txn or __Host-passflow_txn cookie"
  fi
  location=''
  issuer=''

  # 4. A route handler that changes data refuses another origin before anything else, and answers the
  # app's own origin with its signed-out 401. A route with no POST handler (405) is skipped.
  pf_http "$WORK/cross" POST "$base$API_PATH" -H 'Origin: https://evil.example' || true
  status="$(cat "$WORK/cross/status")"
  case "$status" in
    403) pf_pass "cross-origin POST $API_PATH: 403" ;;
    405) pf_skip "POST $API_PATH" "the route has no POST handler" ;;
    *) pf_fail "cross-origin POST $API_PATH" "status $status; want 403 from isSameOrigin" ;;
  esac
  if [ "$status" != 405 ]; then
    app_origin="$(printf '%s' "$APP_BASE_URL" | sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*://[^/?#]+).*#\1#')"
    pf_http "$WORK/same" POST "$base$API_PATH" -H "Origin: $app_origin" || true
    app_origin=''
    status="$(cat "$WORK/same/status")"
    if [ "$status" = 401 ]; then
      pf_pass "same-origin POST $API_PATH signed out: 401"
    else
      pf_fail "same-origin POST $API_PATH signed out" "status $status; want 401 (the app's own origin is APP_BASE_URL's)"
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
