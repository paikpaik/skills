# 대응 가이드

## 원인별 즉시 조치

### Aurora Failover

**즉시 조치**:
1. 자동 복구 대기 (보통 30초~2분) — 강제 개입 금지
2. 앱 DB 연결 재시도 확인: 커넥션 풀 `reconnect: true` 설정 여부
3. 복구 후 에러율 정상화 확인

**재발 방지**:
- 앱에서 DB 연결 실패 시 자동 재연결(retry with backoff) 구현
- Aurora Cluster Endpoint 사용 확인 (Instance Endpoint 직접 사용 금지)
- RDS Proxy 도입 검토 (Failover 시 커넥션 유지)
- CloudWatch Aurora 이벤트 알림 설정

**확인 쿼리**:
```sql
-- 복구 확인
SELECT @@global.read_only;  -- 0이면 writer 복구됨

-- 복제 상태 확인
SELECT server_id, session_id, LAST_SEEN_ACTIVE
FROM information_schema.replica_host_status;
```

---

### App 크래시 / pm2 재시작 루프

**즉시 조치**:
1. 크래시 원인 확인: `pm2 logs --lines 500`
2. 임시 안정화: `pm2 restart all`
3. 메모리 부족이면: 인스턴스 재시작 또는 스케일 아웃
4. 반복 크래시면: 문제 버전 롤백

**재발 방지**:
- `UnhandledPromiseRejection` 전역 핸들러 추가
- 메모리 사용량 모니터링 알림 설정
- pm2 `max_memory_restart` 설정 검토
- 크래시 발생 시 자동 알림 설정

---

### DB 커넥션 풀 고갈

**즉시 조치**:
1. 슬로우 쿼리 확인 및 KILL: `SHOW PROCESSLIST;` → `KILL {connection_id};`
2. 앱 재시작으로 커넥션 풀 초기화
3. DB 최대 커넥션 수 임시 증가: `SET GLOBAL max_connections = 300;`

**재발 방지**:
- 커넥션 풀 크기 조정 (앱 인스턴스 수 × 풀 크기 ≤ DB max_connections × 0.8)
- 슬로우 쿼리 로그 활성화 및 모니터링
- 커넥션 리크 탐지: 미사용 커넥션 자동 반환 설정
- `wait_timeout`, `interactive_timeout` 설정 검토

---

### 502/503 (Upstream Down)

**즉시 조치**:
1. App 서버 상태 확인: `pm2 status` 또는 `systemctl status`
2. 프로세스 재시작: `pm2 restart all`
3. 포트 바인딩 확인: `lsof -i :3000`
4. EB 환경이면: EB 헬스 대시보드 확인

**재발 방지**:
- Graceful shutdown 구현 (SIGTERM 처리)
- Health check 엔드포인트 구현 및 ELB 헬스체크 설정
- 배포 전략 개선 (블루/그린, 롤링 배포)

---

### 504 Gateway Timeout / upstream timed out

**즉시 조치**:
1. 슬로우 API 확인: nginx 응답 시간 분포 분석
2. DB 슬로우 쿼리 확인: `SHOW FULL PROCESSLIST;`
3. 외부 API 의존성 장애 여부 확인
4. nginx upstream timeout 임시 증가 (응급 시만)

**재발 방지**:
- API 응답 시간 SLA 설정 및 모니터링
- DB 인덱스 최적화, 쿼리 리팩토링
- 외부 API 호출에 timeout + 서킷브레이커 적용
- 캐싱 레이어 추가 검토

---

### OOM (메모리 부족)

**즉시 조치**:
1. 메모리 사용량 확인: `free -h`, `pm2 monit`
2. Node.js 힙 크기 확인: `--max-old-space-size` 설정
3. 임시 조치: 프로세스 재시작, 인스턴스 스케일 아웃

**재발 방지**:
- 메모리 프로파일링으로 누수 지점 파악
- `clinic.js` 또는 Chrome DevTools 힙 스냅샷 분석
- 대용량 데이터 스트리밍 처리로 전환
- 메모리 사용량 알림 임계값 설정 (80%)

---

### 디스크 풀

**즉시 조치**:
1. 사용량 확인: `df -h`, `du -sh /var/log/*`
2. 오래된 로그 삭제: `find /var/log -name "*.log.*" -mtime +7 -delete`
3. 로그 로테이션 즉시 실행: `logrotate -f /etc/logrotate.conf`

**재발 방지**:
- logrotate 설정 확인 및 주기 단축
- 디스크 사용량 모니터링 알림 설정 (80%, 90%)
- 로그 중앙화 (CloudWatch Logs, ELK) 검토

---

## 에러율별 대응 절차

### Critical (에러율 > 50%)

```
1. [ ] 장애 인지 및 팀 공유 (Slack/온콜)
2. [ ] 영향 범위 파악 (어떤 기능이 안 되는가)
3. [ ] 즉각 조치 (재시작 / 롤백 / 스케일 아웃)
4. [ ] 복구 확인 (에러율 정상화)
5. [ ] 사용자 공지 (필요 시)
6. [ ] 사후 분석 (RCA) 작성
```

### High (에러율 5~50%)

```
1. [ ] 영향 API 파악 및 우선순위 결정
2. [ ] 원인 확인 (로그, 모니터링 대시보드)
3. [ ] 핀포인트 조치 (특정 기능만 차단 또는 수정 배포)
4. [ ] 복구 확인
5. [ ] 재발 방지 이슈 등록
```

---

## 복구 확인 체크리스트

장애 조치 후 아래를 확인한다:

```
[ ] 에러율이 정상 수준으로 감소했는가?
[ ] 영향받은 API 응답 시간이 정상인가?
[ ] DB 커넥션 수가 정상 범위인가?
[ ] pm2 프로세스가 안정적으로 실행 중인가?
[ ] ELB 헬스체크가 통과하는가?
[ ] 메모리/CPU 사용량이 정상 범위인가?
```

---

## RCA (사후 분석) 템플릿

```markdown
## 장애 사후 분석 — {{DATE}}

### 요약
- 장애 시간: {{START}} ~ {{END}} (총 {{DURATION}}분)
- 영향: {{IMPACT_SUMMARY}}

### 타임라인
- {{TIME}}: {{EVENT}}

### 근본 원인
{{ROOT_CAUSE}}

### 조치 내용
{{ACTIONS_TAKEN}}

### 재발 방지
| 항목 | 담당자 | 기한 |
|------|--------|------|
| {{ACTION_ITEM}} | {{OWNER}} | {{DUE_DATE}} |
```
