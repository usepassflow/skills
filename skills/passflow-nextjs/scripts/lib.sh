# shellcheck shell=bash
# Shared helpers for the Passflow skills' verify.sh scripts.
#
# Source it from a script that runs under `set -euo pipefail`:
#   . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
#
# Works with bash 3.2 (macOS) and later, BSD and GNU userlands.
# No function here prints the value of an environment variable or a token.
#
# Return codes: 0 ok, 1 a check failed, 2 refused or usage error.
#
# Functions
#   Output:        pf_pass CHECK | pf_fail CHECK REASON | pf_skip CHECK REASON | pf_info TEXT
#                  pf_result -> prints "RESULT pass|fail", returns 0|1
#   Tools:         pf_require_tool NAME...            (2 when one is missing)
#                  pf_node_at_least MAJOR.MINOR       (0 when node is that version or newer)
#   JSON:          pf_json_get FILE KEY...            (string, number or boolean; arrays one item per line;
#                                                      jq when present, else node; PF_NO_JQ=1 forces node)
#   package.json:  pf_pkg_field DIR KEY...
#                  pf_has_dep DIR NAME                (dependencies or devDependencies)
#                  pf_dep_range DIR NAME              (the range package.json gives NAME)
#                  pf_has_script DIR NAME
#   Ranges:        pf_range_meets SPEC '>=X.Y'        (0 when every version SPEC admits is X.Y or newer;
#                                                      1 for a SPEC that cannot be compared)
#   Stacks:        pf_index_file                      (scripts/index.json beside this file)
#                  pf_stack_get INDEX STACK_ID KEY... (a stack's field from index.json)
#                  pf_detect_stack DIR INDEX          (stack id, "refused:<stack id>" or "unsupported")
#                  pf_stack_refusal DIR INDEX STACK_ID (the message for "refused:<stack id>")
#                  pf_stack_version_message STACK_ID  ("Next.js 16 or newer", "TanStack Start 1.169.5 or newer with ...")
#   Packages:      pf_detect_pm DIR [INDEX]           (npm | pnpm | yarn-classic | yarn-berry | bun | shrinkwrap
#                                                      | mismatch:<declared>:<lockfile's> | none)
#                  pf_pm_supported PM | pf_pm_refused PM
#                  pf_pm_refusal PM                   (the message for any result that is not a supported PM)
#                  pf_pm_tool PM                      (the command: npm, pnpm or yarn)
#                  pf_package_spec NAME VERSION_ENV   (NAME, or NAME@version when VERSION_ENV is set)
#                  pf_install_line PM NAME VERSION_ENV (the install line to show, with the variable unexpanded)
#                  pf_install DIR [PM]                (install with lifecycle scripts off)
#                  pf_run_script DIR NAME [PM]
#                  pf_exec DIR COMMAND [ARGS...]      (a binary from the project's node_modules)
#                  pf_typecheck DIR [PM]              (0 pass, 1 fail, 3 nothing to check)
#   Env file:      pf_env_missing_keys FILE KEY...    (prints missing names)
#                  pf_load_env FILE KEY...            (exports those keys only; never evaluates a value)
#                  pf_git_tracked DIR FILE
#   Scans:         pf_scan_bundle BUNDLE_DIR ENV_FILE NAME...  (names and values; 0 clean, 1 found, 3 no such dir)
#                  pf_scan_values DIR ENV_FILE 'GLOB...' NAME... (values only, in files matching a GLOB)
#                  pf_guardrail_scan DIR KIND         (KIND: server | spa | api; 0 clean, 1 found)
#   HTTP:          pf_http OUT_DIR METHOD URL [CURL_ARGS...]  (writes status, headers, body to OUT_DIR)
#                  pf_header OUT_DIR NAME             (first value of a response header)
#                  pf_wait_http URL SECONDS [PID]     (1 at once when PID has exited)
#                  pf_port_free PORT | pf_port_busy_refusal PORT
#                  pf_has_token LIST TOKEN            (a whole item of a comma-separated header value)
#                  pf_listener_owned PORT PID         (0 yes, 1 another process, 3 cannot tell: no lsof)
#                  pf_check_listener PORT PID         (prints PASS, FAIL or SKIP for pf_listener_owned)
#   All curl calls use --noproxy '*': the checks talk to this machine only.
#   Processes:     pf_start_bg DIR LOG_FILE COMMAND [ARGS...]  (sets PF_BG_PID)
#                  pf_alive PID
#                  pf_kill_tree PID                   (TERM, then KILL after 5 s; pgrep, ps or /proc)
#                  pf_traps CLEANUP_FUNCTION          (EXIT, and INT/TERM that clean up and exit)

PF_FAILED=0
PF_BG_PID=''
PF_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Directory for temporary files, without a trailing slash.
PF_TMP="${TMPDIR:-/tmp}"
PF_TMP="${PF_TMP%/}"

# ---------------------------------------------------------------- output

pf_pass() { printf 'PASS %s\n' "$1"; }

pf_fail() {
  PF_FAILED=1
  printf 'FAIL %s: %s\n' "$1" "$2"
}

pf_skip() { printf 'SKIP %s: %s\n' "$1" "$2"; }

pf_info() { printf '  %s\n' "$*"; }

pf_result() {
  if [ "$PF_FAILED" -eq 0 ]; then
    printf 'RESULT pass\n'
    return 0
  fi
  printf 'RESULT fail\n'
  return 1
}

# ---------------------------------------------------------------- tools

pf_require_tool() {
  local tool
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      printf 'REFUSED: %s is required and was not found on PATH\n' "$tool" >&2
      return 2
    fi
  done
  return 0
}

# pf_node_at_least 22.12
pf_node_at_least() {
  local want="$1" have want_major want_minor have_major have_minor
  have="$(node -p 'process.versions.node' 2>/dev/null)" || return 1
  want_major="${want%%.*}"
  want_minor="${want#*.}"
  want_minor="${want_minor%%.*}"
  have_major="${have%%.*}"
  have_minor="${have#*.}"
  have_minor="${have_minor%%.*}"
  if [ "$have_major" -gt "$want_major" ]; then return 0; fi
  if [ "$have_major" -eq "$want_major" ] && [ "$have_minor" -ge "$want_minor" ]; then return 0; fi
  return 1
}

