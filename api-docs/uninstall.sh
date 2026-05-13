#!/usr/bin/env bash
set -e

SKILLS_DIR="$HOME/.claude/skills"
SKILLS=("api-docs")

echo "api-docs 제거 중..."
echo ""

for skill in "${SKILLS[@]}"; do
  TARGET="$SKILLS_DIR/$skill"

  if [ -d "$TARGET" ]; then
    rm -rf "$TARGET"
    echo "  → 제거 완료: $skill"
  else
    echo "  → 없음 (건너뜀): $skill"
  fi
done

echo ""
echo "제거 완료!"
