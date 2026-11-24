#!/usr/bin/env bash
# Repository checks, run locally and in CI.
#
#   bash tools/check.sh
#
# 1. Every JSON file parses; the marketplace and plugin manifests have their required fields.
#    skills/index.json has exactly the schema-1 fields (an unknown field anywhere fails), and no file a
#    skill writes is both allowed and denied. Each skill's scripts/index.json is a byte-identical copy.
# 2. Every skills/*/SKILL.md has frontmatter with name = its directory, a description of at most
#    1024 characters, and no keys other than name, description, compatibility and license (which must be MIT).
# 3. Every skill in skills/index.json exists, and every skill directory is in skills/index.json.
# 4. shellcheck passes on every *.sh.
# 5. scripts/lib.sh is byte-identical in every skill. It has no here-documents or here-strings, and no loop in
#    verify.sh reads one: bash may need a temp file for it, and where it cannot create one the loop is skipped.
# 6. No image files, a LICENSE file with the MIT licence, and no banned words.
# 7. tools/test.sh passes, when it exists.
#
# Needs jq and shellcheck. Exit 0 when every check passes, 1 otherwise, 2 when a tool is missing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

for tool in jq shellcheck; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'REFUSED: %s is required\n' "$tool" >&2
    exit 2
  fi
done

FAILED=0
pass() { printf 'PASS %s\n' "$1"; }
fail() {
  FAILED=1
  printf 'FAIL %s: %s\n' "$1" "$2"
}

# Files of this repository, without git internals and local-only directories.
repo_files() {
  find . \( -name .git -o -name node_modules -o -path ./.claude -o -path ./ai-docs -o -path ./logs \) -prune \
    -o -type f ! -name .mcp.json ! -name .gitignore ! -name .worktreeinclude -print | sed 's|^\./||' | LC_ALL=C sort
}

FILES="$(repo_files)"

# ---------------------------------------------------------------- 1. JSON

json_ok=1
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if ! jq empty "$f" >/dev/null 2>&1; then
    fail json "$f does not parse"
    json_ok=0
  fi
done <<EOF
$(printf '%s\n' "$FILES" | grep '\.json$' || true)
EOF

require_json() {
  local file="$1" filter="$2" what="$3"
  if [ ! -f "$file" ]; then
    fail json "$file is missing"
    json_ok=0
  elif ! jq -e "$filter" "$file" >/dev/null 2>&1; then
    fail json "$file: $what"
    json_ok=0
  fi
}

require_json .claude-plugin/marketplace.json '(.name | type == "string" and length > 0)' 'needs a name'
require_json .claude-plugin/marketplace.json '(.owner.name | type == "string" and length > 0)' 'needs owner.name'
require_json .claude-plugin/marketplace.json \
  '(.plugins | type == "array" and length > 0) and all(.plugins[]; (.name | type == "string") and (.source != null))' \
  'every plugin needs a name and a source'
require_json .claude-plugin/plugin.json '(.name | type == "string" and length > 0)' 'needs a name'
require_json .claude-plugin/plugin.json '(.version | type == "string" and length > 0)' 'needs a version'
[ "$json_ok" -eq 1 ] && pass json

# ---------------------------------------------------------------- 1b. skills/index.json, strict schema 1

# Prints one line per problem. Every object has exactly its known fields: the service that reads the file
# refuses any field it does not know.
# The dollar signs are jq variables.
# shellcheck disable=SC2016
SCHEMA_CHECK='
def strs: type == "array" and all(.[]; type == "string");
def exact($allowed; $where):
  if type != "object" then "\($where): must be an object"
  else ((keys - $allowed) as $x | if ($x | length) > 0 then "\($where): unknown field(s) \($x | join(", "))" else empty end),
       (($allowed - keys) as $m | if ($m | length) > 0 then "\($where): missing field(s) \($m | join(", "))" else empty end)
  end;
def subset($of; $where): if strs and all(.[]; . as $k | $of | index($k)) then empty
  else "\($where): must be a list of names from env_keys" end;
