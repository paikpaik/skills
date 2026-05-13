---
name: api-docs
description: "controller/route 코드를 읽고 외부 공유용 API 문서(version, headers, request parameters, response fields, error codes)를 자동 생성합니다."
---

# API Docs — 외부 공유용 API 문서 자동 생성

## 사용법

```
# CWD에서 전체 라우트 자동 탐색
/api-docs

# 특정 디렉토리 지정
/api-docs src/routes/
/api-docs src/controllers/

# 특정 엔드포인트만
/api-docs POST /contents/reward/transaction
/api-docs GET /game/home

# 여러 엔드포인트
/api-docs "POST /contents/reward/transaction" "GET /game/home"
```

---

## Phase 0: 인수 파싱

| 인수 형태 | 모드 |
|-----------|------|
| 없음 | **전체 모드** — CWD에서 모든 라우트 탐색 |
| 디렉토리 경로 | **디렉토리 모드** — 해당 경로 내 라우트 탐색 |
| `METHOD /path` | **단일 모드** — 해당 엔드포인트만 분석 |
| 여러 `METHOD /path` | **선택 모드** — 나열된 엔드포인트만 분석 |

---

## Phase 1: 프레임워크 감지 및 파일 탐색

[framework-patterns.md](references/framework-patterns.md)의 **라우트 정의 패턴** 섹션을 참고한다.

```bash
# 프레임워크 확인
cat package.json | grep -E '"(express|restify|fastify|koa|@nestjs/core)"'

# 라우트 파일 탐색
find . -type f \( -name "*.routes.*" -o -name "router.*" -o -name "*.controller.*" \) \
  -not -path "*/node_modules/*" -not -path "*/.git/*" | head -20
```

탐색 우선순위:

| 우선순위 | 패턴 |
|---------|------|
| 1 | `**/routes/**/*.{js,ts}` |
| 1 | `**/router/**/*.{js,ts}` |
| 2 | `**/controllers/**/*.{js,ts}` |
| 2 | `**/*.controller.{js,ts}` |
| 3 | `**/api/**/*.{js,ts}` |

**탐색 제외**: `node_modules/`, `dist/`, `build/`, `*.spec.*`, `*.test.*`

---

## Phase 2: 라우트 추출

[framework-patterns.md](references/framework-patterns.md)의 **Prefix 합산 규칙**을 따라 각 라우트의 최종 경로를 구성한다.

핸들러가 다른 파일로 분리된 경우(`require`, `import`) 해당 파일까지 추적한다.

---

## Phase 3: 엔드포인트 분석

각 라우트의 핸들러 코드를 읽어 아래 5개 항목을 추출한다.

### 3-1. Version

파일명, 경로, 코드 내 버전 표기에서 추출한다.

```bash
# 파일명 패턴: post.1.0.0.ts, handler.v2.js
# 경로 패턴: /v1/game/home, /api/v2/...
# 코드 내: version: '1.0.0', apiVersion = '2'
grep -n "version\|Version" handler_file.ts | head -10
```

버전을 찾을 수 없으면 `확인 필요`로 표기한다.

### 3-2. Headers

[framework-patterns.md](references/framework-patterns.md)의 **Auth 패턴** 섹션을 참고해 인증 헤더를 판별하고, 그 외 요구되는 헤더를 추출한다.

```bash
grep -n "req\.headers\.\|req\.header(" handler_file.ts
```

`Content-Type`은 Request Body가 있으면 `application/json`으로 자동 포함한다.

### 3-3. Request Parameters

**Path Parameters** — `:param` 패턴 및 `req.params.*` 접근:
```bash
grep -n "req\.params\." handler_file.ts
```

**Query Parameters** — `req.query.*` 접근:
```bash
grep -n "req\.query\." handler_file.ts
```

**Request Body** — `req.body.*` 접근 또는 validation 스키마(Joi/Zod/class-validator) 우선:
```bash
grep -n "req\.body\.\|Joi\.object\|z\.object" handler_file.ts
```

