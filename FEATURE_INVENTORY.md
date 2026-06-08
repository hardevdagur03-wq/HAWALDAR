# Hawaldar — Complete Feature Inventory

> Auto-generated from codebase analysis. Covers all implemented and planned features.

---

## 1. FastAPI Backend Server

| Field | Detail |
|-------|--------|
| **Purpose** | Core HTTP server that powers the entire backend: API routes, rate limiting, frontend proxy, health checks. |
| **Why it exists** | Provides the central hub for all backend communication between frontend, workers, and external tools. |
| **Business value** | Enables a unified API surface with authentication, rate limiting, and frontend proxying — the backbone of the system. |
| **Status** | ✅ Fully implemented |
| **Files** | `main.py` |
| **APIs** | `GET /health`, `GET /favicon.ico`, proxy to Nitro frontend |
| **DB Tables** | — |
| **UI Screens** | — |

**Key behaviors:**
- CORS configured for `localhost:3001`, `localhost:8080`, `localhost:8000`
- Rate limiting middleware applied globally
- Frontend proxy forwards requests to Nitro
- Health check returns system status
- Favicon routes for branding

---

## 2. API Key Authentication

| Field | Detail |
|-------|--------|
| **Purpose** | Protects all API endpoints under `/api/v1` using an `X-API-Key` header. |
| **Why it exists** | Prevents unauthorized access to the backend API. |
| **Business value** | Security layer — ensures only clients with the correct key can interact with the system. |
| **Status** | ✅ Fully implemented |
| **Files** | `api/deps.py`, `api/router.py` |
| **APIs** | All `/api/v1/*` routes require `X-API-Key` header |
| **DB Tables** | — |
| **UI Screens** | — |

**Key behaviors:**
- `verify_api_key()` compares `X-API-Key` header against `HAWALDAR_API_KEY` env var
- Applied as a dependency to the entire `/api/v1` router

---

## 3. Rate Limiting Middleware

| Field | Detail |
|-------|--------|
| **Purpose** | Throttles incoming requests to prevent abuse and overload. |
| **Why it exists** | Protects backend resources from excessive request rates. |
| **Business value** | Prevents accidental or intentional DoS, ensures fair resource usage. |
| **Status** | ✅ Fully implemented |
| **Files** | `main.py` |
| **APIs** | Applied globally to all routes |
| **DB Tables** | — |
| **UI Screens** | — |

---

## 4. System Health Dashboard

| Field | Detail |
|-------|--------|
| **Purpose** | Provides real-time system health metrics: task counts, worker count, proxy health, account totals. |
| **Why it exists** | Operators need to quickly assess system health at a glance. |
| **Business value** | Enables proactive monitoring and rapid incident response. |
| **Status** | ✅ Fully implemented |
| **Files** | `api/routes_system.py`, frontend `AdminHealthHub` |
| **APIs** | `GET /api/v1/system/health` |
| **DB Tables** | `Task`, `Account`, `Proxy` (aggregated counts) |
| **UI Screens** | Admin → System Health tab |

**Key behaviors:**
- Returns task counts by status
- Returns active worker count
- Returns proxy health summary
- Returns account totals

---

## 5. System Throughput Monitoring

| Field | Detail |
|-------|--------|
| **Purpose** | Shows 24-hour hourly task throughput — how many tasks were completed each hour. |
| **Why it exists** | Tracks system performance over time to detect slowdowns or spikes. |
| **Business value** | Performance visibility — helps identify bottlenecks and capacity needs. |
| **Status** | ✅ Fully implemented |
| **Files** | `api/routes_system.py`, frontend `AdminHealthHub` |
| **APIs** | `GET /api/v1/system/throughput` |
| **DB Tables** | `Task` (aggregated by `completed_at` hourly buckets) |
| **UI Screens** | Admin → System Health tab (24h throughput chart) |

**Key behaviors:**
- Buckets completed tasks into 1-hour intervals over the last 24 hours
- Returns array of `{ hour, count }` objects

---

## 6. Task Status Distribution

| Field | Detail |
|-------|--------|
| **Purpose** | Visualizes the distribution of tasks across statuses (pending, claimed, running, completed, failed). |
| **Why it exists** | Gives operators a quick view of task pipeline health. |
| **Business value** | Identifies backlogs or failure spikes instantly. |
| **Status** | ✅ Fully implemented |
| **Files** | `api/routes_system.py`, frontend `AdminHealthHub` |
| **APIs** | `GET /api/v1/system/health` (task counts by status) |
| **DB Tables** | `Task` |
| **UI Screens** | Admin → System Health tab (task status distribution viz) |

---

## 7. Worker Pool

| Field | Detail |
|-------|--------|
| **Purpose** | Manages a pool of concurrent workers that claim and execute tasks from the database. |
| **Why it exists** | Automates task execution with controlled concurrency, proxy rotation, and account management. |
| **Business value** | Core automation engine — runs scraping and posting tasks reliably with retry logic. |
| **Status** | ✅ Fully implemented |
| **Files** | `orchestrator/worker_pool.py` |
| **APIs** | — (internal process) |
| **DB Tables** | `Task`, `Account`, `Proxy` |
| **UI Screens** | Admin → Worker Pool visualization |

**Key behaviors:**
- `MAX_CONCURRENT = 5` workers
- `CLAIM_TIMEOUT_SEC = 600` — claims expire after 10 minutes
- `claim_task()` uses `SELECT FOR UPDATE SKIP LOCKED` for atomic task claiming
- Each worker: claim → load account → resolve proxy → launch BrowserDriver → execute scraper/poster → complete/fail
- `start_pool()` launches N workers as asyncio tasks