. as $root
| exact(["schema", "package_managers", "stacks"]; "top level"),
  (if .schema != 1 then "schema must be 1" else empty end),
  (.package_managers | exact(["supported", "refused", "detect"]; "package_managers")),
  (.package_managers | select(type == "object") |
    (if (.supported | strs) and (.refused | strs) then empty else "package_managers.supported and .refused must be lists of strings" end),
    (if (.detect | type) != "array" then "package_managers.detect must be a list"
     else .detect | to_entries[] | .key as $i | .value |
       exact(["file", "manager"]; "package_managers.detect[\($i)]"),
       (select(type == "object") | (.manager // "") as $m | if (.file | type) == "string" and (.manager | type) == "string"
          and ((($root.package_managers.supported // []) + ($root.package_managers.refused // [])) | index($m)) != null
        then empty else "package_managers.detect[\($i)]: file must be a string and manager a supported or refused manager" end)
     end)),
  (if (.stacks | type) != "array" or (.stacks | length) == 0 then "stacks must be a non-empty list"
   else
     (if ([.stacks[].id] | unique | length) != (.stacks | length) then "stack ids must be unique" else empty end),
     (.stacks | to_entries[] | .key as $i | .value as $s | "stacks[\($i)] (\($s.id // "?"))" as $w |
       ($s | exact(["id", "skill", "detect", "app_type", "default_base_url", "env_file", "env_keys", "secret_env_keys",
                    "not_provisioned_env_keys", "packages", "allowed_paths", "denied_paths"]; $w)),
       ($s | select(type == "object") |
         (if (.id | type) == "string" and (.skill | type) == "string" and (.env_file | type) == "string" then empty
          else "\($w): id, skill and env_file must be strings" end),
         (if (.app_type | type) == "string" or .app_type == null then empty else "\($w): app_type must be a string or null" end),
         (if (.default_base_url | type) == "string" or .default_base_url == null then empty
          else "\($w): default_base_url must be a string or null" end),
         (if (.env_keys | strs) then empty else "\($w): env_keys must be a list of strings" end),
         (.secret_env_keys | subset($s.env_keys; "\($w).secret_env_keys")),
         (.not_provisioned_env_keys | subset($s.env_keys; "\($w).not_provisioned_env_keys")),
         (if (.allowed_paths | strs) and (.denied_paths | strs) then empty else "\($w): allowed_paths and denied_paths must be lists of strings" end),
         (.detect | if type != "object" then "\($w).detect must be an object"
                    else (keys - ["all", "any"]) as $x | if ($x | length) > 0 then "\($w).detect: unknown field(s) \($x | join(", "))" else empty end
                    end),
         (.detect | select(type == "object") |
           (if ((.all // []) | length) + ((.any // []) | length) == 0 then "\($w).detect: needs an all or any entry" else empty end),
           (["all", "any"][] as $k | select(has($k)) | .[$k] |
             if type != "array" then "\($w).detect.\($k) must be a list"
             else to_entries[] | .key as $j | .value |
               (if type != "object" then "\($w).detect.\($k)[\($j)] must be an object"
                else (keys - ["package", "range"]) as $x
                  | if ($x | length) > 0 then "\($w).detect.\($k)[\($j)]: unknown field(s) \($x | join(", "))" else empty end
                end),
               (select(type == "object") |
                 (if (.package | type) == "string" then empty else "\($w).detect.\($k)[\($j)].package must be a string" end),
                 (if has("range") and ((.range | type) != "string" or (.range | test("^>=[0-9]+(\\.[0-9]+){0,2}$") | not))
                  then "\($w).detect.\($k)[\($j)].range must look like >=16 or >=1.169" else empty end))
             end)),
         (if (.packages | type) != "array" or (.packages | length) == 0 then "\($w): packages must be a non-empty list"
          else .packages | to_entries[] | .key as $j | .value |
            exact(["name", "version_env", "env_keys"]; "\($w).packages[\($j)]"),
            (select(type == "object") |
              (if (.name | type) == "string" and (.version_env | type) == "string" and (.version_env | test("^[A-Z][A-Z0-9_]*$"))
               then empty else "\($w).packages[\($j)]: name must be a string and version_env an env var name" end),
              (.env_keys | subset($s.env_keys; "\($w).packages[\($j)].env_keys")))
          end)))
   end)
'
schema_ok=1
schema_errors="$(jq -r "$SCHEMA_CHECK" skills/index.json 2>&1)" || {
  schema_errors="jq could not run the schema check: $schema_errors"
}
if [ -n "$schema_errors" ]; then
  while IFS= read -r line; do
    fail schema "$line"
  done <<EOF
$schema_errors
EOF
  schema_ok=0
fi

# allowed_paths and denied_paths must not contradict each other for a file a skill writes. Patterns are
# matched as the service matches them: anchored at the repository root, `**` across folders, `*` within one.
glob_matches() {
  local path="$1" glob="$2" re
  re="$(printf '%s' "$glob" | sed -e 's/[].[^$+?(){}|\\]/\\&/g' -e 's/\*\*\//<DSTAR_SLASH>/g' -e 's/\*\*/<DSTAR>/g' \
    -e 's/\*/[^\/]*/g' -e 's/<DSTAR_SLASH>/(.*\/)?/g' -e 's/<DSTAR>/.*/g')"
  printf '%s\n' "$path" | grep -Eq "^${re}\$"
}
# Files the skills write.
WRITTEN='src/passflow.ts src/passflow-express.ts src/passflow-fastify.ts src/passflow-hono.ts src/passflow-fetch.ts
src/passflow.tsx src/use-api.ts src/require-sign-in.tsx src/main.tsx server/passflow.ts server/index.ts server/tsconfig.json
lib/passflow.ts proxy.ts middleware.ts src/proxy.ts src/middleware.ts app/account/page.tsx app/api/me/route.ts
components/auth-links.tsx src/lib/passflow.ts src/app/account/page.tsx src/start.ts src/routes/account.tsx
src/routes/api/me.ts src/components/auth-links.tsx package.json package-lock.json pnpm-lock.yaml yarn.lock .gitignore'
for id in $(jq -r '.stacks[]?.id // empty' skills/index.json 2>/dev/null); do
  allowed="$(jq -r --arg id "$id" '.stacks[] | select(.id == $id) | .allowed_paths[]?' skills/index.json)"
  denied="$(jq -r --arg id "$id" '.stacks[] | select(.id == $id) | .denied_paths[]?' skills/index.json)"
  for path in $WRITTEN; do
    is_allowed=0
    for g in $allowed; do
      if glob_matches "$path" "$g"; then is_allowed=1; break; fi
    done
    [ "$is_allowed" -eq 1 ] || continue
    for g in $denied; do
      if glob_matches "$path" "$g"; then
        fail schema "stack $id: $path is allowed and denied ($g)"
        schema_ok=0
      fi
    done
  done
done
[ "$schema_ok" -eq 1 ] && pass schema

# ---------------------------------------------------------------- 1c. index.json copies

copy_ok=1
for d in skills/*/; do
  [ -f "${d}SKILL.md" ] || continue
  if [ ! -f "${d}scripts/index.json" ]; then
    fail copies "${d}scripts/index.json is missing; copy skills/index.json there"
    copy_ok=0
  elif ! cmp -s skills/index.json "${d}scripts/index.json"; then
    fail copies "${d}scripts/index.json differs from skills/index.json"
    copy_ok=0
  fi
done
[ "$copy_ok" -eq 1 ] && pass copies

# ---------------------------------------------------------------- 1d. SKILL.md targets are allowed paths

# The Target column of each SKILL.md asset table, one path per line ("not copied" rows left out).
skill_targets() {
  awk -F'|' '$2 ~ /^[[:space:]]*`assets\// {
      t = $3
      while (match(t, /`[^`]+`/)) { print substr(t, RSTART + 1, RLENGTH - 2); t = substr(t, RSTART + RLENGTH) }
    }' "$1"
}
# Every place a target can land, as the skill describes it: <root>/ is the app folder (Next.js: the project
# root or src/; TanStack Start: src/ or app/), a bare file name sits in the API folder (React + Vite: server/
# or api/), and a Node API without src/ puts each src/ target in lib/.
expand_target() {
  local id="$1" t="$2" r
  case "$id:$t" in
    nextjs:'<root>/'*) for r in '' src/; do printf '%s%s\n' "$r" "${t#<root>/}"; done ;;
    tanstack-start:'<root>/'*) for r in src/ app/; do printf '%s%s\n' "$r" "${t#<root>/}"; done ;;
    react-vite:*/*) printf '%s\n' "$t" ;;
    react-vite:*) for r in server/ api/ server/src/ api/src/; do printf '%s%s\n' "$r" "$t"; done ;;
    node-api:src/*) printf '%s\n%s\n' "$t" "lib/${t#src/}" ;;
    *) printf '%s\n' "$t" ;;
  esac
}
targets_ok=1
for id in $(jq -r '.stacks[]?.id // empty' skills/index.json 2>/dev/null); do
  skill="$(jq -r --arg id "$id" '.stacks[] | select(.id == $id) | .skill' skills/index.json)"
  [ -f "skills/$skill/SKILL.md" ] || continue
  allowed="$(jq -r --arg id "$id" '.stacks[] | select(.id == $id) | .allowed_paths[]?' skills/index.json)"
  denied="$(jq -r --arg id "$id" '.stacks[] | select(.id == $id) | .denied_paths[]?' skills/index.json)"
  count=0
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      count=$((count + 1))
      is_allowed=0
      for g in $allowed; do
        if glob_matches "$path" "$g"; then is_allowed=1; break; fi
      done
      if [ "$is_allowed" -eq 0 ]; then
        fail targets "skills/$skill/SKILL.md target $path (from $target) is not in the $id allowed_paths"
        targets_ok=0
      fi
      for g in $denied; do
        if glob_matches "$path" "$g"; then
          fail targets "skills/$skill/SKILL.md target $path (from $target) matches the $id denied_paths ($g)"
          targets_ok=0
        fi
      done
    done <<EOF
$(expand_target "$id" "$target")
EOF
  done <<EOF
$(skill_targets "skills/$skill/SKILL.md")
EOF
  if [ "$count" -eq 0 ]; then
    fail targets "skills/$skill/SKILL.md has no asset table with a Target column"
    targets_ok=0
  fi
done
[ "$targets_ok" -eq 1 ] && pass targets

# ---------------------------------------------------------------- 2. SKILL.md frontmatter

fm_ok=1
for skill_md in skills/*/SKILL.md; do
  [ -f "$skill_md" ] || continue
  dir="$(basename "$(dirname "$skill_md")")"
  if [ "$(head -n 1 "$skill_md")" != '---' ]; then
    fail frontmatter "$skill_md does not start with ---"
    fm_ok=0
    continue
  fi
  frontmatter="$(awk 'NR == 1 { next } /^---[[:space:]]*$/ { exit } { print }' "$skill_md")"
  name="$(printf '%s\n' "$frontmatter" | sed -n 's/^name:[[:space:]]*//p' | head -n 1)"
  description="$(printf '%s\n' "$frontmatter" | sed -n 's/^description:[[:space:]]*//p' | head -n 1)"
  keys="$(printf '%s\n' "$frontmatter" | sed -n 's/^\([A-Za-z_-][A-Za-z0-9_-]*\):.*/\1/p')"
  if [ "$name" != "$dir" ]; then
    fail frontmatter "$skill_md: name '$name' must be '$dir'"
    fm_ok=0
  fi
  case "$description" in
    '' | '>'* | '|'*)
      fail frontmatter "$skill_md: description must be a non-empty single line"
      fm_ok=0
      ;;
  esac
  if [ "${#description}" -gt 1024 ]; then
    fail frontmatter "$skill_md: description is ${#description} characters; the limit is 1024"
    fm_ok=0
  fi
  for key in $keys; do
    case "$key" in
      name | description | compatibility) ;;
      license)
        if [ "$(printf '%s\n' "$frontmatter" | sed -n 's/^license:[[:space:]]*//p')" != MIT ]; then
          fail frontmatter "$skill_md: license must be MIT"
          fm_ok=0
        fi
        ;;
      *)
        fail frontmatter "$skill_md: key '$key' is not allowed (name, description, compatibility, license)"
        fm_ok=0
        ;;
    esac
  done
done
[ "$fm_ok" -eq 1 ] && pass frontmatter

# ---------------------------------------------------------------- 3. index.json <-> skill directories

idx_ok=1
while IFS= read -r skill; do
  [ -n "$skill" ] || continue
  if [ ! -f "skills/$skill/SKILL.md" ]; then
    fail index "skills/index.json names $skill, but skills/$skill/SKILL.md does not exist"
    idx_ok=0
  fi
done <<EOF
$(jq -r '.stacks[]?.skill // empty' skills/index.json 2>/dev/null || true)
EOF
for d in skills/*/; do
  [ -d "$d" ] || continue
  skill="$(basename "$d")"
  if ! jq -e --arg s "$skill" 'any(.stacks[]; .skill == $s)' skills/index.json >/dev/null 2>&1; then
    fail index "skills/$skill is not in skills/index.json"
    idx_ok=0
  fi
done
[ "$idx_ok" -eq 1 ] && pass index

# ---------------------------------------------------------------- 4. shellcheck

sh_files="$(printf '%s\n' "$FILES" | grep '\.sh$' || true)"
if [ -n "$sh_files" ]; then
  # shellcheck disable=SC2086
  if (printf '%s\n' "$sh_files" | tr '\n' '\0' | xargs -0 shellcheck -x); then
    pass shellcheck
  else
    fail shellcheck "see the output above"
  fi
else
  pass shellcheck
fi

# ---------------------------------------------------------------- 5. lib.sh identical

lib_ok=1
master=''
for lib in skills/*/scripts/lib.sh; do
  [ -f "$lib" ] || continue
  if [ -z "$master" ]; then
    master="$lib"
  elif ! cmp -s "$master" "$lib"; then
    fail lib "$lib differs from $master"
    lib_ok=0
  fi
  line="$(grep -n '<<' "$lib" | head -1 | cut -d: -f1 || true)"
  if [ -n "$line" ]; then
    fail lib "$lib has a here-document or here-string (line $line)"
    lib_ok=0
  fi
done
for d in skills/*/; do
  [ -d "$d" ] || continue
  if [ -f "${d}scripts/verify.sh" ] && [ ! -f "${d}scripts/lib.sh" ]; then
    fail lib "${d}scripts/lib.sh is missing"
    lib_ok=0
  fi
  if [ -f "${d}scripts/verify.sh" ] && grep -qE '^[[:space:]]*done.*<<' "${d}scripts/verify.sh"; then
    fail lib "${d}scripts/verify.sh has a loop that reads a here-document or here-string"
    lib_ok=0
  fi
done
[ "$lib_ok" -eq 1 ] && pass lib

# ---------------------------------------------------------------- 6. content rules

content_ok=1
images="$(printf '%s\n' "$FILES" | grep -iE '\.(png|jpe?g|gif|webp|svg|ico|bmp|tiff?|avif|heic)$' || true)"
if [ -n "$images" ]; then
  fail content "image files are not allowed: $(printf '%s' "$images" | tr '\n' ' ')"
  content_ok=0
fi
if ! head -n 1 LICENSE 2>/dev/null | grep -qx "MIT License"; then
  fail content "LICENSE must exist and hold the MIT License"
  content_ok=0
fi
if [ "$(jq -r .license .claude-plugin/plugin.json)" != MIT ] || [ "$(jq -r ".plugins[0].license" .claude-plugin/marketplace.json)" != MIT ]; then
  fail content "plugin.json and marketplace.json must say license MIT"
  content_ok=0
fi

# Text files, without this script (it names the banned words).
text_files="$(printf '%s\n' "$FILES" | grep -v '^tools/check\.sh$' | grep -viE '\.(png|jpe?g|gif|webp|ico|bmp|tgz|gz|zip)$' || true)"
scan() {
  local rule="$1" pattern="$2" flags="$3" hits
  [ -n "$text_files" ] || return 0
  # shellcheck disable=SC2086
  hits="$(printf '%s\n' "$text_files" | tr '\n' '\0' | xargs -0 grep -nE $flags -- "$pattern" 2>/dev/null | cut -d: -f1,2 || true)"
  if [ -n "$hits" ]; then
    fail content "$rule: $(printf '%s' "$hits" | tr '\n' ' ')"
    content_ok=0
  fi
}
scan 'the phrase "open source"' 'open[- ]source' '-i'
scan 'issue tracker reference' '\bLinear\b|\bPFL-[0-9]+|\btickets?\b' ''
scan 'work-plan reference' '\bphase [0-9]+\b' '-i'
[ "$content_ok" -eq 1 ] && pass content

# ---------------------------------------------------------------- 7. tools/test.sh

if [ -f tools/test.sh ]; then
  if bash tools/test.sh; then
    pass tests
  else
    fail tests "tools/test.sh failed"
  fi
else
  printf 'SKIP tests: tools/test.sh does not exist\n'
fi

if [ "$FAILED" -eq 0 ]; then
  printf 'RESULT pass\n'
  exit 0
fi
printf 'RESULT fail\n'
exit 1
