#!/usr/bin/env bash
#
# Tests the run block of .github/workflows/sync-upstream.yml against local bare
# repos standing in for origin and upstream, with a `gh` stub.
#
# The script under test is extracted from the YAML at runtime (not copied here),
# so edits to the workflow are covered automatically. Only the upstream remote
# URL is rewritten, to point at a local path.
#
# Covers: already-up-to-date, clean merge, conflict, and conflict-with-existing-PR.
# The `gh` calls hit a stub, so GitHub's API and token permissions are NOT
# exercised — only the git logic, control flow, exit codes, and CLI arguments.
#
# Usage:  bash tests/test_sync_upstream_workflow.sh
# Requires: git, python3 with PyYAML.
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WF="$REPO_ROOT/.github/workflows/sync-upstream.yml"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
PASS=0
FAIL=0

check() { # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then
    echo "    ok   $1"
    PASS=$((PASS + 1))
  else
    echo "    FAIL $1: expected '$2' got '$3'"
    FAIL=$((FAIL + 1))
  fi
}

# Replace line N of a file. Portable: `sed -i` differs between BSD and GNU.
set_line() { # set_line <n> <text> <file>
  awk -v n="$1" -v t="$2" 'NR==n{$0=t}1' "$3" > "$3.tmp" && mv "$3.tmp" "$3"
}

python3 - "$WF" "$ROOT/script.sh" <<'PY' || { echo "extract failed (is PyYAML installed?)"; exit 1; }
import sys, yaml
wf, out = sys.argv[1], sys.argv[2]
d = yaml.safe_load(open(wf))
run = d["jobs"]["sync"]["steps"][1]["run"]
assert "https://github.com/CursorTouch/Web-Use.git" in run, "upstream URL not found"
open(out, "w").write(run.replace("https://github.com/CursorTouch/Web-Use.git",
                                 "UPSTREAM_URL_PLACEHOLDER"))
PY
[ -s "$ROOT/script.sh" ] || { echo "could not extract run block"; exit 1; }

# gh stub: logs argv, optionally fails `pr create` to exercise the fallback.
mkdir -p "$ROOT/bin"
cat > "$ROOT/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$@" >> "$GH_LOG"
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "create" ] && [ -n "${GH_CREATE_FAIL:-}" ]; then
  echo "gh: pull request already exists" >&2
  exit 1
fi
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "list" ]; then
  echo "https://example.invalid/pr/1"
fi
exit 0
STUB
chmod +x "$ROOT/bin/gh"

ID() { git -c user.name=t -c user.email=t@t "$@"; }

setup() { # setup <scenario-name> <none|clean|conflict>
  local name="$1"
  local mode="$2"
  local d="$ROOT/$name"
  rm -rf "$d"; mkdir -p "$d"
  git init -q --bare -b main "$d/upstream.git"
  git init -q --bare -b main "$d/origin.git"

  # Seed from a fresh non-bare repo rather than cloning an empty one, so the
  # branch is main regardless of the machine's init.defaultBranch.
  # 20 lines, so a "clean" upstream edit can sit far from the fork's edit:
  # adjacent-line edits produce overlapping hunks and would conflict.
  git init -q -b main "$d/useed"
  seq 1 20 | sed 's/^/line/' > "$d/useed/f.txt"
  ID -C "$d/useed" add f.txt
  ID -C "$d/useed" commit -qm "seed"
  ID -C "$d/useed" remote add up "$d/upstream.git"
  ID -C "$d/useed" push -q up main

  # Fork starts from that same commit (upstream is now non-empty).
  git clone -q "$d/upstream.git" "$d/fork"
  ID -C "$d/fork" remote set-url origin "$d/origin.git"
  ID -C "$d/fork" push -q origin main

  # Fork-local change on line 2 (the thing that can conflict).
  set_line 2 "FORK CHANGE" "$d/fork/f.txt"
  ID -C "$d/fork" commit -qam "fork: local change to line 2"
  ID -C "$d/fork" push -q origin main

  case "$mode" in
    none) : ;;                    # upstream does not advance
    clean)                        # upstream edits line 19: far from line 2
      set_line 19 "UPSTREAM CHANGE" "$d/useed/f.txt"
      ID -C "$d/useed" commit -qam "upstream: change line 19"
      ID -C "$d/useed" push -q up main ;;
    conflict)                     # upstream edits line 2: same line as fork
      set_line 2 "UPSTREAM CHANGE" "$d/useed/f.txt"
      ID -C "$d/useed" commit -qam "upstream: change line 2"
      ID -C "$d/useed" push -q up main ;;
  esac
}