# ---------------------------------------------------------------- JSON

# jq when it is on PATH, unless PF_NO_JQ=1 (which forces the node path).
_pf_use_jq() {
  [ "${PF_NO_JQ:-}" != 1 ] && command -v jq >/dev/null 2>&1
}

# pf_json_get FILE KEY...: prints the value at the key path. Strings, numbers and booleans print as
# they are; an array prints one scalar item per line; objects, null and a missing path print nothing.
# Uses jq when present, else node.
pf_json_get() {
  local file="$1"
  shift
  [ -f "$file" ] || return 0
  if _pf_use_jq; then
    jq -r '$ARGS.positional as $p
      | (try getpath($p) catch null)
      | if type == "array" then .[] | select(type == "string" or type == "number" or type == "boolean") | tostring
        elif type == "string" or type == "number" or type == "boolean" then tostring
        else empty end' "$file" --args "$@" 2>/dev/null || true
    return 0
  fi
  node -e '
    const fs = require("fs");
    const [file, ...path] = process.argv.slice(1);
    let v;
    try { v = JSON.parse(fs.readFileSync(file, "utf8")); } catch { process.exit(0); }
    for (const k of path) {
      if (v === null || typeof v !== "object" || !Object.prototype.hasOwnProperty.call(v, k)) process.exit(0);
      v = v[k];
    }
    const scalar = (x) => ["string", "number", "boolean"].includes(typeof x);
    if (Array.isArray(v)) { for (const x of v) if (scalar(x)) console.log(String(x)); }
    else if (scalar(v)) console.log(String(v));
  ' "$file" "$@" 2>/dev/null || true
}

# ---------------------------------------------------------------- package.json

pf_pkg_field() {
  local dir="$1"
  shift
  pf_json_get "$dir/package.json" "$@"
}

# _pf_json_has FILE KEY...: 0 when the key path exists in FILE with a value other than null, an empty
# string included.
_pf_json_has() {
  local file="$1"
  shift
  [ -f "$file" ] || return 1
  if _pf_use_jq; then
    jq -e '$ARGS.positional as $p | (try getpath($p) catch null) != null' "$file" --args "$@" >/dev/null 2>&1
    return $?
  fi
  node -e '
    const fs = require("fs");
    const [file, ...path] = process.argv.slice(1);
    let v;
    try { v = JSON.parse(fs.readFileSync(file, "utf8")); } catch { process.exit(1); }
    for (const k of path) {
      if (v === null || typeof v !== "object" || !Object.prototype.hasOwnProperty.call(v, k)) process.exit(1);
      v = v[k];
    }
    process.exit(v === null || v === undefined ? 1 : 0);
  ' "$file" "$@" 2>/dev/null
}

# pf_has_dep DIR NAME: NAME is a key of dependencies or devDependencies, whatever its version spec (an empty
# spec included: the package is present, and a range rule then refuses it).
pf_has_dep() {
  local dir="$1" name="$2" field
  for field in dependencies devDependencies; do
    if _pf_json_has "$dir/package.json" "$field" "$name"; then
      return 0
    fi
  done
  return 1
}

# pf_dep_range DIR NAME: the range package.json gives NAME, from dependencies, else devDependencies.
pf_dep_range() {
  local dir="$1" name="$2" field range
  for field in dependencies devDependencies; do
    range="$(pf_pkg_field "$dir" "$field" "$name")"
    if [ -n "$range" ]; then
      printf '%s\n' "$range"
      return 0
    fi
  done
  return 0
}

pf_has_script() {
  [ -n "$(pf_pkg_field "$1" scripts "$2")" ]
}

# ---------------------------------------------------------------- version ranges

# _pf_version_floor SPEC: the lowest version a simple range admits, as "MAJOR MINOR PATCH PRE"
# (PRE is 1 for a pre-release such as 16.0.0-rc.1, else 0).
# Understood: 1.2.3, v1.2.3, =1.2.3, ^1.2.3, ~1.2.3, >=1.2.3, and 1, 1.2, 1.x, 1.2.x, 1.2.*.
# Prints nothing for anything else ("*", "latest", "workspace:^", "npm:…", a git or file URL, "a || b",
# "a - b", "<2", ">1", ">=1 <2"): such a range cannot be compared, so a range rule never matches it.
_pf_version_floor() {
  local spec="$1" re major minor patch pre=0
  spec="$(printf '%s' "$spec" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  re='^(\^|~|>=|=)?[[:space:]]*v?([0-9]+)(\.([0-9]+|[xX*]))?(\.([0-9]+|[xX*]))?(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
  [[ "$spec" =~ $re ]] || return 0
  major="${BASH_REMATCH[2]}"
  minor="${BASH_REMATCH[4]}"
  patch="${BASH_REMATCH[6]}"
  case "$minor" in '' | x | X | '*') minor=0; patch=0 ;; esac
  case "$patch" in '' | x | X | '*') patch=0 ;; esac
  [ -z "${BASH_REMATCH[7]}" ] || pre=1
  printf '%s %s %s %s\n' "$((10#$major))" "$((10#$minor))" "$((10#$patch))" "$pre"
}

# pf_range_meets SPEC REQUIRED: 0 when every version SPEC admits is at least REQUIRED's floor.
# REQUIRED is ">=MAJOR[.MINOR[.PATCH]]" as index.json writes it. Fails safe: a SPEC or REQUIRED that cannot
# be compared (an empty one included) returns 1. A pre-release SPEC (16.0.0-rc.1, 16.1.0-rc.1) returns 1
# whatever its version: as in npm's default semver rules, a range without a pre-release, such as ">=16",
# admits no pre-release.
pf_range_meets() {
  local spec="$1" required="$2" have want
  case "$required" in
    '>='*) ;;
    *) return 1 ;;
  esac
  have="$(_pf_version_floor "$spec")"
  want="$(_pf_version_floor "$required")"
  [ -n "$have" ] && [ -n "$want" ] || return 1
  # shellcheck disable=SC2086
  set -- $have $want
  [ "$4" -eq 0 ] || return 1
  if [ "$1" -ne "$5" ]; then [ "$1" -gt "$5" ]; return $?; fi
  if [ "$2" -ne "$6" ]; then [ "$2" -gt "$6" ]; return $?; fi
  [ "$3" -ge "$7" ]
}

