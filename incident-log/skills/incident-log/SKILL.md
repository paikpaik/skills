---
name: incident-log
description: "서버 장애 로그(nginx, eb-engine, pm2/node, mysql)를 분석해 에러 패턴·영향 API·추정 원인·대응 가이드를 자동 생성합니다."
---

# Incident Log — 장애 로그 자동 분석

## 사용법

```
# EC2에서 직접 (SSH 접속 → 로그 수집 → 분석 한 번에)
/incident-log ssh -i "awskey.pem" root@10.2.4.58

# 로컬 디렉토리 지정
/incident-log /var/log/nginx

# 경로 없이 실행 (CWD 자동 탐색)
/incident-log

# 시간 범위 지정
/incident-log --since "2025-05-13 09:00" --until "2025-05-13 10:00"
```

---

## Phase 0: 모드 감지 및 범위 설정

인수를 파싱해 실행 모드를 결정한다.

### 모드 판별

| 조건 | 모드 |
|------|------|
| 인수가 `ssh`로 시작 | **SSH 모드** → Phase 0-S 진행 |
| 인수가 로컬 경로 | **로컬 모드** → Phase 1로 바로 진행 |
| 인수 없음 | **로컬 모드** → CWD 탐색 |

`--since`, `--until` 플래그는 모든 모드에서 공통으로 적용된다.

---

### Phase 0-S: SSH 모드 — 로그 수집

인수에서 SSH 접속 정보를 파싱한다.

**파싱 규칙**:
- `-i "path"` 또는 `-i path` → SSH 키 경로
- `user@host` 패턴 → 유저와 호스트 분리
- `-i` 없으면 키 없이 접속 시도

**파싱 예시**:
```
ssh -i "awskey.pem" root@10.2.4.58
  → KEY=awskey.pem  USER=root  HOST=10.2.4.58

ssh -i ~/keys/prod.pem ec2-user@prod.example.com
  → KEY=~/keys/prod.pem  USER=ec2-user  HOST=prod.example.com
```

파싱 결과를 사용자에게 보여주고 확인 후 진행한다:
```
SSH 접속 정보:
  호스트: root@10.2.4.58
  키:     awskey.pem
  저장:   /tmp/incident-logs-YYYYMMDD-HHmm/

로그 수집을 시작할까요? (y/N)
```

확인 후 Bash 도구로 아래 순서대로 실행한다.

**1. SSH 접속 테스트**:
```bash
ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=5 "$USER@$HOST" echo ok
```
실패 시 에러 메시지를 출력하고 중단한다.

**2. 로그 파일 수집** — [log-patterns.md](references/log-patterns.md)의 **탐색 경로** 섹션 기준으로 아래를 순서대로 시도한다:
```bash
OUT="/tmp/incident-logs-$(date +%Y%m%d-%H%M)"
mkdir -p "$OUT"
chmod 700 "$OUT"  # 로컬 수집 디렉토리는 소유자만 접근
SSH_OPTS="-i $KEY -o StrictHostKeyChecking=accept-new -o BatchMode=yes"

# 파일 하나씩 scp 시도 (없으면 건너뜀)
scp -q $SSH_OPTS "$USER@$HOST:/var/log/nginx/access.log"   "$OUT/" 2>/dev/null || true
scp -q $SSH_OPTS "$USER@$HOST:/var/log/nginx/access.log.1" "$OUT/" 2>/dev/null || true
scp -q $SSH_OPTS "$USER@$HOST:/var/log/nginx/error.log"    "$OUT/" 2>/dev/null || true
scp -q $SSH_OPTS "$USER@$HOST:/var/log/nginx/error.log.1"  "$OUT/" 2>/dev/null || true
scp -q $SSH_OPTS "$USER@$HOST:/var/log/eb-engine.log"      "$OUT/" 2>/dev/null || true
scp -q $SSH_OPTS "$USER@$HOST:/var/log/eb-activity.log"    "$OUT/" 2>/dev/null || true
scp -q $SSH_OPTS "$USER@$HOST:/var/log/mysqld.log"         "$OUT/" 2>/dev/null || true
scp -q $SSH_OPTS "$USER@$HOST:/var/log/mysql/error.log"    "$OUT/" 2>/dev/null || true

# sudo가 필요한 파일: 600으로 복사 후 scp, 즉시 삭제
REMOTE_TMP_FILES=()
for remote_path in /var/log/web.stdout.log /var/log/messages; do
  fname=$(basename "$remote_path")
  tmp_path="/tmp/incident-collect-$$-$fname"
  ssh $SSH_OPTS "$USER@$HOST" "sudo cp '$remote_path' '$tmp_path' && sudo chmod 600 '$tmp_path' && sudo chown $USER '$tmp_path'" 2>/dev/null || continue
  scp -q $SSH_OPTS "$USER@$HOST:$tmp_path" "$OUT/$fname" 2>/dev/null && REMOTE_TMP_FILES+=("$tmp_path") || true
done

# glob 패턴은 ssh ls 후 scp
for pattern in "~/.pm2/logs/*.log" "/var/app/current/logs/*.log"; do
  files=$(ssh $SSH_OPTS "$USER@$HOST" "ls $pattern 2>/dev/null" 2>/dev/null || true)
  for f in $files; do
    scp -q $SSH_OPTS "$USER@$HOST:$f" "$OUT/" 2>/dev/null || true
  done
done

# rotated gz (sudo 필요 시 동일 패턴 적용)
for pattern in "/var/log/rotated/web.stdout.log*.gz"; do
  files=$(ssh $SSH_OPTS "$USER@$HOST" "sudo ls $pattern 2>/dev/null" 2>/dev/null || true)
  for f in $files; do
    fname=$(basename "$f")
    tmp_path="/tmp/incident-collect-$$-$fname"
    ssh $SSH_OPTS "$USER@$HOST" "sudo cp '$f' '$tmp_path' && sudo chmod 600 '$tmp_path' && sudo chown $USER '$tmp_path'" 2>/dev/null || continue
    scp -q $SSH_OPTS "$USER@$HOST:$tmp_path" "$OUT/$fname" 2>/dev/null && REMOTE_TMP_FILES+=("$tmp_path") || true
  done
done

# 서버 측 임시 파일 즉시 삭제
if [ ${#REMOTE_TMP_FILES[@]} -gt 0 ]; then
  ssh $SSH_OPTS "$USER@$HOST" "rm -f ${REMOTE_TMP_FILES[*]}" 2>/dev/null || true
fi
```

