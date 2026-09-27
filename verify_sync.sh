#!/usr/bin/env bash
# Verify this repository is fully in sync with its remote, and that a fresh clone
# reproduces a working skill.
#
# Designed to run unchanged on a developer machine, in the sandbox, and in CI:
#   - no absolute sandbox paths
#   - no dependency on a separately installed skill-creator
#   - content comparison uses git by default (no `gh`, no network beyond fetch)
#   - `--api` additionally proves the *served* content via the GitHub API
#
# Usage:
#   ./verify_sync.sh                 # full check against origin/main
#   ./verify_sync.sh --api           # also verify the GitHub API surface (needs gh)
#   ./verify_sync.sh --offline       # local integrity only, no fetch
#   ./verify_sync.sh --skip-clone    # skip the fresh-clone stage
#   ./verify_sync.sh --json OUT      # write a machine-readable summary
#
# Exit codes:
#   0  fully in sync and reproducible
#   1  problems found
#   2  bad input / missing prerequisite

set -uo pipefail

REPO="k5801kaohom-blip/skill-drift-audit"
SKILL_NAME="skill-drift-audit"
LOCAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

USE_API=0
OFFLINE=0
SKIP_CLONE=0
JSON_OUT=""
FAIL=0
declare -a RESULTS=()

usage() { sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --api)        USE_API=1 ;;
    --offline)    OFFLINE=1 ;;
    --skip-clone) SKIP_CLONE=1 ;;
    --json)       JSON_OUT="${2:-}"; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

record() {  # status, name, detail
  RESULTS+=("$1|$2|$3")
  if [ "$1" = "FAIL" ]; then FAIL=1; fi
  printf '  [%-4s] %-46s %s\n' "$1" "$2" "$3"
}

need() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- prerequisites
for tool in git python3; do
  if ! need "$tool"; then
    echo "error: required tool not found: $tool" >&2
    exit 2
  fi
done
if [ "$USE_API" -eq 1 ] && ! need gh; then
  echo "error: --api requires the gh CLI" >&2
  exit 2
fi

cd "$LOCAL"

# ---------------------------------------------------------------- 1. commit sync
echo "######## 1. commit sync ########"
if [ "$OFFLINE" -eq 1 ]; then
  record SKIP "commit sync" "offline mode"
else
  if git fetch -q origin 2>/dev/null; then
    record PASS "fetch origin" "ok"
  else
    record FAIL "fetch origin" "could not reach the remote"
  fi
fi

LH="$(git rev-parse HEAD 2>/dev/null || echo '')"
RH="$(git rev-parse origin/main 2>/dev/null || echo '')"
AB="$(git rev-list --left-right --count HEAD...origin/main 2>/dev/null || echo 'unknown')"
DIRTY="$(git status --porcelain | wc -l | tr -d ' ')"

echo "  local  HEAD : $LH"
echo "  remote main : $RH"
echo "  ahead/behind: $AB"
echo "  dirty files : $DIRTY"

if [ "$OFFLINE" -eq 0 ]; then
  if [ -n "$LH" ] && [ "$LH" = "$RH" ]; then
    record PASS "commits in sync" "$(git rev-parse --short HEAD)"
  else
    record FAIL "commits in sync" "HEAD != origin/main"
  fi
fi
if [ "$DIRTY" -eq 0 ]; then
  record PASS "working tree clean" "0 modified files"
else
  record FAIL "working tree clean" "$DIRTY modified file(s)"
fi

# ------------------------------------------------- 2. documented-resource contract
# Inlined so CI does not need skill-creator installed. This is the check that most
# often catches a real defect: SKILL.md naming a file that was never committed.
echo
echo "######## 2. skill contract ########"
SKILL_DIR="$LOCAL/$SKILL_NAME"
if [ ! -f "$SKILL_DIR/SKILL.md" ]; then
  record FAIL "skill contract" "no $SKILL_NAME/SKILL.md"
