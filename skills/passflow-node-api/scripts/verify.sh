#!/usr/bin/env bash
# Checks a Node API (Express, Fastify or Hono) protected with @passflow/node.
#
#   bash verify.sh static [--dir DIR]
#   bash verify.sh run    [--dir DIR] [--port N] [--api PATH] [--origin URL]
#
# Exit 0: every check passed. 1: a check failed. 2: refused or usage error.
# Prints one "PASS <check>", "FAIL <check>: <reason>" or "SKIP <check>: <reason>" line per check,
# then "RESULT pass|fail".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/lib.sh
. "$SCRIPT_DIR/lib.sh"

STACK_ID='node-api'
PACKAGE='@passflow/node'
ENV_FILE_NAME='.env'
ENV_KEYS='PASSFLOW_ISSUER PASSFLOW_AUDIENCE'
NODE_MIN='22.12'
DEFAULT_PORT='8087'
DEFAULT_API='/api/me'

usage() {
  cat >&2 <<'EOF'
Usage:
  bash verify.sh static [--dir DIR]
      Install with lifecycle scripts off, type-check, build (if there is a build script)
      and scan the source for guardrail breaks. Needs no env file and no network beyond the install.

  bash verify.sh run [--dir DIR] [--port N] [--api PATH] [--origin URL]
      Build (with a start script and a build script), start the API with its start (else dev) script
      and check the protected route's answers.
      Refused when something already listens on the port: only a server this script starts is tested.
      --port    port for the API, passed as PORT (default 8087)
      --api     protected route to call (default /api/me)
      --origin  a browser origin the API's CORS allows; checks that the 401 allows it and exposes
                WWW-Authenticate. Leave it out for an API without CORS.

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

DIR="$PWD"
PORT_ARG="$DEFAULT_PORT"
API_PATH="$DEFAULT_API"
ORIGIN=''

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir) DIR="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --port) PORT_ARG="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --api) API_PATH="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --origin) ORIGIN="${2:-}"; shift 2 || { usage; exit 2; } ;;
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

pf_require_tool node || exit 2
if ! pf_node_at_least "$NODE_MIN"; then
  printf 'REFUSED: Node.js %s or newer is required\n' "$NODE_MIN" >&2
  exit 2
fi

STACK="$(pf_detect_stack "$DIR" "$(pf_index_file)")"
case "$STACK" in
  "$STACK_ID") ;;
  refused:*) printf 'REFUSED: %s\n' "$(pf_stack_refusal "$DIR" "$(pf_index_file)" "${STACK#refused:}")" >&2; exit 2 ;;
  *)
    printf 'REFUSED: package.json does not describe a Node API on Express, Fastify or Hono (detected: %s)\n' "$STACK" >&2
    exit 2
    ;;
esac

PM="$(pf_detect_pm "$DIR")"
if ! pf_pm_supported "$PM"; then
  printf 'REFUSED: %s\n' "$(pf_pm_refusal "$PM")" >&2
  exit 2
fi
pf_require_tool "$(pf_pm_tool "$PM")" || exit 2

# ---------------------------------------------------------------- static

run_static() {
  local rc

  if pf_has_dep "$DIR" "$PACKAGE"; then
    pf_pass "dependency $PACKAGE"
  else
    pf_fail "dependency $PACKAGE" "not in dependencies or devDependencies of package.json"
  fi

  rc=0
  pf_install "$DIR" >"$WORK/install.log" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    pf_pass "install ($PM)"
  else
    pf_fail "install ($PM)" "exit $rc; log: $WORK/install.log"
    return 0
  fi

  rc=0
  pf_typecheck "$DIR" >"$WORK/typecheck.log" 2>&1 || rc=$?
  case "$rc" in
    0) pf_pass typecheck ;;
    3) pf_skip typecheck "no typecheck script and no tsconfig.json" ;;
    *) pf_fail typecheck "exit $rc; log: $WORK/typecheck.log" ;;
  esac

  if pf_has_script "$DIR" build; then
    rc=0
    pf_run_script "$DIR" build >"$WORK/build.log" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
      pf_pass build
    else
      pf_fail build "exit $rc; log: $WORK/build.log"
    fi
  else
    pf_skip build "no build script"
  fi

  rc=0
  pf_guardrail_scan "$DIR" api >"$WORK/guardrails.log" 2>&1 || rc=$?
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
  local env_file="$DIR/$ENV_FILE_NAME" missing script base www cc expose allow status rc
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

  script=''
  if pf_has_script "$DIR" start; then
    script=start
  elif pf_has_script "$DIR" dev; then
    script=dev
  else
    printf 'REFUSED: package.json has no start or dev script\n' >&2
    exit 2
  fi

  if ! pf_port_free "$PORT_ARG"; then
    printf 'REFUSED: %s\n' "$(pf_port_busy_refusal "$PORT_ARG")" >&2
    exit 2
  fi

  # shellcheck disable=SC2086
  pf_load_env "$env_file" $ENV_KEYS

  # A start script usually runs the build output (node dist/server.js): build first, so the run tests the
  # current code. A dev script builds or transpiles by itself.
  if [ "$script" = start ] && pf_has_script "$DIR" build; then
    rc=0
    pf_run_script "$DIR" build "$PM" >"$WORK/build.log" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
      pf_pass build
    else
      pf_fail build "exit $rc; log: $WORK/build.log"
      return 0
    fi
  fi

  export PORT="$PORT_ARG"
  pf_traps stop_server
  case "$PM" in
    npm) pf_start_bg "$DIR" "$WORK/server.log" npm run "$script" ;;
    pnpm) pf_start_bg "$DIR" "$WORK/server.log" pnpm run "$script" ;;
    yarn-classic) pf_start_bg "$DIR" "$WORK/server.log" yarn run "$script" ;;
  esac

  # localhost, not 127.0.0.1: an API bound to localhost may listen on ::1 only.
  base="http://localhost:$PORT_ARG"
  if pf_wait_http "$base$API_PATH" 60 "$PF_BG_PID"; then
    pf_pass "server starts on port $PORT_ARG ($script script)"
  elif pf_alive "$PF_BG_PID"; then
    pf_fail "server starts on port $PORT_ARG ($script script)" "no answer within 60 s; log: $WORK/server.log"
    return 0
  else
    pf_fail "server starts on port $PORT_ARG ($script script)" "the process exited; log: $WORK/server.log"
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

  if [ -n "$ORIGIN" ]; then
    pf_http "$WORK/origin" GET "$base$API_PATH" -H "Origin: $ORIGIN" || true
    status="$(cat "$WORK/origin/status")"
    allow="$(pf_header "$WORK/origin" Access-Control-Allow-Origin)"
    expose="$(pf_header "$WORK/origin" Access-Control-Expose-Headers)"
    if [ "$status" = 401 ] && [ "$allow" = "$ORIGIN" ] && pf_has_token "$expose" WWW-Authenticate; then
      pf_pass "CORS: the 401 to $ORIGIN allows that origin and exposes WWW-Authenticate"
    else
      pf_fail "CORS: the 401 to $ORIGIN" "status $status, Access-Control-Allow-Origin '${allow}', Access-Control-Expose-Headers '${expose}'; want 401, the origin and WWW-Authenticate"
    fi
  else
    pf_skip "CORS" "no --origin given"
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