**3. 수집 결과 요약**:
```
수집 완료: /tmp/incident-logs-20250513-0930/
  v nginx/access.log  (2.3 MB)
  v nginx/error.log   (412 KB)
  - eb-engine.log     (없음)
  v pm2/app-out.log   (1.1 MB)
  - mysqld.log        (없음)
```

수집된 파일이 하나도 없으면 중단하고 원인을 안내한다.

수집 완료 후 `$OUT` 을 로컬 경로로 설정하고 **Phase 1로 진행**한다.

---

## Phase 1: 로그 파일 탐색

[log-patterns.md](references/log-patterns.md)의 **탐색 경로** 섹션을 참고해 아래 유형을 탐색한다.

| 유형 | 탐색 패턴 | 우선순위 |
|------|-----------|---------|
| nginx access | `**/nginx/access.log*` | 1 |
| nginx error | `**/nginx/error.log*` | 1 |
| eb-engine | `**/eb-engine.log*`, `**/eb-activity.log*` | 2 |
| pm2 | `~/.pm2/logs/*.log`, `**/logs/*out.log`, `**/logs/*error.log` | 2 |
| node/app | `**/logs/app*.log`, `**/logs/combined*.log` | 3 |
| mysql | `/var/log/mysql/error.log`, `/var/log/mysqld.log`, `**/mysql-error.log` | 2 |

**탐색 규칙**:
- `find` 명령어로 파일 목록을 가져온다. Read 도구로 큰 파일을 통째로 읽지 않는다.
- 로테이션 파일(`.1`, `.2`, `.gz` 등)도 포함. gz는 `zcat`으로 읽는다.
- 파일 크기와 마지막 수정 시각을 함께 표시한다.

---

## Phase 2: 로그 읽기 & 에러 추출

> **큰 파일 처리 원칙**: 파일이 10MB 이상이면 Read 대신 Bash(`grep`, `awk`, `tail`)를 사용한다.

### 2-1. 시간 범위 결정

1. `--since`/`--until` 인수가 있으면 그대로 사용
2. 없으면 각 로그 파일의 최초·최후 타임스탬프를 확인해 전체 범위를 파악한다
3. 에러 폭증 구간을 자동 탐지해 **집중 분석 윈도우**(기본: 에러 밀도 상위 구간 ±30분)를 설정한다

### 2-2. 유형별 추출 전략

**nginx access log** — 표준 combined 포맷 기준:
```bash
# 4xx/5xx 에러 라인만 추출
grep -E '" [45][0-9]{2} ' access.log

# 시간 범위 필터 (awk로 타임스탬프 파싱)
awk '$4 >= "[13/May/2025:09:00" && $4 <= "[13/May/2025:10:00"' access.log
```

