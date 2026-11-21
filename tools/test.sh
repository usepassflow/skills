#!/usr/bin/env bash
# Black-box tests for the detection stage of skills/<name>/scripts/verify.sh
# and for the index.json copies.
#
# Each case copies a fixture from tools/fixtures/ into a temp dir and runs
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
# REQ-10: @tanstack/react-start <1.169 is refused.
expect_refused "REQ-10 @tanstack/react-start ^1.168.0 is refused via passflow-tanstack-start" passflow-tanstack-start stack-start-1168 'TanStack Start 1\.169 or newer'
expect_refused "REQ-10 @tanstack/react-start ^1.168.0 is refused via passflow-react-vite" passflow-react-vite stack-start-1168 'TanStack Start 1\.169 or newer'
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