# ---------------------------------------------------------------- stacks

# The index.json beside this file (a byte-identical copy of skills/index.json).
pf_index_file() {
  printf '%s\n' "$PF_LIB_DIR/index.json"
}

# pf_stack_get INDEX STACK_ID KEY...: a field of one stack in index.json.
pf_stack_get() {
  local index="$1" id="$2"
  shift 2
  [ -f "$index" ] || return 0
  if _pf_use_jq; then
    jq -r --arg id "$id" '$ARGS.positional as $p
      | (.stacks[] | select(.id == $id)) as $s
      | ($s | try getpath($p) catch null)
      | if type == "array" then .[] | select(type == "string" or type == "number" or type == "boolean") | tostring
        elif type == "string" or type == "number" or type == "boolean" then tostring
        else empty end' "$index" --args "$@" 2>/dev/null || true
    return 0
  fi
  node -e '
    const fs = require("fs");
    const [file, id, ...path] = process.argv.slice(1);
    let v;
    try { v = (JSON.parse(fs.readFileSync(file, "utf8")).stacks || []).find((s) => s.id === id); } catch { process.exit(0); }
    for (const k of path) {
      if (v === null || typeof v !== "object" || !Object.prototype.hasOwnProperty.call(v, k)) process.exit(0);
      v = v[k];
    }
    const scalar = (x) => ["string", "number", "boolean"].includes(typeof x);
    if (Array.isArray(v)) { for (const x of v) if (scalar(x)) console.log(String(x)); }
    else if (scalar(v)) console.log(String(v));
  ' "$index" "$id" "$@" 2>/dev/null || true
}

# The stack ids of index.json, in detection order.
pf_stack_ids() {
  local index="$1"
  [ -f "$index" ] || return 0
  if _pf_use_jq; then
    jq -r '.stacks[].id' "$index" 2>/dev/null || true
    return 0
  fi
  node -e '
    const fs = require("fs");
    try { for (const s of JSON.parse(fs.readFileSync(process.argv[1], "utf8")).stacks || []) console.log(s.id); } catch {}
  ' "$index" 2>/dev/null || true
}

# _pf_detect_entries INDEX STACK_ID all|any: one "package<TAB>range" line per entry (range may be empty).
_pf_detect_entries() {
  local index="$1" id="$2" kind="$3"
  if _pf_use_jq; then
    jq -r --arg id "$id" --arg k "$kind" \
      '.stacks[] | select(.id == $id) | (.detect[$k] // [])[] | "\(.package)\t\(.range // "")"' \
      "$index" 2>/dev/null || true
    return 0
  fi
  node -e '
    const fs = require("fs");
    const [file, id, kind] = process.argv.slice(1);
    try {
      const s = (JSON.parse(fs.readFileSync(file, "utf8")).stacks || []).find((x) => x.id === id);
      for (const e of (s && s.detect && s.detect[kind]) || []) console.log(e.package + "\t" + (e.range || ""));
    } catch {}
  ' "$index" "$id" "$kind" 2>/dev/null || true
}

# _pf_stack_selected DIR INDEX STACK_ID: selection by package names alone. Every "all" package is a
# dependency and, when the stack has an "any" list, at least one "any" package is. A stack with no entries
# is never selected.
_pf_stack_selected() {
  local dir="$1" index="$2" id="$3" pkg range tab seen=0 any_seen=0 any_hit=0
  tab="$(printf '\t')"
  while IFS="$tab" read -r pkg range; do
    [ -n "$pkg" ] || continue
    seen=1
    pf_has_dep "$dir" "$pkg" || return 1
  done < <(_pf_detect_entries "$index" "$id" all)
  while IFS="$tab" read -r pkg range; do
    [ -n "$pkg" ] || continue
    any_seen=1
    if pf_has_dep "$dir" "$pkg"; then any_hit=1; fi
  done < <(_pf_detect_entries "$index" "$id" any)
  [ "$seen" -eq 1 ] || [ "$any_seen" -eq 1 ] || return 1
  [ "$any_seen" -eq 0 ] || [ "$any_hit" -eq 1 ]
}

# _pf_stack_range_failure DIR INDEX STACK_ID: prints "package<TAB>rule<TAB>spec" for the first range rule of
# the stack that the project's dependencies do not meet; prints nothing when all hold. An "any" entry's rule
# applies only when that package is a dependency. A spec that cannot be compared fails.
_pf_stack_range_failure() {
  local dir="$1" index="$2" id="$3" kind pkg range spec tab
  tab="$(printf '\t')"
  for kind in all any; do
    while IFS="$tab" read -r pkg range; do
      [ -n "$pkg" ] && [ -n "$range" ] || continue
      pf_has_dep "$dir" "$pkg" || continue
      # An empty spec cannot be compared, so it fails the rule.
      spec="$(pf_dep_range "$dir" "$pkg")"
      if ! pf_range_meets "$spec" "$range"; then
        printf '%s\t%s\t%s\n' "$pkg" "$range" "$spec"
        return 0
      fi
    done < <(_pf_detect_entries "$index" "$id" "$kind")
  done
}