run() { # run <scenario-name> -> echoes exit code
  local d="$ROOT/$1"
  sed "s|UPSTREAM_URL_PLACEHOLDER|$d/upstream.git|" "$ROOT/script.sh" > "$d/run.sh"
  ( cd "$d/fork" && PATH="$ROOT/bin:$PATH" GH_LOG="$d/gh.log" \
      GH_CREATE_FAIL="${GH_CREATE_FAIL:-}" bash "$d/run.sh" > "$d/out.txt" 2>&1 )
  echo $?
}

# --verify -q so a missing ref prints nothing instead of echoing the ref name.
sha() { git -C "$1" rev-parse --verify -q "$2" 2>/dev/null || echo MISSING; }

BR="refs/heads/sync/upstream-$(date -u +%Y%m%d)"

echo
echo "SCENARIO 1: upstream/main already an ancestor (nothing to do)"
setup s1 none
before=$(sha "$ROOT/s1/origin.git" main)
rc=$(run s1)
check "exit code 0" "0" "$rc"
check "origin/main untouched" "$before" "$(sha "$ROOT/s1/origin.git" main)"
check "reported up to date" "yes" \
  "$(grep -q 'Already up to date' "$ROOT/s1/out.txt" && echo yes || echo no)"
check "no gh call" "yes" "$([ ! -f "$ROOT/s1/gh.log" ] && echo yes || echo no)"

echo
echo "SCENARIO 2: upstream advances, merges cleanly"
setup s2 clean
rc=$(run s2)
up=$(sha "$ROOT/s2/upstream.git" main)
check "exit code 0" "0" "$rc"
check "origin/main contains upstream commit" "yes" \
  "$(git -C "$ROOT/s2/origin.git" merge-base --is-ancestor "$up" main && echo yes || echo no)"
check "no sync branch created" "MISSING" "$(sha "$ROOT/s2/origin.git" "$BR")"
check "no gh call" "yes" "$([ ! -f "$ROOT/s2/gh.log" ] && echo yes || echo no)"

echo
echo "SCENARIO 3: upstream conflicts"
setup s3 conflict
before=$(sha "$ROOT/s3/origin.git" main)
rc=$(run s3)
check "exit code 1 (fires failure notification)" "1" "$rc"
check "origin/main NOT modified" "$before" "$(sha "$ROOT/s3/origin.git" main)"
check "sync branch pushed at upstream sha" "$(sha "$ROOT/s3/upstream.git" main)" \
  "$(sha "$ROOT/s3/origin.git" "$BR")"
check "merge aborted, no MERGE_HEAD left" "yes" \
  "$([ ! -f "$ROOT/s3/fork/.git/MERGE_HEAD" ] && echo yes || echo no)"
check "no conflict markers left in tree" "yes" \
  "$(grep -q '<<<<<<<' "$ROOT/s3/fork/f.txt" && echo no || echo yes)"
check "gh pr create called" "yes" \
  "$(grep -q 'pr create --base main --head sync/upstream-' "$ROOT/s3/gh.log" && echo yes || echo no)"
check "error annotation emitted" "yes" \
  "$(grep -q '::error::' "$ROOT/s3/out.txt" && echo yes || echo no)"

echo
echo "SCENARIO 4: conflict, and gh pr create fails (PR already exists)"
setup s4 conflict
GH_CREATE_FAIL=1
rc=$(run s4)
check "still exits 1" "1" "$rc"
check "fell back to gh pr list" "yes" \
  "$(grep -q 'pr list --head sync/upstream-' "$ROOT/s4/gh.log" && echo yes || echo no)"
unset GH_CREATE_FAIL

echo
echo "=================================="
echo " passed: $PASS   failed: $FAIL"
echo "=================================="
[ "$FAIL" -eq 0 ]
