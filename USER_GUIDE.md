# USER_GUIDE.md — Hawaldar Platform User Guide

## Overview

Hawaldar is a social media automation platform that manages content posting through a multi-stage pipeline: data ingestion → AI processing → worker nodes → network adapters. The UI is split into three pages:

| Page | URL | Role |
|------|-----|------|
| Landing | `/` | Public marketing / status overview |
| Admin Dashboard | `/admin` | Super Admin system management |
| Team Dashboard | `/dashboard` | Team-level content & task view |

---

## 1. Landing Page — `/`

**Purpose:** Public entry point. Displays platform value proposition, live system metrics, and a pipeline architecture visualizer.

### Sections

#### Hero
- Headline and call-to-action branding.

#### Live Metrics Strip
- Four live-updating stats (auto-refresh every 15 s via health hook):
  - **Tasks** — total tasks processed
  - **Accounts** — registered accounts count
  - **Proxy Health** — percentage of healthy proxies
  - **Workers** — active worker count

#### Pipeline Architecture Visualizer
- Four-stage diagram illustrating the data flow:
  1. **Data Ingestion** — incoming content/tasks
  2. **AI Processing** — content generation / analysis
  3. **Worker Nodes** — task execution
  4. **Network Adapters** — platform posting
- Purely visual; no user interaction.

---

## 2. Admin Dashboard — `/admin`

**Purpose:** Super Admin view for full system control. Uses a `DashboardShell` sidebar to switch between four sections.

### Navigation (Sidebar)

| Section | Icon area | Description |
|---------|-----------|-------------|
| System Health | — | Worker & queue metrics |
| Account Registry | — | Manage posting accounts |
| Proxy Pool | — | Proxy monitoring & health checks |
| Dead Letter Queue | — | Retry or dismiss failed tasks |

Mobile: sections appear as tabs in a sticky header.

---

### 2.1 System Health (`AdminHealthHub.tsx`)

**URL:** `/admin` (default section)

#### MetricCards (top row, 4 cards)

| Card | Icon | Value | Subtitle |
|------|------|-------|----------|
| Active Workers | — | live count | worker pool size |
| Tasks in Queue | — | live count | pending tasks |
| Task Throughput 24 h | — | count | tasks completed in last 24 h |
| Proxy Health | — | % | percentage of proxies healthy |

All values auto-refresh every 15 s.

#### Worker Pool Visualization
- 5 boxes displayed, each labeled **RUNNING** or **IDLE**.
- Real-time status from worker health endpoint.

#### 24 h Task Throughput AreaChart
- X-axis: time (24 h window)
- Y-axis: task count
- Two series: **Scrape** and **Post**
- Auto-refreshes every 30 s.

#### Task Status Distribution BarChart
- Breakdown of tasks by status (e.g., pending, running, completed, failed).
- Visual bar representation.

---

### 2.2 Account Registry (`AccountRegistry.tsx`)

**URL:** `/admin` → "Account Registry" section

#### Controls (top)

| Control | Type | Purpose |
|---------|------|---------|
| Search | Text input | Filter profiles by name or handle |
| Network Filter | Dropdown | Filter by platform network |

#### Accounts Table

| Column | Content |
|--------|---------|
| Profile | Profile name + handle |
| Network | Platform (e.g., Twitter, Instagram) |
| Attached Proxy | Proxy assigned to this account |
| Daily Cap Status | Progress bar showing daily post usage |
| Bypass | **Direct** or **Proxy** indicator |
| Active | Active/Inactive badge |
| Actions | **Launch** button |

#### Launch Button
- **Endpoint:** `POST /accounts/{profileId}/launch`
- **Behind the scenes:**
  1. Request sent to server with profile ID.
  2. Server spawns `auto_login.py` subprocess for the target profile.
  3. Subprocess handles authentication / session creation.
  4. On success: toast notification confirms launch.
  5. Account registry table re-fetches (30 s auto-refresh) to reflect updated status.

#### Data Refresh
- Accounts list auto-refreshes every 30 s.

---

### 2.3 Proxy Pool (`ProxyMonitor.tsx`)

**URL:** `/admin` → "Proxy Pool" section

#### Summary Badges (top)
- Three status badges showing counts:
  - **Active** — healthy proxies
  - **Degraded** — partially working
  - **Dead** — non-functional

#### Proxies Table

| Column | Content |
|--------|---------|
| Proxy ID | Unique identifier |
| Host | Proxy host address |
| Region | Geographic region |
| Latency | Response time (ms) |
| Success % | Success rate percentage |
| Last Checked | Timestamp of last health check |
| Status | Active / Degraded / Dead badge |
| Actions | **Check** button |

#### Check Button
- **Endpoint:** `POST /proxies/{rawId}/check`
- **Behind the scenes:**
  1. Server sends a real HTTP ping through the proxy.
  2. Measures latency and success/failure.
  3. Updates proxy status in database.
  4. Returns result; UI shows **toast notification** with health status.
  5. Table auto-refreshes to reflect updated metrics.

#### Data Refresh
- Proxy list auto-refreshes every 30 s.

---

### 2.4 Dead Letter Queue (`DeadLetterManager.tsx`)

**URL:** `/admin` → "Dead Letter Queue" section

