# Claude Code Skills

Claude Code에서 사용할 수 있는 커스텀 Skill 모음입니다.  
레포를 클론하지 않고 원격으로 바로 설치할 수 있습니다.

---

## Skills 목록

| Skill | 커맨드 | 설명 |
|-------|--------|------|
| [incident-log](#incident-log) | `/incident-log` | 서버 장애 로그 자동 분석 및 요약 보고서 생성 |

---

## incident-log

서버 장애 발생 시 로그 파일을 자동으로 분석해 에러 패턴·영향 API·추정 원인·대응 가이드를 마크다운 보고서로 생성합니다.

**지원 로그**

- nginx access / error log
- eb-engine.log (Elastic Beanstalk)
- pm2 / Node.js app log
- MySQL / Aurora error log

**출력 내용**

- 주요 에러 TOP N (건수, 비율, 최초 발생 시각)
- 에러 버스트 타임라인 (ASCII 히스토그램)
- 영향받은 API 목록 및 에러 코드
- 추정 원인 + 신뢰도 (Aurora Failover, 크래시 루프, 커넥션 풀 고갈 등)
- 즉시 조치 / 재발 방지 대응 가이드
- RCA 템플릿

**설치**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/paikpaik/skills/main/incident-log/install.sh)
```

**제거**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/paikpaik/skills/main/incident-log/uninstall.sh)
```

**사용법**

```
/incident-log                                          # CWD에서 로그 자동 탐색
/incident-log /var/log                                 # 경로 지정
/incident-log --since "2025-05-13 09:00" --until "2025-05-13 10:00"
```

---

## 새 Skill 추가 방법

`ex/tutor/` 를 참고해 아래 구조로 디렉토리를 만들고 PR을 올려주세요.

```
<skill-name>/
├── install.sh
├── uninstall.sh
└── skills/
    └── <skill-name>/
        ├── SKILL.md          # 슬래시 커맨드 정의
        └── references/       # 부가 참조 문서 (선택)
```
