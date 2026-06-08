# Static vs Dynamic Analysis

## Frontend - Screens & Components

| Feature | Current Source | Static or Dynamic | Production Ready? | Required Changes |
|---------|---------------|-------------------|-------------------|------------------|
| **Dashboard (index.tsx)** | | | | |
| Pipeline visualization text | Hardcoded labels ("Data ingestion", "Processing pipes", "Background worker nodes", "Network adapters") | Static | No | Fetch from backend or config API |
| Task status distribution chart | system/health endpoint | Dynamic | Yes | — |
| 24h throughput chart | system/throughput endpoint | Dynamic | Yes | — |
| **Accounts Screen** | | | | |
| Profile list | useAccounts hook → GET /accounts | Dynamic | Yes | — |
| Launch button | POST /accounts/{profileId}/launch | Dynamic | Yes | — |
| Owner field in response | Hardcoded "system" in routes_accounts.py | Static | No | Remove or derive from auth |
| **Proxies Screen** | | | | |
| Proxy list | useProxies hook → GET /proxies | Dynamic | Yes | — |
| Check button | POST /proxies/{rawId}/check → real HTTP ping | Dynamic | Yes | — |
| Latency cache | In-memory dict lost on restart | Static | No | Use SQLite or Redis |
| Default successRate fallback | Hardcoded 100/75/0 for active/degraded/dead | Static | No | Compute from real check history |
| **Tasks Screen** | | | | |
| Task list | useTasks hook → GET /tasks | Dynamic | Yes | — |
| Dead letter list | useDeadLetters hook → GET /dead-letters | Dynamic | Yes | — |
| Retry button | POST /dead-letters/{rawId}/retry → real DB update | Dynamic | Yes | — |
| Dismiss button | DELETE /dead-letters/{rawId} → real DB delete | Dynamic | Yes | — |
| **Content Feed Screen** | | | | |
| Content items | useContentFeed hook → processed_messages table | Dynamic | Yes | — |
| **Health Hub (AdminHealthHub.tsx)** | | | | |
| Worker pool visualization | Array.from({length: concurrencyLimit}) — 5 boxes | Dynamic (count) | Partial | Count is live, box layout hardcoded |
| Tooltip style | Hardcoded dark theme object | Static | Yes | Move to CSS class |
| Health metrics | useSystemHealth hook → GET /system/health | Dynamic | Yes | — |
| **System Health Screen** | | | | |
| All health data | useSystemHealth hook → GET /system/health | Dynamic | Yes | — |
| **Throughput Screen** | | | | |
| Throughput data | useThroughput hook → GET /system/throughput | Dynamic | Yes | — |

## Frontend - Hooks & Data Fetching

| Feature | Current Source | Static or Dynamic | Production Ready? | Required Changes |
|---------|---------------|-------------------|-------------------|------------------|
| useSystemHealth | fetch → GET /system/health, 15s interval | Dynamic | Yes | — |
| useThroughput | fetch → GET /system/throughput, 30s interval | Dynamic | Yes | — |
| useAccounts | fetch → GET /accounts, 30s interval | Dynamic | Yes | — |
| useTasks | fetch → GET /tasks, 20s interval | Dynamic | Yes | — |
| useProxies | fetch → GET /proxies, 30s interval | Dynamic | Yes | — |
| useDeadLetters | fetch → GET /dead-letters, 20s interval | Dynamic | Yes | — |
| useContentFeed | fetch → GET /content-feed, 30s interval | Dynamic | Yes | — |

## Frontend - API Layer (src/lib/)

| Feature | Current Source | Static or Dynamic | Production Ready? | Required Changes |
|---------|---------------|-------------------|-------------------|------------------|
| mock-data.ts | 112 profiles, 42 proxies, 64 tasks, 9 dead letters, 6 content items | Static (reference only) | N/A | File header says wired components now use useApi.ts — no changes needed |
| api.ts: toggleProfile() | PATCH /accounts/{profileId}/toggle | Static | No | Endpoint does not exist in backend — add endpoint or remove function |
| api.ts: swapProxy() | POST /proxies/{proxyId}/swap | Static | No | Endpoint does not exist in backend — add endpoint or remove function |
| api.ts: requeueTask() | POST /dead-letters/{taskId}/retry | Static | No | Wrong URL pattern — actual is /dead-letters/{dl_id}/retry |
| api.ts: purgeTask() | DELETE /dead-letters/{taskId} | Dynamic | Yes | Works but URL pattern differs from retry — normalize |
| styles.css | CSS custom properties (colors, gradients) | Static | Yes | Theme values — expected static |
| vite.config.ts | server.port = 3001 | Static | Yes | Dev server config — expected static |

## Backend - API Endpoints (api/)

| Feature | Current Source | Static or Dynamic | Production Ready? | Required Changes |
|---------|---------------|-------------------|-------------------|------------------|
| GET /accounts | SQLite read | Dynamic | Yes | — |
| POST /accounts/{profileId}/launch | Spawns real subprocess | Dynamic | Yes | — |
| PATCH /accounts/{profileId}/toggle | **Does not exist** | Static | No | Add endpoint |
| GET /proxies | SQLite read | Dynamic | Yes | — |
| POST /proxies/{rawId}/check | Real HTTP request through proxy | Dynamic | Yes | — |
| POST /proxies/{proxyId}/swap | **Does not exist** | Static | No | Add endpoint |
| GET /tasks | SQLite read | Dynamic | Yes | — |
| GET /dead-letters | SQLite read | Dynamic | Yes | — |
| POST /dead-letters/{dl_id}/retry | Real DB update | Dynamic | Yes | — |
| DELETE /dead-letters/{rawId} | Real DB delete | Dynamic | Yes | — |
| GET /system/health | Live system metrics | Dynamic | Yes | — |
| GET /system/throughput | Live throughput data | Dynamic | Yes | — |
| GET /content-feed | processed_messages table | Dynamic | Yes | — |