#### Dead Letter Cards
Each failed task renders as a card containing:

| Element | Description |
|---------|-------------|
| Icon | ⚠️ AlertTriangle indicator |
| Task ID | Unique task identifier |
| Type Badge | Task type label |
| Attempts Badge | Number of retry attempts |
| Profile | Associated account profile |
| Failed Time | Timestamp of failure |
| Error Message | Human-readable error text |
| Trace | Full stack trace in `<pre>` block |

#### Action Buttons

| Button | Endpoint | Behavior |
|--------|----------|----------|
| **Retry** | `POST /dead-letters/{rawId}/retry` | 1. Server re-queues the task. 2. Toast confirms retry. 3. DLQ list re-fetches. |
| **Dismiss** | `DELETE /dead-letters/{rawId}` | 1. Server removes the dead letter record. 2. Toast confirms dismissal. 3. DLQ list re-fetches. |

#### Data Refresh
- Dead letter list auto-refreshes every 20 s.

---

## 3. Team Dashboard — `/dashboard`

**Purpose:** Team-level view for content management and task tracking. Three sections, each accessed via navigation.

---

### 3.1 Profile Overview (`ProfileOverview.tsx`)

**URL:** `/dashboard` → "Profile Overview" section

#### MetricCards (top row, 3 cards)

| Card | Value | Subtitle |
|------|-------|----------|
| My Profiles | count | total profiles assigned to team |
| Posts Today | ratio (e.g., 3/5) | posts completed vs. daily cap |
| Next Scheduled Post | timestamp | when the next post is queued |

#### Profile Cards Grid
Each profile renders as a card showing:

| Field | Description |
|-------|-------------|
| Name | Profile display name |
| Handle | @handle |
| Network | Platform (Twitter, etc.) |
| Active Status | Active/Inactive badge |
| Daily Cap Progress Bar | Visual bar of posts used vs. limit |

---

### 3.2 Content Feed (`ContentFeedHub.tsx`)

**URL:** `/dashboard` → "Content Feed" section

#### Controls
- **Refresh Button** — manually re-fetches feed; also auto-refreshes every 30 s.

#### Feed Cards (Grid)
Each content item renders as a `FeedCard`:

| Field | Description |
|-------|-------------|
| Platform Badge | Target platform icon/label |
| Action Badge | Action type (post, repost, etc.) |
| Timestamp | When content was posted/scheduled |
| Content Preview | 3-line clamped text preview |
| Handle | Source account handle |
| Message ID | Platform message identifier |

---

### 3.3 Task Ledger (`TaskLedger.tsx`)

**URL:** `/dashboard` → "Task Ledger" section

#### Tasks Table

| Column | Content |
|--------|---------|
| Task Type | Type of task (scrape, post, etc.) |
| Profile | Associated account profile |
| Execution Timestamp | When task was executed |
| Queue Status | Current status (pending, running, done, failed) |
| Idempotency Key | Unique key preventing duplicate execution |

Data auto-refreshes every 20 s.

---

## 4. Common Components

| Component | Usage |
|-----------|-------|
| `DashboardShell` | Wraps admin/dashboard pages. Provides sidebar nav, sticky header with title + right slot, mobile tab navigation. |
| `MetricCard` | Reusable stat card: icon + label + value + subtitle with accent styling. |
| `StatusBadge` | Colored badge with optional dot indicator for statuses (active, degraded, dead, etc.). |
| `Panel` | Rounded card container with title bar and optional right slot for section content. |

---

## 5. API & Data Flow Summary

### Auto-Refresh Intervals

| Hook | Interval |
|------|----------|
| Health | 15 s |
| Throughput | 30 s |
| Accounts | 30 s |
| Tasks | 20 s |
| Proxies | 30 s |
| Dead Letters | 20 s |
| Content Feed | 30 s |

### Lifecycle of a Launch Action

```
UI (Launch button)
  → POST /accounts/{profileId}/launch
    → Server spawns auto_login.py subprocess
      → Subprocess authenticates with platform
        → DB updated with session/status
          → UI re-fetches account list
            → Table reflects new state
```

### Lifecycle of a Proxy Check

```
UI (Check button)
  → POST /proxies/{rawId}/check
    → Server performs HTTP ping via proxy
      → Latency & success recorded in DB
        → Toast notification sent to UI
          → Table re-fetches with updated metrics
```

### Lifecycle of Dead Letter Retry

```
UI (Retry button)
  → POST /dead-letters/{rawId}/retry
    → Server re-queues task to worker pool
      → Toast notification sent to UI
        → DLQ list re-fetches
          → Card disappears (task is back in queue)
```

### Lifecycle of Dead Letter Dismiss

```
UI (Dismiss button)
  → DELETE /dead-letters/{rawId}
    → Server removes dead letter record from DB
      → Toast notification sent to UI
        → DLQ list re-fetches
          → Card is removed from view
```

---

## 6. Keyboard & Accessibility Notes

- All interactive elements (buttons, inputs) are focusable.
- Tables are scrollable on mobile via horizontal overflow.
- `DashboardShell` provides consistent layout across all authenticated pages.
- Toast notifications appear as non-blocking overlays for action feedback.