---

## 8. Account Management

| Field | Detail |
|-------|--------|
| **Purpose** | Lists and manages social media accounts with platform/active filters, proxy info, and daily post counts. |
| **Why it exists** | Operators need visibility into which accounts are active, their proxy assignments, and daily usage. |
| **Business value** | Central account registry for managing the fleet of social media accounts. |
| **Status** | ✅ Fully implemented |
| **Files** | `api/routes_accounts.py`, frontend `AccountRegistry` |
| **APIs** | `GET /api/v1/accounts` |
| **DB Tables** | `Account`, `Proxy` (JOIN for host info), `DailyStat` (today's posts) |
| **UI Screens** | Admin → Account Registry tab |

**Key behaviors:**
- Filter by `platform` and `active_only`
- Returns proxy host info via JOIN
- Returns today's post count per account
- Table with search and filter capabilities

---

## 9. Account Launch (Browser Login)

| Field | Detail |
|-------|--------|
| **Purpose** | Launches a browser-based login flow for a specific account using decrypted credentials. |
| **Why it exists** | Enables operators to log into social media accounts through a real browser session. |
| **Business value** | Automates the account authentication process — critical for scraping/posting. |
| **Status** | ✅ Fully implemented |
| **Files** | `api/routes_accounts.py`, `scripts/auto_login.py` |
| **APIs** | `POST /api/v1/accounts/{profile_id}/launch` |
| **DB Tables** | `Account` |
| **UI Screens** | Admin → Account Registry (Launch button) |

**Key behaviors:**
- Decrypts account password from stored encrypted value
- Spawns `auto_login.py` as a subprocess
- Passes credentials via stdin
- Supports Twitter, Facebook, Instagram login flows

---

## 10. Task Listing & Filtering

| Field | Detail |
|-------|--------|
| **Purpose** | Lists all tasks with status and task type filters. |
| **Why it exists** | Operators need to view and filter tasks to monitor pipeline activity. |
| **Business value** | Task visibility — essential for debugging and operational awareness. |
| **Status** | ✅ Fully implemented |
| **Files** | `api/routes_tasks.py`, frontend `TaskLedger` |
| **APIs** | `GET /api/v1/tasks` |
| **DB Tables** | `Task` |
| **UI Screens** | Dashboard → Task Ledger tab |

**Key behaviors:**
- Filter by `status` and `task_type`
- Returns full task details including error messages

---

## 11. Dead Letter Queue

| Field | Detail |
|-------|--------|
| **Purpose** | Manages failed tasks that exceeded retry limits, with retry and dismiss capabilities. |
| **Why it exists** | Failed tasks need manual review and potential reprocessing. |
| **Business value** | Prevents data loss — failed tasks aren't silently dropped but queued for review. |
| **Status** | ✅ Fully implemented |
| **Files** | `api/routes_tasks.py`, frontend `DeadLetterManager` |
| **APIs** | `GET /api/v1/dead-letters`, `POST /api/v1/dead-letters/{id}/retry`, `DELETE /api/v1/dead-letters/{id}` |
| **DB Tables** | `DeadLetter`, `Task` |
| **UI Screens** | Admin → Dead Letter Manager tab |

**Key behaviors:**
- List all dead letters with error details
- Retry: requeues the original task back into the pipeline
- Dismiss: permanently removes the dead letter record

---

## 12. Content Feed

| Field | Detail |
|-------|--------|
| **Purpose** | Displays a feed of processed content items across all accounts. |
| **Why it exists** | Operators need to see what content has been scraped and processed. |
| **Business value** | Content visibility — tracks the output of the scraping pipeline. |
| **Status** | ✅ Fully implemented |
| **Files** | `api/routes_tasks.py`, frontend `ContentFeedHub` |
| **APIs** | `GET /api/v1/content-feed` |
| **DB Tables** | `ProcessedMessage`, `Account` |
| **UI Screens** | Dashboard → Content Feed tab |

**Key behaviors:**
- Returns processed messages with account context
- Displayed as a content feed grid in the frontend

---

## 13. Proxy Management

| Field | Detail |
|-------|--------|
| **Purpose** | Lists all proxies with status filtering and cached latency information. |
| **Why it exists** | Proxies are critical for anti-detection — operators need to monitor their health. |
| **Business value** | Proxy fleet management — ensures reliable, distributed access to platforms. |
| **Status** | ✅ Fully implemented |
| **Files** | `api/routes_proxies.py`, frontend `ProxyMonitor` |
| **APIs** | `GET /api/v1/proxies` |
| **DB Tables** | `Proxy` |
| **UI Screens** | Admin → Proxy Monitor tab |

**Key behaviors:**
- Filter by proxy `status` (active, inactive, checking)
- Returns cached latency from last check
- Table with check button for manual verification

---

## 14. Proxy Health Check

| Field | Detail |
|-------|--------|
| **Purpose** | Performs a real HTTP ping through a proxy to measure latency and verify connectivity. |
| **Why it exists** | Proxies can go down — this allows manual or automated health verification. |
| **Business value** | Ensures proxy reliability before routing traffic through them. |
| **Status** | ✅ Fully implemented |
| **Files** | `api/routes_proxies.py` |
| **APIs** | `POST /api/v1/proxies/{id}/check` |
| **DB Tables** | `Proxy` (updates `status`, `last_checked_at`) |
| **UI Screens** | Admin → Proxy Monitor (Check button) |

**Key behaviors:**
- Sends real HTTP request through the proxy
- Measures round-trip latency
- Updates proxy status and `last_checked_at` timestamp

---

## 15. SQLite WAL Database

| Field | Detail |
|-------|--------|
| **Purpose** | Persistent storage with WAL mode for concurrent read/write access. |
| **Why it exists** | Backend and workers need concurrent database access without locking issues. |
| **Business value** | Reliable data persistence with high-concurrency support. |
| **Status** | ✅ Fully implemented |
| **Files** | `db/connection.py`, `db/schema.py` |
| **APIs** | — (internal) |
| **DB Tables** | All tables |
| **UI Screens** | — |

**Key behaviors:**
- `PRAGMA journal_mode=WAL` for concurrent reads
- `PRAGMA busy_timeout=5000` to handle lock contention
- `PRAGMA foreign_keys=ON` for referential integrity
- `init_db()` creates all tables on startup

---

## 16. Account Model

| Field | Detail |
|-------|--------|
| **Purpose** | Stores social media account credentials, proxy assignments, and daily limits. |
| **Why it exists** | Central registry for all managed social media accounts. |
| **Business value** | Account fleet management — tracks which accounts are active and their configurations. |
| **Status** | ✅ Fully implemented |
| **Files** | `db/models.py` |
| **DB Tables** | `Account` |

**Schema:**
- `platform` — social media platform
- `handle` — account handle/username
- `display_name` — display name
- `browser_profile_id` — linked browser profile
- `proxy_id` — assigned proxy (UNIQUE constraint)
- `bypass_proxy` — flag to skip proxy
- `encrypted_password` — encrypted credentials
- `daily_pull_cap` — max daily scrapes
- `daily_post_cap` — max daily posts
- `is_active` — active/inactive flag

---

## 17. Proxy Model

| Field | Detail |
|-------|--------|
| **Purpose** | Stores proxy server configurations for anti-detection routing. |
| **Why it exists** | Each account routes through a unique proxy to avoid detection. |
| **Business value** | Anti-detection infrastructure — distributes traffic across multiple IP addresses. |
| **Status** | ✅ Fully implemented |
| **Files** | `db/models.py` |
| **DB Tables** | `Proxy` |

**Schema:**
- `host`, `port`, `protocol` — connection details
- `username`, `password` — authentication (encrypted)
- `country` — proxy location for locale/timezone selection
- `status` — active/inactive/checking
- `last_checked_at` — last health check timestamp

---

## 18. Task Model

| Field | Detail |
|-------|--------|
| **Purpose** | Represents a unit of work (scrape or post) to be executed by the worker pool. |
| **Why it exists** | Task queue system for reliable, retryable work execution. |
| **Business value** | Core work unit — enables reliable, idempotent task execution with retry logic. |
| **Status** | ✅ Fully implemented |
| **Files** | `db/models.py` |
| **DB Tables** | `Task` |

**Schema:**
- `account_id` — linked account
- `task_type` — scrape or post
- `platform` — target platform
- `status` — pending/claimed/running/completed/failed
- `payload` — task-specific data
- `idempotency_key` — prevents duplicate execution
- `priority` — execution priority
- `claimed_by` — worker ID that claimed it
- `locked_at` — claim timestamp
- `attempts`, `max_attempts` — retry tracking
- `scheduled_at`, `started_at`, `completed_at` — lifecycle timestamps
- `error_message` — failure details

---

## 19. ProcessedMessage Model

| Field | Detail |
|-------|--------|
| **Purpose** | Tracks scraped content items with deduplication via content hash. |
| **Why it exists** | Prevents reprocessing the same content across multiple scrapes. |
| **Business value** | Deduplication — ensures content isn't processed twice, saving resources. |
| **Status** | ✅ Fully implemented |
| **Files** | `db/models.py` |
| **DB Tables** | `ProcessedMessage` |

**Schema:**
- `platform` — source platform
- `message_id` — original message ID
- `content_hash` — deduplication hash
- `account_id` — scraped by which account
- `action` — action taken
- `raw_content` — original content
- `posted_at` — when it was posted/created

---

## 20. DeadLetter Model

| Field | Detail |
|-------|--------|
| **Purpose** | Stores failed tasks that exceeded retry limits for manual review. |
| **Why it exists** | Prevents silent data loss — failed tasks are preserved for investigation. |
| **Business value** | Error visibility — ensures no task is lost without operator awareness. |
| **Status** | ✅ Fully implemented |
| **Files** | `db/models.py` |
| **DB Tables** | `DeadLetter` |

**Schema:**
- `task_id` — original task reference
- `account_id` — which account failed
- `error_message` — failure reason
- `full_payload` — complete task payload for retry
- `failed_at` — failure timestamp

---

## 21. DailyStat Model

| Field | Detail |
|-------|--------|
| **Purpose** | Tracks daily scrape and post counts per account for rate limiting. |
| **Why it exists** | Accounts have daily caps — this enforces and tracks usage. |
| **Business value** | Rate limit enforcement — prevents account bans from over-activity. |
| **Status** | ✅ Fully implemented |
| **Files** | `db/models.py` |
| **DB Tables** | `DailyStat` |

**Schema:**
- `account_id` — which account
- `date` — the date
- `scrapes_done` — scrapes performed today
- `posts_done` — posts made today

---

## 22. Browser Profile Manager (Playwright)

| Field | Detail |
|-------|--------|
| **Purpose** | Manages Playwright persistent browser contexts with anti-detection stealth. |
| **Why it exists** | Social media platforms detect automation — stealth browsing is essential. |
| **Business value** | Anti-detection engine — enables reliable scraping and posting without bans. |
| **Status** | ✅ Fully implemented |
| **Files** | `browser/profile_manager.py` |
| **APIs** | — (internal) |
| **DB Tables** | — |
| **UI Screens** | — |

**Key behaviors:**
- Playwright persistent context per browser profile
- Full stealth injection on every context
- Anti-detect browser arguments
- Randomized viewport, user agent, hardware profile

---

## 23. Stealth Injection (20 Patches)

| Field | Detail |
|-------|--------|
| **Purpose** | Injects 20 stealth patches to mask browser automation fingerprints. |
| **Why it exists** | Platforms use browser fingerprinting to detect automation tools. |
| **Business value** | Core anti-detection — makes automated browsers appear as real human users. |
| **Status** | ✅ Fully implemented |
| **Files** | `browser/stealth_injector.py` |
| **APIs** | — (internal) |
| **DB Tables** | — |
| **UI Screens** | — |

**Patches applied:**
1. `navigator.webdriver` — masks automation flag
2. `chrome.runtime` — fake Chrome runtime object
3. `permissions` — spoofed permission queries
4. Phantom traces — remove automation artifacts
5. `plugins` — fake plugin array
6. `mimeTypes` — fake MIME type array
7. `hardwareConcurrency` — randomized CPU count
8. `deviceMemory` — randomized RAM amount
9. Screen dimensions — randomized resolution
10. `webgl` vendor/renderer — spoofed GPU info
11. Canvas noise — subtle canvas fingerprint noise
12. Audio noise — subtle audio context noise
13. `navigator.connection` — fake connection API
14. `navigator.language` — locale-appropriate language
15. Cookie behavior — normalized cookie handling
16. `navigator.dnt` — Do Not Track flag
17. PDF viewer — disabled to avoid detection
18. Various feature flags disabled
19. `disable AutomationControlled` — Chrome flag
20. `disable WebDriverInjection` — Chrome flag

---

## 24. Browser Fingerprint Randomization

| Field | Detail |
|-------|--------|
| **Purpose** | Randomizes browser fingerprint attributes to appear as unique real users. |
| **Why it exists** | Consistent fingerprints across sessions enable tracking and detection. |
| **Business value** | Identity isolation — each browsing session looks like a different real user. |
| **Status** | ✅ Fully implemented |
| **Files** | `browser/profile_manager.py`, `browser/stealth_injector.py` |
| **APIs** | — (internal) |
| **DB Tables** | — |
| **UI Screens** | — |

**Randomized attributes:**
- Viewport dimensions
- User agent string
- Hardware profile (CPU/GPU/screen)
- Device scale factor
- Locale
- Timezone (selected from proxy country)

---

## 25. Country-Based Locale/Timezone Mapping

| Field | Detail |
|-------|--------|
| **Purpose** | Maps proxy country to appropriate locale and timezone settings. |
| **Why it exists** | Browsers with mismatched locale/timezone and IP geolocation are flagged. |
| **Business value** | Geolocation consistency — browser settings match the proxy's apparent location. |
| **Status** | ✅ Fully implemented |
| **Files** | `browser/stealth_injector.py` |
| **APIs** | — (internal) |
| **DB Tables** | `Proxy` (country field) |
| **UI Screens** | — |

**Key behaviors:**
- `COUNTRY_TIMEZONES` mapping — country code to timezone
- `COUNTRY_LOCALES` mapping — country code to locale string
- Used during browser context creation

---

## 26. Anti-Detect Browser Arguments

| Field | Detail |
|-------|--------|
| **Purpose** | Launches browser with specific Chrome flags to disable automation detection features. |
| **Why it exists** | Chrome has built-in automation detection that must be disabled. |
| **Business value** | Deep anti-detection — disables Chrome's native automation flags. |
| **Status** | ✅ Fully implemented |
| **Files** | `browser/profile_manager.py` |
| **APIs** | — (internal) |
| **DB Tables** | — |
| **UI Screens** | — |

**Arguments applied:**
- `--disable-blink-features=AutomationControlled`
- `--disable-blink-features=WebDriverInjection`
- `--disable-field-trial-config`
- Various feature disable flags

---

## 27. Twitter Scraper

| Field | Detail |
|-------|--------|
| **Purpose** | Scrapes Twitter/X mentions by navigating to the notifications/mentions tab. |
| **Why it exists** | Monitors brand mentions and engagement on Twitter. |
| **Business value** | Social listening — captures mentions for response or analysis. |
| **Status** | ✅ Fully implemented |
| **Files** | `platforms/twitter/scraper.py`, `platforms/base.py` |
| **APIs** | — (internal browser automation) |
| **DB Tables** | `Task`, `ProcessedMessage` |
| **UI Screens** | Dashboard → Content Feed (results) |

**Key behaviors:**
- Navigates to `x.com/notifications/mentions`
- Extracts tweet data (author, content, timestamp, etc.)
- Human-like mouse movement and scroll behavior
- Returns `ScrapedItem` dataclass

---

## 28. Twitter Poster

| Field | Detail |
|-------|--------|
| **Purpose** | Publishes tweets to Twitter/X with human-like browser interactions. |
| **Why it exists** | Automates content posting to Twitter. |
| **Business value** | Content distribution — automated posting with anti-detection measures. |
| **Status** | ✅ Fully implemented |
| **Files** | `platforms/twitter/poster.py`, `platforms/base.py` |
| **APIs** | — (internal browser automation) |
| **DB Tables** | `Task`, `DailyStat` |
| **UI Screens** | Dashboard → Task Ledger (task results) |

**Key behaviors:**
- Navigates to `x.com/compose/tweet`
- Bezier curve mouse movement for natural feel
- Human-like typing with random delays
- Clicks the post button
- Returns `PostResult` dataclass

---

## 29. Facebook Scraper

| Field | Detail |
|-------|--------|
| **Purpose** | Scrapes Facebook page posts by parsing article elements. |
| **Why it exists** | Monitors Facebook page content and engagement. |
| **Business value** | Cross-platform social listening — extends monitoring to Facebook. |
| **Status** | ✅ Fully implemented |
| **Files** | `platforms/facebook/scraper.py`, `platforms/base.py` |
| **APIs** | — (internal browser automation) |
| **DB Tables** | `Task`, `ProcessedMessage` |
| **UI Screens** | Dashboard → Content Feed (results) |

**Key behaviors:**
- Targets `role="article"` elements on Facebook pages
- Extracts post data from page content
- Returns `ScrapedItem` dataclass

---

## 30. Facebook Poster

| Field | Detail |
|-------|--------|
| **Purpose** | Posts content to Facebook pages via browser automation. |
| **Why it exists** | Automates content posting to Facebook pages. |
| **Business value** | Cross-platform content distribution — extends posting to Facebook. |
| **Status** | ✅ Fully implemented |
| **Files** | `platforms/facebook/scraper.py` (contains both), `platforms/base.py` |
| **APIs** | — (internal browser automation) |
| **DB Tables** | `Task`, `DailyStat` |
| **UI Screens** | Dashboard → Task Ledger (task results) |

---

## 31. Instagram Scraper

| Field | Detail |
|-------|--------|
| **Purpose** | Scrapes Instagram profile grid posts by parsing article links. |
| **Why it exists** | Monitors Instagram profile content and engagement. |
| **Business value** | Cross-platform social listening — extends monitoring to Instagram. |
| **Status** | ✅ Fully implemented |
| **Files** | `platforms/instagram/scraper.py`, `platforms/base.py` |
| **APIs** | — (internal browser automation) |
| **DB Tables** | `Task`, `ProcessedMessage` |
| **UI Screens** | Dashboard → Content Feed (results) |

**Key behaviors:**
- Targets `article a[href*="/p/"]` elements on profile pages
- Extracts post data from grid
- Returns `ScrapedItem` dataclass

---

## 32. Instagram Poster

| Field | Detail |
|-------|--------|
| **Purpose** | Posts content to Instagram (stub implementation). |
| **Why it exists** | Planned automation for Instagram posting. |
| **Business value** | Cross-platform content distribution — planned for Instagram. |
| **Status** | ⚠️ Partially implemented (stub only) |
| **Files** | `platforms/instagram/scraper.py` (contains stub), `platforms/base.py` |
| **APIs** | — (internal browser automation) |
| **DB Tables** | `Task`, `DailyStat` |
| **UI Screens** | — |

---

## 33. Platform Base Classes

| Field | Detail |
|-------|--------|
| **Purpose** | Defines abstract base classes for scrapers and posters with standardized interfaces. |
| **Why it exists** | Provides a consistent API across all platform implementations. |
| **Business value** | Extensibility — new platforms can be added by implementing the base interfaces. |
| **Status** | ✅ Fully implemented |
| **Files** | `platforms/base.py` |
| **APIs** | — (internal) |
| **DB Tables** | — |
| **UI Screens** | — |

**Defined interfaces:**
- `BaseScraper.scrape()` — abstract scrape method
- `BasePoster.post()` — abstract post method
- `ScrapedItem` — standardized scraped content dataclass
- `PostResult` — standardized post result dataclass

---

## 34. AI Pipeline — Gemini Processor (Mock)

| Field | Detail |
|-------|--------|
| **Purpose** | Mock implementation of an AI processing pipeline for analyzing scraped mentions. |
| **Why it exists** | Placeholder for future AI-powered content analysis and response generation. |
| **Business value** | Planned: automated content analysis, sentiment detection, response drafting. |
| **Status** | ⚠️ Partially implemented (mock data only) |
| **Files** | `ai_pipeline/gemini_processor.py` |
| **APIs** | Calls AGY CLI subprocess (planned) |
| **DB Tables** | — |
| **UI Screens** | — |

**Key behaviors:**
- `scrape_raw_mentions()` — returns MOCK data
- `process_with_agy()` — calls AGY CLI subprocess
- `write_insights()` — writes JSON output

---

## 35. AI Pipeline — MCP Server

| Field | Detail |
|-------|--------|
| **Purpose** | Model Context Protocol server providing 3 tools for AI pipeline integration. |
| **Why it exists** | Enables AI agents to interact with the Hawaldar data pipeline. |
| **Business value** | AI integration layer — allows AI tools to read data and manage queues. |
| **Status** | ⚠️ Partially implemented (tools defined, integration pending) |
| **Files** | `ai_pipeline/mcp_server.py` |
| **APIs** | MCP protocol (FastMCP) |
| **DB Tables** | — |
| **UI Screens** | — |

**Tools available:**
1. `read_prepared_data` — reads processed pipeline data
2. `queue_social_post` — queues a post to the task pipeline
3. `check_queue_status` — checks current queue status

---

## 36. Auto Login Script

| Field | Detail |
|-------|--------|
| **Purpose** | Browser-based login script for Twitter, Facebook, and Instagram. |
| **Why it exists** | Automates the initial account authentication process through real browser interactions. |
| **Business value** | Account onboarding — enables rapid setup of new social media accounts. |
| **Status** | ✅ Fully implemented |
| **Files** | `scripts/auto_login.py` |
| **APIs** | Called by `POST /api/v1/accounts/{profile_id}/launch` |
| **DB Tables** | `Account` |
| **UI Screens** | Admin → Account Registry (Launch button) |

**Key behaviors:**
- Reads credentials from stdin (subprocess-safe)
- Supports Twitter, Facebook, Instagram login flows
- Uses Playwright browser automation
- Launched as subprocess from the API

---

## 37. Database Seed Script

| Field | Detail |
|-------|--------|
| **Purpose** | Seeds the database with sample data for development and testing. |
| **Why it exists** | Developers need realistic test data to work with. |
| **Business value** | Development velocity — enables rapid development and testing without manual data entry. |
| **Status** | ✅ Fully implemented |
| **Files** | `scripts/seed_db.py` |
| **APIs** | — (standalone script) |
| **DB Tables** | `Account`, `Proxy`, `Task`, `ProcessedMessage`, `DailyStat`, `DeadLetter` |
| **UI Screens** | — |

**Seed data:**
- 6 accounts
- 5 proxies
- 10 tasks
- 15 messages
- 42 daily stats
- 1 dead letter

---

## 38. Frontend — Admin Health Hub

| Field | Detail |
|-------|--------|
| **Purpose** | Admin dashboard showing system health, worker pool, throughput chart, and task distribution. |
| **Why it exists** | Central monitoring view for system operators. |
| **Business value** | Operational visibility — enables real-time system monitoring. |
| **Status** | ✅ Fully implemented |
| **Files** | Frontend admin components |
| **APIs** | `GET /api/v1/system/health`, `GET /api/v1/system/throughput` |
| **DB Tables** | — (reads via API) |
| **UI Screens** | Admin → System Health tab |

**Components:**
- System health metrics display
- Worker pool visualization
- 24-hour throughput chart
- Task status distribution

---

## 39. Frontend — Account Registry

| Field | Detail |
|-------|--------|
| **Purpose** | Admin table for managing social media accounts with search, filter, and launch capabilities. |
| **Why it exists** | Operators need to manage the account fleet from a single interface. |
| **Business value** | Account management — centralizes account operations. |
| **Status** | ✅ Fully implemented |
| **Files** | Frontend admin components |
| **APIs** | `GET /api/v1/accounts`, `POST /api/v1/accounts/{profile_id}/launch` |
| **DB Tables** | — (reads via API) |
| **UI Screens** | Admin → Account Registry tab |

**Features:**
- Search by handle/display name
- Filter by platform and active status
- Launch button for browser login
- Displays proxy info and daily post counts

---

## 40. Frontend — Proxy Monitor

| Field | Detail |
|-------|--------|
| **Purpose** | Admin table for monitoring proxy health with manual check capability. |
| **Why it exists** | Operators need to verify proxy health and manage the proxy fleet. |
| **Business value** | Proxy fleet management — ensures reliable proxy availability. |
| **Status** | ✅ Fully implemented |
| **Files** | Frontend admin components |
| **APIs** | `GET /api/v1/proxies`, `POST /api/v1/proxies/{id}/check` |
| **DB Tables** | — (reads via API) |
| **UI Screens** | Admin → Proxy Monitor tab |

**Features:**
- Filter by proxy status
- Check button for manual health verification
- Displays latency, country, and status

---

## 41. Frontend — Dead Letter Manager

| Field | Detail |
|-------|--------|
| **Purpose** | Admin interface for reviewing and managing failed tasks in the dead letter queue. |
| **Why it exists** | Failed tasks need manual review, retry, or dismissal. |
| **Business value** | Error management — ensures failed tasks are handled appropriately. |
| **Status** | ✅ Fully implemented |
| **Files** | Frontend admin components |
| **APIs** | `GET /api/v1/dead-letters`, `POST /api/v1/dead-letters/{id}/retry`, `DELETE /api/v1/dead-letters/{id}` |
| **DB Tables** | — (reads via API) |
| **UI Screens** | Admin → Dead Letter Manager tab |

**Features:**
- Lists failed tasks with error details
- Retry button to requeue tasks
- Dismiss button to permanently remove dead letters

---

## 42. Frontend — Profile Overview (Dashboard)

| Field | Detail |
|-------|--------|
| **Purpose** | Dashboard profile cards showing account status with usage cap bars. |
| **Why it exists** | Quick overview of account usage against daily limits. |
| **Business value** | Usage monitoring — prevents hitting daily caps unexpectedly. |
| **Status** | ✅ Fully implemented |
| **Files** | Frontend dashboard components |
| **APIs** | `GET /api/v1/accounts` |
| **DB Tables** | — (reads via API) |
| **UI Screens** | Dashboard → Profile Overview |

**Features:**
- Profile cards with account info
- Visual usage cap bars (scrapes/posts vs limits)

---

## 43. Frontend — Content Feed Hub (Dashboard)

| Field | Detail |
|-------|--------|
| **Purpose** | Dashboard grid displaying scraped content items from the pipeline. |
| **Why it exists** | Shows the output of the scraping pipeline in a visual format. |
| **Business value** | Content visibility — operators can review what's being captured. |
| **Status** | ✅ Fully implemented |
| **Files** | Frontend dashboard components |
| **APIs** | `GET /api/v1/content-feed` |
| **DB Tables** | — (reads via API) |
| **UI Screens** | Dashboard → Content Feed tab |

**Features:**
- Grid layout of content items
- Account attribution for each item

---

## 44. Frontend — Task Ledger (Dashboard)

| Field | Detail |
|-------|--------|
| **Purpose** | Dashboard table showing task history with full details. |
| **Why it exists** | Operators need to review past task execution for debugging and auditing. |
| **Business value** | Task history — provides audit trail for all automated actions. |
| **Status** | ✅ Fully implemented |
| **Files** | Frontend dashboard components |
| **APIs** | `GET /api/v1/tasks` |
| **DB Tables** | — (reads via API) |
| **UI Screens** | Dashboard → Task Ledger tab |

**Features:**
- Full task history table
- Status, type, and timing details
- Error message display

---

## 45. Frontend — Home Page

| Field | Detail |
|-------|--------|
| **Purpose** | Landing page with hero section showing live metrics and pipeline architecture. |
| **Why it exists** | First impression for the application — shows system status and architecture. |
| **Business value** | System overview — demonstrates pipeline capabilities at a glance. |
| **Status** | ✅ Fully implemented |
| **Files** | Frontend home components |
| **APIs** | `GET /api/v1/system/health` |
| **DB Tables** | — (reads via API) |
| **UI Screens** | Home page `/` |

**Features:**
- Hero section with live metrics
- Pipeline architecture visualizer

---

## 46. Auto-Refreshing Data Hooks

| Field | Detail |
|-------|--------|
| **Purpose** | React hooks that automatically fetch and refresh data from the backend API. |
| **Why it exists** | UI needs real-time data without manual refresh. |
| **Business value** | Real-time UI — data stays current automatically. |
| **Status** | ✅ Fully implemented |
| **Files** | Frontend hooks |
| **APIs** | All `/api/v1/*` endpoints |
| **DB Tables** | — (reads via API) |
| **UI Screens** | All dashboard and admin screens |

**Hooks available:**
- `useSystemHealth` — system health metrics
- `useThroughput` — 24h throughput data
- `useAccounts` — account list
- `useTasks` — task list
- `useProxies` — proxy list
- `useDeadLetters` — dead letter queue
- `useContentFeed` — content feed items

Each hook has configurable auto-refresh intervals.

---

## 47. Frontend API Client

| Field | Detail |
|-------|--------|
| **Purpose** | TypeScript API client for making backend requests. |
| **Why it exists** | Centralized API communication layer for the frontend. |
| **Business value** | Consistent API communication — single source of truth for all backend calls. |
| **Status** | ⚠️ Partially implemented (some functions target non-existent endpoints) |
| **Files** | `lib/api.ts` |
| **APIs** | Various `/api/v1/*` endpoints |
| **DB Tables** | — |
| **UI Screens** | All frontend screens |

**Implemented functions:**
- `toggleProfile` — **NOTE: hits endpoint that DOESN'T EXIST in backend**
- `swapProxy` — **NOTE: hits endpoint that DOESN'T EXIST in backend**
- `requeueTask` — requeues a dead letter
- `purgeTask` — deletes a dead letter

---

## 48. Frontend Mock Data (Reference Only)

| Field | Detail |
|-------|--------|
| **Purpose** | Static mock data for development reference — not used by live components. |
| **Why it exists** | Provides sample data structure for development and testing. |
| **Business value** | Development reference — shows expected data shapes. |
| **Status** | ⚠️ Reference only (not used by live components) |
| **Files** | `lib/mock-data.ts` |
| **APIs** | — |
| **DB Tables** | — |
| **UI Screens** | — |

**Mock data:**
- 112 profiles
- 42 proxies
- 64 tasks
- 9 dead letters
- 6 content items

---

## 49. Frontend — TanStack Start + Vite

| Field | Detail |
|-------|--------|
| **Purpose** | Frontend framework and build tooling for the admin dashboard. |
| **Why it exists** | Provides the UI framework with server-side rendering and fast builds. |
| **Business value** | Modern frontend stack — fast development and production performance. |
| **Status** | ✅ Fully implemented |
| **Files** | Frontend configuration files |
| **APIs** | — |
| **DB Tables** | — |
| **UI Screens** | All frontend screens |

**Routes:**
- `/` — Home page
- `/admin` — Admin panel (Health, Accounts, Proxies, Dead Letters)
- `/dashboard` — Dashboard (Profiles, Content Feed, Tasks)

---

## 50. Proxy Config Resolution

| Field | Detail |
|-------|--------|
| **Purpose** | Decrypts proxy credentials and resolves proxy configuration for browser sessions. |
| **Why it exists** | Workers need decrypted proxy credentials to route browser traffic. |
| **Business value** | Secure credential handling — passwords encrypted at rest, decrypted only when needed. |
| **Status** | ✅ Fully implemented |
| **Files** | `orchestrator/worker_pool.py`, `config.py` |
| **APIs** | — (internal) |
| **DB Tables** | `Proxy` |
| **UI Screens** | — |

**Key behaviors:**
- `resolve_proxy_config()` decrypts proxy password
- Returns proxy dict for Playwright context
- Used by worker pool before launching browser

---

## 51. Idempotent Task Execution

| Field | Detail |
|-------|--------|
| **Purpose** | Prevents duplicate task execution via idempotency keys. |
| **Why it exists** | Workers may retry or reprocess tasks — idempotency prevents duplicates. |
| **Business value** | Data integrity — ensures each task is executed exactly once. |
| **Status** | ✅ Fully implemented |
| **Files** | `orchestrator/worker_pool.py`, `db/models.py` |
| **APIs** | — (internal) |
| **DB Tables** | `Task` (idempotency_key) |
| **UI Screens** | — |

---

## 52. Atomic Task Claiming

| Field | Detail |
|-------|--------|
| **Purpose** | Uses `SELECT FOR UPDATE SKIP LOCKED` for atomic, race-free task claiming. |
| **Why it exists** | Multiple workers compete for tasks — atomic claiming prevents double-claiming. |
| **Business value** | Concurrency safety — ensures no two workers claim the same task. |
| **Status** | ✅ Fully implemented |
| **Files** | `orchestrator/worker_pool.py` |
| **APIs** | — (internal) |
| **DB Tables** | `Task` |
| **UI Screens** | — |

---

## 53. Task Retry Logic

| Field | Detail |
|-------|--------|
| **Purpose** | Automatically retries failed tasks up to `max_attempts` before moving to dead letter queue. |
| **Why it exists** | Transient failures should be retried before permanent failure. |
| **Business value** | Resilience — handles transient errors automatically. |
| **Status** | ✅ Fully implemented |
| **Files** | `orchestrator/worker_pool.py`, `db/models.py` |
| **APIs** | — (internal) |
| **DB Tables** | `Task` (attempts, max_attempts), `DeadLetter` |
| **UI Screens** | Admin → Dead Letter Manager |

---

## 54. Task Claim Timeout

| Field | Detail |
|-------|--------|
| **Purpose** | Expires task claims after 600 seconds to prevent stuck tasks. |
| **Why it exists** | Workers may crash or hang — timeout ensures tasks aren't permanently locked. |
| **Business value** | Fault tolerance — stuck tasks are automatically released for reprocessing. |
| **Status** | ✅ Fully implemented |
| **Files** | `orchestrator/worker_pool.py`, `config.py` |
| **APIs** | — (internal) |
| **DB Tables** | `Task` (locked_at) |
| **UI Screens** | — |

---

## 55. Human-Like Browser Interactions

| Field | Detail |
|-------|--------|
| **Purpose** | Simulates human-like mouse movements, scrolling, and typing in browser automation. |
| **Why it exists** | Platforms detect non-human interaction patterns and block automated access. |
| **Business value** | Anti-detection — makes automation indistinguishable from human behavior. |
| **Status** | ✅ Fully implemented |
| **Files** | `platforms/twitter/scraper.py`, `platforms/twitter/poster.py` |
| **APIs** | — (browser automation) |
| **DB Tables** | — |
| **UI Screens** | — |

**Key behaviors:**
- Bezier curve mouse movement
- Randomized scroll behavior
- Human-like typing with variable delays
- Natural interaction timing

---

## 56. Proxy-to-Country Assignment

| Field | Detail |
|-------|--------|
| **Purpose** | Maps each proxy to a country for locale/timezone selection. |
| **Why it exists** | Browser locale/timezone should match the proxy's apparent location. |
| **Business value** | Geolocation consistency — prevents detection from mismatched settings. |
| **Status** | ✅ Fully implemented |
| **Files** | `db/models.py` (Proxy.country), `browser/stealth_injector.py` |
| **APIs** | — (internal) |
| **DB Tables** | `Proxy` |
| **UI Screens** | Admin → Proxy Monitor |

---

## 57. Proxy Unique Constraint on Accounts

| Field | Detail |
|-------|--------|
| **Purpose** | Ensures each proxy is assigned to only one account (UNIQUE constraint). |
| **Why it exists** | Multiple accounts sharing a proxy would be detected. |
| **Business value** | IP isolation — each account appears to come from a unique IP address. |
| **Status** | ✅ Fully implemented |
| **Files** | `db/models.py` |
| **APIs** | — (enforced at DB level) |
| **DB Tables** | `Account` (proxy_id UNIQUE) |
| **UI Screens** | Admin → Account Registry |

---

## 58. Encrypted Password Storage

| Field | Detail |
|-------|--------|
| **Purpose** | Stores account and proxy passwords in encrypted form. |
| **Why it exists** | Plain-text credentials would be a security risk. |
| **Business value** | Security — credentials protected at rest. |
| **Status** | ✅ Fully implemented |
| **Files** | `db/models.py`, `orchestrator/worker_pool.py`, `api/routes_accounts.py` |
| **APIs** | `POST /api/v1/accounts/{profile_id}/launch` (decrypts on use) |
| **DB Tables** | `Account`, `Proxy` |
| **UI Screens** | — |

---

## 59. Daily Usage Cap Tracking

| Field | Detail |
|-------|--------|
| **Purpose** | Tracks daily scrape and post counts per account against configured caps. |
| **Why it exists** | Exceeding daily caps risks account bans from platforms. |
| **Business value** | Rate limit enforcement — prevents account suspension. |
| **Status** | ✅ Fully implemented |
| **Files** | `db/models.py`, `orchestrator/worker_pool.py` |
| **APIs** | — (internal) |
| **DB Tables** | `DailyStat`, `Account` (daily_pull_cap, daily_post_cap) |
| **UI Screens** | Dashboard → Profile Overview (cap bars) |

---

## 60. Frontend Home Page Pipeline Visualizer

| Field | Detail |
|-------|--------|
| **Purpose** | Visual representation of the pipeline architecture on the home page. |
| **Why it exists** | Helps users understand how the system works at a glance. |
| **Business value** | User education — demonstrates system capabilities. |
| **Status** | ✅ Fully implemented |
| **Files** | Frontend home components |
| **APIs** | — |
| **DB Tables** | — |
| **UI Screens** | Home page `/` |

---

## Summary by Status

| Status | Count | Features |
|--------|-------|----------|
| ✅ Fully implemented | 53 | Backend server, auth, rate limiting, system health/throughput, worker pool, account management, task management, dead letters, content feed, proxy management, health checks, all DB models, browser stealth (20 patches), fingerprint randomization, all platform scrapers/posters, auto login, seed script, all admin/dashboard UI, hooks, atomic claiming, retry logic, encryption, daily caps |
| ⚠️ Partially implemented | 4 | AI Pipeline (Gemini mock), MCP Server (tools defined), Instagram Poster (stub), Frontend API client (toggleProfile/swapProxy hit non-existent endpoints) |
| ❌ Not implemented | 3 | Instagram posting (full), AI content analysis (real), toggleProfile endpoint, swapProxy endpoint |

---

*End of Feature Inventory*