## Backend - Core Modules

| Feature | Current Source | Static or Dynamic | Production Ready? | Required Changes |
|---------|---------------|-------------------|-------------------|------------------|
| **main.py** | | | | |
| NITRO_PORT | Env var, defaults to 8080 | Dynamic | Partial | Frontend runs on 3001 — port mismatch |
| CORS_ORIGINS | Hardcoded localhost:3001, 8080, 8000 | Static | No | Use env var or config file |
| **config.py** | | | | |
| ADSPOWER_API | Hardcoded http://127.0.0.1:50325 | Static | No | Never used — remove or make configurable |
| PLATFORM_CAPS | Hardcoded {twitter: {daily_posts: 50, daily_scrapes: 10}} | Static | No | Never referenced — remove or wire to config |
| **db/models.py** | | | | |
| _utcnow() | Returns ISO string, not DateTime | Static | No | Return proper DateTime for DB |
| **api/routes_accounts.py** | | | | |
| Owner field | Hardcoded "system" | Static | No | Derive from auth/session |

## Backend - Orchestrator & Workers

| Feature | Current Source | Static or Dynamic | Production Ready? | Required Changes |
|---------|---------------|-------------------|-------------------|------------------|
| **orchestrator/worker_pool.py** | | | | |
| Worker imports | Only TwitterScraper/TwitterPoster | Static | Partial | Facebook/Instagram not wired |
| INSIGHTS_PATH | Hardcoded data/latest_insights.json | Static | No | Use env var or config |
| Task claiming | Live SQLite read/write | Dynamic | Yes | — |
| BrowserDriver execution | Real Chromium via Playwright | Dynamic | Yes | — |

## Backend - Browser & Stealth

| Feature | Current Source | Static or Dynamic | Production Ready? | Required Changes |
|---------|---------------|-------------------|-------------------|------------------|
| **browser/profile_manager.py** | | | | |
| STEALTH_ARGS | Hardcoded Chrome flags | Static | Yes | Expected static — Chrome flags |
| **browser/stealth_injector.py** | | | | |
| HARDWARE_PROFILES | Static array | Static | Yes | Expected static — profile templates |
| SCREEN_RESOLUTIONS | Static array | Static | Yes | Expected static — resolution pool |
| GPU_PROFILES | Static array | Static | Yes | Expected static — GPU spoofing pool |
| USER_AGENTS | Static array | Static | Yes | Expected static — UA rotation pool |
| VIEWPORTS | Static array | Static | Yes | Expected static — viewport pool |
| Auto-login subprocess | Spawns real browser window | Dynamic | Yes | — |

## Backend - AI Pipeline

| Feature | Current Source | Static or Dynamic | Production Ready? | Required Changes |
|---------|---------------|-------------------|-------------------|------------------|
| **ai_pipeline/gemini_processor.py** | | | | |
| scrape_raw_mentions() | Returns hardcoded string of 8 sample tweets | Static | No | Replace with real scraping or API call |
| SYSTEM_PROMPT | Hardcoded text | Static | Yes | Expected static — prompt engineering |

## Backend - Security & Rate Limiting

| Feature | Current Source | Static or Dynamic | Production Ready? | Required Changes |
|---------|---------------|-------------------|-------------------|------------------|
| Fernet encryption/decryption | Real cryptographic operations | Dynamic | Yes | — |
| Rate limiter | In-memory per IP | Dynamic | Partial | Lost on restart — use Redis for production |

## Summary

| Category | Static | Dynamic | Total |
|----------|--------|---------|-------|
| Frontend Screens/Components | 8 | 10 | 18 |
| Frontend Hooks | 0 | 7 | 7 |
| Frontend API Layer | 4 | 1 | 5 |
| Backend API Endpoints | 2 | 10 | 12 |
| Backend Core Modules | 5 | 0 | 5 |
| Backend Orchestrator | 2 | 2 | 4 |
| Backend Browser/Stealth | 1 | 2 | 3 |
| Backend AI Pipeline | 2 | 0 | 2 |
| Backend Security | 0 | 2 | 2 |
| **Total** | **24** | **34** | **58** |

## Critical Issues (Production Blockers)

1. `toggleProfile()` — backend endpoint missing
2. `swapProxy()` — backend endpoint missing
3. `requeueTask()` — wrong URL pattern (frontend vs backend mismatch)
4. `scrape_raw_mentions()` — returns mock data, no real scraping
5. `ADSPOWER_API` — hardcoded, never used
6. `PLATFORM_CAPS` — hardcoded, never referenced
7. `_utcnow()` — returns ISO string instead of DateTime
8. Owner field hardcoded to "system"
9. `_latency_cache` — in-memory only, lost on restart
10. Facebook/Instagram workers not wired
11. CORS_ORIGINS hardcoded — not configurable
