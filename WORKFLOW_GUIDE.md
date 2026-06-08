# WORKFLOW_GUIDE.md

Complete workflow diagrams with actual codebase references.

---

## 1. Account Creation Flow

**There is NO create account API endpoint.**

Accounts are created by directly inserting into the SQLite database via `seed_db.py` or direct SQL.
The `GET /accounts` endpoint only lists existing accounts.

```
┌──────────────────────────────────────────────┐
│              ACCOUNT CREATION                │
│  (No API endpoint - direct DB insertion)     │
├──────────────────────────────────────────────┤
│                                              │
│  seed_db.py ──► INSERT INTO accounts ──► DB  │
│                                              │
│  Direct SQL ──► INSERT INTO accounts ──► DB  │
│                                              │
│  GET /accounts ──► SELECT * FROM accounts    │
│                     (list only, no create)   │
│                                              │
└──────────────────────────────────────────────┘
```

---

## 2. Account Launch Flow

```
┌─────────────────┐
│  AccountRegistry │
│     .tsx        │
└────────┬────────┘
         │ User clicks "Launch"
         ▼
┌─────────────────────────────────────┐
│ POST /accounts/{profile_id}/launch  │
│ Header: X-API-Key                   │
│ routes_accounts.py:launch_browser() │
└────────┬────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  1. Query Account by browser_profile_id      │
│  2. Decrypt account.encrypted_password       │
│     via utils.crypto.decrypt()               │
│  3. If proxy_id set AND not bypass_proxy:    │
│     - Query Proxy record                     │
│     - Decrypt proxy.password                 │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  Spawn subprocess:                           │
│  python scripts/auto_login.py {profile_id}   │
│  {username}                                  │
│                                              │
│  Write JSON payload to stdin:                │
│  {"password": "...", "proxy": {...}}         │
│                                              │
│  Return {"status": "launched"} immediately   │
│  (non-blocking)                              │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  scripts/auto_login.py                       │
│  1. Read credentials from stdin              │
│  2. Detect platform from profile_id prefix:  │
│     pf-tw- = Twitter                         │
│     pf-fb- = Facebook                        │
│     pf-ig- = Instagram                       │
│  3. Create BrowserDriver:                    │
│     profile_id, proxy, headless=False,       │
│     slow_mo=80                               │
│  4. Navigate to platform login URL           │
│  5. Fill username/password fields            │
│  6. Click login button                       │
│  7. Verify success indicator                 │
│  8. Exit code 0 (success) or 1 (failure)     │
└──────────────────────────────────────────────┘
```

---

## 3. Task Execution Flow

