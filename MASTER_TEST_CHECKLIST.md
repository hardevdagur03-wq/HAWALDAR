# MASTER TEST CHECKLIST

## 1. API Authentication & Security
- [ ] API key authentication blocks unauthenticated requests
- [ ] Valid API key allows access to protected endpoints
- [ ] Invalid API key returns 401/403
- [ ] Missing API key returns 401/403
- [ ] CORS middleware allows configured origins
- [ ] CORS middleware blocks unconfigured origins
- [ ] CORS headers present on all API responses

## 2. Rate Limiting
- [ ] Tier 1 rate limit enforced
- [ ] Tier 2 rate limit enforced
- [ ] Tier 3 rate limit enforced
- [ ] Tier 4 rate limit enforced
- [ ] Rate limit headers returned in responses
- [ ] Requests over limit return 429

## 3. System Health Endpoints
- [ ] GET /health returns standalone status (no auth)
- [ ] GET /health returns 200 OK
- [ ] GET /system/health returns wrapped {"system": {...}} format
- [ ] GET /system/health includes system metadata
- [ ] GET /system/throughput returns 24 hourly buckets
- [ ] GET /system/throughput bucket data is valid

## 4. Account Management
- [ ] GET /accounts returns list of accounts
- [ ] GET /accounts with platform filter returns only matching accounts
- [ ] GET /accounts with active_only filter returns only active accounts
- [ ] POST /accounts/{profile_id}/launch spawns subprocess
- [ ] POST /accounts/{profile_id}/launch with invalid profile_id returns error
- [ ] Auto-login subprocess executes after launch

## 5. Task Management
- [ ] GET /tasks returns list of tasks
- [ ] GET /tasks with status filter works
- [ ] GET /tasks with task_type filter works
- [ ] GET /tasks with limit filter works
- [ ] Task lifecycle: pending → claimed → running → completed
- [ ] Task lifecycle: pending → claimed → running → failed
- [ ] Task lifecycle: pending → claimed → running → dead_letter
- [ ] Task claiming uses SELECT FOR UPDATE SKIP LOCKED
- [ ] Concurrent task claims do not produce duplicates

## 6. Dead Letter Queue
- [ ] GET /dead-letters returns list of dead-lettered tasks
- [ ] GET /dead-letters with limit filter works
- [ ] POST /dead-letters/{id}/retry resets task and deletes DL entry
- [ ] POST /dead-letters/{id}/retry with invalid ID returns error
- [ ] DELETE /dead-letters/{id} marks task failed and deletes DL entry
- [ ] DELETE /dead-letters/{id} with invalid ID returns error

## 7. Content Feed
- [ ] GET /content-feed returns list of processed messages
- [ ] Content feed entries contain expected fields
- [ ] Content feed entries are ordered chronologically

## 8. Proxy Management
- [ ] GET /proxies returns list of proxies
- [ ] GET /proxies with status filter works
- [ ] POST /proxies/{id}/check performs real HTTP ping
- [ ] POST /proxies/{id}/check returns ping result
- [ ] POST /proxies/{id}/check with invalid ID returns error

## 9. Frontend - Home Page
- [ ] Hero section renders correctly
- [ ] Live metrics display current values
- [ ] Pipeline visualizer renders
- [ ] Home page loads without errors

## 10. Frontend - Admin Dashboard
- [ ] System Health component renders
- [ ] Account Registry component renders
- [ ] Proxy Pool component renders
- [ ] Dead Letter Queue component renders
- [ ] Admin dashboard loads without errors

## 11. Frontend - Team Dashboard
- [ ] Profile Overview component renders
- [ ] Content Feed component renders
- [ ] Task Ledger component renders
- [ ] Team dashboard loads without errors

## 12. Frontend Actions
- [ ] Launch button on AccountRegistry triggers POST /accounts/{id}/launch
- [ ] Check button on ProxyMonitor triggers POST /proxies/{id}/check
- [ ] Retry button on DeadLetterManager triggers POST /dead-letters/{id}/retry
- [ ] Dismiss button on DeadLetterManager triggers DELETE /dead-letters/{id}
- [ ] Refresh button on ContentFeedHub reloads content feed
- [ ] Search input on AccountRegistry filters accounts
- [ ] Network filter dropdown on AccountRegistry filters by network/platform
- [ ] All action buttons show loading state during request
- [ ] All action buttons show success/error feedback

## 13. Database Operations
- [ ] SQLite WAL mode enabled
- [ ] 6 tables created correctly
- [ ] Foreign key enforcement enabled
- [ ] CHECK constraints enforced
- [ ] Unique constraints enforced
- [ ] Indexes created and used by queries
- [ ] Fernet encryption encrypts sensitive data
- [ ] Fernet decryption decrypts data correctly

## 14. Worker Pool
- [ ] Worker pool caps at max 5 concurrent workers
- [ ] Workers process tasks from queue
- [ ] Worker crash does not corrupt state
- [ ] Worker pool recovers after failure

## 15. Browser Automation
- [ ] Browser stealth applies 20 patches
- [ ] Stealth patches prevent detection
- [ ] Proxy routing works through browser
- [ ] Browser launches with stealth settings
- [ ] Browser session cleanup on completion

## 16. Platform Adapters
- [ ] Platform-specific adapters handle account types
- [ ] Adapters integrate with browser automation
- [ ] Adapters handle login flows

## 17. AI Pipeline
- [ ] AI pipeline processes content
- [ ] Pipeline handles input validation
- [ ] Pipeline produces expected output format
- [ ] Pipeline errors are handled gracefully

## 18. Error Handling
- [ ] 404 returned for non-existent endpoints
- [ ] 500 returned for unhandled server errors
- [ ] Error responses contain useful messages
- [ ] Graceful degradation when dependencies fail
- [ ] Dead letters created for unrecoverable task errors

## 19. Performance
- [ ] Health endpoints respond within acceptable time
- [ ] Account list endpoints scale with data size
- [ ] Task claiming does not cause lock contention
- [ ] Concurrent requests handled without degradation
- [ ] Frontend pages load within acceptable time

## 20. Cross-cutting Concerns
- [ ] Frontend proxy catch-all route serves SPA
- [ ] Frontend proxy falls back to index.html for client routes
- [ ] API responses use consistent JSON format
- [ ] Logging captures errors and key events
- [ ] Environment configuration loads correctly
