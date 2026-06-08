# Hawaldar API Documentation

**Base URL:** `http://localhost:8000/api/v1`

---

## Authentication

All `/api/v1/*` endpoints require the `X-API-Key` header.

| Header | Value |
|--------|-------|
| `X-API-Key` | Value from `HAWALDAR_API_KEY` env var (default: `hawaldar_dev_key_2024` in `.env`) |

---

## Rate Limiting

Enforced via middleware in `main.py`. Returns `429` with body:
```json
{"detail": "Rate limit exceeded. Please try again later."}
```

| Endpoint prefix | Limit |
|-----------------|-------|
| `/api/v1/accounts` | 10 requests / 60s per IP |
| `/api/v1/proxies` | 20 requests / 60s per IP |
| `/api/v1/dead-letters` | 30 requests / 60s per IP |
| Default (all other) | 100 requests / 60s per IP |

---

## Developer Docs

Available only when `HAWALDAR_ENV=development`.

| URL | Description |
|-----|-------------|
| `GET /api/v1/docs` | Swagger UI |
| `GET /api/v1/redoc` | ReDoc UI |
| `GET /api/v1/openapi.json` | OpenAPI JSON spec |

---

## Endpoints

---

### 1. Health Check

`GET /api/v1/health`

**Status:** Working

Standalone endpoint outside `api_router`. No auth required.