```
┌──────────────────────────────────────────────┐
│  Worker Pool (worker_pool.py)                │
│  N async workers (max 5)                     │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  Worker Loop (each worker):                  │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │ a. claim_task()                        │  │
│  │    SELECT Task WHERE status='pending'  │  │
│  │    AND scheduled_at<=now               │  │
│  │    ORDER BY priority, scheduled_at     │  │
│  │    LIMIT 1 FOR UPDATE SKIP LOCKED      │  │
│  └────────────┬───────────────────────────┘  │
│               ▼                              │
│  ┌────────────────────────────────────────┐  │
│  │ b. Update task:                        │  │
│  │    status='claimed'                    │  │
│  │    claimed_by='worker-N'               │  │
│  │    locked_at=now                       │  │
│  └────────────┬───────────────────────────┘  │
│               ▼                              │
│  ┌────────────────────────────────────────┐  │
│  │ c. Load Account by task.account_id     │  │
│  └────────────┬───────────────────────────┘  │
│               ▼                              │
│  ┌────────────────────────────────────────┐  │
│  │ d. resolve_proxy_config():             │  │
│  │    If account has proxy_id             │  │
│  │    AND not bypass_proxy:               │  │
│  │    - Decrypt proxy password            │  │
│  │    - Build proxy dict                  │  │
│  └────────────┬───────────────────────────┘  │
│               ▼                              │
│  ┌────────────────────────────────────────┐  │
│  │ e. Update task:                        │  │
│  │    status='running'                    │  │
│  │    started_at=now                      │  │
│  └────────────┬───────────────────────────┘  │
│               ▼                              │
│  ┌────────────────────────────────────────┐  │
│  │ f. Create BrowserDriver:               │  │
│  │    profile_id, proxy, headless=True    │  │
│  └────────────┬───────────────────────────┘  │
│               ▼                              │
│  ┌────────────────────────────────────────┐  │
│  │ g. Task type dispatch:                 │  │
│  │                                        │  │
│  │  task_type='scrape'                    │  │
│  │    └─► TwitterScraper                  │  │
│  │        scrape_mentions(page, handle)   │  │
│  │                                        │  │
│  │  task_type='post'                      │  │
│  │    └─► TwitterPoster                   │  │
│  │        publish_post(page, payload)     │  │
│  └────────────┬───────────────────────────┘  │
│               ▼                              │
│  ┌────────────────────────────────────────┐  │
│  │ h. Result handling:                    │  │
│  │                                        │  │
│  │  Success:                              │  │
│  │    status='completed'                  │  │
│  │    completed_at=now                    │  │
│  │                                        │  │
│  │  Failure:                              │  │
│  │    attempts += 1                       │  │
│  │    if attempts >= max_attempts:        │  │
│  │      status='failed'                   │  │
│  │      + create DeadLetter               │  │
│  │    else:                               │  │
│  │      status='pending' (retry)          │  │
│  └────────────┬───────────────────────────┘  │
│               ▼                              │
│  ┌────────────────────────────────────────┐  │
│  │ i. Release lock:                       │  │
│  │    claimed_by=None                     │  │
│  │    locked_at=None                      │  │
│  └────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

---

## 4. Browser Profile Flow

```
┌──────────────────────────────────────────────┐
│  BrowserDriver.__init__()                    │
│  Stores: profile_id, proxy, slow_mo, headless│
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  BrowserDriver.launch()                      │
│                                              │
│  1. Create profile directory:                │
│     data/profiles/{profile_id}/              │
│                                              │
│  2. Start Playwright async                   │
│                                              │
│  3. Resolve locale/timezone from proxy       │
│     country                                  │
│                                              │
│  4. Pick random:                             │
│     - viewport                               │
│     - user agent                             │
│     - hardware profile                       │
│                                              │
│  5. Generate stealth JavaScript from         │
│     hardware profile                         │
│                                              │
│  6. Build Chrome version headers             │
│                                              │
│  7. Launch persistent context with:          │
│     - user_data_dir                          │
│     - headless                               │
│     - slow_mo                                │
│     - args (20+ stealth flags)               │
│     - viewport                               │
│     - user_agent                             │
│     - locale                                 │
│     - timezone                               │
│     - proxy                                  │
│     - extra_http_headers                     │
│                                              │
│  8. Apply playwright-stealth                 │
│                                              │
│  9. Inject stealth script via                │
│     page.add_init_script()                   │
│                                              │
│  10. Return BrowserSession(                  │
│        context, page, profile_id, profile_dir│
│      )                                       │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  BrowserDriver.close()                       │
│  1. Close context                            │
│  2. Stop Playwright                          │
└──────────────────────────────────────────────┘
```

---

## 5. Social Posting Flow (Twitter)

```
┌──────────────────────────────────────────────┐
│  TwitterPoster.publish_post(page, content)   │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  1. Pre-navigation idle mouse movement       │
│     (random position, small wander)          │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  2. Navigate to x.com/compose/tweet          │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  3. Wait for tweetTextarea_0 to be visible   │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  4. Human-like pause (0.8-2.0s)             │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  5. _human_click():                          │
│     - Idle mouse                             │
│     - Bezier curve to random point in        │
│       textarea                               │
│     - Click                                  │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  6. _human_type():                           │
│     - Type each char with 28-65ms base delay │
│     - Longer delay on punctuation, spaces,   │
│       uppercase                              │
│     - Occasional micro-pauses                │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  7. Pause 1.0-2.5s (reviewing)             │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  8. Wait for tweetButton to be visible       │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  9. _human_click() on post button            │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  10. Wait for navigation to **/home          │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  11. Return PostResult(success=True)         │
└──────────────────────────────────────────────┘
```

---

## 6. Scraping Flow (Twitter)

```
┌──────────────────────────────────────────────┐
│  TwitterScraper.scrape_mentions(page, handle,│
│                                limit=5)      │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  1. Pre-navigation idle mouse movement       │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  2. Navigate to x.com/notifications/mentions │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  3. Wait for [data-testid="tweetText"]       │
│     selector                                 │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  4. Human-like pause                         │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  5. _human_scroll() (3-7 steps, variable     │
│     speed)                                   │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  6. For each tweet (up to limit):            │
│                                              │
│     ┌────────────────────────────────────┐   │
│     │ Wait 0.5-1.5s between extractions  │   │
│     └───────────────┬────────────────────┘   │
│                     ▼                        │
│     ┌────────────────────────────────────┐   │
│     │ Get inner_text of tweet element    │   │
│     └───────────────┬────────────────────┘   │
│                     ▼                        │
│     ┌────────────────────────────────────┐   │
│     │ Walk up to find author handle via: │   │
│     │ xpath ancestor::article            │   │
│     │   → [data-testid="User-Name"] a    │   │
│     │   → href                           │   │
│     └───────────────┬────────────────────┘   │
│                     ▼                        │
│     ┌────────────────────────────────────┐   │
│     │ Append {author, content} to results│   │
│     └───────────────┬────────────────────┘   │
│                     ▼                        │
│     ┌────────────────────────────────────┐   │
│     │ Occasional scroll and idle mouse   │   │
│     └───────────────┬────────────────────┘   │
│                     │                        │
│                     ▼                        │
│              (next tweet)                    │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  7. Return results list                      │
└──────────────────────────────────────────────┘
```

---

## 7. Proxy Check Flow

```
┌──────────────────────────────────────────────┐
│  ProxyMonitor.tsx                            │
│  User clicks "Check" button                  │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  POST /proxies/{rawId}/check                 │
│  routes_proxies.py:check_proxy()             │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  1. Load Proxy by id                         │
│  2. Decrypt proxy.password                   │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  3. Build proxy URL:                         │
│     protocol://username:password@host:port   │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  4. Make async GET to http://httpbin.org/ip   │
│     through proxy (8s timeout)               │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  5. Measure latency:                         │
│     (end - start) * 1000ms                   │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  6. Update in-memory _latency_cache[id] =    │
│     {latencyMs, successRate}                 │
│                                              │
│  7. Update proxy.last_checked_at             │
└────────┬─────────────────────────────────────┘
         │
         ├── Success ──────────────────────────┐
         │   If status was 'degraded':         │
         │     mark as 'active'                │
         │                                     │
         ├── Failure ──────────────────────────┤
         │   If status was 'active':           │
         │     mark as 'degraded'              │
         │                                     │
         ▼                                     │