else
  CONTRACT_OUT="$(python3 "$SKILL_DIR/scripts/check_skill_contract.py" --skill "$SKILL_DIR" 2>&1)"
  CONTRACT_RC=$?
  if [ "$CONTRACT_RC" -eq 0 ]; then
    record PASS "skill contract" "$(printf '%s\n' "$CONTRACT_OUT" | grep -c '^  \[' ) documented resources"
  else
    record FAIL "skill contract" "CONTRACT_VIOLATED"
    printf '%s\n' "$CONTRACT_OUT" | sed -n '/PROBLEMS/,/^$/p' | sed 's/^/      /'
  fi
fi

# --------------------------------------------- 3. structural validation (inlined)
echo
echo "######## 3. skill structure ########"
STRUCT_OUT="$(python3 - "$SKILL_DIR" "$SKILL_NAME" <<'PY' 2>&1
import re, sys
from pathlib import Path

skill = Path(sys.argv[1]); name = sys.argv[2]
doc = skill / "SKILL.md"
if not doc.is_file():
    print("FAIL no SKILL.md"); raise SystemExit(1)
text = doc.read_text(encoding="utf-8")
problems = []

if not text.startswith("---"):
    problems.append("missing YAML frontmatter")
else:
    parts = text.split("---", 2)
    fm = parts[1] if len(parts) >= 3 else ""
    if "name:" not in fm:
        problems.append("frontmatter missing name:")
    elif not re.search(r"^name:\s*%s\s*$" % re.escape(name), fm, re.M):
        problems.append("frontmatter name does not match the directory name")
    if "description:" not in fm:
        problems.append("frontmatter missing description:")

lines = len(text.splitlines())
if lines > 500:
    problems.append(f"SKILL.md is {lines} lines (keep under 500)")

for p in skill.rglob("*"):
    if p.is_file() and p.name in ("example.py", "example_template.txt", "api_reference.md"):
        problems.append(f"leftover scaffold: {p.relative_to(skill)}")

for f in sorted(skill.rglob("*.py")):
    try:
        compile(f.read_text(encoding="utf-8"), str(f), "exec")
    except SyntaxError as exc:
        problems.append(f"{f.relative_to(skill)} does not compile: {exc}")

if problems:
    print("FAIL")
    for p in problems:
        print(f"  - {p}")
    raise SystemExit(1)
print(f"OK {lines} lines, frontmatter valid, all python compiles")
PY
)"
STRUCT_RC=$?
if [ "$STRUCT_RC" -eq 0 ]; then
  record PASS "skill structure" "${STRUCT_OUT#OK }"
else
  record FAIL "skill structure" "validation failed"
  printf '%s\n' "$STRUCT_OUT" | sed 's/^/      /'
fi

# ------------------------------------------------------- 4. content equality
# Compares every tracked file against origin/main. This is what proves the remote
# carries the same bytes, not merely the same commit id.
echo
echo "######## 4. content equality with origin/main ########"
if [ "$OFFLINE" -eq 1 ]; then
  record SKIP "content equality" "offline mode"
else
  DIFFS=0; COUNT=0
  while IFS= read -r f; do
    COUNT=$((COUNT + 1))
    if ! git diff --quiet origin/main -- "$f" 2>/dev/null; then
      record FAIL "identical: $f" "differs from origin/main"
      DIFFS=$((DIFFS + 1))
    fi
  done < <(git ls-tree -r --name-only origin/main 2>/dev/null)
  if [ "$DIFFS" -eq 0 ]; then
    record PASS "content equality" "$COUNT files byte-identical"
  fi
fi

# ------------------------------------------------- 5. newest content is present
echo
echo "######## 5. newest sections reachable on origin/main ########"
SKILL_ON_REMOTE="$(git show origin/main:"$SKILL_NAME/SKILL.md" 2>/dev/null)"
CITIZEN_ON_REMOTE="$(git show origin/main:"$SKILL_NAME/references/citizen-developer-testing.md" 2>/dev/null)"

