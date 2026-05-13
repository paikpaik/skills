#!/usr/bin/env bash
set -e

REPO_RAW="https://raw.githubusercontent.com/paikpaik/skills/main"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
SKILLS=("incident-log")

# 로컬 파일이 있으면 로컬에서, 없으면 GitHub에서 다운로드
install_file() {
  local skill="$1"
  local relative="$2"   # skills/incident-log/SKILL.md 형태
  local target="$3"

  local local_path="$SCRIPT_DIR/$relative"
  if [ -f "$local_path" ]; then
    cp "$local_path" "$target"
  else
    curl -fsSL "$REPO_RAW/incident-log/$relative" -o "$target"
  fi
}

echo "incident-log 설치 중..."
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

  install_file "$skill" "skills/$skill/SKILL.md"                              "$TARGET/SKILL.md"
  install_file "$skill" "skills/$skill/references/log-patterns.md"            "$TARGET/references/log-patterns.md"
  install_file "$skill" "skills/$skill/references/cause-mapping.md"           "$TARGET/references/cause-mapping.md"
  install_file "$skill" "skills/$skill/references/response-guide.md"          "$TARGET/references/response-guide.md"

  echo "  → 설치 완료: $skill"
done

echo ""
echo "설치 완료!"
echo "  /incident-log              — CWD에서 로그 자동 탐색 후 분석"
echo "  /incident-log /var/log     — 지정 경로 분석"
echo "  /incident-log --since '2025-05-13 09:00' --until '2025-05-13 10:00'"