# pf_detect_stack DIR INDEX: index.json's detect rules against DIR/package.json (dependencies plus
# devDependencies). Stacks are tried in array order and the first one selected by package names wins
# (see _pf_stack_selected). Its range rules must then hold; there is no fall-through to a later stack.
# Prints the stack id, "refused:<stack id>" when a range rule fails, or "unsupported".
pf_detect_stack() {
  local dir="$1" index="$2" id
  if [ ! -f "$dir/package.json" ]; then
    printf 'unsupported\n'
    return 0
  fi
  for id in $(pf_stack_ids "$index"); do
    _pf_stack_selected "$dir" "$index" "$id" || continue
    if [ -n "$(_pf_stack_range_failure "$dir" "$index" "$id")" ]; then
      printf 'refused:%s\n' "$id"
    else
      printf '%s\n' "$id"
    fi
    return 0
  done
  printf 'unsupported\n'
}

# pf_stack_version_message STACK_ID: what a stack's range rules ask for, in words.
pf_stack_version_message() {
  case "$1" in
    nextjs) printf 'Next.js 16 or newer\n' ;;
    tanstack-start) printf 'TanStack Start 1.169.5 or newer with TanStack Router 1.170.46 or newer\n' ;;
    *) printf 'a newer version of its framework\n' ;;
  esac
}

# pf_stack_refusal DIR INDEX STACK_ID: the message for a project refused as "refused:<stack id>".
pf_stack_refusal() {
  local dir="$1" index="$2" id="$3" failure pkg rule spec tab
  tab="$(printf '\t')"
  failure="$(_pf_stack_range_failure "$dir" "$index" "$id")"
  IFS="$tab" read -r pkg rule spec < <(printf '%s\n' "$failure")
  printf 'this project needs %s: package.json gives %s "%s", which does not meet %s. A tag, workspace:, a URL or a compound range cannot be checked; write a version range such as "^%s".\n' \
    "$(pf_stack_version_message "$id")" "$pkg" "$spec" "$rule" "${rule#>=}"
}

# ---------------------------------------------------------------- package managers

# pf_detect_pm DIR [INDEX]: npm | pnpm | yarn-classic | yarn-berry | bun | shrinkwrap
#                            | mismatch:<declared>:<lockfile's> | none.
#   1. A `packageManager` field naming yarn@2 or newer, or bun, gives yarn-berry or bun (refused).
#   2. A root npm-shrinkwrap.json gives shrinkwrap (refused: npm would write to it, not to package-lock.json).
#   3. index.json's package_managers.detect entries whose file exists in DIR: if any names a refused
#      manager, that manager; otherwise the first match.
#   4. A yarn.lock with a `__metadata:` line is a Yarn Berry lockfile, whatever else matched: yarn-berry.
#   5. No entry matches (no lockfile): none (refused: the change needs a committed lockfile).
#   6. A `packageManager` field naming a supported manager other than the lockfile's gives
#      mismatch:<declared>:<lockfile's> (refused: the project's own files disagree on the manager).
pf_detect_pm() {
  local dir="$1" index="${2:-}" field declared='' file manager first='' refused='' tab
  [ -n "$index" ] || index="$(pf_index_file)"
  tab="$(printf '\t')"
  field="$(pf_pkg_field "$dir" packageManager)"
  case "$field" in
    yarn@1 | yarn@1.* | yarn@1+*) declared=yarn-classic ;;
    yarn@*) printf 'yarn-berry\n'; return 0 ;;
    bun@*) printf 'bun\n'; return 0 ;;
    npm@*) declared=npm ;;
    pnpm@*) declared=pnpm ;;
  esac
  if [ -e "$dir/npm-shrinkwrap.json" ]; then
    printf 'shrinkwrap\n'
    return 0
  fi
  while IFS="$tab" read -r file manager; do
    [ -n "$file" ] && [ -n "$manager" ] || continue
    [ -e "$dir/$file" ] || continue
    [ -n "$first" ] || first="$manager"
    if [ -z "$refused" ] && pf_pm_refused "$manager" "$index"; then refused="$manager"; fi
  done < <(_pf_pm_detect_entries "$index")
  if [ -n "$refused" ]; then
    printf '%s\n' "$refused"
  elif [ -f "$dir/yarn.lock" ] && grep -q '^__metadata:' "$dir/yarn.lock" 2>/dev/null; then
    printf 'yarn-berry\n'
  elif [ -z "$first" ]; then
    printf 'none\n'
  elif [ -n "$declared" ] && [ "$declared" != "$first" ]; then
    printf 'mismatch:%s:%s\n' "$declared" "$first"
  else
    printf '%s\n' "$first"
  fi
}

# One "file<TAB>manager" line per package_managers.detect entry, in order.
_pf_pm_detect_entries() {
  local index="$1"
  [ -f "$index" ] || return 0
  if _pf_use_jq; then
    jq -r '.package_managers.detect[] | "\(.file)\t\(.manager)"' "$index" 2>/dev/null || true
    return 0
  fi
  node -e '
    const fs = require("fs");
    try {
      for (const e of JSON.parse(fs.readFileSync(process.argv[1], "utf8")).package_managers.detect || [])
        console.log(e.file + "\t" + e.manager);
    } catch {}
  ' "$index" 2>/dev/null || true
}

# pf_pm_supported PM [INDEX]: PM is in package_managers.supported.
pf_pm_supported() {
  local pm="$1" index="${2:-}"
  [ -n "$index" ] || index="$(pf_index_file)"
  pf_json_get "$index" package_managers supported | grep -qx -- "$pm"
}

# pf_pm_refused PM [INDEX]: PM is in package_managers.refused.
pf_pm_refused() {
  local pm="$1" index="${2:-}"
  [ -n "$index" ] || index="$(pf_index_file)"
  pf_json_get "$index" package_managers refused | grep -qx -- "$pm"
}

# pf_pm_refusal PM: the message for a result of pf_detect_pm that is not a supported manager.
pf_pm_refusal() {
  local declared lock
  case "$1" in
    none)
      printf 'no lockfile found. Passflow skills need a committed lockfile: package-lock.json (npm), pnpm-lock.yaml (pnpm) or yarn.lock (Yarn 1, classic). Install once with your package manager, commit the lockfile, then run again.\n'
      ;;
    shrinkwrap)
      printf 'this project has an npm-shrinkwrap.json. Passflow skills cannot change it; they update package-lock.json, pnpm-lock.yaml or yarn.lock only. Remove the shrinkwrap or integrate by hand.\n'
      ;;
    mismatch:*)
      declared="${1#mismatch:}"
      lock="${declared#*:}"
      declared="${declared%%:*}"
      printf 'package.json names %s in packageManager, but the lockfile belongs to %s. Make them agree (remove the stale lockfile or fix packageManager), then run again.\n' \
        "$(pf_pm_tool "$declared")" "$(pf_pm_tool "$lock")"
      ;;
    *)
      printf 'this project uses %s. Passflow skills support npm, pnpm and Yarn 1 (classic) only.\n' "$1"
      ;;
  esac
}