**nginx error log** — 형식: `YYYY/MM/DD HH:MM:SS [level] pid#tid: *cid msg`:
```bash
grep -E '\[(error|crit|alert|emerg)\]' error.log
```

**eb-engine.log** — EB 배포·헬스 이벤트:
```bash
grep -E '(ERROR|WARN|Failed|unhealthy|timeout|deploy)' eb-engine.log
```

**pm2/node log** — JavaScript 에러 패턴:
```bash
grep -E '(Error:|WARN|fatal|Unhandled|ECONNREFUSED|ETIMEDOUT|heap|OOM)' app.log
```

**mysql error log** — 형식: `YYYY-MM-DD HH:MM:SS` prefix:
```bash
grep -E '(ERROR|Warning|Got error|Aborted|Read.only|ER_)' mysqld.log
```

### 2-3. 에러 라인 정규화

[log-patterns.md](references/log-patterns.md)의 **에러 패턴 분류** 섹션을 참고해 각 에러 라인을 다음 필드로 정규화한다:

| 필드 | 설명 |
|------|------|
| `timestamp` | 파싱된 datetime |
| `source` | 로그 출처 (nginx-access / nginx-error / eb / pm2 / mysql) |
| `level` | error / warn / info |
| `category` | [cause-mapping.md](references/cause-mapping.md) 분류 코드 |
| `message` | 정규화된 에러 메시지 (동적 값 마스킹) |
| `endpoint` | 관련 API 엔드포인트 (nginx-access에서 추출) |
| `count` | 집계 시 사용 |

---

## Phase 3: 패턴 집계

정규화된 에러 라인을 집계한다.

### 3-1. TOP N 에러

- `message` 기준으로 그룹핑 (동적 ID·IP·포트 마스킹 후)
- 건수 내림차순 정렬, 기본 TOP 10
- 각 에러별: 총 건수, 비율(%), 최초 발생 시각, 최후 발생 시각, 로그 출처

### 3-2. 시간대별 분포 (버스트 탐지)

- 1분 단위 버킷으로 에러 건수 집계
- 평균 대비 3σ 이상 구간을 **에러 버스트**로 표시
- ASCII 히스토그램으로 시각화

```
09:10 ███░░░░░░░░  (12)
09:14 ████████████████████████████  (284)  ← 버스트
09:15 ██████████████████████  (221)  ← 버스트
09:28 ██░░░░░░░░░  (8)
```

### 3-3. 최초 발생 시점

- 전체 로그 중 가장 이른 에러 타임스탬프
- 유형별 최초 발생 시점 (장애 발생 순서 파악용)

---

## Phase 4: 영향 API 추출

nginx access log를 기반으로 영향받은 엔드포인트를 추출한다.

1. **에러 집중 구간**의 4xx/5xx 응답 라인에서 `METHOD /path` 추출
2. 엔드포인트별 집계: 에러 건수, 주 에러 코드, 평균 응답 시간
3. 에러 비율(해당 API의 전체 요청 대비)이 높은 순으로 정렬
4. 경로 변수 마스킹: `/users/12345` → `/users/:id`
5. **ELB HealthChecker 499**는 별도 항목으로 분리 (실제 사용자 영향 구분)

---

## Phase 5: 원인 추정

[cause-mapping.md](references/cause-mapping.md)를 참고해 에러 패턴 → 원인을 추정한다.

### 5-1. 단일 패턴 매핑

각 TOP 에러를 cause-mapping.md의 **패턴→원인 테이블**에 조회한다.

### 5-2. 복합 패턴 분석 (상관관계)

에러가 동시에 여러 개 발생한 경우, cause-mapping.md의 **복합 패턴** 섹션을 참고해 근본 원인(Root Cause)을 추론한다.

예:
- `ER_READ_ONLY_MODE` + `upstream timed out` + 에러 폭증이 동시에 시작 → **Aurora Failover** 가능성 높음
- `ECONNREFUSED` + pm2 restart → **App 크래시 후 재시작**
- `499` 급증 + nginx upstream timeout → **백엔드 응답 지연 → 클라이언트 타임아웃**

### 5-3. 타임라인 기반 인과관계

에러 유형별 최초 발생 시각을 비교해 어떤 에러가 먼저 발생했는지 파악하고 원인→결과 체인을 구성한다.

### 5-4. 신뢰도 표기

각 원인 추정에 신뢰도를 표기한다:
- `[높음]` — 여러 로그에서 패턴 일치, 타임라인 일관성 있음
- `[중간]` — 일부 패턴 일치, 다른 원인 가능성 존재
- `[낮음]` — 단일 로그 기반, 추가 확인 필요

---

