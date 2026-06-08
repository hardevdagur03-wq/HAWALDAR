# Production Gap Analysis

## Security Gaps

| # | Gap | Current State | Required State | Priority |
|---|-----|---------------|----------------|----------|
| S1 | API key stored as plaintext env var | `api/deps.py` compares `HAWALDAR_API_KEY` via simple string equality — no hashing, no rotation | Hashed API keys with rotation support, key versioning | Critical |
| S2 | CORS allows only localhost | `main.py` `allow_origins` includes `localhost` only | Whitelist of production domains, environment-driven config | High |
| S3 | Fernet key loaded from `.env` file | `utils/crypto.py` uses `load_dotenv` to read key | Key stored in vault (AWS Secrets Manager, HashiCorp Vault, Azure Key Vault) | High |
| S4 | No CSRF protection | No CSRF tokens on any endpoint | CSRF tokens on all state-changing endpoints | High |
| S5 | No request body validation/sanitization | No Pydantic models for input on any endpoint | Pydantic models on all POST/PUT/PATCH endpoints | High |
| S6 | In-memory rate limiter | `rate_limiter` uses dict — lost on restart, not shared across instances | Redis-backed rate limiter shared across instances | High |
| S7 | Credentials written to subprocess stdin | `auto_login.py` writes to stdin — visible in process listing on Linux | Use `CREATE_NO_WINDOW` on Windows, `subprocess.DEVNULL` or keyring on Linux | Medium |
| S8 | No HTTPS enforcement | HTTP accepted without redirect | HTTPS-only with HSTS header, HTTP→HTTPS redirect | High |
| S9 | No encryption at rest for database | `data/hawaldar.db` stored as plaintext SQLite file | Database encryption (SQLCipher or encrypted volume mount) | Medium |
| S10 | No input length validation on query params | `limit`, `status`, `platform` accept arbitrary values | Max length constraints on all query parameters | Medium |

## Missing Validation

| # | Gap | Current State | Required State | Priority |
|---|-----|---------------|----------------|----------|
| V1 | No Pydantic request body models | All POST endpoints accept raw dict/None | Pydantic `BaseModel` for every POST/PUT/PATCH body | High |
| V2 | No task payload content validation | Task payload accepted without schema check | Validate payload against platform-specific schema | High |
| V3 | No account handle format validation | Any string accepted as account handle | Regex/format validation per platform (e.g., `@username`) | Medium |
| V4 | No proxy host/port format validation | Any string accepted for proxy host/port | Validate host is valid hostname/IP, port is 1–65535 | Medium |
| V5 | No platform string validation at API level | Platform enforced only by DB `CHECK` constraint | Enum validation at API layer before DB write | Low |
| V6 | No status string validation at API level | Status enforced only by DB `CHECK` constraint | Enum validation at API layer before DB write | Low |

## Missing Monitoring

| # | Gap | Current State | Required State | Priority |
|---|-----|---------------|----------------|----------|
| M1 | No structured logging | Basic `logging` config, unstructured output | Structured JSON logging with correlation IDs | High |
| M2 | No metrics endpoint | No Prometheus/OpenMetrics endpoint | `/metrics` endpoint exposing request counts, latencies, error rates | High |
| M3 | No SQLite health check | `/api/v1/health` returns hardcoded 200 | Active SQLite connectivity check (read/write test query) | Medium |
| M4 | No alerting on worker failures | Worker exceptions logged but not alerted | Alert (webhook/email) when worker fails N consecutive tasks | High |
| M5 | No alerting on proxy degradation | Proxy failures logged per-request | Alert when proxy failure rate exceeds threshold | High |
| M6 | No alerting on rate limit hits | Rate limit rejections logged at debug level | Alert when rate limit hit rate exceeds threshold | Medium |
| M7 | No request ID tracking | No unique ID per request | Generate UUID per request, include in all log lines and responses | High |
| M8 | No distributed tracing | No trace/span propagation | OpenTelemetry or similar for cross-service tracing | Medium |

## Missing Notifications

| # | Gap | Current State | Required State | Priority |
|---|-----|---------------|----------------|----------|
| N1 | No task failure notifications | Task failures logged silently | Webhook/email on task failure with retry count and error details | High |
| N2 | No proxy degradation notifications | Proxy status changed silently | Webhook/email when proxy transitions to degraded state | High |
| N3 | No daily cap notifications | Daily cap reached silently | Webhook/email when daily cap is hit, with current count and limit | Medium |
| N4 | No dead letter notifications | Dead letter tasks created silently | Webhook/email when a task enters dead letter queue | Medium |

## Missing Tests

| # | Gap | Current State | Required State | Priority |
|---|-----|---------------|----------------|----------|
| T1 | Zero test files | No `tests/` directory with actual tests | Minimum 80% coverage on core business logic | Critical |
| T2 | No unit tests | No unit tests for any module | Unit tests for all services, utilities, adapters, and routes | Critical |
| T3 | No integration tests | No tests hitting API endpoints | Integration tests for all API routes with test DB | High |
| T4 | No E2E tests | No frontend E2E tests | Playwright/Cypress tests for critical user flows | High |
| T5 | No load tests | No performance testing | Locust/k6 scripts for expected production load | Medium |
| T6 | No security tests | No SAST/DAST/dependency scanning | Automated security testing in CI pipeline | High |

## Missing Error Handling