check_needle() {  # haystack, needle, label
  if printf '%s' "$1" | grep -qF -- "$2"; then
    record PASS "$3" "present"
  else
    record FAIL "$3" "MISSING"
  fi
}
check_needle "$SKILL_ON_REMOTE"   "citizen developer test"      "SKILL.md: citizen test step"
check_needle "$SKILL_ON_REMOTE"   "citizen_test_kit.py"         "SKILL.md: kit script named"
check_needle "$SKILL_ON_REMOTE"   "Never present one as a pass" "SKILL.md: honest reporting"
check_needle "$CITIZEN_ON_REMOTE" "PASS_WITH_FRICTION"          "reference: verdict enum"
check_needle "$CITIZEN_ON_REMOTE" "eight validity checks"       "reference: eight checks"
check_needle "$CITIZEN_ON_REMOTE" "four norms"                  "reference: four norms"

# ------------------------------------------------------ 6. API surface (opt-in)
if [ "$USE_API" -eq 1 ]; then
  echo
  echo "######## 6. GitHub API surface ########"
  if gh api "repos/$REPO/contents/$SKILL_NAME/SKILL.md" --jq '.content' 2>/dev/null \
       | base64 -d | grep -qF "citizen_test_kit.py"; then
    record PASS "API serves the current SKILL.md" "via gh api"
  else
    record FAIL "API serves the current SKILL.md" "unexpected content"
  fi
fi

# ---------------------------------------------------- 7. clone reproducibility
echo
echo "######## 7. fresh clone reproduces a working skill ########"
if [ "$SKIP_CLONE" -eq 1 ]; then
  record SKIP "fresh clone" "skipped by request"
else
  WORKDIR="$(mktemp -d)"
  if git clone -q "https://github.com/$REPO.git" "$WORKDIR/clone" 2>/dev/null; then
    record PASS "clone" "$REPO"
    bash -n "$WORKDIR/clone/install.sh" 2>/dev/null \
      && record PASS "install.sh syntax" "ok" || record FAIL "install.sh syntax" "parse error"
    bash -n "$WORKDIR/clone/package.sh" 2>/dev/null \
      && record PASS "package.sh syntax" "ok" || record FAIL "package.sh syntax" "parse error"

    SKILLS_DIR="$WORKDIR/skills" bash "$WORKDIR/clone/install.sh" >/dev/null 2>&1
    N=$(find "$WORKDIR/skills" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$N" -gt 0 ]; then
      record PASS "install from clone" "$N files"
      C="$(python3 "$WORKDIR/skills/$SKILL_NAME/scripts/check_skill_contract.py" \
             --skill "$WORKDIR/skills/$SKILL_NAME" 2>&1 | tail -1)"
      case "$C" in
        *CONTRACT_OK*) record PASS "installed skill contract" "CONTRACT_OK" ;;
        *)             record FAIL "installed skill contract" "$C" ;;
      esac
    else
      record FAIL "install from clone" "installed 0 files"
    fi
    rm -rf "$WORKDIR"
  else
    record FAIL "clone" "could not clone $REPO"
    rm -rf "$WORKDIR"
  fi
fi

# ------------------------------------------------------------------- summary
echo
PASSES=$(printf '%s\n' "${RESULTS[@]}" | grep -c '^PASS|')
FAILS=$(printf '%s\n' "${RESULTS[@]}" | grep -c '^FAIL|')
SKIPS=$(printf '%s\n' "${RESULTS[@]}" | grep -c '^SKIP|')
echo "checks: $PASSES passed, $FAILS failed, $SKIPS skipped"

if [ -n "$JSON_OUT" ]; then
  python3 - "$JSON_OUT" "$FAIL" "$PASSES" "$FAILS" "$SKIPS" "${RESULTS[@]}" <<'PY'
import json, sys
from pathlib import Path
out, fail, p, f, s = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
entries = []
for raw in sys.argv[6:]:
    status, _, rest = raw.partition("|")
    name, _, detail = rest.partition("|")
    entries.append({"status": status, "check": name, "detail": detail})
report = {
    "passed": p, "failed": f, "skipped": s,
    "verdict": "IN_SYNC" if fail == 0 else "PROBLEMS_FOUND",
    "checks": entries,
}
Path(out).parent.mkdir(parents=True, exist_ok=True)
Path(out).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"report: {out}")
PY
fi

if [ "$FAIL" -eq 0 ]; then
  echo "VERDICT: repository fully in sync and reproducible"
else
  echo "VERDICT: problems found"
fi
exit $FAIL
