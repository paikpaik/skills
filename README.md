# Claude Code Skills

Claude Code에서 사용할 수 있는 커스텀 Skill 모음입니다.

---

## Skills

| Skill | 커맨드 | 설명 |
|-------|--------|------|
| [incident-log](incident-log/skills/incident-log/SKILL.md) | `/incident-log` | 서버 장애 로그 자동 분석 및 요약 보고서 생성 |
| [api-docs](api-docs/skills/api-docs/SKILL.md) | `/api-docs` | controller/route 코드 기반 API 문서 자동 생성 |
| [diff-review](diff-review/skills/diff-review/SKILL.md) | `/diff-review` | 커밋 전 변경사항 분석 및 코드 리뷰 |

---

## 설치

각 스킬은 독립적으로 설치합니다.

```bash
# incident-log
bash <(curl -fsSL https://raw.githubusercontent.com/paikpaik/skills/main/incident-log/install.sh)

# api-docs
bash <(curl -fsSL https://raw.githubusercontent.com/paikpaik/skills/main/api-docs/install.sh)
```

레포를 클론한 경우 로컬에서 설치할 수 있습니다.

```bash
bash incident-log/install.sh
bash api-docs/install.sh
```

---

## 구조

```
<skill-name>/
├── install.sh
├── uninstall.sh
├── README.md
└── skills/
    └── <skill-name>/
        ├── SKILL.md          # 슬래시 커맨드 정의
        └── references/       # 부가 참조 문서 (선택)
```

새 스킬을 추가하려면 위 구조로 디렉토리를 만들고 이 README의 Skills 테이블에 한 줄을 추가합니다.