**분기 처리**: 동일 파라미터가 값에 따라 동작이 달라지는 경우(예: `feature`, `type`, `subType` 등) 각 분기별로 Example을 별도 작성한다.

### 3-4. Response Fields

실제 응답 구조를 코드에서 추출한다:
```bash
grep -n "res\.json\|res\.send\|reply\.send\|return {" handler_file.ts
```

응답 필드가 조건에 따라 동적으로 구성되는 경우(예: feature별 `result.cash`, `result.ticket`), 가능한 모든 필드를 표로 나열하고 Example을 분기별로 작성한다.

### 3-5. Error Codes

코드에서 에러를 반환하는 패턴을 탐색한다:
```bash
grep -n "throw\|reject\|err_\|ErrorCode\.\|new Error\|res\.status\|next(err" handler_file.ts
```

에러 코드 문자열과 그 발생 조건(주변 if/조건문)을 함께 추출해 설명을 작성한다.

---

## Phase 4: 문서 생성

각 엔드포인트를 아래 형식으로 작성한다. **소스 경로, Redis, DB, 처리 흐름은 포함하지 않는다.**

---

```markdown
## `{METHOD} {PATH}`

{한 줄 설명}

---

### Version

`{version}`

---

### Headers

| 헤더 | 필수 | 설명 |
|------|------|------|
| `Authorization` | Y | {인증 유형 및 방식 설명} |
| `Content-Type` | Y | `application/json` |

(인증 없으면 Authorization 행 생략)

---

### Request Parameters

#### Path Parameters

| 파라미터 | 타입 | 필수 | 설명 |
|---------|------|------|------|
| `{name}` | `{type}` | Y/N | {설명} |

(없으면 섹션 생략)

#### Query Parameters

| 파라미터 | 타입 | 필수 | 기본값 | 설명 |
|---------|------|------|--------|------|
| `{name}` | `{type}` | Y/N | `{default}` | {설명} |

(없으면 섹션 생략)

#### Request Body

| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `{field}` | `{type}` | Y/N | {설명} |

**Example**

```json
{
  "{field}": "{example_value}"
}
```

분기가 있는 경우 케이스별로 Example 추가:

**Example — {케이스명}**

```json
{
  "{field}": "{example_value}"
}
```

(Request Body 없으면 섹션 생략)

---

### Response Fields

| 필드 | 타입 | 설명 |
|------|------|------|
| `{field}` | `{type}` | {설명} |

**Example**

```json
{
  "{field}": "{example_value}"
}
```

분기가 있는 경우 케이스별로 Example 추가:

**Example — {케이스명}**

```json
{
  "{field}": "{example_value}"
}
```

---

### Error Codes

| 코드 | 설명 |
|------|------|
| `{error_code}` | {발생 조건 설명} |
```

---

## Phase 5: 파일 저장

분석 완료 후 **현재 디렉토리**에 즉시 저장한다. 저장 확인은 묻지 않는다.

- 단일/선택 모드: `api-docs-{METHOD}-{path-slug}-{YYYYMMDD-HHmm}.md`
- 전체/디렉토리 모드: `api-docs-{YYYYMMDD-HHmm}.md`

저장 완료 후 알린다:
```
문서 저장 완료: ./api-docs-{slug}-{YYYYMMDD-HHmm}.md
총 {N}개 엔드포인트 문서화
```

---

## 분석 품질 원칙

- 코드에서 확인되지 않은 항목은 추측하지 말고 `확인 필요`로 표기한다
- 파라미터 설명은 코드 주석, 변수명, 사용 문맥에서 추론한다
- 분기(feature, type, subType 등)는 코드 내 조건문을 따라가 각 케이스별 Example을 작성한다
- 에러 코드는 발생 조건(어떤 상황에서 이 에러가 나오는지)을 함께 기술한다
- 파일이 크면 Read 대신 `grep -n`으로 관련 라인만 추출한다
- 공통 미들웨어나 응답 래퍼는 라우터 상단/엔트리 파일에서 찾아 각 엔드포인트에 적용한다
