# Hawaldar — Complete Testing Guide

> Backend: FastAPI on `http://localhost:8000`  
> Frontend: Nitro SSR on `http://localhost:3001` (proxied through FastAPI)  
> API prefix: `/api/v1`  
> Auth header: `X-API-Key: hawaldar_dev_key_2024`  
> Database: SQLite at `data/hawaldar.db` (seeded with 6 accounts, 5 proxies, 10 tasks, 15 messages, 42 daily stats, 1 dead letter)

---

## Table of Contents

1. [Authentication](#1-authentication)
2. [Rate Limiting](#2-rate-limiting)
3. [Health Endpoints](#3-health-endpoints)
4. [System Health & Throughput](#4-system-health--throughput)
5. [Account Registry](#5-account-registry)
6. [Account Launch](#6-account-launch)
7. [Task Ledger](#7-task-ledger)
8. [Dead Letter Queue](#8-dead-letter-queue)
9. [Content Feed](#9-content-feed)
10. [Proxy Pool](#10-proxy-pool)
11. [Proxy Health Check](#11-proxy-health-check)
12. [Worker Pool](#12-worker-pool)
13. [Browser Anti-Detection](#13-browser-anti-detection)
14. [Frontend — Home Page](#14-frontend--home-page)
15. [Frontend — Admin Page](#15-frontend--admin-page)
16. [Frontend — Dashboard Page](#16-frontend--dashboard-page)
17. [Frontend — Broken API Functions](#17-frontend--broken-api-functions)
18. [Database Integrity](#18-database-integrity)
19. [CORS Configuration](#19-cors-configuration)
20. [Favicon Endpoints](#20-favicon-endpoints)

---

## 1. Authentication

### TC-AUTH-001: Valid API key grants access

**Preconditions:** Backend running on port 8000. `.env` contains `HAWALDAR_API_KEY=hawaldar_dev_key_2024`.

**Test Data:**
```
Header: X-API-Key: hawaldar_dev_key_2024
```

**Steps:**
1. Send `GET http://localhost:8000/api/v1/accounts` with header `X-API-Key: hawaldar_dev_key_2024`.

**Expected Result:** HTTP 200. Response body contains `{"accounts": [...], "total": 6}`.

**Implementation Details:** `api/deps.py:32-40` — `verify_api_key()` reads `HAWALDAR_API_KEY` env var, compares against header. `api/router.py:18` — dependency applied to all `/api/v1/*` routes.

**Failure Scenarios:**
- Missing header → HTTP 401 `{"detail": "Invalid or missing API Key"}`
- Wrong key → HTTP 401
- Empty key → HTTP 401

---

### TC-AUTH-002: Missing API key returns 401

**Preconditions:** Backend running.

**Test Data:**
```
No X-API-Key header
```

**Steps:**
1. Send `GET http://localhost:8000/api/v1/accounts` with no API key header.

**Expected Result:** HTTP 401 `{"detail": "Invalid or missing API Key"}`.

**Implementation Details:** `api/deps.py:32-40` — `auto_error=False` in `APIKeyHeader`, then explicit check in `verify_api_key()`.

**Failure Scenarios:**
- If `HAWALDAR_API_KEY` env var is unset, default is `"change_me_in_production"` — all requests with the real key will fail.
- If middleware crashes before auth, FastAPI returns 500.

---

### TC-AUTH-003: Health endpoint bypasses authentication

**Preconditions:** Backend running. No API key provided.

**Test Data:**
```
GET http://localhost:8000/api/v1/health
No headers
```

**Steps:**
1. Send `GET http://localhost:8000/api/v1/health` without any API key.

**Expected Result:** HTTP 200. Response body contains `{"status": "ok", "service": "hawaldar", ...}`.

**Implementation Details:** `main.py:128-145` — `/api/v1/health` is defined directly on the FastAPI `app`, not on `api_router` which has the `verify_api_key` dependency. `api/router.py:18` — dependency only applies to `api_router`.

**Failure Scenarios:**
- If someone moves the health endpoint into `api_router`, it would require auth — breaking the health check.
- Nitro frontend being down returns `"frontend": "down"` but does not fail the request.

---

## 2. Rate Limiting

### TC-RL-001: Accounts endpoint rate limit (10/60s)

**Preconditions:** Backend running. Valid API key available.

**Test Data:**
```
11 rapid requests to /api/v1/accounts
```

**Steps:**
1. Send 10 `GET /api/v1/accounts` requests within 60 seconds.
2. Send an 11th request.

**Expected Result:** First 10 return HTTP 200. 11th returns HTTP 429 `{"detail": "Rate limit exceeded. Please try again later."}`.

**Implementation Details:** `main.py:75-116` — `rate_limiter_middleware` checks `_request_history[(ip, "/api/v1/accounts")]`. Limit is `(10, 60)` from `RATE_LIMIT_WINDOWS`.

**Failure Scenarios:**
- `_request_history` is an in-memory dict — resets on server restart.
- No cleanup of old entries beyond the window check — memory grows unbounded under sustained load.
- Different client IPs get independent buckets — no cross-IP limiting.

---

### TC-RL-002: Proxies endpoint rate limit (20/60s)

**Preconditions:** Backend running. Valid API key.

**Test Data:**
```
21 rapid requests to /api/v1/proxies
```

**Steps:**
1. Send 20 `GET /api/v1/proxies` requests within 60 seconds.
2. Send a 21st request.

**Expected Result:** First 20 return HTTP 200. 21st returns HTTP 429.

**Implementation Details:** `main.py:77` — `"/api/v1/proxies": (20, 60)`.

**Failure Scenarios:**
- Same as TC-RL-001 — in-memory, no persistence, no cross-IP limiting.

---

### TC-RL-003: Dead-letters endpoint rate limit (30/60s)

**Preconditions:** Backend running. Valid API key.

**Test Data:**
```
31 rapid requests to /api/v1/dead-letters
```

**Steps:**
1. Send 30 `GET /api/v1/dead-letters` requests within 60 seconds.
2. Send a 31st request.

**Expected Result:** First 30 return HTTP 200. 31st returns HTTP 429.

**Implementation Details:** `main.py:78` — `"/api/v1/dead-letters": (30, 60)`.

**Failure Scenarios:**
- Same as above.

---

### TC-RL-004: Default rate limit (100/60s)

**Preconditions:** Backend running. Valid API key.

**Test Data:**
```
101 rapid requests to /api/v1/tasks
```

**Steps:**
1. Send 100 `GET /api/v1/tasks` requests within 60 seconds.
2. Send a 101st request.

**Expected Result:** First 100 return HTTP 200. 101st returns HTTP 429.

**Implementation Details:** `main.py:80` — `DEFAULT_LIMIT = (100, 60)`. `main.py:100-101` — if no route key matches, uses `"default"`.

**Failure Scenarios:**
- Endpoints not in `RATE_LIMIT_WINDOWS` and not under `/api/v1` are not rate-limited at all (e.g., `/favicon.ico`).

---

### TC-RL-005: Non-API routes bypass rate limiting

**Preconditions:** Backend running.

**Test Data:**
```
GET http://localhost:8000/favicon.ico
```

**Steps:**
1. Send 200 rapid requests to `http://localhost:8000/favicon.ico`.

**Expected Result:** All return HTTP 204. No rate limiting applied.

**Implementation Details:** `main.py:87-88` — `if not path.startswith("/api/v1"): return await call_next(request)`.

**Failure Scenarios:**
- If the prefix check is removed, favicon and frontend proxy requests would be rate-limited.

---

## 3. Health Endpoints

### TC-HEALTH-001: Standalone health check

**Preconditions:** Backend running on port 8000.

**Test Data:**
```
GET http://localhost:8000/api/v1/health
```

**Steps:**
1. Send `GET http://localhost:8000/api/v1/health`.

**Expected Result:** HTTP 200. Body:
```json
{
  "status": "ok",
  "service": "hawaldar",
  "version": "0.1.0",
  "timestamp": "<ISO 8601 UTC>",
  "frontend": "up" | "down"
}
```

**Implementation Details:** `main.py:128-145` — Makes async HTTP call to `NITRO_URL` (port from `NITRO_PORT` env, default 8080) with 2s timeout. If Nitro responds with status < 500, `frontend` is `"up"`, otherwise `"down"`.

**Failure Scenarios:**
- Nitro not running → `frontend: "down"`, HTTP still 200.
- `httpx.ConnectError` caught silently — no crash.
- `NITRO_PORT` env var misconfigured → always `"down"`.

---

## 4. System Health & Throughput

### TC-SYS-001: System health returns live task counts

**Preconditions:** Backend running. Database seeded.

**Test Data:**
```
GET http://localhost:8000/api/v1/system/health
Header: X-API-Key: hawaldar_dev_key_2024
```

**Steps:**
1. Send `GET /api/v1/system/health` with valid API key.

**Expected Result:** HTTP 200. Body wrapped in `{"system": {...}}`:
```json
{
  "system": {
    "tasks": {"total": 10, "pending": 4, "claimed": 1, "running": 1, "completed": 3, "failed": 0, "dead_letter": 1},
    "workers": {"active": <running_count>, "limit": 5},
    "proxies": {"total": 5, "active": 4, "degraded": 1, "dead": 0, "health_pct": 80},
    "accounts": {"total": 6, "active": 5},
    "timestamp": "<ISO 8601 UTC>"
  }
}
```

**Implementation Details:** `api/routes_system.py:19-98` — Queries `Task`, `Proxy`, `Account` tables. Groups task counts by status, proxy counts by status. `workers.active` = `running` task count. `workers.limit` = hardcoded `5`. `health_pct` = `round((active/total)*100)`.

**Failure Scenarios:**
- Empty database → all counts 0, `health_pct` 0.
- DB locked by concurrent write → SQLAlchemy `OperationalError`.
- If response is not wrapped in `system` key → frontend `AdminHealthHub` crashes at `data!.system` (`AdminHealthHub.tsx:29`).

---

### TC-SYS-002: System throughput returns 24 hourly buckets

**Preconditions:** Backend running. Database seeded.

**Test Data:**
```
GET http://localhost:8000/api/v1/system/throughput
Header: X-API-Key: hawaldar_dev_key_2024
```

**Steps:**
1. Send `GET /api/v1/system/throughput` with valid API key.

**Expected Result:** HTTP 200. Body:
```json
{
  "throughput": [
    {"hour": "0:00", "scrape": 0, "post": 0},
    {"hour": "1:00", "scrape": 0, "post": 0},
    ...
    {"hour": "23:00", "scrape": <count>, "post": <count>}
  ]
}
```
Exactly 24 buckets, oldest first. Each bucket has `hour`, `scrape`, `post` (integers).

**Implementation Details:** `api/routes_system.py:101-147` — Builds 24 empty buckets for the last 24 hours, then iterates `Task` rows where `created_at >= cutoff` (24h ago). Maps `task_type` ("scrape"/"post") to the matching hour bucket. Only tasks within the last 24 hours appear.

**Failure Scenarios:**
- No tasks in last 24h → all buckets show 0/0.
- `Task.created_at` is NULL → skipped by `if not created_at_str` check.
- Invalid `created_at` format → caught by `except (ValueError, AttributeError)`.
- Frontend `AdminHealthHub.tsx:38-40` falls back to empty 24h array if data is null.

---

## 5. Account Registry

### TC-ACCT-001: List all accounts

**Preconditions:** Backend running. Database seeded with 6 accounts.

**Test Data:**
```
GET http://localhost:8000/api/v1/accounts
Header: X-API-Key: hawaldar_dev_key_2024
```

**Steps:**
1. Send `GET /api/v1/accounts` with valid API key.

**Expected Result:** HTTP 200. Body:
```json
{
  "accounts": [
    {
      "id": "pf-tw-001",
      "name": "Tech Startup Daily",
      "handle": "techstartup_daily",
      "network": "Twitter",
      "proxyId": "px-001",
      "proxyHost": "198.51.100.42:8080",
      "dailyCap": 5,
      "postedToday": 0,
      "active": true,
      "bypassProxy": false,
      "owner": "system"
    },
    ...
  ],
  "total": 6
}
```

**Implementation Details:** `api/routes_accounts.py:29-91` — Joins `Account` with `Proxy` for host, counts today's completed "post" tasks for `postedToday`. `id` field uses `browser_profile_id` if set, else generates `pf-{id:04d}`.

**Failure Scenarios:**
- Empty DB → `{"accounts": [], "total": 0}`.
- Account with no proxy → `proxyId: ""`, `proxyHost: ""`.
- `postedToday` counts only tasks with `status == "completed"` and `completed_at` matching today's ISO date.

---

### TC-ACCT-002: Filter accounts by platform

**Preconditions:** Backend running. Database seeded.

**Test Data:**
```
GET http://localhost:8000/api/v1/accounts?platform=twitter
Header: X-API-Key: hawaldar_dev_key_2024
```

**Steps:**
1. Send `GET /api/v1/accounts?platform=twitter`.
2. Send `GET /api/v1/accounts?platform=facebook`.
3. Send `GET /api/v1/accounts?platform=instagram`.

**Expected Result:**
1. Returns 3 accounts (techstartup_daily, codehumor_bot, devtoolscurator).
2. Returns 2 accounts (ai_newsroom, startupstories_daily).
3. Returns 1 account (designpulse_feed).

**Implementation Details:** `api/routes_accounts.py:44-45` — `q.filter(Account.platform == platform.lower())`. The filter is case-insensitive via `.lower()`.

**Failure Scenarios:**
- Unknown platform string → returns empty list `{"accounts": [], "total": 0}` (no error).
- Case mismatch handled by `.lower()`.

---

### TC-ACCT-003: Filter accounts by active status

**Preconditions:** Backend running. Database seeded (5 active, 1 inactive).

**Test Data:**
```
GET http://localhost:8000/api/v1/accounts?active_only=true
Header: X-API-Key: hawaldar_dev_key_2024
```

**Steps:**
1. Send `GET /api/v1/accounts?active_only=true`.

**Expected Result:** Returns 5 accounts (devtoolscurator excluded since `is_active=False`).

**Implementation Details:** `api/routes_accounts.py:46-47` — `q.filter(Account.is_active == True)`.

**Failure Scenarios:**
- `active_only=false` returns all 6 (default behavior).
- Boolean parsing: FastAPI Query handles `"true"`, `"false"`, `"1"`, `"0"`.

---

### TC-ACCT-004: Combined platform and active_only filters

**Preconditions:** Backend running. Database seeded.

**Test Data:**
```
GET http://localhost:8000/api/v1/accounts?platform=twitter&active_only=true
```

**Steps:**
1. Send the combined filter request.

**Expected Result:** Returns 2 accounts (twitter accounts excluding devtoolscurator which is inactive).

**Implementation Details:** `api/routes_accounts.py:44-47` — Both filters applied via chained `filter()`.

**Failure Scenarios:**
- No accounts match both filters → empty list.

---

## 6. Account Launch

### TC-LAUNCH-001: Launch browser for valid profile

**Preconditions:** Backend running. Database seeded. `scripts/auto_login.py` exists.

**Test Data:**
```
POST http://localhost:8000/api/v1/accounts/pf-tw-001/launch
Header: X-API-Key: hawaldar_dev_key_2024
```

**Steps:**
1. Send `POST /api/v1/accounts/pf-tw-001/launch` with valid API key.

**Expected Result:** HTTP 200. Body:
```json
{"status": "launched", "profile_id": "pf-tw-001"}
```

**Implementation Details:** `api/routes_accounts.py:94-170` — Looks up account by `browser_profile_id`. Decrypts `encrypted_password` via `utils.crypto.decrypt`. Resolves proxy config if assigned. Spawns `subprocess.Popen` running `scripts/auto_login.py` with profile_id and username. Credentials piped via stdin (not CLI args). Uses `CREATE_NO_WINDOW` on Windows.

**Failure Scenarios:**
- Profile not found → HTTP 404 `{"detail": "Profile pf-tw-001 not found"}`.
- No encrypted password → HTTP 400 `{"detail": "No encrypted password stored for this account"}`.
- Decryption fails → HTTP 500 `{"detail": "Internal server error occurred during decryption"}`.
- `auto_login.py` subprocess fails → API still returns 200 (fire-and-forget). Failure logged.
- stdin write fails → logged but does not crash request.

---

### TC-LAUNCH-002: Launch with non-existent profile

**Preconditions:** Backend running.

**Test Data:**
```
POST http://localhost:8000/api/v1/accounts/pf-fake-999/launch
Header: X-API-Key: hawaldar_dev_key_2024
```

**Steps:**
1. Send `POST /api/v1/accounts/pf-fake-999/launch`.

**Expected Result:** HTTP 404 `{"detail": "Profile pf-fake-999 not found"}`.

**Implementation Details:** `api/routes_accounts.py:104-106` — `Account.browser_profile_id == profile_id` query returns None.

**Failure Scenarios:**
- None beyond expected 404.

---

## 7. Task Ledger

### TC-TASK-001: List all tasks

**Preconditions:** Backend running. Database seeded with 10 tasks.

**Test Data:**
```
GET http://localhost:8000/api/v1/tasks
Header: X-API-Key: hawaldar_dev_key_2024
```

**Steps:**
1. Send `GET /api/v1/tasks` with valid API key.

**Expected Result:** HTTP 200. Body:
```json
{
  "tasks": [
    {
      "id": "tsk-00000001",
      "type": "Scrape",
      "profile": "Tech Startup Daily",
      "network": "Twitter",
      "status": "Pending",
      "timestamp": "<ISO 8601>",
      "idempotencyKey": "idem-0001",
      "worker": null
    },
    ...
  ],
  "total": 10
}
```
Ordered by `created_at DESC`. Default limit 100.

**Implementation Details:** `api/routes_tasks.py:23-80` — Queries `Task`, joins `Account` for profile name. `worker` extracted from `claimed_by` string (e.g., `"worker-1"` → `1`). `type` capitalized (e.g., "Scrape", "Post"). `status` capitalized.

**Failure Scenarios:**
- Empty task list → `{"tasks": [], "total": 0}`.
- Task with no account → `profile` falls back to `"account-{id}"`.
- `claimed_by` does not start with `"worker-"` → `worker: null`.

---

### TC-TASK-002: Filter tasks by status

**Preconditions:** Backend running. Database seeded.

**Test Data:**
```
GET http://localhost:8000/api/v1/tasks?status=pending
```

**Steps:**
1. Send `GET /api/v1/tasks?status=pending`.

**Expected Result:** Returns only tasks with `"status": "Pending"`. Based on seed data: tasks 1, 3, 7, 9 (4 pending tasks).

**Implementation Details:** `api/routes_tasks.py:39-40` — `q.filter(Task.status == status.lower())`.

**Failure Scenarios:**
- Unknown status → empty list.
- Case handled by `.lower()`.

---

### TC-TASK-003: Filter tasks by type

**Preconditions:** Backend running. Database seeded.

**Test Data:**
```
GET http://localhost:8000/api/v1/tasks?task_type=scrape
```

**Steps:**
1. Send `GET /api/v1/tasks?task_type=scrape`.

**Expected Result:** Returns only scrape tasks (tasks 1, 2, 5, 7, 8, 10 = 6 tasks).

**Implementation Details:** `api/routes_tasks.py:41-42` — `q.filter(Task.task_type == task_type.lower())`.

**Failure Scenarios:**
- Unknown type → empty list.

---

### TC-TASK-004: Limit task results

**Preconditions:** Backend running. Database seeded.

**Test Data:**
```
GET http://localhost:8000/api/v1/tasks?limit=3
```

**Steps:**
1. Send `GET /api/v1/tasks?limit=3`.

**Expected Result:** Returns exactly 3 tasks.

**Implementation Details:** `api/routes_tasks.py:44` — `.limit(limit)` applied after ordering.

**Failure Scenarios:**
- `limit=0` → FastAPI validation error (constraint `ge=1`).
- `limit=501` → FastAPI validation error (constraint `le=500`).

---

## 8. Dead Letter Queue

### TC-DLQ-001: List dead letters

**Preconditions:** Backend running. Database seeded with 1 dead letter.

**Test Data:**
```
GET http://localhost:8000/api/v1/dead-letters
Header: X-API-Key: hawaldar_dev_key_2024
```

**Steps:**
1. Send `GET /api/v1/dead-letters` with valid API key.

**Expected Result:** HTTP 200. Body:
```json
{
  "deadLetters": [
    {
      "id": "dlq-001",
      "rawId": 1,
      "taskId": "tsk-00000010",
      "profile": "Dev Tools Curator",
      "type": "Scrape",
      "attempts": 0,
      "failedAt": "<ISO 8601>",
      "error": "Timeout: page did not load within 30s",
      "trace": "{\"url\": ...}"
    }
  ],
  "total": 1
}
```

**Implementation Details:** `api/routes_tasks.py:87-145` — Queries `DeadLetter` ordered by `failed_at DESC`. Joins `Task` for `attempts` count and `task_type`. Joins `Account` for profile name. `rawId` is the numeric DB ID used for retry/dismiss API calls.

**Failure Scenarios:**
- Empty DLQ → `{"deadLetters": [], "total": 0}`.
- Dead letter with no task → `taskId: ""`, `type: "Post"` (default).
- `task.attempts` is None → defaults to 0 (`task.attempts or 0`).

---

### TC-DLQ-002: Retry dead letter — requeues task

**Preconditions:** Backend running. Database seeded with 1 dead letter (id=1, task_id linked to dead_letter status task).

**Test Data:**
```
POST http://localhost:8000/api/v1/dead-letters/1/retry
Header: X-API-Key: hawaldar_dev_key_2024
```

**Steps:**
1. Send `POST /api/v1/dead-letters/1/retry`.
2. Verify the linked task status changed to `"pending"`.
3. Verify the dead letter record is deleted.

**Expected Result:** HTTP 200. Body:
```json
{"status": "requeued", "taskId": <task_id>}
```
Task status → `"pending"`, `claimed_by` → null, `locked_at` → null, `attempts` → 0, `error_message` → null. Dead letter record deleted.

**Implementation Details:** `api/routes_tasks.py:148-175` — Finds `DeadLetter` by numeric ID. Resets linked `Task`: `status="pending"`, clears `claimed_by`, `locked_at`, `attempts=0`, `error_message=None`. Deletes `DeadLetter` row. Commits.

**Failure Scenarios:**
- Dead letter not found → HTTP 404 `{"detail": "Dead letter not found"}`.
- Task already claimed by another worker → reset still applies (race condition possible).
- DB commit fails → session rollback, dead letter not deleted.

---

### TC-DLQ-003: Dismiss dead letter — marks task failed

**Preconditions:** Backend running. Database seeded.

**Test Data:**
```
DELETE http://localhost:8000/api/v1/dead-letters/1
Header: X-API-Key: hawaldar_dev_key_2024
```

**Steps:**
1. Send `DELETE /api/v1/dead-letters/1`.
2. Verify the linked task status changed to `"failed"`.
3. Verify the dead letter record is deleted.

**Expected Result:** HTTP 200. Body:
```json
{"status": "dismissed", "id": 1}
```
Task status → `"failed"`. Dead letter record deleted.

**Implementation Details:** `api/routes_tasks.py:178-201` — Finds `DeadLetter` by numeric ID. Sets linked `Task.status = "failed"`. Deletes `DeadLetter` row. Commits.

**Failure Scenarios:**
- Dead letter not found → HTTP 404 `{"detail": "Dead letter not found"}`.
- Task does not exist → only dead letter deleted, no task update.

---

## 9. Content Feed

### TC-FEED-001: List content feed

**Preconditions:** Backend running. Database seeded with 15 processed messages.

**Test Data:**
```
GET http://localhost:8000/api/v1/content-feed
Header: X-API-Key: hawaldar_dev_key_2024
```

**Steps:**
1. Send `GET /api/v1/content-feed` with valid API key.

**Expected Result:** HTTP 200. Body:
```json
{
  "feed": [
    {
      "id": "msg-000015",
      "platform": "Instagram",
      "messageId": "msg-0015",
      "handle": "designpulse_feed",
      "action": "scraped",
      "content": "Sample content from @designpulse_feed — message #15",
      "postedAt": "<ISO 8601>",
      "createdAt": "<ISO 8601>"
    },
    ...
  ],
  "total": 15
}
```
Ordered by `created_at DESC`. Default limit 50. Content truncated to 500 chars.

**Implementation Details:** `api/routes_tasks.py:208-251` — Queries `ProcessedMessage`, joins `Account` for handle. Content truncated via `[:500]`. `action` defaults to `"scraped"` if None.

**Failure Scenarios:**
- Empty feed → `{"feed": [], "total": 0}`.
- Message with no account → `handle: "unknown"`.
- `platform` is None → `"Unknown"`.

---

### TC-FEED-002: Content feed with custom limit

**Preconditions:** Backend running. Database seeded.

**Test Data:**
```
GET http://localhost:8000/api/v1/content-feed?limit=5
```

**Steps:**
1. Send `GET /api/v1/content-feed?limit=5`.

**Expected Result:** Returns exactly 5 feed items.

**Implementation Details:** `api/routes_tasks.py:209` — `Query(50, ge=1, le=200)`.

**Failure Scenarios:**
- `limit=0` → validation error.
- `limit=201` → validation error.

---

## 10. Proxy Pool

### TC-PROXY-001: List all proxies

**Preconditions:** Backend running. Database seeded with 5 proxies.

**Test Data:**
```
GET http://localhost:8000/api/v1/proxies
Header: X-API-Key: hawaldar_dev_key_2024
```

**Steps:**
1. Send `GET /api/v1/proxies` with valid API key.

**Expected Result:** HTTP 200. Body:
```json
{
  "proxies": [
    {
      "id": "px-001",
      "rawId": 1,
      "host": "198.51.100.42:8080",
      "region": "US",
      "status": "Active",
      "latencyMs": 0,
      "successRate": 100,
      "assignedProfiles": 1,
      "lastChecked": "<ISO 8601>"
    },
    ...
  ],
  "total": 5
}
```

**Implementation Details:** `api/routes_proxies.py:29-85` — Queries `Proxy`, counts assigned `Account` records. `latencyMs` and `successRate` from in-memory `_latency_cache` (populated by `/check` endpoint). Defaults: Active→100%, Degraded→75%, Dead→0%.

**Failure Scenarios:**
- Empty proxy pool → `{"proxies": [], "total": 0}`.
- Cache empty → uses status-based defaults.
- Proxy with no `country` → `region: "unknown"`.

---

### TC-PROXY-002: Filter proxies by status

**Preconditions:** Backend running. Database seeded.

**Test Data:**
```
GET http://localhost:8000/api/v1/proxies?status=active
```

**Steps:**
1. Send `GET /api/v1/proxies?status=active`.
2. Send `GET /api/v1/proxies?status=degraded`.

**Expected Result:**
1. Returns 4 active proxies (px-001, px-002, px-004, px-005).
2. Returns 1 degraded proxy (px-003).

**Implementation Details:** `api/routes_proxies.py:45-46` — `q.filter(Proxy.status == status.lower())`.

**Failure Scenarios:**
- Unknown status → empty list.
- `"Dead"` status → returns 0 (no dead proxies in seed data).

---

## 11. Proxy Health Check

### TC-PCHECK-001: Check a reachable proxy

**Preconditions:** Backend running. Proxy at px-001 is active and reachable.

**Test Data:**
```
POST http://localhost:8000/api/v1/proxies/1/check
Header: X-API-Key: hawaldar_dev_key_2024
```

**Steps:**
1. Send `POST /api/v1/proxies/1/check`.
2. Verify latency is stored in cache.
3. Verify `lastCheckedAt` updated in DB.

**Expected Result:** HTTP 200. Body:
```json
{
  "id": "px-001",
  "latencyMs": <positive_integer>,
  "successRate": 100,
  "success": true,
  "status": "Active",
  "checkedAt": "<ISO 8601>"
}
```

**Implementation Details:** `api/routes_proxies.py:88-156` — Builds proxy URL with auth. Makes real HTTP GET to `http://httpbin.org/ip` through the proxy with 8s timeout. Measures latency via `time.perf_counter()`. Updates `_latency_cache` in-memory. Persists `last_checked_at`. If success and was "degraded" → auto-promotes to "active". If failure and was "active" → auto-degrades to "degraded".

**Failure Scenarios:**
- Proxy unreachable → `latencyMs: 0`, `successRate: 0`, `success: false`, `status: "Degraded"`.
- Proxy ID not found → HTTP 404 `{"detail": "Proxy 1 not found"}`.
- `httpbin.org` down → treated as proxy failure.
- Timeout after 8s → failure.
- Password decryption fails → raw password used.

---

### TC-PCHECK-002: Check non-existent proxy

**Preconditions:** Backend running.

**Test Data:**
```
POST http://localhost:8000/api/v1/proxies/999/check
Header: X-API-Key: hawaldar_dev_key_2024
```

**Steps:**
1. Send `POST /api/v1/proxies/999/check`.

**Expected Result:** HTTP 404 `{"detail": "Proxy 999 not found"}`.

**Implementation Details:** `api/routes_proxies.py:99-101` — Query returns None, raises `HTTPException(404)`.

**Failure Scenarios:**
- None beyond expected 404.

---

### TC-PCHECK-003: Auto-degrade on failed check

**Preconditions:** Backend running. Proxy at px-001 is "active".

**Test Data:**
```
POST http://localhost:8000/api/v1/proxies/1/check
(with proxy configured to be unreachable)
```

**Steps:**
1. Ensure proxy 1 is currently "active" in DB.
2. Send `POST /api/v1/proxies/1/check` (check will fail).
3. Query `GET /api/v1/proxies?status=degraded`.

**Expected Result:** Proxy 1 status changes from "active" to "degraded". The `success` field in the check response is `false`.

**Implementation Details:** `api/routes_proxies.py:141-144` — `if not success and proxy.status == "active": proxy.status = "degraded"`.

**Failure Scenarios:**
- Already degraded → stays degraded.
- Already dead → no change.

---

### TC-PCHECK-004: Auto-promote on successful check

**Preconditions:** Backend running. Proxy at px-003 is "degraded".

**Test Data:**
```
POST http://localhost:8000/api/v1/proxies/3/check
```

**Steps:**
1. Send `POST /api/v1/proxies/3/check` (check succeeds).
2. Verify proxy status changed to "active".

**Expected Result:** `success: true`, `status: "Active"`.

**Implementation Details:** `api/routes_proxies.py:143-144` — `elif success and proxy.status == "degraded": proxy.status = "active"`.

**Failure Scenarios:**
- If proxy was "dead" → no auto-promote (only dead→active requires explicit handling not implemented).

---

## 12. Worker Pool

### TC-WORKER-001: Worker pool caps at MAX_CONCURRENT

**Preconditions:** Backend running. Worker pool started via `start_pool()`.

**Test Data:**
```
5 or more pending tasks in database
```

**Steps:**
1. Start the worker pool with `num_workers=5`.
2. Insert 6+ pending tasks.
3. Observe logs.

**Expected Result:** Only 5 workers are spawned. The 6th task stays pending until a worker finishes.

**Implementation Details:** `orchestrator/worker_pool.py:164-168` — `start_pool(num_workers=MAX_CONCURRENT)` creates `MAX_CONCURRENT` (5) `asyncio.Task` instances. Each worker loops: claim → execute → complete/fail → repeat.

**Failure Scenarios:**
- If `MAX_CONCURRENT` changed to 0 → no workers spawned, tasks stay pending.
- If a worker crashes → `asyncio.gather` does not restart it (no supervision).
- If DB engine shared across workers → potential thread safety issues (SQLite single-writer).

---

### TC-WORKER-002: Worker claims pending task

**Preconditions:** Worker pool running. At least 1 pending task with `scheduled_at <= now`.

**Test Data:**
```
Task: status="pending", scheduled_at="<past>", priority=5
```

**Steps:**
1. Insert a pending task.
2. Wait for worker to claim it.

**Expected Result:** Task status changes to `"claimed"`, `claimed_by` set to `"worker-{id}"`, `locked_at` set to current UTC.

**Implementation Details:** `orchestrator/worker_pool.py:66-86` — Uses `SELECT ... FOR UPDATE SKIP LOCKED` pattern (SQLite emulation). Selects by `priority ASC, scheduled_at ASC`. Updates `status="claimed"`, `claimed_by`, `locked_at`.

**Failure Scenarios:**
- No pending tasks → worker sleeps 5s, retries.
- Task `scheduled_at` in future → not claimed.
- Two workers try to claim same task → SQLite serialization, one wins.

---

### TC-WORKER-003: Worker executes scrape task

**Preconditions:** Worker pool running. Browser profile exists. Pending scrape task.

**Test Data:**
```
Task: task_type="scrape", account_id=1, status="pending"
Account: browser_profile_id="pf-tw-001", platform="twitter"
```

**Steps:**
1. Insert scrape task for account 1.
2. Wait for worker to claim and execute.

**Expected Result:** Worker opens browser via `BrowserDriver`, instantiates `TwitterScraper`, calls `scrape_mentions()`. Writes results to `data/latest_insights.json`. Task status → `"completed"`.

**Implementation Details:** `orchestrator/worker_pool.py:125-133` — Creates `BrowserDriver` with profile_id, proxy, headless=True. Calls `TwitterScraper().scrape_mentions(page, account.handle)`. Writes JSON to `INSIGHTS_PATH`.

**Failure Scenarios:**
- Browser launch fails → task marked failed, attempts incremented.
- Scraper throws → `RuntimeError`, task retried or marked failed.
- Account missing `browser_profile_id` → `ValueError`, task fails.

---

### TC-WORKER-004: Worker executes post task

**Preconditions:** Worker pool running. Browser profile exists. Pending post task.

**Test Data:**
```
Task: task_type="post", account_id=2, status="pending", payload='{"text": "Hello"}'
Account: browser_profile_id="pf-tw-002"
```

**Steps:**
1. Insert post task.
2. Wait for worker to claim and execute.

**Expected Result:** Worker opens browser, instantiates `TwitterPoster`, calls `publish_post(page, payload)`. Task status → `"completed"`.

**Implementation Details:** `orchestrator/worker_pool.py:135-141` — `TwitterPoster().publish_post(page, payload)`. Checks `result.success`.

**Failure Scenarios:**
- Post fails → `RuntimeError(f"Post failed: {result.error}")`.
- No payload → empty string used.
- Account has no proxy configured → direct connection (logged).

---

### TC-WORKER-005: Worker retries failed task

**Preconditions:** Worker pool running. Task with `attempts=0`, `max_attempts=3`.

**Test Data:**
```
Task: status="pending", attempts=0, max_attempts=3
```

**Steps:**
1. Insert task that will cause an error (e.g., missing browser profile).
2. Wait for worker to fail.

**Expected Result:** `attempts` incremented to 1. Status → `"pending"` (retriable). `error_message` set. `locked_at` and `claimed_by` cleared.

**Implementation Details:** `orchestrator/worker_pool.py:151-159` — `task.attempts += 1`. `task.status = "failed" if task.attempts >= task.max_attempts else "pending"`.

**Failure Scenarios:**
- After 3 failures → `status = "failed"` (not retried).
- Error message truncated by DB column limit (Text type — unlimited in SQLite).

---

### TC-WORKER-006: Worker resolves proxy config

**Preconditions:** Worker pool running. Account with proxy assigned.

**Test Data:**
```
Account: proxy_id=1, bypass_proxy=False
Proxy: host="198.51.100.42", port=8080, protocol="http"
```

**Steps:**
1. Worker claims task for account with proxy.
2. Observe logs.

**Expected Result:** Proxy resolved to `{"server": "http://198.51.100.42:8080", "username": "proxy_user1", "password": "Pr0xy!Pass1", "country": "US"}`. Browser routed through proxy.

**Implementation Details:** `orchestrator/worker_pool.py:30-63` — `resolve_proxy_config()` checks `bypass_proxy`, then `proxy_id`. Decrypts proxy password.

**Failure Scenarios:**
- `bypass_proxy=True` → returns None (direct connection).
- No `proxy_id` → returns None.
- Proxy not found in DB → returns None with warning.
- Decryption fails → raw password used.

---

## 13. Browser Anti-Detection

### TC-BROWSER-001: Stealth patches applied

**Preconditions:** Playwright installed. Browser profile directory writable.

**Test Data:**
```
BrowserDriver(profile_id="test-001", headless=True)
```

**Steps:**
1. Create `BrowserDriver` instance.
2. Launch browser session.
3. Check `navigator.webdriver` in page context.

**Expected Result:** `navigator.webdriver === false`. 20+ stealth args passed to Chromium. `playwright-stealth` applied. Custom init script injected.

**Implementation Details:** `browser/profile_manager.py:66-101` — `STEALTH_ARGS` list with 20+ flags: `--disable-blink-features=AutomationControlled`, `--disable-field-trial-config`, etc. `browser/profile_manager.py:215-219` — `Stealth().apply_stealth_async(page)` + `page.add_init_script(stealth_script)`.

**Failure Scenarios:**
- Playwright not installed → `ModuleNotFoundError`.
- Chromium binary missing → `BrowserDriverError`.
- Stealth script fails → caught, logged, browser still launches.
- `--enable-automation` removed via `ignore_default_args`.

---

### TC-BROWSER-002: Proxy routing through browser

**Preconditions:** Playwright installed. Valid proxy configured.

**Test Data:**
```python
proxy = {"server": "http://198.51.100.42:8080", "username": "proxy_user1", "password": "Pr0xy!Pass1", "country": "US"}
BrowserDriver(profile_id="test-002", proxy=proxy, headless=True)
```

**Steps:**
1. Launch browser with proxy config.
2. Navigate to `http://httpbin.org/ip`.
3. Check response IP.

**Expected Result:** Browser routes through proxy. Response IP matches proxy IP. Locale set to `en-US`, timezone `America/New_York` (based on country "US").

**Implementation Details:** `browser/profile_manager.py:156-165,196-201` — Country mapped to locale/timezone via `COUNTRY_TIMEZONES` and `COUNTRY_LOCALES` dicts. Proxy config passed to Playwright context.

**Failure Scenarios:**
- Proxy unreachable → browser launch fails with `BrowserDriverError`.
- Unknown country → defaults to `en-US`, `America/Chicago`.
- `country` key stripped before passing to Playwright.

---

### TC-BROWSER-003: Randomized fingerprints

**Preconditions:** Playwright installed.

**Test Data:**
```
Launch browser 3 times with same profile_id
```

**Steps:**
1. Launch `BrowserDriver` 3 times.
2. Record viewport, user agent, hardware fingerprint each time.

**Expected Result:** Different viewport, user agent, and hardware fingerprint each launch (randomized from pools in `stealth_injector.py`).

**Implementation Details:** `browser/profile_manager.py:170-172` — `random.choice(VIEWPORTS)`, `random.choice(USER_AGENTS)`, `pick_hardware()`. `browser/profile_manager.py:190` — `device_scale_factor` randomized.

**Failure Scenarios:**
- Small pool of options → some repetition possible.
- Same seed → deterministic (if `random.seed()` called).

---

## 14. Frontend — Home Page

### TC-FE-001: Home page renders hero and metrics

**Preconditions:** Frontend running on port 3001. Backend running on port 8000.

**Test Data:**
```
Navigate to http://localhost:3001/
```

**Steps:**
1. Open browser to `http://localhost:3001/`.
2. Verify hero section renders.
3. Verify live metrics load.

**Expected Result:** Hero section with project name. Metric cards showing system data (from `/api/v1/system/health`). Pipeline visualizer component renders.

**Implementation Details:** `autonomous-flow-suite-main/src/routes/index.tsx` — Route handler for `/`. Uses `useSystemHealth()` hook to fetch data.

**Failure Scenarios:**
- Backend down → metrics show error state with retry button.
- Nitro down → 502 from proxy endpoint (`main.py:180-187`).
- API key missing in `.env` → frontend API calls fail with 401.

---

## 15. Frontend — Admin Page

### TC-FE-002: Admin page renders all panels

**Preconditions:** Frontend running. Backend running. Database seeded.

**Test Data:**
```
Navigate to http://localhost:3001/admin
```

**Steps:**
1. Open `http://localhost:3001/admin`.
2. Verify System Health panel loads.
3. Verify Account Registry panel loads.
4. Verify Proxy Pool panel loads.
5. Verify Dead Letter Queue panel loads.

**Expected Result:** All four panels render with real data from API.

**Implementation Details:** `autonomous-flow-suite-main/src/routes/admin.tsx` — Imports `AdminHealthHub`, `AccountRegistry`, `ProxyMonitor`, `DeadLetterManager`.

**Failure Scenarios:**
- API errors → each panel independently shows `ErrorState` with retry.
- Empty data → empty states with messages.

---

### TC-FE-003: Admin health hub shows worker pool visualization

**Preconditions:** Admin page loaded. System health data available.

**Test Data:**
```
GET /api/v1/system/health → workers.active = 2
```

**Steps:**
1. Navigate to admin page.
2. Observe worker pool visualization.

**Expected Result:** 5 worker boxes shown. First 2 show "RUNNING" (green), last 3 show "IDLE" (dashed border).

**Implementation Details:** `AdminHealthHub.tsx:62-79` — Renders `concurrencyLimit` (5) boxes. Index `< activeWorkers` → "RUNNING".

**Failure Scenarios:**
- `activeWorkers > concurrencyLimit` → more boxes highlighted than exist (visual bug).
- Data loading → spinner shown.

---

### TC-FE-004: Admin health hub throughput chart

**Preconditions:** Admin page loaded. Throughput data available.

**Test Data:**
```
GET /api/v1/system/throughput → 24 hourly buckets
```

**Steps:**
1. Navigate to admin page.
2. Observe 24h throughput chart.

**Expected Result:** Area chart with 24 data points. Purple area for scrapes, green area for posts.

**Implementation Details:** `AdminHealthHub.tsx:88-118` — Recharts `AreaChart` with `scrape` and `post` data keys.

**Failure Scenarios:**
- Throughput API fails → falls back to empty 24h array (`AdminHealthHub.tsx:39-40`).
- All zeros → flat chart.

---

### TC-FE-005: Account registry search filter

**Preconditions:** Admin page loaded. 6 accounts in DB.

**Test Data:**
```
Search input: "tech"
```

**Steps:**
1. Navigate to admin page.
2. Type "tech" in the search input.

**Expected Result:** Table filters to show only "Tech Startup Daily" (name matches "tech").

**Implementation Details:** `AccountRegistry.tsx:18-27` — `filtered` useMemo filters by `name.includes(query)` or `handle.includes(query)` (case-insensitive).

**Failure Scenarios:**
- Empty search → all accounts shown.
- No match → empty table.

---

### TC-FE-006: Account registry network filter

**Preconditions:** Admin page loaded. 6 accounts across 3 networks.

**Test Data:**
```
Network dropdown: "Twitter"
```

**Steps:**
1. Navigate to admin page.
2. Select "Twitter" from network dropdown.

**Expected Result:** Table shows only Twitter accounts (3 accounts).

**Implementation Details:** `AccountRegistry.tsx:18-27` — `network === "All" || p.network === network`.

**Failure Scenarios:**
- "All" selected → all accounts shown.
- Dropdown populated from unique `network` values in data.

---

### TC-FE-007: Account launch button

**Preconditions:** Admin page loaded. Account exists with profile_id.

**Test Data:**
```
Click "Launch" button for pf-tw-001
```

**Steps:**
1. Navigate to admin page.
2. Click "Launch" button for Tech Startup Daily.

**Expected Result:** Button shows "Launching..." with disabled state for 2 seconds. API call made to `POST /accounts/pf-tw-001/launch`.

**Implementation Details:** `AccountRegistry.tsx:29-43` — `handleLaunch()` sets `launching` state, calls API, resets after 2s timeout.

**Failure Scenarios:**
- API error → logged to console, button still resets.
- Profile not found → 404 error logged.
- Button disabled during launch to prevent double-click.

---

### TC-FE-008: Proxy monitor check button

**Preconditions:** Admin page loaded. Proxies listed.

**Test Data:**
```
Click "Check" button for px-001
```

**Steps:**
1. Navigate to admin page.
2. Click "Check" button for proxy px-001.

**Expected Result:** Button shows "Checking..." with spinning icon. After response, toast notification shows latency or failure message. Table refetches.

**Implementation Details:** `ProxyMonitor.tsx:35-61` — `handleCheck()` calls `POST /proxies/{rawId}/check`. Shows success toast with latency or warning toast for failure. Calls `refetch()`.

**Failure Scenarios:**
- Check succeeds → green toast with latency.
- Check fails → yellow toast "Proxy marked as degraded."
- API error → red toast.
- Dead proxy → check button disabled.

---

### TC-FE-009: Dead letter retry button

**Preconditions:** Admin page loaded. Dead letters exist.

**Test Data:**
```
Click "Retry" button for dlq-001
```

**Steps:**
1. Navigate to admin page.
2. Click "Retry" button for dead letter.

**Expected Result:** Button shows "Retrying..." with spinner. Toast confirms requeue. List refetches.

**Implementation Details:** `DeadLetterManager.tsx:23-39` — `handleRetry()` calls `POST /dead-letters/{rawId}/retry`. Shows success/error toast.

**Failure Scenarios:**
- Success → toast "Task tsk-... requeued successfully."
- Not found → 404 error toast.
- Buttons disabled during any in-flight request (`busy !== null`).

---

### TC-FE-010: Dead letter dismiss button

**Preconditions:** Admin page loaded. Dead letters exist.

**Test Data:**
```
Click "Dismiss" button for dlq-001
```

**Steps:**
1. Navigate to admin page.
2. Click "Dismiss" button.

**Expected Result:** Button shows "Dismissing..." with spinner. Toast confirms dismissal. List refetches.

**Implementation Details:** `DeadLetterManager.tsx:42-59` — `handleDismiss()` calls `DELETE /dead-letters/{rawId}`.

**Failure Scenarios:**
- Success → toast "Dead letter dlq-... dismissed."
- Error → red toast.

---

### TC-FE-011: Empty dead letter queue

**Preconditions:** Admin page loaded. No dead letters in DB.

**Test Data:**
```
Delete all dead letters from DB
```

**Steps:**
1. Navigate to admin page.
2. Observe dead letter section.

**Expected Result:** Shows message: "Queue clear — no dead-lettered tasks."

**Implementation Details:** `DeadLetterManager.tsx:66-68` — `items.length === 0` renders empty state.

**Failure Scenarios:**
- None.

---

## 16. Frontend — Dashboard Page

### TC-FE-012: Dashboard profile overview

**Preconditions:** Dashboard page loaded. Accounts and tasks available.

**Test Data:**
```
Navigate to http://localhost:3001/dashboard
```

**Steps:**
1. Open `http://localhost:3001/dashboard`.
2. Verify profile overview cards.

**Expected Result:** Three metric cards: "My profiles" (count), "Posts today" (ratio), "Next scheduled post" (time). Account cards grid below.

**Implementation Details:** `ProfileOverview.tsx:8-71` — Uses `useAccounts()` and `useTasks()` hooks. Calculates totals. Finds next pending/running task.

**Failure Scenarios:**
- No accounts → "0" profiles, "0/0" posts.
- No pending tasks → "—" for next post, "nothing queued" subtitle.
- API errors → spinner or error state.

---

### TC-FE-013: Dashboard content feed

**Preconditions:** Dashboard page loaded. Processed messages exist.

**Test Data:**
```
Navigate to http://localhost:3001/dashboard
```

**Steps:**
1. Open dashboard page.
2. Scroll to content feed section.
3. Click "Refresh" button.

**Expected Result:** Feed cards showing platform, action, content preview, handle, and ID. Refresh button refetches data.

**Implementation Details:** `ContentFeedHub.tsx:60-103` — Uses `useContentFeed()` hook. Renders `FeedCard` for each item. `RefreshCw` button calls `refetch()`.

**Failure Scenarios:**
- Empty feed → "No processed messages yet" with icon.
- API error → error state with retry.

---

### TC-FE-014: Dashboard task ledger

**Preconditions:** Dashboard page loaded. Tasks exist.

**Test Data:**
```
Navigate to http://localhost:3001/dashboard
```

**Steps:**
1. Open dashboard page.
2. Scroll to task ledger section.

**Expected Result:** Table showing task type, profile, timestamp, status, idempotency key. Status badges color-coded (Completed=green, Running=blue, Pending=yellow, Failed=red).

**Implementation Details:** `TaskLedger.tsx:14-54` — Uses `useTasks()` hook. `variantFor` maps status to badge color.

**Failure Scenarios:**
- Empty tasks → empty table.
- Running task → pulsing dot on status badge.

---

## 17. Frontend — Broken API Functions

These test cases document the known broken functions in `lib/api.ts`. These functions will NOT work against the actual backend.

### TC-BROKEN-001: toggleProfile() calls non-existent endpoint

**Preconditions:** Frontend loaded. `lib/api.ts` available.

**Test Data:**
```typescript
toggleProfile("pf-tw-001", false)
```

**Steps:**
1. Call `toggleProfile("pf-tw-001", false)`.

**Expected Result:** HTTP 404 or 405 (Method Not Allowed). `PATCH /accounts/pf-tw-001/toggle` does not exist.

**Implementation Details:** `lib/api.ts:12-20` — Sends `PATCH /accounts/{profileId}/toggle` with `{"active": false}`. Backend has no `PATCH` route for accounts — only `GET /accounts` and `POST /accounts/{id}/launch` exist (`api/routes_accounts.py`).

**Failure Scenarios:**
- Request hits the catch-all frontend proxy (`main.py:162-191`) and returns HTML or 502.
- If FastAPI schema mode enabled, returns 404 for unregistered route.

---

### TC-BROKEN-002: swapProxy() calls non-existent endpoint

**Preconditions:** Frontend loaded.

**Test Data:**
```typescript
swapProxy("px-001")
```

**Steps:**
1. Call `swapProxy("px-001")`.

**Expected Result:** HTTP 404 or 405. `POST /proxies/px-001/swap` does not exist.

**Implementation Details:** `lib/api.ts:22-29` — Sends `POST /proxies/{proxyId}/swap`. Backend only has `GET /proxies` and `POST /proxies/{id}/check` (`api/routes_proxies.py`). The `swap` route is not implemented.

**Failure Scenarios:**
- Same as TC-BROKEN-001.

---

### TC-BROKEN-003: requeueTask() uses wrong URL pattern

**Preconditions:** Frontend loaded. Dead letters exist.

**Test Data:**
```typescript
requeueTask("tsk-00000010")  // passes taskId, not DL id
```

**Steps:**
1. Call `requeueTask("tsk-00000010")`.

**Expected Result:** HTTP 404. URL is `/dead-letters/tsk-00000010/requeue` but backend expects numeric DL id, not task ID string.

**Implementation Details:** `lib/api.ts:31-38` — Sends `POST /dead-letters/{taskId}/requeue`. Backend route is `POST /dead-letters/{dl_id}/retry` (`api/routes_tasks.py:148`). Two problems: (1) wrong path segment name, (2) passes task ID string instead of numeric DL id.

**Failure Scenarios:**
- `"tsk-00000010"` is not a valid integer → FastAPI route `dl_id: int` fails with validation error.
- Even if corrected, the function name suggests it takes taskId but the API needs DL id.

---

### TC-BROKEN-004: purgeTask() works but different URL pattern

**Preconditions:** Frontend loaded. Dead letters exist.

**Test Data:**
```typescript
purgeTask("1")  // passes numeric DL id as string
```

**Steps:**
1. Call `purgeTask("1")`.

**Expected Result:** HTTP 200 `{"status": "dismissed", "id": 1}`. This actually works because the URL `DELETE /dead-letters/1` matches the backend route.

**Implementation Details:** `lib/api.ts:40-47` — Sends `DELETE /dead-letters/{taskId}`. Backend route is `DELETE /dead-letters/{dl_id}` (`api/routes_tasks.py:178`). Works by coincidence because DL id is numeric and matches.

**Failure Scenarios:**
- If caller passes a task ID string like `"tsk-00000010"` → FastAPI validation error (not an integer).
- Function is named `purgeTask` but operates on dead letters — confusing API.
- The frontend component `DeadLetterManager.tsx:50` does NOT use this function — it calls the API directly with correct URL and `rawId`.

---

## 18. Database Integrity

### TC-DB-001: Seed data completeness

**Preconditions:** Fresh database. `scripts/seed_db.py` available.

**Test Data:**
```
python scripts/seed_db.py
```

**Steps:**
1. Delete `data/hawaldar.db` if exists.
2. Run `python scripts/seed_db.py`.
3. Query each table.

**Expected Result:**
- `accounts`: 6 rows
- `proxies`: 5 rows
- `tasks`: 10 rows (4 pending, 1 claimed, 3 completed, 1 running, 1 dead_letter)
- `processed_messages`: 15 rows
- `daily_stats`: 42 rows (6 accounts × 7 days)
- `dead_letters`: 1 row

**Implementation Details:** `scripts/seed_db.py:32-201` — Creates all tables via `init_db()`, inserts seed data. Checks existing count to skip if already seeded.

**Failure Scenarios:**
- Already seeded → skips with message "Database already has N accounts".
- Missing dependencies → import errors.
- Fernet key mismatch → encrypted passwords won't decrypt.

---

### TC-DB-002: Foreign key constraints

**Preconditions:** Database seeded.

**Test Data:**
```
Try to insert task with invalid account_id
```

**Steps:**
1. Attempt to insert a task with `account_id=9999` (non-existent).

**Expected Result:** SQLite `FOREIGN KEY constraint failed` error.

**Implementation Details:** `db/connection.py:34` — `PRAGMA foreign_keys=ON`. `db/models.py:80` — `account_id = Column(Integer, ForeignKey("accounts.id"), nullable=False)`.

**Failure Scenarios:**
- If `foreign_keys=ON` pragma not set → constraint not enforced.
- If connection pool reuses connections → pragma may not persist.

---

### TC-DB-003: WAL mode enabled

**Preconditions:** Database file accessible.

**Test Data:**
```
Check SQLite journal mode
```

**Steps:**
1. Open database connection.
2. Query `PRAGMA journal_mode`.

**Expected Result:** Returns `wal`.

**Implementation Details:** `db/connection.py:32` — `cursor.execute("PRAGMA journal_mode=WAL")`.

**Failure Scenarios:**
- If DB is on read-only filesystem → WAL mode fails, falls back to delete.

---

### TC-DB-004: Unique constraints

**Preconditions:** Database seeded.

**Test Data:**
```
Try to insert duplicate account with same browser_profile_id
```

**Steps:**
1. Attempt to insert account with `browser_profile_id="pf-tw-001"` (already exists).

**Expected Result:** SQLite UNIQUE constraint violation.

**Implementation Details:** `db/models.py:23` — `browser_profile_id = Column(String(255), unique=True)`. `db/models.py:72` — `Index("idx_dedup", "platform", "message_id", unique=True)`.

**Failure Scenarios:**
- SQLAlchemy `IntegrityError` raised.
- Session not rolled back → transaction in broken state.

---

## 19. CORS Configuration

### TC-CORS-001: Allowed origins

**Preconditions:** Backend running.

**Test Data:**
```
Origin: http://localhost:3001
```

**Steps:**
1. Send preflight `OPTIONS` request with `Origin: http://localhost:3001`.

**Expected Result:** Response includes `Access-Control-Allow-Origin: http://localhost:3001`.

**Implementation Details:** `main.py:53-60` — `CORS_ORIGINS` list includes `localhost:3001`, `localhost:8080`, `localhost:8000` and their `127.0.0.1` variants.

**Failure Scenarios:**
- Origin not in list → CORS headers missing, browser blocks request.
- `localhost` vs `127.0.0.1` treated as different origins.

---

### TC-CORS-002: Disallowed origin

**Preconditions:** Backend running.

**Test Data:**
```
Origin: http://evil.com
```

**Steps:**
1. Send request with `Origin: http://evil.com`.

**Expected Result:** No `Access-Control-Allow-Origin` header in response. Browser blocks cross-origin request.

**Implementation Details:** `main.py:53-60` — Only listed origins are allowed.

**Failure Scenarios:**
- If `allow_origins=["*"]` were used → all origins allowed (security risk).

---

## 20. Favicon Endpoints

### TC-FAV-001: Favicon.ico returns 204

**Preconditions:** Backend running.

**Test Data:**
```
GET http://localhost:8000/favicon.ico
```

**Steps:**
1. Send `GET /favicon.ico`.

**Expected Result:** HTTP 204. Empty body. Content-Type: `image/x-icon`.

**Implementation Details:** `main.py:151-153` — Returns `Response(content=b"", media_type="image/x-icon", status_code=204)`.

**Failure Scenarios:**
- None — always returns 204.

---

### TC-FAV-002: Favicon.png returns 204

**Preconditions:** Backend running.

**Test Data:**
```
GET http://localhost:8000/favicon.png
```

**Steps:**
1. Send `GET /favicon.png`.

**Expected Result:** HTTP 204. Empty body. Content-Type: `image/png`.

**Implementation Details:** `main.py:155-157` — Returns `Response(content=b"", media_type="image/png", status_code=204)`.

**Failure Scenarios:**
- None.

---

## Appendix: Seed Data Reference

### Accounts (6)

| ID | Platform | Handle | Profile ID | Proxy ID | Bypass | Active | Daily Cap |
|----|----------|--------|------------|----------|--------|--------|-----------|
| 1 | twitter | techstartup_daily | pf-tw-001 | 1 | No | Yes | 5 |
| 2 | twitter | codehumor_bot | pf-tw-002 | 2 | No | Yes | 10 |
| 3 | twitter | devtoolscurator | pf-tw-003 | None | Yes | No | 3 |
| 4 | facebook | ai_newsroom | pf-fb-001 | 3 | No | Yes | 4 |
| 5 | facebook | startupstories_daily | pf-fb-002 | 4 | No | Yes | 3 |
| 6 | instagram | designpulse_feed | pf-ig-001 | 5 | No | Yes | 2 |

### Proxies (5)

| ID | Host | Port | Protocol | Country | Status |
|----|------|------|----------|---------|--------|
| 1 | 198.51.100.42 | 8080 | http | US | active |
| 2 | 203.0.113.17 | 1080 | socks5 | DE | active |
| 3 | 192.0.2.88 | 3128 | http | GB | degraded |
| 4 | 198.51.100.99 | 443 | https | CA | active |
| 5 | 203.0.113.200 | 8888 | http | JP | active |

### Tasks (10)

| ID | Type | Account | Status |
|----|------|---------|--------|
| 1 | scrape | techstartup_daily | pending |
| 2 | scrape | codehumor_bot | completed |
| 3 | post | techstartup_daily | pending |
| 4 | post | codehumor_bot | claimed |
| 5 | scrape | ai_newsroom | completed |
| 6 | post | ai_newsroom | completed |
| 7 | scrape | startupstories_daily | pending |
| 8 | scrape | designpulse_feed | running |
| 9 | post | designpulse_feed | pending |
| 10 | scrape | devtoolscurator | dead_letter |

---

## Appendix: Key File Reference

| Component | File | Key Lines |
|-----------|------|-----------|
| FastAPI app | `main.py` | 41-48 (app), 84-116 (rate limiter), 128-145 (health), 162-191 (proxy) |
| API router | `api/router.py` | 18 (prefix + auth dep) |
| Auth | `api/deps.py` | 28-40 (verify_api_key) |
| Accounts | `api/routes_accounts.py` | 29-91 (list), 94-170 (launch) |
| System | `api/routes_system.py` | 19-98 (health), 101-147 (throughput) |
| Tasks | `api/routes_tasks.py` | 23-80 (list), 87-145 (DL list), 148-175 (retry), 178-201 (dismiss), 208-251 (feed) |
| Proxies | `api/routes_proxies.py` | 29-85 (list), 88-156 (check) |
| ORM models | `db/models.py` | 16-35 (Account), 38-55 (Proxy), 58-73 (ProcessedMessage), 76-102 (Task), 105-113 (DeadLetter), 116-127 (DailyStat) |
| DB connection | `db/connection.py` | 20-38 (engine), 41-43 (session) |
| Worker pool | `orchestrator/worker_pool.py` | 26 (MAX_CONCURRENT), 66-86 (claim), 89-161 (run_worker), 164-168 (start_pool) |
| Browser | `browser/profile_manager.py` | 66-101 (STEALTH_ARGS), 112-276 (BrowserDriver) |
| Frontend API | `lib/api.ts` | 12-47 (broken functions) |
| Admin health | `AdminHealthHub.tsx` | 22-145 |
| Account registry | `AccountRegistry.tsx` | 8-140 |
| Proxy monitor | `ProxyMonitor.tsx` | 20-129 |
| Dead letters | `DeadLetterManager.tsx` | 14-122 |
| Profile overview | `ProfileOverview.tsx` | 8-72 |
| Content feed | `ContentFeedHub.tsx` | 60-103 |
| Task ledger | `TaskLedger.tsx` | 14-54 |
| Auto-login | `scripts/auto_login.py` | 78-117 (do_login), 120-156 (Twitter), 159-187 (Facebook), 189-233 (Instagram) |
| Seed script | `scripts/seed_db.py` | 32-201 |