**Response:**
```json
{
  "status": "ok",
  "service": "hawaldar",
  "version": "0.1.0",
  "timestamp": "2025-01-01T00:00:00Z",
  "frontend": "up"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `status` | string | Always `"ok"` |
| `service` | string | Always `"hawaldar"` |
| `version` | string | Current version |
| `timestamp` | string | ISO datetime |
| `frontend` | string | `"up"` or `"down"` — checks if Nitro SSR server at `NITRO_PORT` is reachable |

**Example:**
```bash
curl http://localhost:8000/api/v1/health
```

---

### 2. System Health

`GET /api/v1/system/health`

**Status:** Working

**Response:**
```json
{
  "system": {
    "tasks": {
      "total": 120,
      "pending": 5,
      "claimed": 2,
      "running": 3,
      "completed": 100,
      "failed": 10,
      "dead_letter": 3
    },
    "workers": {
      "active": 3,
      "limit": 5
    },
    "proxies": {
      "total": 10,
      "active": 8,
      "degraded": 1,
      "dead": 1,
      "health_pct": 80.0
    },
    "accounts": {
      "total": 20,
      "active": 18
    },
    "timestamp": "2025-01-01T00:00:00Z"
  }
}
```

**Example:**
```bash
curl -H "X-API-Key: hawaldar_dev_key_2024" http://localhost:8000/api/v1/system/health
```

---

### 3. System Throughput

`GET /api/v1/system/throughput`

**Status:** Working

Returns 24 hourly buckets of scrape/post task counts from the last 24 hours, oldest first.

**Response:**
```json
{
  "throughput": [
    {"hour": "00:00", "scrape": 12, "post": 5},
    {"hour": "01:00", "scrape": 8, "post": 3},
    {"hour": "02:00", "scrape": 15, "post": 7},
    {"hour": "23:00", "scrape": 10, "post": 4}
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `hour` | string | `"H:00"` format |
| `scrape` | int | Completed scrape tasks in that hour |
| `post` | int | Completed post tasks in that hour |

Data sourced from tasks table `WHERE created_at >= 24h ago`, grouped by hour.

**Example:**
```bash
curl -H "X-API-Key: hawaldar_dev_key_2024" http://localhost:8000/api/v1/system/throughput
```

---

### 4. List Accounts

`GET /api/v1/accounts`

**Status:** Working

**Query Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `platform` | string | No | Filter by `"twitter"`, `"facebook"`, or `"instagram"` |
| `active_only` | string | No | `"true"` to show only active accounts |

**Response:**
```json
{
  "accounts": [
    {
      "id": "pf-tw-001",
      "name": "Main Account",
      "handle": "@main",
      "network": "twitter",
      "proxyId": "px-001",
      "proxyHost": "192.168.1.1:8080",
      "dailyCap": 50,
      "postedToday": 12,
      "active": true,
      "bypassProxy": false,
      "owner": "admin"
    }
  ],
  "total": 1
}
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | `browser_profile_id` or `"pf-{id:04d}"` |
| `proxyHost` | string | `"host:port"` from joined proxies table |
| `postedToday` | int | Count of completed post tasks for this account today |
| `active` | bool | Whether account is active |
| `bypassProxy` | bool | Whether account bypasses proxy |

**Example:**
```bash
curl -H "X-API-Key: hawaldar_dev_key_2024" \
  "http://localhost:8000/api/v1/accounts?platform=twitter&active_only=true"
```

---

### 5. Launch Account Browser

`POST /api/v1/accounts/{profile_id}/launch`

**Status:** Working

**Path Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `profile_id` | string | `browser_profile_id` (e.g. `"pf-tw-001"`) |

**Request Body:** None

**Response:**
```json
{
  "status": "launched",
  "profile_id": "pf-tw-001"
}
```

**Process:**
1. Decrypts encrypted_password from account record
2. Resolves proxy configuration
3. Spawns `scripts/auto_login.py` as subprocess
4. Writes credentials + proxy to stdin

**Errors:**
| Code | Condition |
|------|-----------|
| 404 | Profile not found |
| 400 | No encrypted password |
| 500 | Decryption fails |

**Example:**
```bash
curl -X POST \
  -H "X-API-Key: hawaldar_dev_key_2024" \
  http://localhost:8000/api/v1/accounts/pf-tw-001/launch
```

---

### 6. List Tasks

`GET /api/v1/tasks`

**Status:** Working

**Query Parameters:**

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `status` | string | No | — | Filter by task status |
| `task_type` | string | No | — | Filter by `"scrape"` or `"post"` |
| `limit` | int | No | 100 | Max results (cap: 500) |

**Response:**
```json
{
  "tasks": [
    {
      "id": "abc-123",
      "type": "Post",
      "profile": "pf-tw-001",
      "network": "twitter",
      "status": "Completed",
      "timestamp": "2025-01-01T00:00:00Z",
      "idempotencyKey": "key-xyz",
      "worker": 1
    }
  ],
  "total": 1
}
```

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | `task_type` capitalized |
| `status` | string | Task status capitalized |
| `worker` | int/null | Numeric worker ID from `claimed_by`, or null |

**Example:**
```bash
curl -H "X-API-Key: hawaldar_dev_key_2024" \
  "http://localhost:8000/api/v1/tasks?task_type=post&status=pending&limit=50"
```

---

### 7. List Dead Letters

`GET /api/v1/dead-letters`

**Status:** Working

**Query Parameters:**

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `limit` | int | No | 50 | Max results (cap: 200) |

**Response:**
```json
{
  "deadLetters": [
    {
      "id": "dl-001",
      "rawId": 42,
      "taskId": 100,
      "profile": "pf-tw-001",
      "type": "Post",
      "attempts": 3,
      "failedAt": "2025-01-01T00:00:00Z",
      "error": "Connection timeout",
      "trace": "full stack trace..."
    }
  ],
  "total": 1
}
```

| Field | Type | Description |
|-------|------|-------------|
| `rawId` | int | Numeric DB id for retry/dismiss calls |
| `attempts` | int | Read from `Task.attempts` (not hardcoded) |

**Example:**
```bash
curl -H "X-API-Key: hawaldar_dev_key_2024" \
  "http://localhost:8000/api/v1/dead-letters?limit=100"
```

---

### 8. Retry Dead Letter

`POST /api/v1/dead-letters/{dl_id}/retry`

**Status:** Working

**Path Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `dl_id` | int | The `rawId` from dead letter record |

**Request Body:** None

**Response:**
```json
{
  "status": "requeued",
  "taskId": 100
}
```

**Process:**
1. Resets Task: `status=pending`, clears lock/attempts/error
2. Deletes DeadLetter record

**Errors:**
| Code | Condition |
|------|-----------|
| 404 | Dead letter not found |

**Example:**
```bash
curl -X POST \
  -H "X-API-Key: hawaldar_dev_key_2024" \
  http://localhost:8000/api/v1/dead-letters/42/retry
```

---

### 9. Dismiss Dead Letter

`DELETE /api/v1/dead-letters/{dl_id}`

**Status:** Working

**Path Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `dl_id` | int | Numeric dead letter ID |

**Request Body:** None

**Response:**
```json
{
  "status": "dismissed",
  "id": 42
}
```

**Process:**
1. Marks Task as `"failed"`
2. Deletes DeadLetter record

**Errors:**
| Code | Condition |
|------|-----------|
| 404 | Dead letter not found |

**Example:**
```bash
curl -X DELETE \
  -H "X-API-Key: hawaldar_dev_key_2024" \
  http://localhost:8000/api/v1/dead-letters/42
```

---

### 10. Content Feed

`GET /api/v1/content-feed`

**Status:** Working

**Query Parameters:**

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `limit` | int | No | 50 | Max results (cap: 200) |

**Response:**
```json
{
  "feed": [
    {
      "id": "msg-001",
      "platform": "twitter",
      "messageId": "twt-msg-abc",
      "handle": "@main",
      "action": "post",
      "content": "Hello world!",
      "postedAt": "2025-01-01T00:00:00Z",
      "createdAt": "2025-01-01T00:00:00Z"
    }
  ],
  "total": 1
}
```

Reads from `processed_messages` table.

**Example:**
```bash
curl -H "X-API-Key: hawaldar_dev_key_2024" \
  "http://localhost:8000/api/v1/content-feed?limit=25"
```

---

### 11. List Proxies

`GET /api/v1/proxies`

**Status:** Working

**Query Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `status` | string | No | Filter by `"active"`, `"degraded"`, or `"dead"` |

**Response:**
```json
{
  "proxies": [
    {
      "id": "px-001",
      "rawId": 1,
      "host": "192.168.1.1:8080",
      "region": "us-east",
      "status": "active",
      "latencyMs": 120,
      "successRate": 98.5,
      "assignedProfiles": 3,
      "lastChecked": "2025-01-01T00:00:00Z"
    }
  ],
  "total": 1
}
```

| Field | Type | Description |
|-------|------|-------------|
| `rawId` | int | Numeric DB id |
| `latencyMs` | int | From in-memory cache (populated by `/check`), default 0 if unchecked |
| `successRate` | float | From in-memory cache, default 0 if unchecked |
| `assignedProfiles` | int | Count of accounts using this proxy |

**Example:**
```bash
curl -H "X-API-Key: hawaldar_dev_key_2024" \
  "http://localhost:8000/api/v1/proxies?status=active"
```

---

### 12. Check Proxy Health

`POST /api/v1/proxies/{proxy_id}/check`

**Status:** Working

**Path Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `proxy_id` | int | Numeric proxy ID |

**Request Body:** None

**Response (success):**
```json
{
  "id": "px-001",
  "latencyMs": 120,
  "successRate": 98.5,
  "success": true,
  "status": "Active",
  "checkedAt": "2025-01-01T00:00:00Z"
}
```

**Response (failure):**
```json
{
  "id": "px-001",
  "latencyMs": 0,
  "successRate": 0,
  "success": false,
  "status": "Degraded",
  "checkedAt": "2025-01-01T00:00:00Z"
}
```

**Process:**
1. Builds proxy URL with decrypted password
2. Makes GET to `http://httpbin.org/ip` through proxy
3. Measures latency
4. On success: stores latency in cache, updates `last_checked_at`
5. On failure: marks proxy as `"degraded"`, latency=0, successRate=0

**Example:**
```bash
curl -X POST \
  -H "X-API-Key: hawaldar_dev_key_2024" \
  http://localhost:8000/api/v1/proxies/1/check
```

---

## Frontend Integration

All frontend hooks live in `src/hooks/useApi.ts`.

| Hook | Endpoint | Refresh Interval |
|------|----------|------------------|
| `useHealth` | `/health` | 15s |
| `useThroughput` | `/system/throughput` | 30s |
| `useAccounts` | `/accounts` | 30s |
| `useTasks` | `/tasks` | 20s |
| `useProxies` | `/proxies` | 30s |
| `useDeadLetters` | `/dead-letters` | 20s |
| `useContentFeed` | `/content-feed` | 30s |

All hooks use:
- `API_BASE` = `VITE_API_BASE_URL` env var or `"http://localhost:8000/api/v1"`
- `X-API-Key` header from `VITE_API_KEY` env var

---

## Broken / Stub Endpoints

These exist in `src/lib/api.ts` but have **no backend implementation**:

| Function | Client Path | Status |
|----------|-------------|--------|
| `toggleProfile()` | `PATCH /accounts/{profileId}/toggle` | **Broken** — 404 |
| `swapProxy()` | `POST /proxies/{proxyId}/swap` | **Broken** — 404 |
| `requeueTask()` | `POST /dead-letters/{taskId}/requeue` | **Broken** — wrong path, should be `/dead-letters/{dl_id}/retry` |
| `purgeTask()` | `DELETE /dead-letters/{taskId}` | **Broken** — wrong param type, should be integer `dl_id` |

### Corrected Endpoints (working):

| Client Intent | Correct Path |
|---------------|--------------|
| Requeue dead letter | `POST /dead-letters/{dl_id}/retry` |
| Dismiss dead letter | `DELETE /dead-letters/{dl_id}` |

---

## Quick Reference

| # | Method | Endpoint | Auth | Rate |
|---|--------|----------|------|------|
| 1 | GET | `/health` | No | 100/60s |
| 2 | GET | `/system/health` | Yes | 100/60s |
| 3 | GET | `/system/throughput` | Yes | 100/60s |
| 4 | GET | `/accounts` | Yes | 10/60s |
| 5 | POST | `/accounts/{id}/launch` | Yes | 10/60s |
| 6 | GET | `/tasks` | Yes | 100/60s |
| 7 | GET | `/dead-letters` | Yes | 30/60s |
| 8 | POST | `/dead-letters/{id}/retry` | Yes | 30/60s |
| 9 | DELETE | `/dead-letters/{id}` | Yes | 30/60s |
| 10 | GET | `/content-feed` | Yes | 100/60s |
| 11 | GET | `/proxies` | Yes | 20/60s |
| 12 | POST | `/proxies/{id}/check` | Yes | 20/60s |