| # | Gap | Current State | Required State | Priority |
|---|-----|---------------|----------------|----------|
| E1 | Bare `except Exception` in worker pool | `worker_pool.py` catches all exceptions generically | Differentiate transient vs. permanent errors, apply appropriate recovery | High |
| E2 | Generic 500 on decryption failure | `routes_accounts.py` launch endpoint catches decryption errors but returns 500 | Specific error codes (422 for invalid credentials, 500 only for unexpected) | Medium |
| E3 | Generic failure for all httpx errors | `routes_proxies.py` check_proxy catches all httpx exceptions as one | Differentiate timeout vs. connection refused vs. SSL error with distinct messages | Medium |
| E4 | No retry for transient DB errors | SQLite operational errors crash the request | Exponential backoff retry on `OperationalError`/`DatabaseError` | High |
| E5 | No circuit breaker for proxy failures | Proxy failure logged and skipped, no circuit state | Circuit breaker pattern: open after N failures, half-open after cooldown | High |
| E6 | No graceful shutdown | Worker pool killed on process exit, tasks may be lost | Signal handlers to drain in-flight tasks before shutdown | High |

## Missing Features for Production

| # | Gap | Current State | Required State | Priority |
|---|-----|---------------|----------------|----------|
| F1 | No account CRUD API | Only read + launch endpoints | Create, update, delete, list, get-by-id endpoints | High |
| F2 | No proxy CRUD API | Only read + check endpoints | Create, update, delete, list, get-by-id endpoints | High |
| F3 | No task creation API | Only read endpoint | Create task endpoint with validation | High |
| F4 | No user management / RBAC | Single API key for all access | Multi-user with roles (admin/operator/viewer) and per-key scoping | High |
| F5 | No audit logging | No record of who did what | Audit log table tracking all state-changing operations with actor, timestamp, diff | Medium |
| F6 | No data export / backup | No mechanism to export or back up data | Automated SQLite backup, CSV/JSON export API | Medium |
| F7 | No task scheduling UI | Worker pool runs continuously but no scheduling | Cron-like scheduler with UI for recurring task configuration | Medium |
| F8 | Facebook adapter not wired | `facebook.py` adapter exists but not called by `worker_pool.py` | Wire Facebook adapter into worker pool dispatch | High |
| F9 | Instagram adapter not wired | `instagram.py` adapter exists but not called by `worker_pool.py` | Wire Instagram adapter into worker pool dispatch | High |
| F10 | AI pipeline standalone only | AI pipeline runs as separate script, not integrated | Expose AI pipeline as API endpoint or background task | Medium |
| F11 | MCP server standalone only | MCP server runs as separate process | Integrate MCP server as optional plugin/middleware in main app | Low |
| F12 | No daily stats aggregation | `daily_stats` table has no aggregation mechanism | Cron job or trigger to roll up daily stats into summary table | Medium |
| F13 | No proxy health auto-check | Proxy checked only via manual `/check` endpoint | Background task polling proxy health at intervals, updating status | Medium |
| F14 | No stale task recovery | Referenced in `architecture.md` but not implemented | Worker detects stale tasks (running > threshold) and resets/retries | High |
| F15 | No graceful degradation on proxy failure | Proxy failure silently skips task | Fallback to alternative proxy, mark task as retriable, notify | High |

## Performance Gaps

| # | Gap | Current State | Required State | Priority |
|---|-----|---------------|----------------|----------|
| P1 | SQLite single-writer bottleneck | All writes serialized under SQLite's single-writer model | Evaluate PostgreSQL for concurrent writes, or implement write-ahead queue | High |
| P2 | In-memory rate limiter not shared | Dict-based, lost on restart, per-process only | Redis-backed rate limiter shared across all instances | High |
| P3 | In-memory latency cache lost on restart | Latency data stored in Python dict | Persist latency cache to DB or Redis | Medium |
| P4 | No connection pooling | New `httpx.AsyncClient` session per request | Persistent `AsyncClient` with connection pool, reuse across requests | High |
| P5 | No response caching | Every request hits DB directly | Redis or in-memory cache for frequently read data (accounts, proxies) | Medium |
| P6 | No pagination on list endpoints | Uses `limit` param but no offset/cursor | Cursor-based or offset pagination with `total_count` in response | Medium |

## Frontend Gaps

| # | Gap | Current State | Required State | Priority |
|---|-----|---------------|----------------|----------|
| FE1 | 4 functions call non-existent endpoints | `lib/api.ts`: `toggleProfile`, `swapProxy`, `requeueTask`, `purgeTask` hit 404s | Either implement backend endpoints or remove/stub frontend calls | Critical |
| FE2 | No component-level error boundaries | Error boundary only at root level | Wrap each route/feature section in its own error boundary | High |
| FE3 | No loading skeletons | All loading states use `<Spinner />` | Skeleton placeholders matching actual content layout | Medium |
| FE4 | No optimistic updates | All mutations trigger full data refetch | Optimistic UI updates with rollback on failure | Medium |
| FE5 | No offline support | App requires network for all operations | Service worker for caching static assets and API responses | Low |
| FE6 | No service worker | No PWA capabilities | Register service worker for offline-first where applicable | Low |
| FE7 | No SEO beyond basic meta tags | Minimal `<meta>` tags only | Open Graph, Twitter cards, structured data, sitemap | Low |
| FE8 | No accessibility audit | No `aria-label` attributes on interactive elements | Run axe/Lighthouse a11y audit, fix all violations | High |