# pf_pm_tool PM: the command for a supported manager (yarn-classic -> yarn).
pf_pm_tool() {
  case "$1" in
    yarn-classic) printf 'yarn\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# pf_package_spec @passflow/node PASSFLOW_NODE_VERSION -> "@passflow/node" or "@passflow/node@0.2.0".
pf_package_spec() {
  local name="$1" var="$2" version=''
  case "$var" in
    '' | *[!A-Za-z0-9_]* | [0-9]*) ;;
    *) version="${!var:-}" ;;
  esac
  if [ -n "$version" ]; then
    printf '%s@%s\n' "$name" "$version"
  else
    printf '%s\n' "$name"
  fi
}

# pf_install_line npm @passflow/node PASSFLOW_NODE_VERSION prints:
#   npm install "@passflow/node${PASSFLOW_NODE_VERSION:+@$PASSFLOW_NODE_VERSION}"
pf_install_line() {
  local pm="$1" name="$2" var="$3" cmd
  case "$pm" in
    npm) cmd='npm install' ;;
    pnpm) cmd='pnpm add' ;;
    yarn-classic) cmd='yarn add' ;;
    *) return 2 ;;
  esac
  # The dollar signs are literal: the line is shown to the user, who runs it.
  # shellcheck disable=SC2016
  printf '%s "%s${%s:+@$%s}"\n' "$cmd" "$name" "$var" "$var"
}

# pf_install DIR [PM]: installs the project's dependencies with lifecycle scripts off. PM defaults to
# pf_detect_pm DIR; pass it for a folder whose lockfile lives in a parent.
pf_install() {
  local dir="$1" pm="${2:-}"
  [ -n "$pm" ] || pm="$(pf_detect_pm "$dir")"
  case "$pm" in
    npm) (cd "$dir" && npm install --ignore-scripts --no-audit --no-fund) ;;
    pnpm) (cd "$dir" && pnpm install --ignore-scripts) ;;
    yarn-classic) (cd "$dir" && yarn install --ignore-scripts) ;;
    *)
      printf 'REFUSED: %s\n' "$(pf_pm_refusal "$pm")" >&2
      return 2
      ;;
  esac
}

# pf_run_script DIR NAME [PM]
pf_run_script() {
  local dir="$1" name="$2" pm="${3:-}"
  [ -n "$pm" ] || pm="$(pf_detect_pm "$dir")"
  case "$pm" in
    npm) (cd "$dir" && npm run --silent "$name") ;;
    pnpm) (cd "$dir" && pnpm run --silent "$name") ;;
    yarn-classic) (cd "$dir" && yarn run --silent "$name") ;;
    *) return 2 ;;
  esac
}

# pf_exec DIR COMMAND [ARGS...]: runs a binary installed in the project, never one fetched for the run.
pf_exec() {
  local dir="$1" bin="$2"
  shift 2
  if [ ! -x "$dir/node_modules/.bin/$bin" ]; then
    printf '%s is not installed in %s/node_modules/.bin\n' "$bin" "$dir" >&2
    return 127
  fi
  (cd "$dir" && "./node_modules/.bin/$bin" "$@")
}

# pf_typecheck DIR [PM]: the `typecheck` script if there is one, else tsc when tsconfig.json exists:
# `tsc -b --noEmit` for a tsconfig.json with project references (a solution-style file such as Vite's,
# where plain `tsc --noEmit` checks nothing), `tsc -p tsconfig.json --noEmit` otherwise.
# Returns 3 when there is nothing to check. Under `set -e`, call it as `rc=0; pf_typecheck "$dir" || rc=$?`.
pf_typecheck() {
  local dir="$1" pm="${2:-}"
  if pf_has_script "$dir" typecheck; then
    pf_run_script "$dir" typecheck "$pm"
    return $?
  fi
  if [ -f "$dir/tsconfig.json" ]; then
    if grep -q '"references"[[:space:]]*:' "$dir/tsconfig.json" 2>/dev/null; then
      pf_exec "$dir" tsc -b --noEmit
    else
      pf_exec "$dir" tsc -p tsconfig.json --noEmit
    fi
    return $?
  fi
  return 3
}

# ---------------------------------------------------------------- env file

# Reads NAME=VALUE lines. Accepts `export NAME=VALUE` and one pair of surrounding quotes. Skips comments.
# Prints "NAME<TAB>VALUE" lines on stdout for internal use only: callers must never echo them.
_pf_env_pairs() {
  local file="$1" line name value
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      '' | '#'*) continue ;;
    esac
    line="${line#export }"
    case "$line" in
      *=*) ;;
      *) continue ;;
    esac
    name="${line%%=*}"
    name="$(printf '%s' "$name" | tr -d ' \t')"
    value="${line#*=}"
    case "$name" in
      '' | *[!A-Za-z0-9_]* | [0-9]*) continue ;;
    esac
    # Spaces around "=" and at the end do not count.
    value="${value#"${value%%[![:space:]]*}"}"
    case "$value" in
      \"*)
        # A quoted value ends at its closing quote; anything after it (a comment) is dropped.
        value="${value#\"}"
        value="${value%%\"*}"
        ;;
      \'*)
        value="${value#\'}"
        value="${value%%\'*}"
        ;;
      *)
        # Unquoted: " #" starts a comment, as in the dotenv loaders of Node.js, Next.js and Vite.
        case "$value" in
          '#'*) value='' ;;
          *[[:space:]]'#'*) value="$(printf '%s' "$value" | sed 's/[[:space:]]#.*$//')" ;;
        esac
        value="${value%"${value##*[![:space:]]}"}"
        ;;
    esac
    printf '%s\t%s\n' "$name" "$value"
  done <"$file"
}