## Phase 6: 보고서 생성

분석이 완료되면 **현재 디렉토리**에 `incident-report-{{YYYYMMDD-HHmm}}.md` 파일로 즉시 저장한다. 저장 확인은 묻지 않는다.

**로그 샘플(원본) 섹션 작성 시 주의**: 인증 헤더(`Authorization`, `authorization`), 토큰, 비밀번호가 포함된 라인은 해당 값을 `[REDACTED]`로 마스킹한 후 기록한다.

파일 저장 후 로컬 임시 수집 디렉토리(`/tmp/incident-logs-*`)를 삭제하고 아래와 같이 알린다:
```
보고서 저장 완료: ./incident-report-{{YYYYMMDD-HHmm}}.md
임시 로그 파일 삭제 완료: /tmp/incident-logs-{{YYYYMMDD-HHmm}}/
```

보고서 형식은 다음과 같다.

---

```markdown
# 장애 요약 보고서

> 분석 시각: {{NOW}}
> 로그 분석 기간: {{START}} ~ {{END}}
> 분석 파일: {{FILE_LIST}}

---

## 1. 개요

| 항목 | 내용 |
|------|------|
| 장애 추정 시작 | {{FIRST_ERROR_TIME}} |
| 에러 집중 구간 | {{BURST_START}} ~ {{BURST_END}} ({{DURATION}}분) |
| 총 에러 건수 | {{TOTAL_ERRORS}}건 |
| 영향 API 수 | {{AFFECTED_APIS}}개 |
| 추정 원인 | {{PRIMARY_CAUSE}} |

---

## 2. 주요 에러 TOP {{N}}

| 순위 | 에러 유형 | 건수 | 비율 | 최초 발생 | 로그 출처 |
|------|-----------|------|------|-----------|-----------|
| 1 | ... | ... | ...% | ... | ... |

### 에러 버스트 타임라인
```
{{ASCII_HISTOGRAM}}
```

---

## 3. 장애 타임라인

```
{{FIRST_ERROR_TIME}} ── [{{SOURCE}}] {{FIRST_ERROR_MSG}}
...
{{LAST_ERROR_TIME}}  ── 에러 소멸 (정상화 추정)
```

---

## 4. 영향 API

| 엔드포인트 | 에러 건수 | 주 에러 코드 | 에러 비율 | 평균 응답(ms) |
|-----------|-----------|--------------|-----------|--------------|
| POST /... | ... | 502, 504 | ...% | ... |

> ELB HealthChecker 499: {{ELB_499_COUNT}}건 (서비스 불가 판정 횟수)

---

## 5. 추정 원인

### [{{CONFIDENCE}}] {{CAUSE_TITLE}}
{{CAUSE_DESCRIPTION}}

**근거**:
- {{EVIDENCE_1}}
- {{EVIDENCE_2}}

**타임라인 일관성**: {{TIMELINE_CONSISTENCY}}

---

## 6. 대응 가이드

### 즉시 조치 (지금 당장)
{{IMMEDIATE_ACTIONS}}

### 확인 사항
{{VERIFICATION_CHECKLIST}}

### 재발 방지
{{PREVENTION_ACTIONS}}

---

## 7. 로그 샘플 (원본)

<details>
<summary>주요 에러 원본 로그 (각 유형별 최대 5건)</summary>

**nginx error**
```
{{NGINX_ERROR_SAMPLES}}
```

**mysql**
```
{{MYSQL_SAMPLES}}
```

**pm2/node**
```
{{PM2_SAMPLES}}
```
</details>
```

---

## 분석 품질 원칙

- 추정 원인이 불확실하면 "확인 필요"로 표기하고 확인 명령어를 제시한다
- 로그 파일이 없거나 빈 경우 해당 항목을 "로그 없음"으로 표시하고 계속 진행한다
- 에러가 없는 로그는 "정상" 으로 표시한다
- 동적 값(IP, 사용자ID, 트랜잭션ID)은 집계 전 마스킹해 같은 에러가 다른 에러로 집계되지 않도록 한다

## 보안 원칙

- 서버 측 임시 파일: `chmod 600` + scp 완료 즉시 `rm -f`로 삭제한다
- 로컬 임시 파일: 보고서 저장 후 `/tmp/incident-logs-*` 디렉토리 전체를 삭제한다
- 보고서 원본 샘플: `Authorization`, `Cookie`, `token`, `password` 등 인증 관련 값은 `[REDACTED]`로 마스킹한다
- sudo로 생성하는 임시 파일은 프로세스별 고유 이름(`$$` 포함)을 사용해 충돌 및 심볼릭 링크 공격을 방지한다
