#!/usr/bin/env bash
# Verify the skill-drift-audit repository is fully in sync with its remote.
set -uo pipefail

REPO="k5801kaohom-blip/skill-drift-audit"
LOCAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAIL=0

echo "######## 1. commit sync ########"
cd "$LOCAL"
git fetch -q origin
LH=$(git rev-parse HEAD)
RH=$(git rev-parse origin/main)
AB=$(git rev-list --left-right --count HEAD...origin/main)
DIRTY=$(git status --porcelain | wc -l)
echo "  local  HEAD : $LH"
echo "  remote main : $RH"
echo "  ahead/behind: $AB"
echo "  dirty files : $DIRTY"
[ "$LH" = "$RH" ] && echo "  -> commits in sync" || { echo "  -> MISMATCH"; FAIL=1; }
[ "$DIRTY" -eq 0 ] && echo "  -> working tree clean" || { echo "  -> UNCOMMITTED CHANGES"; FAIL=1; }

echo
echo "######## 2. remote file tree ########"
gh api "repos/$REPO/git/trees/main?recursive=1" --jq '.tree[] | select(.type=="blob") | .path' \
  | sed 's/^/  /'

echo
echo "######## 3. byte-for-byte content check ########"
FILES=(
  "skill-drift-audit/SKILL.md"
  "skill-drift-audit/scripts/audit_skill_drift.py"
  "skill-drift-audit/scripts/check_skill_contract.py"
  "skill-drift-audit/scripts/citizen_test_kit.py"
  "skill-drift-audit/references/citizen-developer-testing.md"
  "skill-drift-audit/references/drift-failure-modes.md"
  "skill-drift-audit/templates/audit_report.example.json"
  "README.md" "install.sh" "package.sh" "LICENSE" ".gitignore"
)
for f in "${FILES[@]}"; do
  gh api "repos/$REPO/contents/$f" --jq '.content' 2>/dev/null | base64 -d > /tmp/verify_remote_file
  if cmp -s /tmp/verify_remote_file "$LOCAL/$f"; then
    echo "  identical  $f"
  else
    echo "  DIFFERS    $f"
    FAIL=1
  fi
done

echo
echo "######## 4. newest content actually present on the remote ########"
gh api "repos/$REPO/contents/skill-drift-audit/SKILL.md" --jq '.content' 2>/dev/null \
  | base64 -d > /tmp/verify_skill.md
gh api "repos/$REPO/contents/skill-drift-audit/references/citizen-developer-testing.md" \
  --jq '.content' 2>/dev/null | base64 -d > /tmp/verify_citizen.md

check() {  # file, needle, label
  if grep -qF -- "$2" "$1"; then echo "  present  $3"; else echo "  MISSING  $3"; FAIL=1; fi
}
check /tmp/verify_skill.md "citizen developer test"       "SKILL.md: citizen developer test"
check /tmp/verify_skill.md "citizen_test_kit.py"          "SKILL.md: citizen_test_kit.py"
check /tmp/verify_skill.md "Never present one as a pass"  "SKILL.md: honest reporting rule"
# SKILL.md describes the verdicts in prose and points at the reference for the names,
# so assert the pointer rather than the enum values here.
check /tmp/verify_skill.md "five verdicts are in"         "SKILL.md: pointer to the verdict table"
check /tmp/verify_citizen.md "PASS_WITH_FRICTION"         "reference: PASS_WITH_FRICTION"
check /tmp/verify_citizen.md "COACHED"                    "reference: COACHED"
check /tmp/verify_citizen.md "INVALID"                    "reference: INVALID"
check /tmp/verify_citizen.md "eight validity checks"      "reference: eight validity checks"
check /tmp/verify_citizen.md "four norms"                 "reference: the four norms"

echo
echo "######## 5. fresh clone reproduces the skill ########"
rm -rf /tmp/verify_clone
git clone -q "https://github.com/$REPO.git" /tmp/verify_clone 2>/dev/null
if [ -d /tmp/verify_clone ]; then
  echo "  clone OK"
  bash -n /tmp/verify_clone/install.sh && echo "  install.sh syntax OK"
  bash -n /tmp/verify_clone/package.sh && echo "  package.sh syntax OK"
  rm -rf /tmp/verify_install && mkdir -p /tmp/verify_install
  SKILLS_DIR=/tmp/verify_install bash /tmp/verify_clone/install.sh > /dev/null 2>&1
  N=$(find /tmp/verify_install -type f | wc -l)
  echo "  installed $N files from the clone"
  python3 /home/ubuntu/skills/skill-creator/scripts/quick_validate.py skill-drift-audit 2>&1 | tail -1 | sed 's/^/  /'
  python3 /tmp/verify_install/skill-drift-audit/scripts/check_skill_contract.py \
    --skill /tmp/verify_install/skill-drift-audit 2>&1 | tail -1 | sed 's/^/  /'
else
  echo "  clone FAILED"
  FAIL=1
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "VERDICT: repository fully in sync and reproducible"
else
  echo "VERDICT: problems found"
fi
exit $FAIL
