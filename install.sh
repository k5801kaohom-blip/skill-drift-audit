#!/usr/bin/env bash
# Install the skill-drift-audit skill into a local skills directory.
set -euo pipefail

SKILL_NAME="skill-drift-audit"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/${SKILL_NAME}"
TARGET_ROOT="${SKILLS_DIR:-$HOME/skills}"
TARGET_DIR="${TARGET_ROOT}/${SKILL_NAME}"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "找不到技能資料夾：$SOURCE_DIR" >&2
  exit 1
fi

mkdir -p "$TARGET_ROOT"

if [[ -e "$TARGET_DIR" ]]; then
  BACKUP="${TARGET_DIR}.backup.$(date +%Y%m%d%H%M%S)"
  echo "偵測到既有安裝，備份至：$BACKUP"
  mv "$TARGET_DIR" "$BACKUP"
fi

cp -R "$SOURCE_DIR" "$TARGET_DIR"
find "$TARGET_DIR" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
find "$TARGET_DIR" -name '*.pyc' -delete 2>/dev/null || true
chmod +x "$TARGET_DIR"/scripts/*.py 2>/dev/null || true

echo "已安裝技能至：$TARGET_DIR"
echo
echo "環境需求：Python 3.10 以上；本技能僅使用標準函式庫。"
echo "選用工具：gh CLI（確認遠端同步）、pyyaml（技能結構驗證）"
echo
echo "驗證指令："
echo "  python ${TARGET_DIR}/scripts/audit_skill_drift.py --help"
echo "  python ${TARGET_DIR}/scripts/check_skill_contract.py --skill ${TARGET_DIR}"
echo "  python ${TARGET_DIR}/scripts/citizen_test_kit.py --emit --skill-name demo --out ./citizen_test"