┌──────────────────────────────────────────────┐
│  8. Return:                                 │
│     {id, latencyMs, successRate, success,   │
│      status, checkedAt}                     │
└──────────────────────────────────────────────┘
```

---

## 8. Dead Letter Retry Flow

```
┌──────────────────────────────────────────────┐
│  DeadLetterManager.tsx                       │
│  User clicks "Retry" button                  │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  POST /dead-letters/{rawId}/retry            │
│  routes_tasks.py:retry_dead_letter()         │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  1. Load DeadLetter by id                    │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  2. If task_id set:                          │
│     - Load Task                              │
│     - Reset status='pending'                 │
│     - Clear claimed_by=None                  │
│     - Clear locked_at=None                   │
│     - Clear attempts=0                       │
│     - Clear error_message=None               │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  3. Delete DeadLetter record                 │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  4. Return {status: "requeued", taskId}      │
└──────────────────────────────────────────────┘
```

---

## 9. AI Pipeline Flow

```
┌──────────────────────────────────────────────┐
│  gemini_processor.py:run_pipeline()          │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  Step 1: scrape_raw_mentions()               │
│  Returns HARDCODED string (MOCK)             │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  Step 2: process_with_agy(raw_text)          │
│                                              │
│  a. Requires GEMINI_API_KEY env var          │
│                                              │
│  b. Locate 'agy' CLI binary:                │
│     - Check AGY_BIN env var                  │
│     - Fall back to PATH                      │
│                                              │
│  c. Build combined prompt:                   │
│     system + raw text                        │
│                                              │
│  d. Subprocess:                              │
│     agy --model gemini-2.0-flash             │
│         --prompt "..."                       │
│                                              │
│  e. Parse JSON response                      │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  Step 3: write_insights(mentions)            │
│  - Validate data                             │
│  - Write to data/latest_insights.json        │
└──────────────────────────────────────────────┘


┌──────────────────────────────────────────────┐
│  mcp_server.py (Claude Desktop integration)  │
├──────────────────────────────────────────────┤
│                                              │
│  read_prepared_data():                       │
│    └─► reads data/latest_insights.json       │
│                                              │
│  queue_social_post(profile_id, platform,     │
│                    content):                 │
│    └─► inserts Task into DB                  │
│                                              │
│  check_queue_status():                       │
│    └─► returns task count summary            │
│                                              │
└──────────────────────────────────────────────┘
```

---

## Quick Reference: Key File Paths

| Workflow | File | Function |
|----------|------|----------|
| Account Launch | `routes_accounts.py` | `launch_browser()` |
| Auto Login | `scripts/auto_login.py` | main |
| Task Worker | `worker_pool.py` | worker loop |
| Browser Profile | `browser_driver.py` | `BrowserDriver` |
| Twitter Posting | `twitter_poster.py` | `publish_post()` |
| Twitter Scraping | `twitter_scraper.py` | `scrape_mentions()` |
| Proxy Check | `routes_proxies.py` | `check_proxy()` |
| Dead Letter Retry | `routes_tasks.py` | `retry_dead_letter()` |
| AI Pipeline | `gemini_processor.py` | `run_pipeline()` |
| MCP Server | `mcp_server.py` | various |
| Crypto | `utils/crypto.py` | `decrypt()` |