# The value of NAME in FILE (the last assignment wins), for internal use only: never print it.
_pf_env_value() {
  _pf_env_pairs "$1" | awk -F '\t' -v n="$2" '$1 == n { v = substr($0, length(n) + 2) } END { printf "%s", v }'
}

# pf_env_missing_keys FILE KEY...: prints each KEY that has no non-empty value in FILE.
pf_env_missing_keys() {
  local file="$1" key
  shift
  for key in "$@"; do
    if [ -z "$(_pf_env_value "$file" "$key")" ]; then
      printf '%s\n' "$key"
    fi
  done
}

# pf_load_env FILE KEY...: exports each KEY that FILE assigns, and nothing else from FILE. Values are never
# evaluated, expanded or printed. The app reads the rest of its env file itself.
pf_load_env() {
  local file="$1" name value
  shift
  [ -f "$file" ] || return 1
  while IFS="$(printf '\t')" read -r name value; do
    [ -n "$name" ] || continue
    case " $* " in
      *" $name "*) export "$name=$value" ;;
    esac
  done < <(_pf_env_pairs "$file")
}

# pf_git_tracked DIR FILE: 0 when git tracks FILE. Outside a git repo: 1.
pf_git_tracked() {
  local dir="$1" file="$2"
  command -v git >/dev/null 2>&1 || return 1
  (cd "$dir" && git rev-parse --is-inside-work-tree >/dev/null 2>&1) || return 1
  (cd "$dir" && git ls-files --error-unmatch -- "$file" >/dev/null 2>&1)
}

# ---------------------------------------------------------------- scans

# _pf_scan_value DIR NAME SOURCE VALUE: prints "<file>: value of NAME (SOURCE)" for each file under DIR
# that holds VALUE; returns 1 when one does or the search could not run. The value reaches grep through a pipe,
# never a command line that `ps` could show nor a file left behind on a signal. Values shorter than 8
# characters are not searched (they would match by chance).
_pf_scan_value() {
  local dir="$1" name="$2" source="$3" value="$4" hits
  [ "${#value}" -ge 8 ] || return 0
  hits="$(printf '%s\n' "$value" | grep -rlF -f - -- "$dir" 2>/dev/null)" || [ "$?" -eq 1 ] || {
    printf '  could not search for the value of %s (%s)\n' "$name" "$source"
    return 1
  }
  [ -n "$hits" ] || return 0
  printf '%s\n' "$hits" | while IFS= read -r f; do printf '  %s: value of %s (%s)\n' "$f" "$name" "$source"; done
  return 1
}

# _pf_scan_values DIR ENV_FILE NAME: searches DIR for NAME's value from ENV_FILE and, when it
# differs, for the value NAME has in this process's environment (a CI secret store, for example).
_pf_scan_values() {
  local dir="$1" env_file="$2" name="$3" file_value='' env_value='' found=0
  case "$name" in
    '' | *[!A-Za-z0-9_]* | [0-9]*) return 0 ;;
  esac
  if [ -n "$env_file" ] && [ -f "$env_file" ]; then
    file_value="$(_pf_env_value "$env_file" "$name")"
    _pf_scan_value "$dir" "$name" "$(basename "$env_file")" "$file_value" || found=1
  fi
  env_value="${!name:-}"
  if [ -n "$env_value" ] && [ "$env_value" != "$file_value" ]; then
    _pf_scan_value "$dir" "$name" environment "$env_value" || found=1
  fi
  file_value=''
  env_value=''
  return "$found"
}

# pf_scan_bundle BUNDLE_DIR ENV_FILE NAME...: searches built client files for each env NAME and for each
# NAME's value, from ENV_FILE when it exists and from the environment when NAME is set there. Prints
# "<file>: <NAME>" or "<file>: value of <NAME> (<source>)" per hit, never the value. An empty ENV_FILE
# searches the names only. Returns 0 clean, 1 found, 3 when BUNDLE_DIR does not exist.
pf_scan_bundle() {
  local bundle="$1" env_file="$2" name hits found=0
  shift 2
  [ -d "$bundle" ] || return 3
  for name in "$@"; do
    hits="$(grep -rlF -- "$name" "$bundle" 2>/dev/null || true)"
    if [ -n "$hits" ]; then
      found=1
      printf '%s\n' "$hits" | while IFS= read -r f; do printf '  %s: %s\n' "$f" "$name"; done
    fi
    if [ -n "$env_file" ]; then
      _pf_scan_values "$bundle" "$env_file" "$name" || found=1
    fi
  done
  return "$found"
}

# pf_scan_values DIR ENV_FILE 'GLOB...' NAME...: like pf_scan_bundle, but values only and only in files whose
# name matches one of the space-separated *.ext GLOBs (server output that is sent to browsers, for example).
# Returns 0 clean, 1 found, 3 when DIR does not exist.
pf_scan_values() {
  local dir="$1" env_file="$2" globs="$3" name glob ends='' out found=0
  shift 3
  [ -d "$dir" ] || return 3
  set -f
  for glob in $globs; do ends="$ends|\\${glob#\*}"; done
  for name in "$@"; do
    out="$(_pf_scan_values "$dir" "$env_file" "$name")" && continue
    printf '%s\n' "$out" | grep -E "(${ends#|}): value of|^  could not"
    [ "${PIPESTATUS[1]}" -eq 1 ] || found=1
  done
  set +f
  return "$found"
}

# Source files of the app: TypeScript and JavaScript outside dependencies and build output.
_pf_source_files() {
  find "$1" \
    \( -name node_modules -o -name .git -o -name .next -o -name .output -o -name .vinxi -o -name .nitro \
       -o -name .tanstack -o -name dist -o -name build -o -name coverage -o -name .turbo -o -name .vercel \) -prune \
    -o -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.mjs' -o -name '*.cjs' \) \
    -print 2>/dev/null
}

