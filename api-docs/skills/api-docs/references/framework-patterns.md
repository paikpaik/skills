# 프레임워크 패턴 참조

## 라우트 정의 패턴

### Express

```js
// 직접 정의
app.get('/path', handler)
app.post('/path', middleware, handler)

// Router 사용
const router = express.Router()
router.get('/path', handler)
app.use('/prefix', router)

// 탐색 grep 패턴
// router\.(get|post|put|patch|delete)\s*\(
// app\.(get|post|put|patch|delete)\s*\(
```

### Restify

```js
server.get('/path', handler)
server.post('/path', handler)
server.put('/path', handler)
server.del('/path', handler)   // delete 대신 del

// 탐색 grep 패턴
// server\.(get|post|put|patch|del)\s*\(
```

### NestJS

```ts
@Controller('prefix')
export class MyController {
  @Get('path')
  @Post('path')
  @Put(':id')
  @Patch(':id')
  @Delete(':id')
}

// 탐색 grep 패턴
// @(Get|Post|Put|Patch|Delete)\s*\(
// @Controller\s*\(
```

### Koa / Koa-Router

```js
router.get('/path', handler)
router.post('/path', handler)
app.use(router.routes())

// 탐색 grep 패턴
// router\.(get|post|put|patch|delete)\s*\(
```

### Fastify

```js
fastify.get('/path', opts, handler)
fastify.post('/path', opts, handler)
fastify.register(routes, { prefix: '/v1' })

// 탐색 grep 패턴
// fastify\.(get|post|put|patch|delete)\s*\(
```

---

## Prefix 합산 규칙

라우트의 최종 경로는 모든 prefix를 합산해 계산한다.

```
app.use('/api')
  → router.use('/v1')
    → router.get('/game/home')
      → 최종: GET /api/v1/game/home
```

**탐색 순서**:
1. 엔트리 파일(app.js, server.js, index.js)에서 `app.use(prefix, router)` 패턴 찾기
2. 라우터 파일 내 중첩 `router.use(prefix, subRouter)` 패턴 찾기
3. NestJS는 `@Controller(prefix)` + `@Get/Post(path)` 합산

---

## Auth 패턴

### 인증 미들웨어 탐지

아래 이름/패턴이 라우트 미들웨어 목록에 있으면 인증 필요로 판단한다.

```
# 미들웨어명 패턴
authenticate, authorize, auth, verifyToken, checkAuth,
requireAuth, isAuthenticated, jwtMiddleware, passportJwt,
bearerAuth, apiKeyAuth, basicAuth
```

### 인증 유형 판별

| 코드 패턴 | 인증 유형 |
|-----------|----------|
| `req.headers.authorization` + `Bearer` / `jwt.verify` | Bearer JWT |
| `req.headers.authorization` + `Basic` / `Buffer.from(...).toString('base64')` | Basic Auth |
| `req.headers['x-api-key']` / `req.headers['api-key']` | API Key |
| `req.session` / `req.user` (passport) | Session / OAuth |

### NestJS Guards

```ts
@UseGuards(JwtAuthGuard)    → Bearer JWT
@UseGuards(BasicAuthGuard)  → Basic Auth
@Public()                   → 인증 없음 (공개 데코레이터)
```

---

## Validation 스키마 패턴

### Joi

```js
const schema = Joi.object({
  userId: Joi.number().required(),
  amount: Joi.number().min(1).max(1000),
  type: Joi.string().valid('A', 'B').default('A'),
})
schema.validate(req.body)
```

### Zod

```ts
const schema = z.object({
  userId: z.number(),
  amount: z.number().min(1).optional(),
})
schema.parse(req.body)
```

### class-validator (NestJS)

```ts
class CreateRewardDto {
  @IsNumber()
  @IsNotEmpty()
  userId: number

  @IsOptional()
  @IsString()
  type?: string
}
```

---

## 공통 응답 래퍼 패턴

프로젝트마다 응답 형식이 다를 수 있다. 아래 패턴을 탐지해 공통 형식을 파악한다.

```js
// 패턴 1: 직접 객체
res.json({ code: 'SUCCESS', data: {...}, message: null })

// 패턴 2: 헬퍼 함수
sendSuccess(res, data)
ApiResponse.success(res, data)
reply.send({ result: data })

// 패턴 3: 미들웨어 주입
res.success(data)
res.error(code, message)
```

엔트리 파일이나 `middleware/response.js` 등에서 공통 래퍼를 찾아 전체에 적용한다.

---

## Redis 접근 패턴

```js
// ioredis / node-redis
redis.get(key)
redis.set(key, value)
redis.set(key, value, 'EX', ttlSeconds)
redis.del(key)
redis.expire(key, ttl)
redis.incr(key)
redis.hget(hash, field)
redis.hset(hash, field, value)

// 캐시 래퍼
cache.get(key)
cache.set(key, value, ttl)
cache.invalidate(key)
cacheManager.get(key)
```

키 패턴은 템플릿 리터럴로 추출한다:
```js
`reward:${userId}`       → reward:{userId}
`game:home:${userId}:v2` → game:home:{userId}:v2
```

---

## DB 접근 패턴

### Sequelize

```js
Model.findOne({ where: { id } })          → SELECT
Model.findAll({ where: { status } })      → SELECT
Model.create({ field: value })            → INSERT
Model.update({ field }, { where: { id }}) → UPDATE
Model.destroy({ where: { id } })          → DELETE
sequelize.query('SELECT ...', ...)        → RAW
```

### TypeORM

```ts
repository.findOne({ where: { id } })    → SELECT
repository.find({ where: { status } })   → SELECT
repository.save(entity)                  → INSERT / UPDATE
repository.delete({ id })                → DELETE
dataSource.query('SELECT ...')           → RAW
```

### Raw SQL (mysql2 / pg)

```js
db.query('SELECT ... FROM table WHERE ...')
db.execute('INSERT INTO table ...')
pool.query('UPDATE table SET ...')
```
