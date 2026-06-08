# Hawaldar Database Guide

## Overview

- **Engine:** SQLite at `data/hawaldar.db`
- **Mode:** WAL (Write-Ahead Logging)
- **ORM:** SQLAlchemy

---

## Connection (`db/connection.py`)

| Function | Description |
|---|---|
| `get_engine(db_path=None)` | Creates engine with `check_same_thread=False` |
| `get_session(engine)` | Returns `sessionmaker` with `expire_on_commit=False` |

**PRAGMAs applied:**
```
journal_mode = WAL
busy_timeout  = 5000
foreign_keys  = ON
```

---

## Tables

### 1. `accounts`

| Column | Type | Constraints | Default |
|---|---|---|---|
| `id` | Integer | PK, autoincrement | |
| `platform` | String(20) | NOT NULL, CHECK IN ('twitter','facebook','instagram') | |
| `handle` | String(255) | NOT NULL | |
| `display_name` | String(255) | | |
| `browser_profile_id` | String(255) | UNIQUE | |
| `proxy_id` | Integer | FK `proxies.id`, UNIQUE (1:1 binding) | |
| `bypass_proxy` | Boolean | | `False` |
| `encrypted_password` | String(512) | nullable | |
| `daily_pull_cap` | Integer | | `10` |
| `daily_post_cap` | Integer | | `5` |
| `is_active` | Boolean | | `True` |
| `created_at` | String(30) | | utcnow |
| `updated_at` | String(30) | | utcnow, onupdate utcnow |

**Seed data:** 6 rows (3 twitter, 2 facebook, 1 instagram)

---

### 2. `proxies`

| Column | Type | Constraints | Default |
|---|---|---|---|
| `id` | Integer | PK, autoincrement | |
| `host` | String(255) | NOT NULL | |
| `port` | Integer | NOT NULL | |
| `protocol` | String(10) | CHECK IN ('http','https','socks5') | `"http"` |
| `username` | String(255) | | |
| `password` | String(255) | Fernet encrypted | |
| `country` | String(10) | | |
| `status` | String(20) | CHECK IN ('active','degraded','dead') | `"active"` |
| `last_checked_at` | String(30) | | |
| `created_at` | String(30) | | utcnow |

**Seed data:** 5 rows (US, DE, GB, CA, JP)

---

### 3. `tasks`

| Column | Type | Constraints | Default |
|---|---|---|---|
| `id` | Integer | PK, autoincrement | |
| `account_id` | Integer | FK `accounts.id`, NOT NULL | |
| `task_type` | String(10) | CHECK IN ('scrape','post') | |
| `platform` | String(20) | NOT NULL | |
| `status` | String(20) | CHECK IN ('pending','claimed','running','completed','failed','dead_letter') | `"pending"` |
| `payload` | Text | | |
| `idempotency_key` | String(64) | | |
| `priority` | Integer | | `5` |
| `claimed_by` | String(255) | | |
| `locked_at` | String(30) | | |
| `attempts` | Integer | | `0` |
| `max_attempts` | Integer | | `3` |
| `scheduled_at` | String(30) | | utcnow |
| `started_at` | String(30) | | |
| `completed_at` | String(30) | | |
| `error_message` | Text | | |
| `created_at` | String(30) | | utcnow |

**Indexes:**
- `idx_tasks_pending` — `(status, priority, scheduled_at)`
- `idx_tasks_claimed` — `(status, locked_at)`

**Seed data:** 10 rows (mix of pending, completed, claimed, running, dead_letter)

---

### 4. `processed_messages`

| Column | Type | Constraints | Default |
|---|---|---|---|
| `id` | Integer | PK, autoincrement | |
| `platform` | String(20) | NOT NULL | |
| `message_id` | String(255) | NOT NULL | |
| `content_hash` | String(64) | NOT NULL | |
| `account_id` | Integer | FK `accounts.id` | |
| `action` | String(10) | | |
| `raw_content` | Text | | |
| `posted_at` | String(30) | | |
| `created_at` | String(30) | | utcnow |

**Indexes:**
- `idx_dedup` — `(platform, message_id)` UNIQUE

**Seed data:** 15 rows

---

### 5. `dead_letters`

| Column | Type | Constraints | Default |
|---|---|---|---|
| `id` | Integer | PK, autoincrement | |
| `task_id` | Integer | FK `tasks.id` | |
| `account_id` | Integer | FK `accounts.id` | |
| `error_message` | Text | | |
| `full_payload` | Text | | |
| `failed_at` | String(30) | | utcnow |

**Seed data:** 1 row

---

### 6. `daily_stats`

| Column | Type | Constraints | Default |
|---|---|---|---|
| `id` | Integer | PK, autoincrement | |
| `account_id` | Integer | FK `accounts.id`, NOT NULL | |
| `date` | String(10) | NOT NULL | |
| `scrapes_done` | Integer | | `0` |
| `posts_done` | Integer | | `0` |

**Indexes:**
- `idx_daily_stats_unique` — `(account_id, date)` UNIQUE

**Seed data:** 42 rows (6 accounts × 7 days)

---

## Relations

```
accounts.proxy_id          → proxies.id          (1:1, UNIQUE constraint)
tasks.account_id           → accounts.id         (N:1)
processed_messages.account_id → accounts.id      (N:1)
dead_letters.task_id       → tasks.id            (N:1)
dead_letters.account_id    → accounts.id         (N:1)
daily_stats.account_id     → accounts.id         (N:1)
```

---

## Known Issues

| # | Issue | Severity |
|---|---|---|
| 1 | All timestamps stored as `String(30)` ISO format instead of proper `DateTime` columns | Medium |
| 2 | No `ON DELETE CASCADE` on any FK (SQLite limitation; requires application-level cascading) | Low |
| 3 | `processed_messages.content_hash` has no dedicated index — only composite with `message_id` via `idx_dedup` | Medium |
| 4 | `daily_stats` has no auto-aggregation mechanism — must be populated by external code | Medium |
| 5 | `dead_letters` has no unique constraint on `task_id` — could have duplicate entries | Low |
| 6 | `encrypted_password` is nullable but launch endpoint returns 400 when missing | Medium |
| 7 | `platform` CHECK constraint only allows `twitter`/`facebook`/`instagram` — no reddit/bluesky/etc. | Low |
| 8 | No index on `accounts.handle` or `accounts.browser_profile_id` for lookup by handle | Medium |
| 9 | No index on `tasks.claimed_by` for worker-based queries | Low |