# Prints "<file>:<line>" for each line of FILES that matches the extended regex. Never the line itself,
# which could hold a value.
_pf_grep_lines() {
  local pattern="$1" files="$2" flags="${3:-}"
  [ -n "$files" ] || return 0
  printf '%s\n' "$files" | while IFS= read -r f; do
    # shellcheck disable=SC2086
    grep -nE $flags -- "$pattern" "$f" 2>/dev/null | cut -d: -f1 | while IFS= read -r n; do printf '%s:%s\n' "$f" "$n"; done
  done
}

# Prints "<file>:<line>" for each <Link ...> opening tag in FILES whose href or to points at /auth/, the tag
# split over several lines included (Prettier puts each prop on its own line). The tag ends at the first ">"
# outside braces, so `onClick={() => go()}` before href does not end it.
_pf_auth_link_lines() {
  local files="$1"
  [ -n "$files" ] || return 0
  printf '%s\n' "$files" | while IFS= read -r f; do
    awk -v file="$f" -v target="(href|to)=[{\"'\`]*/auth/" '
      {
        rest = $0
        while (rest != "") {
          if (!inside) {
            i = index(rest, "<Link")
            if (i == 0) break
            after = substr(rest, i + 5, 1)
            rest = substr(rest, i + 5)
            if (after != "" && after !~ /[[:space:]>]/) continue
            inside = 1; start = NR; tag = ""; depth = 0
          }
          # Walk to the ">" that closes the tag, counting braces.
          n = length(rest); j = 0
          for (k = 1; k <= n; k++) {
            c = substr(rest, k, 1)
            if (c == "{") depth++
            else if (c == "}" && depth > 0) depth--
            else if (c == ">" && depth == 0) { j = k; break }
          }
          if (j == 0) { tag = tag " " rest; break }
          tag = tag " " substr(rest, 1, j - 1)
          rest = substr(rest, j + 1)
          inside = 0
          if (tag ~ target) print file ":" start
        }
      }' "$f" 2>/dev/null
  done
}

_PF_SCAN_FOUND=0

# _pf_report RULE HITS: prints each hit under its rule and records that something was found.
_pf_report() {
  if [ -n "$2" ]; then
    _PF_SCAN_FOUND=1
    printf '%s\n' "$2" | while IFS= read -r h; do printf '  %s: %s\n' "$1" "$h"; done
  fi
}

# pf_guardrail_scan DIR KIND: source-only checks. KIND is server (Next.js, TanStack Start), spa or api.
# Prints "  <rule>: <file>:<line>" per finding. Returns 0 clean, 1 found.
pf_guardrail_scan() {
  local dir="$1" kind="$2" files hits auth_files=''
  _PF_SCAN_FOUND=0
  files="$(_pf_source_files "$dir")"

  hits="$(_pf_grep_lines 'NEXT_PUBLIC_[A-Z0-9_]*SECRET' "$files")"
  _pf_report 'secret in a NEXT_PUBLIC_ variable' "$hits"
  hits="$(_pf_grep_lines 'VITE_[A-Z0-9_]*SECRET' "$files")"
  _pf_report 'secret in a VITE_ variable' "$hits"

  hits="$(_pf_grep_lines "(from|require\\()[[:space:]]*['\"](jwt-decode|jsonwebtoken)['\"]|jwtDecode[[:space:]]*\\(" "$files")"
  _pf_report 'hand-decoded token (use createVerifier)' "$hits"

  # atob() or a base64 Buffer decode, in files that handle tokens.
  if [ -n "$files" ]; then
    auth_files="$(printf '%s\n' "$files" | while IFS= read -r f; do
      if grep -qiE 'token|bearer|authorization|passflow' "$f" 2>/dev/null; then printf '%s\n' "$f"; fi
    done)"
  fi
  hits="$(_pf_grep_lines "atob[[:space:]]*\\(|Buffer\\.from\\([^)]*['\"]base64(url)?['\"]" "$auth_files")"
  _pf_report 'hand-decoded token (use createVerifier)' "$hits"

  if [ "$kind" = server ]; then
    hits="$(_pf_grep_lines '(localStorage|sessionStorage).*token|token.*(localStorage|sessionStorage)' "$files" -i)"
    _pf_report 'token in browser storage' "$hits"
  fi

  if [ "$kind" = server ] || [ "$kind" = spa ]; then
    hits="$(_pf_auth_link_lines "$files")"
    _pf_report 'sign-in or sign-out link must be a plain <a href>' "$hits"
  fi

  return "$_PF_SCAN_FOUND"
}

# ---------------------------------------------------------------- HTTP

# pf_http OUT_DIR METHOD URL [CURL_ARGS...]: one request, no redirects followed. Writes OUT_DIR/status,
# OUT_DIR/headers and OUT_DIR/body. Returns curl's exit code.
pf_http() {
  local out="$1" method="$2" url="$3" rc=0
  shift 3
  mkdir -p "$out"
  : >"$out/headers"
  : >"$out/body"
  curl --noproxy '*' -sS -X "$method" --max-time 15 -o "$out/body" -D "$out/headers" -w '%{http_code}' "$@" -- "$url" \
    >"$out/status" 2>"$out/error" || rc=$?
  return "$rc"
}

# pf_header OUT_DIR NAME: the first value of a response header, case-insensitive, without the CR.
pf_header() {
  local out="$1" name="$2"
  tr -d '\r' <"$out/headers" | awk -v n="$name" '
    BEGIN { n = tolower(n) ":" }
    { i = index($0, ":"); if (i > 0 && tolower(substr($0, 1, i)) == n) { v = substr($0, i + 1); sub(/^[ \t]+/, "", v); print v; exit } }'
}

# pf_wait_http URL SECONDS [PID]: waits until URL answers with any HTTP status. With PID, gives up as soon
# as that process has exited (returns 1), so a server that failed to start is never mistaken for one that
# answers.
pf_wait_http() {
  local url="$1" seconds="$2" pid="${3:-}" i=0 code
  while [ "$i" -lt "$seconds" ]; do
    if [ -n "$pid" ] && ! pf_alive "$pid"; then
      return 1
    fi
    code="$(curl --noproxy '*' -s -o /dev/null -w '%{http_code}' --max-time 2 -- "$url" 2>/dev/null || true)"
    if [ -n "$code" ] && [ "$code" != 000 ]; then
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

# pf_port_free PORT: 0 when nothing accepts a connection on PORT at 127.0.0.1 or at localhost (which may be
# ::1). Any listener counts, HTTP or not.
pf_port_free() {
  local port="$1" host rc
  for host in 127.0.0.1 localhost; do
    rc=0
    curl --noproxy '*' -s -o /dev/null --max-time 2 -- "http://$host:$port/" 2>/dev/null || rc=$?
    # 7: connection refused. Anything else, success included, means something listens.
    [ "$rc" -eq 7 ] || return 1
  done
  return 0
}

# pf_has_token LIST TOKEN: 0 when the comma-separated header value LIST holds TOKEN as a whole item,
# case-insensitive ("WWW-Authenticate" is in "Content-Type, www-authenticate", not in "X-WWW-Authenticate").
pf_has_token() {
  printf '%s\n' "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -qixF -- "$2"
}

# pf_listener_owned PORT PID: 0 when every process listening on PORT is PID or runs under it, 1 when one is
# not (another server owns the port), 3 when that cannot be told (no lsof, or lsof sees no listener).
pf_listener_owned() {
  local port="$1" pid="$2" listeners tree p
  command -v lsof >/dev/null 2>&1 || return 3
  listeners="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | LC_ALL=C sort -u || true)"
  [ -n "$listeners" ] || return 3
  tree=" $(_pf_tree "$pid" | tr '\n' ' ') "
  for p in $listeners; do
    case "$tree" in
      *" $p "*) ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# pf_check_listener PORT PID: one PASS, FAIL or SKIP line on whether the server that answers on PORT is the
# one verify.sh started (PID or a process under it).
pf_check_listener() {
  local rc=0
  pf_listener_owned "$1" "$2" || rc=$?
  case "$rc" in
    0) pf_pass "port $1 is served by the process verify.sh started" ;;
    1) pf_fail "port $1 is served by the process verify.sh started" "another process listens on port $1" ;;
    *) pf_skip "listener owner" "lsof is not available or saw no listener on port $1" ;;
  esac
}

