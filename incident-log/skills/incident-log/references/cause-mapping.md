# 원인 매핑 참조

## 단일 패턴 → 원인 테이블

| 분류 코드 | 추정 원인 | 신뢰도 | 확인 명령어 |
|-----------|-----------|--------|-------------|
| `DB_READONLY` | Aurora Failover / 읽기 전용 복제본에 Write 시도 | 높음 | `SHOW VARIABLES LIKE 'read_only';` |
| `DB_CONN` + 대량 | DB 커넥션 풀 고갈 | 높음 | `SHOW STATUS LIKE 'Threads_connected';` |
| `UPSTREAM_DOWN` | App 서버 프로세스 다운 / 재시작 중 | 높음 | `pm2 status`, `systemctl status app` |
| `TIMEOUT` + nginx | 백엔드 처리 지연 (느린 쿼리, 외부 API 대기) | 중간 | slow query log 확인 |
| `CLIENT_TIMEOUT` (499) 급증 | 응답 지연으로 클라이언트/ELB가 먼저 끊음 | 높음 | nginx 응답 시간 분포 확인 |
| `OOM` | Node.js 메모리 누수 또는 급격한 트래픽 | 높음 | `pm2 monit`, 메모리 메트릭 |
| `APP_CRASH` + `APP_RESTART` | 앱 크래시 반복 (pm2 자동 재시작) | 높음 | pm2 로그 직전 스택트레이스 확인 |
| `RESOURCE` (too many open files) | 파일 디스크립터 제한 초과 | 높음 | `ulimit -n`, `/proc/pid/fd` |
| `DEPLOY` | 배포 실패로 인한 서비스 불안정 | 높음 | EB 배포 이력 확인 |
| `DISK_FULL` | 디스크 공간 부족 | 높음 | `df -h` |
| `DB_DEADLOCK` | 동시 트랜잭션 충돌 | 중간 | `SHOW ENGINE INNODB STATUS;` |
| `DB_LOCK` | 장시간 트랜잭션으로 인한 락 대기 | 중간 | `SHOW PROCESSLIST;` |
| `RATE_LIMIT` | 트래픽 급증 또는 DDoS 의심 | 중간 | 클라이언트 IP 분포 확인 |
| `DNS_ERR` | DNS 서버 불안정 또는 잘못된 호스트 설정 | 높음 | `dig`, `/etc/hosts` 확인 |
| `SSL_ERR` | 인증서 만료 또는 SSL 설정 오류 | 높음 | `openssl s_client -connect host:443` |
| `DB_REPLICATION` | MySQL 복제 중단 | 높음 | `SHOW SLAVE STATUS\G` |

---

## 복합 패턴 → 근본 원인

### C1. Aurora Failover

**트리거 조건**:
- `ER_READ_ONLY_MODE` (mysql) **AND** `upstream timed out` (nginx) **AND** 두 에러가 같은 시간에 시작

**설명**:
Aurora Multi-AZ Failover 발생 시, 기존 Writer 인스턴스가 Reader로 전환되면서 쓰기 요청이 일시적으로 `ER_READ_ONLY_MODE` 에러를 반환한다. 동시에 연결 재설정으로 인해 nginx에서 `upstream timed out`이 폭증한다. Failover 완료 후(보통 30초~2분) 자동 복구된다.

**신뢰도 판단**:
- 높음: mysql 에러와 nginx 타임아웃이 동시 시작, 수분 내 자동 복구
- 중간: mysql 에러만 있거나 타임아웃만 있는 경우

**확인 명령어**:
```sql
-- Aurora 이벤트 확인
SHOW GLOBAL STATUS LIKE 'aurora%';

-- 현재 writer 확인
SELECT server_id, session_id, LAST_SEEN_ACTIVE, REPLICA_LAG_IN_MILLISECONDS, HAS_ONGOING_TRANSACTION
FROM information_schema.replica_host_status;
```

---

