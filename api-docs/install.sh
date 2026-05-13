#!/usr/bin/env bash
set -e

REPO_RAW="https://raw.githubusercontent.com/paikpaik/skills/main"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
SKILLS=("api-docs")

install_file() {
  local skill="$1"
  local relative="$2"
  local target="$3"

  local local_path="$SCRIPT_DIR/$relative"
  if [ -f "$local_path" ]; then
    cp "$local_path" "$target"
  else
    curl -fsSL "$REPO_RAW/api-docs/$relative" -o "$target"
  fi
}

echo "api-docs 설치 중..."
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

  mkdir -p "$TARGET/references"

  install_file "$skill" "skills/$skill/SKILL.md"                                    "$TARGET/SKILL.md"
  install_file "$skill" "skills/$skill/references/framework-patterns.md"            "$TARGET/references/framework-patterns.md"

  echo "  → 설치 완료: $skill"
done

echo ""
echo "설치 완료!"
echo "  /api-docs                        — CWD 전체 라우트 문서화"
echo "  /api-docs src/routes/            — 특정 디렉토리"
echo "  /api-docs POST /contents/reward  — 단일 엔드포인트"
