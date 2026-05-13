#!/usr/bin/env bash
set -e

REPO_RAW="https://raw.githubusercontent.com/paikpaik/skills/main"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
SKILLS=("diff-review")

install_file() {
  local skill="$1"
  local relative="$2"
  local target="$3"

  local local_path="$SCRIPT_DIR/$relative"
  if [ -f "$local_path" ]; then
    cp "$local_path" "$target"
  else
    curl -fsSL "$REPO_RAW/diff-review/$relative" -o "$target"
  fi
}

echo "diff-review 설치 중..."
echo ""

for skill in "${SKILLS[@]}"; do
  TARGET="$SKILLS_DIR/$skill"

  if [ -d "$TARGET" ]; then
    printf "  '%s' 가 이미 존재합니다. 덮어쓸까요? (y/N): " "$skill"
    read -r answer
    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
      echo "  → 건너뜀: $skill"
      continue
    fi
    rm -rf "$TARGET"
  fi

  mkdir -p "$TARGET"

  install_file "$skill" "skills/$skill/SKILL.md" "$TARGET/SKILL.md"

  echo "  → 설치 완료: $skill"
done

echo ""
echo "설치 완료!"
echo "  /diff-review              — staged + unstaged 전체 리뷰"
echo "  /diff-review --staged     — staged만 리뷰"
echo "  /diff-review HEAD~3       — 최근 3커밋 리뷰"