# pf_port_busy_refusal PORT: the message for a port that is already taken.
pf_port_busy_refusal() {
  printf 'something already listens on port %s. Stop it or pass a free port with --port; verify.sh tests only a server it starts itself.\n' "$1"
}

# ---------------------------------------------------------------- processes

# pf_start_bg DIR LOG_FILE COMMAND [ARGS...]: starts COMMAND in DIR in the background; sets PF_BG_PID.
pf_start_bg() {
  local dir="$1" log="$2"
  shift 2
  (cd "$dir" && exec "$@") >"$log" 2>&1 &
  # Read by the sourcing script.
  # shellcheck disable=SC2034
  PF_BG_PID=$!
}

# pf_alive PID: 0 while PID runs (a zombie left by an exited child does not count).
pf_alive() {
  local state
  kill -0 "$1" 2>/dev/null || return 1
  state="$(ps -o stat= -p "$1" 2>/dev/null || true)"
  case "$state" in
    Z*) return 1 ;;
  esac
  return 0
}

# _pf_children PID: the direct children of PID, one per line. Uses pgrep, else ps, else /proc, so it works
# in slim images without procps.
_pf_children() {
  local pid="$1" stat_file stat ppid
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -P "$pid" 2>/dev/null || true
  elif command -v ps >/dev/null 2>&1; then
    ps -A -o pid= -o ppid= 2>/dev/null | awk -v p="$pid" '$2 == p { print $1 }' || true
  elif [ -d /proc ]; then
    for stat_file in /proc/[0-9]*/stat; do
      [ -r "$stat_file" ] || continue
      stat="$(cat "$stat_file" 2>/dev/null || true)"
      # The command name in field 2 may hold spaces: the fields after it start at the last ")".
      stat="${stat##*) }"
      ppid="$(printf '%s' "$stat" | cut -d' ' -f2)"
      if [ "$ppid" = "$pid" ]; then
        stat_file="${stat_file#/proc/}"
        printf '%s\n' "${stat_file%/stat}"
      fi
    done
  fi
}

# _pf_tree PID: PID and every process under it, parents first.
_pf_tree() {
  local child
  printf '%s\n' "$1"
  for child in $(_pf_children "$1"); do
    _pf_tree "$child"
  done
}

# pf_kill_tree PID: stops PID and every process under it: TERM, up to 5 s to exit, then KILL.
pf_kill_tree() {
  local pid="$1" pids p i=0 left
  [ -n "$pid" ] || return 0
  # The whole tree is listed first: a wrapper (npm, yarn) that exits on TERM would orphan its children.
  pids="$(_pf_tree "$pid")"
  for p in $pids; do
    kill "$p" 2>/dev/null || true
  done
  while [ "$i" -lt 10 ]; do
    left=''
    for p in $pids; do
      if pf_alive "$p"; then left="$left $p"; fi
    done
    [ -n "$left" ] || break
    sleep 0.5
    i=$((i + 1))
  done
  for p in $pids; do
    if pf_alive "$p"; then kill -9 "$p" 2>/dev/null || true; fi
  done
  wait "$pid" 2>/dev/null || true
}

# pf_traps CLEANUP_FUNCTION: runs CLEANUP_FUNCTION on exit, and on INT or TERM runs it and exits 130 or 143,
# so an interrupted run never carries on with its checks.
pf_traps() {
  # The function name is expanded now, on purpose.
  # shellcheck disable=SC2064
  trap "$1" EXIT
  # shellcheck disable=SC2064
  trap "$1; trap - EXIT; exit 130" INT
  # shellcheck disable=SC2064
  trap "$1; trap - EXIT; exit 143" TERM
}
