# 로그 패턴 참조

## 탐색 경로

```
# nginx
/var/log/nginx/access.log
/var/log/nginx/access.log.1
/var/log/nginx/error.log
/var/log/nginx/error.log.1
/etc/nginx/logs/access.log
/home/*/logs/nginx/*.log

# EB (Elastic Beanstalk)
/var/app/current/logs/eb-engine.log
/var/log/eb-engine.log
/var/log/eb-activity.log
/opt/elasticbeanstalk/deployment/logs/*.log

# PM2
~/.pm2/logs/*.log
./logs/*-out.log
./logs/*-error.log
./logs/combined*.log
./logs/app*.log

# Node/App 일반
./logs/*.log
./log/*.log
/tmp/app*.log

# MySQL / Aurora
/var/log/mysql/error.log
/var/log/mysqld.log
/var/log/mysql.err
/tmp/mysql*.err
```

---

## 타임스탬프 파싱 패턴

| 로그 유형 | 예시 | 파싱 정규식 |
|-----------|------|-------------|
| nginx access | `13/May/2025:09:14:32 +0900` | `(\d{2}/\w{3}/\d{4}:\d{2}:\d{2}:\d{2})` |
| nginx error | `2025/05/13 09:14:32` | `(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})` |
| eb-engine | `2025-05-13 09:14:32` | `(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})` |
| pm2/node | `2025-05-13T09:14:32.000Z` | `(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})` |
| mysql | `2025-05-13T09:14:32.123456Z` | `(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})` |
| mysql (legacy) | `250513  9:14:32` | `(\d{6}\s+\d{1,2}:\d{2}:\d{2})` |

---

## 에러 패턴 분류

### nginx access log 에러 코드

| 코드 | 의미 | 분류 코드 |
|------|------|-----------|
| 400 | Bad Request | `CLIENT_ERR` |
| 401 | Unauthorized | `AUTH_ERR` |
| 403 | Forbidden | `AUTH_ERR` |
| 404 | Not Found | `CLIENT_ERR` |
| 408 | Request Timeout | `TIMEOUT` |
| 413 | Payload Too Large | `CLIENT_ERR` |
| 429 | Too Many Requests | `RATE_LIMIT` |
| 499 | Client Closed Request | `CLIENT_TIMEOUT` |
| 500 | Internal Server Error | `APP_ERR` |
| 502 | Bad Gateway | `UPSTREAM_DOWN` |
| 503 | Service Unavailable | `UPSTREAM_DOWN` |
| 504 | Gateway Timeout | `TIMEOUT` |

### nginx error log 패턴

| 패턴 | 분류 코드 | 설명 |
|------|-----------|------|
| `upstream timed out` | `TIMEOUT` | 업스트림 응답 시간 초과 |
| `connect() failed` | `UPSTREAM_CONN` | 업스트림 연결 실패 |
| `no live upstreams` | `UPSTREAM_DOWN` | 업스트림 전체 다운 |
| `upstream prematurely closed` | `UPSTREAM_DOWN` | 업스트림 연결 비정상 종료 |
| `recv() failed` | `UPSTREAM_CONN` | 응답 수신 실패 |
| `SSL_do_handshake() failed` | `SSL_ERR` | SSL 핸드쉐이크 실패 |
| `too many open files` | `RESOURCE` | 파일 디스크립터 고갈 |
| `worker_connections are not enough` | `RESOURCE` | 커넥션 수 초과 |

### pm2 / Node.js 패턴

| 패턴 | 분류 코드 | 설명 |
|------|-----------|------|
| `Error: ECONNREFUSED` | `DB_CONN` | DB/Redis 연결 거부 |
| `Error: ETIMEDOUT` | `TIMEOUT` | 연결/쿼리 타임아웃 |
| `Error: ENOTFOUND` | `DNS_ERR` | DNS 조회 실패 |
| `UnhandledPromiseRejection` | `APP_ERR` | 미처리 Promise 예외 |
| `heap out of memory` | `OOM` | Node.js 메모리 부족 |
| `FATAL ERROR: CALL_AND_RETRY_LAST` | `OOM` | V8 힙 메모리 초과 |
| `Sequelize.*Error` | `DB_ERR` | ORM 쿼리 에러 |
| `ER_LOCK_DEADLOCK` | `DB_DEADLOCK` | DB 데드락 |
| `ER_READ_ONLY_MODE` | `DB_READONLY` | DB 읽기 전용 모드 |
| `ER_TOO_MANY_USER_CONNECTIONS` | `DB_CONN` | DB 커넥션 풀 초과 |
| `socket hang up` | `UPSTREAM_CONN` | 소켓 연결 강제 종료 |
| `connect ECONNRESET` | `UPSTREAM_CONN` | 연결 리셋 |
| `app crashed` (pm2) | `APP_CRASH` | 앱 크래시 (pm2 감지) |
| `restarting app` (pm2) | `APP_RESTART` | 앱 재시작 |

### MySQL / Aurora 패턴

| 패턴 | 분류 코드 | 설명 |
|------|-----------|------|
| `ER_READ_ONLY_MODE` / `ERROR 1290` | `DB_READONLY` | 읽기 전용 (failover 중) |
| `Aborted connection` | `DB_CONN` | 클라이언트 연결 비정상 종료 |
| `Got an error reading communication packets` | `DB_CONN` | 패킷 수신 에러 |
| `Too many connections` | `DB_CONN` | 최대 커넥션 초과 |
| `InnoDB: page corruption` | `DB_CORRUPTION` | 데이터 손상 |
| `slave.*error` | `DB_REPLICATION` | 복제 에러 |
| `Deadlock found` | `DB_DEADLOCK` | 데드락 |
| `Lock wait timeout exceeded` | `DB_LOCK` | 락 대기 타임아웃 |
| `Table .* is marked as crashed` | `DB_CORRUPTION` | 테이블 손상 |
| `disk full` | `DISK_FULL` | 디스크 공간 부족 |
| `binlog` | `DB_BINLOG` | 바이너리 로그 관련 |

### EB (Elastic Beanstalk) 패턴

| 패턴 | 분류 코드 | 설명 |
|------|-----------|------|
| `unhealthy` | `HEALTH` | 인스턴스 헬스체크 실패 |
| `deploy failed` | `DEPLOY` | 배포 실패 |
| `Command failed` | `DEPLOY` | EB 커맨드 실패 |
| `Environment health changed` | `HEALTH` | 환경 헬스 변경 |
| `Terminating` | `SCALING` | 인스턴스 종료 (스케일 다운) |
| `Launching` | `SCALING` | 인스턴스 시작 (스케일 업) |
| `Application health is WARNING` | `HEALTH` | 헬스 경고 |
| `Application health is DEGRADED` | `HEALTH` | 헬스 저하 |

---

## 동적 값 마스킹 규칙

집계 전 아래 패턴을 치환해 같은 에러가 다른 에러로 집계되지 않도록 한다.

| 원본 패턴 | 마스킹 결과 |
|-----------|-------------|
| IPv4 주소 `\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}` | `{IP}` |
| 포트 번호 `:\d{4,5}` | `:{PORT}` |
| 숫자 ID `/\d+` in path | `/:id` |
| UUID `[0-9a-f-]{36}` | `{UUID}` |
| JWT 토큰 `eyJ[A-Za-z0-9._-]+` | `{TOKEN}` |
| 타임스탬프 숫자 `\b\d{10,13}\b` | `{TS}` |
| 파일 디스크립터 `fd=\d+` | `fd={N}` |
| connection id `connection \d+` | `connection {N}` |