### C2. App 크래시 후 pm2 재시작 루프

**트리거 조건**:
- `APP_CRASH` + `APP_RESTART` (pm2) **AND** `UPSTREAM_DOWN` 502/503 (nginx)
- pm2 restart 이벤트가 단시간에 반복

**설명**:
앱 프로세스가 크래시되면 pm2가 자동 재시작하지만, 재시작 중에는 nginx upstream이 다운된 상태여서 502/503이 발생한다. 크래시가 반복되면 재시작 간격 동안 지속적으로 에러가 발생한다.

**확인 명령어**:
```bash
pm2 logs --lines 200  # 크래시 직전 스택트레이스 확인
pm2 info app-name     # restart count, uptime 확인
```

---

### C3. DB 커넥션 풀 고갈

**트리거 조건**:
- `ER_TOO_MANY_USER_CONNECTIONS` 또는 `ECONNREFUSED` (node) **AND** 에러가 점진적으로 증가

**설명**:
트래픽 급증 또는 슬로우 쿼리로 인해 DB 커넥션이 오래 점유되면 커넥션 풀이 고갈된다. 이후 신규 요청이 모두 에러를 반환한다.

**확인 명령어**:
```sql
SHOW STATUS LIKE 'Threads_connected';
SHOW STATUS LIKE 'Max_used_connections';
SHOW PROCESSLIST;  -- 슬로우 쿼리 확인
```

---

### C4. 트래픽 급증 → 리소스 고갈

**트리거 조건**:
- 특정 시간부터 모든 에러 유형이 동시에 증가
- 특정 엔드포인트에 요청이 집중
- 499 클라이언트 타임아웃 급증

**설명**:
정상적인 트래픽 급증 또는 특정 기능의 N+1 쿼리 등 비효율로 인해 전체 리소스가 고갈된다. 단일 원인이 아닌 시스템 전반의 포화 상태다.

**확인 명령어**:
```bash
# 요청 수 시간대별 확인
awk '{print $4}' access.log | cut -c1-15 | sort | uniq -c

# 특정 엔드포인트 요청 집중 확인
awk '{print $7}' access.log | sort | uniq -c | sort -rn | head -20
```

---

### C5. 배포 후 장애

**트리거 조건**:
- `DEPLOY` (eb-engine) 이벤트 **AND** 배포 완료 직후 에러 폭증

**설명**:
코드 배포 후 새 버전에서 에러가 발생하는 경우. 설정 누락, 환경 변수 오류, 신규 코드 버그 등이 원인일 수 있다.

**확인 명령어**:
```bash
eb events  # EB 배포 이벤트 확인
git log --oneline -10  # 최근 배포 커밋 확인
```

---

### C6. 외부 의존성 장애 (External API/Service)

**트리거 조건**:
- `ETIMEDOUT` + 특정 외부 호스트명이 에러에 반복 등장
- 내부 DB/인프라 에러는 없는데 타임아웃 폭증

**설명**:
외부 결제 API, SMS/푸시 서비스, 외부 데이터 제공자 등이 장애인 경우. 해당 의존성을 사용하는 API만 에러가 집중된다.

**확인 명령어**:
```bash
# 에러 발생 시점 외부 API 응답 확인
curl -w "@curl-format.txt" -o /dev/null -s "https://external-api.example.com/health"
```

---

## 장애 심각도 분류

| 등급 | 조건 | 대응 우선순위 |
|------|------|---------------|
| **Critical** | 전체 서비스 불가 (502/503 > 50%), DB 다운, OOM | 즉시 대응 |
| **High** | 주요 기능 장애 (특정 API 에러율 > 30%), Aurora Failover | 30분 내 대응 |
| **Medium** | 일부 기능 저하 (에러율 5-30%), 성능 저하 | 2시간 내 대응 |
| **Low** | 산발적 에러 (에러율 < 5%), 경고성 메시지 | 근무 시간 내 대응 |
