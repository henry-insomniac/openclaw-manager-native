# OpenClaw Manager Native Performance Report

Date: 2026-03-12

## Test Environment

- Hardware: Apple M1 Pro, 32 GB RAM
- OS: macOS 26.2 (build 25C56)
- App under test: `/Applications/OpenClaw Manager Native.app`
- App version: `1.0.6`
- Runtime mode: installed app + bundled `openclaw-manager-daemon`

## Scope

This audit covered four areas:

1. Startup responsiveness
2. Steady-state resource usage by page
3. API latency and cache behavior
4. Structural bottlenecks in the current refresh pipeline

## Methodology

### Startup

- Repeated 5 cold launches of the installed app
- Measured:
  - time until the first app window became visible via Accessibility
  - time until `GET /api/health` returned `200`

### Page Resource Sampling

- Kept the installed app running
- Navigated to:
  - overview
  - monitor
  - diagnostics
- Sampled app + daemon for 35 seconds per page with `top`
- Metrics captured:
  - `%CPU`
  - RSS memory
  - thread count

### API Latency

- Started a separate daemon on `127.0.0.1:3337`
- Benchmarked:
  - `/api/health`
  - `/api/openclaw/manager`
  - `/api/openclaw/system`
  - `/api/machine/summary`
  - `/api/machine/summary?fresh=1`
  - `/api/support/summary`
  - `/api/support/summary?fresh=1`
- Used 20 runs for light endpoints and 8 runs for heavy `fresh=1` endpoints

### Code Path Review

- Verified startup and refresh scope from:
  - `Sources/OpenClawManagerNative/main.swift`
  - `Sources/OpenClawManagerNative/NativeStore.swift`
  - `cmd/openclaw-manager-daemon/main.go`

## Executive Findings

### 1. High: full diagnostics refresh is the dominant user-visible latency source

- `GET /api/support/summary?fresh=1` took:
  - average `3494.56 ms`
  - median `3406.83 ms`
  - max `4490.59 ms`
- This is the slowest path in the product.
- Any explicit full refresh or diagnostics-heavy flow will inherit this delay.

Impact:

- Manual full refresh will feel slow even when the UI itself is responsive.
- Startup data hydration is slower than window appearance because the app launches the window first, then immediately fires a default `.full` refresh.

### 2. High: machine fresh collection is expensive, but the current cache keeps monitor polling acceptable

- `GET /api/machine/summary?fresh=1` took:
  - average `2249.06 ms`
  - median `2243.97 ms`
  - max `2344.04 ms`
- Hot cached `GET /api/machine/summary` calls were usually `1-2 ms`.
- Once the 3 second TTL expires, the same non-fresh endpoint can fall back to roughly `2.2 s` again.

Observed sequence on the cached endpoint:

- `2258.44 ms`
- `2.26 ms`
- `1.99 ms`
- `2.12 ms`
- `2.06 ms`
- `1.89 ms`
- `2216.63 ms`

Impact:

- The monitor page is efficient in steady state because it usually hits cache.
- Any future change that increases monitor polling frequency or bypasses cache will become visible quickly.

### 3. Medium: monitor page is measurably heavier than overview/diagnostics, but still within a safe desktop range

Steady-state 35 second samples:

| Page | Combined CPU Avg | Combined CPU Max | App RSS Avg | Daemon RSS Avg |
| --- | ---: | ---: | ---: | ---: |
| Overview | `0.28%` | `3.7%` | `51.0 MB` | `15.0 MB` |
| Monitor | `1.56%` | `11.7%` | `61.22 MB` | `15.23 MB` |
| Diagnostics | `0.34%` | `3.3%` | `54.57 MB` | `16.0 MB` |

Monitor page deltas vs overview:

- combined CPU average: `+1.28%`
- app memory: `+10.22 MB`
- daemon memory: effectively flat

Impact:

- The new charts and 5 second monitor polling do have a real cost.
- That cost is modest enough for normal desktop use and does not currently look dangerous.

### 4. Medium: startup feels visually fast, but not fully data-ready

Cold launch results:

| Metric | Average | Median | Max |
| --- | ---: | ---: | ---: |
| First window visible | `241.4 ms` | `77.3 ms` | `934.9 ms` |
| `/api/health` ready | `68.8 ms` | `71.9 ms` | `89.2 ms` |

Raw startup runs:

- Window: `89.2`, `53.5`, `52.0`, `77.3`, `934.9` ms
- Health: `89.2`, `53.5`, `52.0`, `77.3`, `71.9` ms

Interpretation:

- Runtime readiness is excellent.
- The `934.9 ms` window outlier is likely Accessibility/UI-detection noise, not an actual backend regression.
- The real startup gap is not window creation; it is the follow-up `.full` refresh triggered from app startup.

### 5. Medium: cached endpoints are fast, but their latency profile is bimodal

Standalone daemon benchmark:

| Endpoint | Avg | Median | P95 | Max |
| --- | ---: | ---: | ---: | ---: |
| `/api/health` | `1.97 ms` | `0.43 ms` | `3.83 ms` | `29.14 ms` |
| `/api/openclaw/manager` | `118.51 ms` | `24.45 ms` | `134.66 ms` | `1888.40 ms` |
| `/api/openclaw/system` | `23.42 ms` | `22.97 ms` | `24.85 ms` | `27.84 ms` |
| `/api/machine/summary` | `112.38 ms` | `0.41 ms` | `112.83 ms` | `2238.91 ms` |
| `/api/machine/summary?fresh=1` | `2249.06 ms` | `2243.97 ms` | `2319.85 ms` | `2344.04 ms` |
| `/api/support/summary` | `214.99 ms` | `0.54 ms` | `219.27 ms` | `4275.93 ms` |
| `/api/support/summary?fresh=1` | `3494.56 ms` | `3406.83 ms` | `4131.55 ms` | `4490.59 ms` |

Interpretation:

- Hot cache hits are effectively instantaneous.
- Average latency alone is misleading because cache misses dominate the mean.
- For product behavior, the important distinction is:
  - hot hit: fast enough to feel local
  - TTL miss or fresh call: multi-second wait

## Detailed Notes

### Manager Summary

The first `/api/openclaw/manager` request after daemon startup was slow (`1644.92 ms`), then stabilized to roughly `25-42 ms`.

Observed sequence:

- `1644.92 ms`
- `30.33 ms`
- `36.16 ms`
- `40.52 ms`
- `40.49 ms`
- `40.33 ms`
- `39.65 ms`
- `25.70 ms`
- `38.00 ms`
- `42.00 ms`

This looks like a one-time warm-up cost rather than steady-state pressure.

### Support Summary

Hot cached `/api/support/summary` requests stayed around `1.36-3.50 ms` in repeated back-to-back calls.

That means the normal diagnostics page is not expensive because of rendering alone. The expensive part is rebuilding fresh support data.

### Monitor Polling Design

The current design choice is sound:

- monitor page: `5s` polling with `monitorOnly`
- diagnostics page: `30s` polling with `.full`
- other pages: `30s` polling with `managerOnly`

This is the main reason the monitor page remains usable despite a `~2.25 s` fresh machine collection path.

## Code-Linked Interpretation

### Startup path

At launch the app does this sequence:

1. initialize environment
2. restart bundled runtime
3. open the main window
4. call `refreshManagerData()` with default `.full`
5. start periodic timers

Effect:

- the shell appears quickly
- manager, support, and machine data are fetched immediately after
- first meaningful data hydration can therefore lag behind first paint by several seconds

### Refresh scopes

The scope split is already preventing larger regressions:

- `.managerOnly`
- `.monitorOnly`
- `.full`

This is a strong design decision and should be preserved.

### Cache TTLs

Current daemon TTLs relevant to UI performance:

- support summary: `10s`
- machine summary: `3s`
- support gateway/events: `45s`
- support maintenance/environment subparts: `2m`

The `3s` machine TTL is the main reason non-fresh monitor requests can still occasionally hit a multi-second refresh if the call lands just after expiry.

## Recommendations

### Priority 1

Change startup hydration from eager `.full` to staged loading:

- startup immediately with `managerOnly`
- load machine summary right after first paint
- defer support summary until diagnostics is opened, or load it in the background without blocking initial UI expectations

Expected gain:

- better perceived startup
- lower risk that the app feels "slow" despite the window already being open

### Priority 2

Change non-fresh support summary behavior so stale data can be returned immediately while a background refresh updates cache.

Expected gain:

- avoids multi-second cliff on a normal non-fresh diagnostics read
- preserves responsiveness without losing eventual freshness

### Priority 3

Split machine summary into mixed cadences instead of one all-in refresh.

Suggested direction:

- CPU / memory / network: fast cadence
- disk / top process list: slower cadence
- expensive process collection: separate cache

Expected gain:

- monitor page gets cheaper without losing the live feel

### Priority 4

Add internal telemetry for:

- app launch to first window
- app launch to first manager data
- app launch to first machine data
- app launch to first support data

Expected gain:

- future regressions become measurable without rerunning manual AppleScript tests

## Bottom Line

The app is already in a decent steady-state place:

- startup shell visibility is fast
- overview and diagnostics idle costs are low
- monitor page overhead is real but acceptable

The main performance problem is not rendering. It is synchronous data collection on fresh and TTL-expired backend paths, especially support summary and machine summary.

If only one optimization is taken next, it should be startup staging plus a less blocking non-fresh support summary strategy.

## Post-Fix Validation

The following fixes were applied after the audit:

- app startup now stages data loading:
  - first `managerOnly`
  - then `monitorOnly`
  - support summary warms in the background instead of blocking first paint
- non-fresh `/api/support/summary` now returns cached data immediately and refreshes in the background when expired
- non-fresh `/api/machine/summary` now does the same
- header refresh now follows the current page scope instead of defaulting to full refresh outside monitor

Validation against the rebuilt daemon:

| Check | Before | After |
| --- | ---: | ---: |
| `/api/support/summary` first call after TTL expiry | `3810.07 ms` | `1.06 ms` |
| `/api/machine/summary` first call after TTL expiry | `2194.69 ms` | `1.93 ms` |

Observed sequence after the fix:

- support: cold `4670.52 ms` -> hot `0.84 ms` -> after 10s TTL `1.06 ms`
- machine: cold `2296.99 ms` -> hot `0.86 ms` -> after 3s TTL `1.93 ms`

This confirms the main perceived-latency cliff on normal non-fresh reads has been removed.
