# Integration Testing Plan: Real-System Coverage, Gaps & TDD Roadmap

**Date:** 2026-03-13
**Report ID:** 001
**Subject:** Comprehensive plan for real-system integration testing, gap analysis, and TDD approach
**Status:** Active — Claude will implement all phases described here

---

## 1. Executive Summary

This report is the implementation guide for Claude to:

1. Improve the existing integration test infrastructure with proper logging
2. Fill coverage gaps across all implemented ADT operations
3. Add TDD-style stubs for missing ADT features (failing gracefully with `t.Skip` and warning messages, not breaking CI)
4. Fix known test bugs

**Target:** Run `go test -tags=integration -v ./pkg/adt/ 2>&1 | tee test-run-$(date +%Y%m%d).log` and get complete, actionable insight into what works, what's broken, and what's missing.

**Current state:** ~35 integration tests across ~22 functions tested
**Target state:** ~85 integration tests across ~55+ functions

---

## 2. SAP ABAP Docker System: Prerequisites & Status

### 2.1 Current Docker Image Status (March 2026)

> **IMPORTANT:** The ABAP Cloud Developer Trial 2023 Docker image is **temporarily unavailable** on Docker Hub as of February 2026. SAP removed it for unforeseen reasons and is actively working on **ABAP Cloud Developer Trial 2025** (based on ABAP Platform 2025 SP01). Follow updates at the [official SAP Community blog post](https://community.sap.com/t5/technology-blog-posts-by-sap/abap-cloud-developer-trial-2023-available-now/ba-p/14057183).

**Alternatives while waiting for 2025:**
- SAP Cloud Appliance Library (CAL): [ABAP Cloud Developer Trial 2023 on CAL](https://cal.sap.com/catalog#/applianceTemplates/4d7b4410-ee54-4691-9901-4828d05dfc29) — hosted appliance, same product
- **ABAP Platform 2022** image may still be available: `sapse/abap-cloud-developer-trial:ABAPTRIAL_2022`
- For the 2023 image, tag: `sapse/abap-cloud-developer-trial:2023` (once re-released)

Use SAP Community tag **`#abap_trial`** for support questions.

### 2.2 System Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 16 GB | 32 GB |
| Disk | 100 GB free | 150 GB |
| CPU | 4 cores | 8 cores |
| OS | Linux/macOS/Windows WSL2 | Linux or macOS |

**macOS M-series note:** Rosetta emulation required. See [M-series guide](https://community.sap.com/t5/technology-blog-posts-by-members/m-series-apple-chip-macbooks-and-abap-trial-containers-using-docker-and/ba-p/13593215).

### 2.3 Pull & First Run

```bash
# Once available — check https://hub.docker.com/r/sapse/abap-cloud-developer-trial/tags
docker pull sapse/abap-cloud-developer-trial:2023

# First run (creates container named a4h)
# Note: takes 15-30 min on first start
docker run --stop-timeout 7200 \
  -i --name a4h \
  -h vhcala4hci \
  -p 3200:3200 \
  -p 3300:3300 \
  -p 8443:8443 \
  -p 30213:30213 \
  -p 50000:50000 \
  -p 50001:50001 \
  sapse/abap-cloud-developer-trial:2023 \
  -skip-limits-check
```

**System ready indicator:** Watch for all ICM processes to start:
```bash
docker logs -f a4h 2>&1 | grep -E "ICM|started|Startup|ERROR" | head -30
```

### 2.4 Start / Stop (After First Run)

```bash
# Start (subsequent starts after first run)
docker start -ai a4h

# Stop (ALWAYS use graceful stop — abrupt stop corrupts the container!)
docker stop --time 7200 a4h

# Shell into container
docker exec -it a4h bash

# Check running status
docker ps -a | grep a4h
```

### 2.5 Default Credentials

| Parameter | Value |
|-----------|-------|
| User | `DEVELOPER` |
| Password | `Down1oad` (2022/2023 images) |
| Client | `001` |
| System ID | `A4H` |
| ADT URL | `http://localhost:50000` |
| SAP GUI host | `localhost`, system number `00` |

**License note:** The shipped ABAP license lasts only **3 months**. Renew via [minisap](https://go.support.sap.com/minisap/#/minisap) choosing system A4H. See the [FAQ](https://github.com/SAP-docs/abap-platform-trial-image/blob/main/faq-v7.md) for renewal steps.

### 2.6 Environment Variables for Testing

Create `.env.test` (already in `.gitignore`):
```bash
# .env.test — DO NOT COMMIT
export SAP_URL=http://localhost:50000
export SAP_USER=DEVELOPER
export SAP_PASSWORD=Down1oad
export SAP_CLIENT=001
export SAP_LANGUAGE=EN
export SAP_INSECURE=false
export SAP_TEST_VERBOSE=true    # Enable detailed HTTP request/response logging
export SAP_TEST_NO_CLEANUP=     # Set to "true" to skip object cleanup for debugging
```

### 2.7 Verify ADT Connection

```bash
# Quick connectivity test
curl -s -u DEVELOPER:Down1oad \
  -H "X-CSRF-Token: Fetch" \
  "http://localhost:50000/sap/bc/adt/core/discovery" \
  -o /dev/null -w "HTTP %{http_code}\n"
# Expected: HTTP 200

# Detailed check with token
curl -v -u DEVELOPER:Down1oad \
  -H "X-CSRF-Token: Fetch" \
  "http://localhost:50000/sap/bc/adt/core/discovery" 2>&1 | \
  grep -E "HTTP|x-csrf-token|sap-client"
```

---

## 3. Implementation Plan for Claude

Claude will implement these phases in order. Each phase has clear file targets and patterns.

### Phase 1: Test Infrastructure (Do This First)

**Files to modify:** `pkg/adt/integration_test.go`

#### 1.1 Add `testLogger` struct

Add at the top of `integration_test.go` after imports:

```go
// testLogger provides structured, timestamped logging for integration tests.
// Enable verbose mode with SAP_TEST_VERBOSE=true to see HTTP-level details.
type testLogger struct {
    t       *testing.T
    verbose bool
    start   time.Time
}

func newTestLogger(t *testing.T) *testLogger {
    t.Helper()
    return &testLogger{
        t:       t,
        verbose: os.Getenv("SAP_TEST_VERBOSE") == "true",
        start:   time.Now(),
    }
}

func (l *testLogger) Info(format string, args ...interface{}) {
    l.t.Helper()
    elapsed := time.Since(l.start).Round(time.Millisecond)
    l.t.Logf("[INFO  +%6v] %s", elapsed, fmt.Sprintf(format, args...))
}

func (l *testLogger) Debug(format string, args ...interface{}) {
    if !l.verbose {
        return
    }
    l.t.Helper()
    elapsed := time.Since(l.start).Round(time.Millisecond)
    l.t.Logf("[DEBUG +%6v] %s", elapsed, fmt.Sprintf(format, args...))
}

func (l *testLogger) Warn(format string, args ...interface{}) {
    l.t.Helper()
    elapsed := time.Since(l.start).Round(time.Millisecond)
    l.t.Logf("[WARN  +%6v] %s", elapsed, fmt.Sprintf(format, args...))
}

func (l *testLogger) Todo(feature string) {
    l.t.Helper()
    l.t.Logf("[TODO ] Feature not yet implemented or tested: %s", feature)
    l.t.Skip("TODO: " + feature)
}
```

#### 1.2 Replace `getIntegrationClient` with `requireIntegrationClient`

```go
// requireIntegrationClient returns a configured ADT client or skips the test
// if environment variables are not set. Logs connection details at INFO level.
func requireIntegrationClient(t *testing.T) *Client {
    t.Helper()
    url := os.Getenv("SAP_URL")
    user := os.Getenv("SAP_USER")
    pass := os.Getenv("SAP_PASSWORD")

    if url == "" || user == "" || pass == "" {
        t.Skip("Integration tests require SAP_URL, SAP_USER, SAP_PASSWORD — see reports/2026-03-13-001-integration-testing-plan.md")
    }

    client := os.Getenv("SAP_CLIENT")
    if client == "" {
        client = "001"
    }
    lang := os.Getenv("SAP_LANGUAGE")
    if lang == "" {
        lang = "EN"
    }

    log := newTestLogger(t)
    log.Info("Connecting to %s as %s (client=%s, lang=%s)", url, user, client, lang)

    opts := []Option{
        WithClient(client),
        WithLanguage(lang),
        WithTimeout(60 * time.Second),
    }
    if os.Getenv("SAP_INSECURE") == "true" {
        opts = append(opts, WithInsecureSkipVerify())
    }

    return NewClient(url, user, pass, opts...)
}
```

#### 1.3 Add `withTempProgram` and `withTempClass` helpers

```go
// tempObjectName returns a unique name for test objects to avoid collisions.
func tempObjectName(base string) string {
    // Use last 5 digits of unix timestamp for uniqueness
    return fmt.Sprintf("%s_%05d", base, time.Now().Unix()%100000)
}

// withTempProgram creates a program in $TMP, runs fn with its URL, then deletes it.
// Handles cleanup even when the test fails.
func withTempProgram(t *testing.T, client *Client, name, source string, fn func(objectURL string)) {
    t.Helper()
    ctx := context.Background()
    log := newTestLogger(t)

    result, err := client.CreateAndActivateProgram(ctx, name, "Integration test object", "$TMP", source, "")
    if err != nil {
        t.Fatalf("Setup: could not create program %s: %v", name, err)
    }
    log.Info("Created test program: %s (URL: %s)", name, result.ObjectURL)

    t.Cleanup(func() {
        if os.Getenv("SAP_TEST_NO_CLEANUP") == "true" {
            log.Warn("Cleanup skipped (SAP_TEST_NO_CLEANUP=true) — delete %s manually", name)
            return
        }
        lockCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
        defer cancel()
        lock, err := client.LockObject(lockCtx, result.ObjectURL, "MODIFY")
        if err != nil {
            log.Warn("Cleanup: could not lock %s: %v", name, err)
            return
        }
        if err := client.DeleteObject(lockCtx, result.ObjectURL, lock.Handle, ""); err != nil {
            log.Warn("Cleanup: could not delete %s: %v", name, err)
        } else {
            log.Info("Cleanup: deleted %s", name)
        }
    })

    fn(result.ObjectURL)
}
```

#### 1.4 Fix Bug B-004: Replace standard program lock tests with $TMP objects

In `TestIntegration_LockUnlock`, replace the usage of `SAPMSSY0` with a temp program created and deleted within the test.

### Phase 2: Read-Only Gap Tests

Add these tests to `integration_test.go`. All are safe to run in parallel (`t.Parallel()`).

**T-001: GetInterface**
```go
func TestIntegration_GetInterface(t *testing.T) {
    t.Parallel()
    client := requireIntegrationClient(t)
    log := newTestLogger(t)
    ctx := context.Background()

    // IF_SERIALIZABLE_OBJECT is a stable standard interface
    source, err := client.GetInterface(ctx, "IF_SERIALIZABLE_OBJECT")
    if err != nil {
        t.Skipf("Could not get IF_SERIALIZABLE_OBJECT: %v", err)
    }
    if source == "" {
        t.Error("Interface source is empty")
    }
    log.Info("Got interface source: %d chars", len(source))
    log.Debug("Preview: %.200s", source)
    if !strings.Contains(strings.ToUpper(source), "INTERFACE") {
        t.Errorf("Source does not look like an interface definition: %.100s", source)
    }
}
```

**T-002: GetFunctionGroup + GetFunction**
**T-003: GetView + GetStructure**
**T-004: GetSystemInfo**
**T-005: GetInstalledComponents**
**T-006: GetClassComponents**
**T-014: GetDumps**
**T-015: ListTraces**
**T-017: FeatureProber**

Each follows the same pattern: `t.Parallel()`, `requireIntegrationClient`, `newTestLogger`, skip gracefully on not-found, assert non-empty results, log all returned fields for diagnostics.

### Phase 3: Write/CRUD Gap Tests

These require sequential execution (no `t.Parallel()`) and use `withTempProgram`/`withTempClass`:

**T-007: GetInactiveObjects** — create object → check it's inactive → activate → check it's gone from inactive list
**T-008: RunATCCheck** — create program with known lint issues → run ATC → assert findings
**T-009: GetCallGraph** — use known class URI → get callers/callees → assert non-empty
**T-010: ExecuteABAP** — execute `DATA lv_x TYPE i. lv_x = 1 + 1.` → assert no errors
**T-012: GrepPackage** — create program with known string → grep for it → assert found
**T-013: EditSource edge cases** — pattern not found, multiple matches
**T-016: ClassIncludes Full** — create class → read/write all 5 include types

### Phase 4: Transport Tests

**T-011: Transport Lifecycle**
```go
func TestIntegration_TransportLifecycle(t *testing.T) {
    // GetUserTransports → CreateTransport → GetTransport → ListTransports
    // Does NOT release (too destructive). Deletes transport at cleanup.
}
```

**T-018: GetTransportInfo** — get transport info for a known $TMP object
**T-019: ListTransports** — list current user's transports, log count

### Phase 5: TDD Stubs for Missing ADT Features

These are tests that **don't exist yet in vsp** but should be specified as test stubs. Use `newTestLogger(t).Todo(...)` which calls `t.Skip` — they appear as SKIP in output, not failures, but they're visible and executable.

**Missing features to stub:**

```go
func TestIntegration_GetDomain(t *testing.T) {
    log := newTestLogger(t)
    log.Todo("GetDomain not implemented in client.go — ADT endpoint: /sap/bc/adt/ddic/domains/{name}/source/main")
}

func TestIntegration_GetDataElement(t *testing.T) {
    log := newTestLogger(t)
    log.Todo("GetDataElement not implemented in client.go — ADT endpoint: /sap/bc/adt/ddic/dataelements/{name}/source/main")
}

func TestIntegration_WhereUsed(t *testing.T) {
    log := newTestLogger(t)
    log.Todo("WhereUsed not implemented — ADT endpoint: /sap/bc/adt/ris/where_used — high value feature for impact analysis")
}

func TestIntegration_GetEnhancements(t *testing.T) {
    log := newTestLogger(t)
    log.Todo("Enhancement discovery not implemented — ADT endpoint: /sap/bc/adt/enhancements")
}

func TestIntegration_GetAbapAST(t *testing.T) {
    log := newTestLogger(t)
    log.Todo("ABAP AST parsing not implemented — ADT endpoint: /sap/bc/adt/abapsource/abapast")
}

func TestIntegration_GetVersionHistory(t *testing.T) {
    log := newTestLogger(t)
    log.Todo("Version history not implemented — ADT endpoint: /sap/bc/adt/vit/wb/object_versions")
}
```

### Phase 6: Bug Regression Tests

For each known bug, add a test that documents and verifies the fix:

**B-001: EditSource returns error when pattern not found**
```go
func TestIntegration_EditSource_PatternNotFound(t *testing.T) {
    // Create temp program → EditSource with pattern that doesn't exist
    // Expected: error containing "not found" or similar message
    // Current behavior: TBD — test documents whatever happens
}
```

**B-007: GetTableContents with 0 rows**
```go
func TestIntegration_GetTableContents_EmptyResult(t *testing.T) {
    // Query T000 with WHERE condition that returns no rows
    // Expected: empty result, no error
}
```

**B-010: GetClass returns all include types**
```go
func TestIntegration_GetClass_AllIncludes(t *testing.T) {
    // Get a class we know has test includes
    // Assert all 5 keys present in map: main, localDef, localImp, macros, testclasses
    // Log what keys are actually returned
}
```

---

## 4. Current Test Coverage Analysis

### 4.1 Quality of Existing Tests

| # | Test Name | Quality | Issues to Fix |
|---|-----------|---------|---------------|
| 1 | SearchObject | OK | No structure validation |
| 2 | GetProgram | Soft | Falls back to Skip |
| 3 | GetClass | Soft | Skips if not found |
| 4-6 | Table/Query | OK | No edge cases |
| 12 | CRUD_FullWorkflow | **Good** | Only PROG type |
| 13 | LockUnlock | Risky | Locks SAPMSSY0 (B-004) |
| 14 | ClassWithUnitTests | **Good** | Most thorough |
| 33-35 | Debugger | Weak | Mostly skipped |

**Quality:** Good = full lifecycle | OK = happy path | Soft = many skips | Weak = mostly skipped

### 4.2 Test Improvements to Existing Tests

In addition to new tests, update existing tests to:
- Use `requireIntegrationClient` instead of `getIntegrationClient`
- Add `newTestLogger` for structured output
- Add `t.Cleanup` for all object creation (currently some tests leak objects)
- Remove blanket `t.Skipf` on first error — log the failure and try alternatives instead

---

## 5. Gap Analysis: Missing Integration Tests

### 5.1 Client-Level Operations (pkg/adt/client.go)

| Method | Integration Test | Priority |
|--------|-----------------|----------|
| GetInterface | ❌ T-001 | HIGH |
| GetFunctionGroup | ❌ T-002 | HIGH |
| GetFunction | ❌ T-002 | HIGH |
| GetInclude | ❌ | MEDIUM |
| GetSRVD | ❌ | MEDIUM |
| GetMessageClass | ❌ | MEDIUM |
| GetView | ❌ T-003 | HIGH |
| GetStructure | ❌ T-003 | HIGH |
| GetTransaction | ❌ | MEDIUM |
| GetSystemInfo | ❌ T-004 | HIGH |
| GetInstalledComponents | ❌ T-005 | HIGH |
| GetCallGraph | ❌ T-009 | HIGH |
| GetCallersOf / GetCalleesOf | ❌ T-009 | HIGH |
| GetObjectStructureCAI | ❌ | HIGH |
| GetDumps / GetDump | ❌ T-014 | HIGH |
| ListTraces / GetTrace | ❌ T-015 | HIGH |
| GetSQLTraceState / ListSQLTraces | ❌ | MEDIUM |

### 5.2 CRUD Operations (pkg/adt/crud.go)

| Method | Integration Test | Priority |
|--------|-----------------|----------|
| CreateObject(INTF) | ❌ | HIGH |
| CreateObject(FUGR/FM) | ❌ | HIGH |
| CreateObject(TABL) | ❌ | HIGH |
| CreateObject(DOMA/DTEL/STRU) | ❌ | HIGH |
| CreateObject(DDLS/BDEF/SRVD/SRVB) | partial | MEDIUM |
| GetClassInclude (locals_def/imp/macros) | ❌ T-016 | HIGH |
| UpdateClassInclude | ❌ T-016 | HIGH |
| UnpublishServiceBinding | ❌ | MEDIUM |

### 5.3 Development Tools (pkg/adt/devtools.go)

| Method | Integration Test | Priority |
|--------|-----------------|----------|
| GetInactiveObjects | ❌ T-007 | HIGH |
| ActivatePackage | ❌ | MEDIUM |
| RunATCCheck | ❌ T-008 | HIGH |
| GetATCWorklist | ❌ T-008 | HIGH |
| GetATCCustomizing | ❌ | MEDIUM |

### 5.4 Code Intelligence (pkg/adt/codeintel.go)

| Method | Integration Test | Priority |
|--------|-----------------|----------|
| GetClassComponents | ❌ T-006 | HIGH |
| SetPrettyPrinterSettings | ❌ | MEDIUM |
| CodeCompletionFull | ❌ | LOW |

### 5.5 Transport Management (pkg/adt/transport.go)

| Method | Integration Test | Priority |
|--------|-----------------|----------|
| GetUserTransports | ❌ T-011 | HIGH |
| GetTransportInfo | ❌ T-018 | HIGH |
| CreateTransport | ❌ T-011 | HIGH |
| ListTransports | ❌ T-019 | HIGH |
| GetTransport | ❌ T-011 | HIGH |
| ReleaseTransport | ❌ (dangerous) | LOW |
| DeleteTransport | ❌ (dangerous) | LOW |

### 5.6 Workflows (pkg/adt/workflows.go)

| Method | Integration Test | Priority |
|--------|-----------------|----------|
| GrepObject / GrepPackage | ❌ T-012 | HIGH |
| ExecuteABAP | ❌ T-010 | HIGH |
| CompareSource | ❌ | MEDIUM |
| CloneObject | ❌ | MEDIUM |
| RenameObject | ❌ | MEDIUM |
| GetClassInfo | ❌ | MEDIUM |

### 5.7 Missing ADT Features (not yet implemented in vsp)

These need both implementation and tests. Phase 5 stubs document them:

| Feature | ADT Endpoint | Priority |
|---------|-------------|----------|
| GetDomain source | `/sap/bc/adt/ddic/domains/{name}/source/main` | HIGH |
| GetDataElement source | `/sap/bc/adt/ddic/dataelements/{name}/source/main` | HIGH |
| WhereUsed analysis | `/sap/bc/adt/ris/where_used` | HIGH |
| GetEnhancements | `/sap/bc/adt/enhancements` | MEDIUM |
| GetAbapAST | `/sap/bc/adt/abapsource/abapast` | MEDIUM |
| Version history | `/sap/bc/adt/vit/wb/object_versions` | MEDIUM |
| Semantic highlighting | `/sap/bc/adt/abapsource/semantichighlighting` | LOW |
| GetIncludes (recursive) | `/sap/bc/adt/programs/{name}/includes` | MEDIUM |

---

## 6. Known Bugs — Regression Tests

| Bug | Description | Test |
|-----|-------------|------|
| B-001 | EditSource: behavior undefined when pattern not found | T-013 |
| B-002 | GetDomain/GetDataElement not in client.go | Phase 5 stub |
| B-003 | CreateObject unvalidated for many types (INTF, TABL, etc.) | Phase 3 |
| B-004 | LockUnlock test locks SAPMSSY0 (standard program — risky) | Fix in Phase 1 |
| B-005 | DebuggerListener test always times out; no meaningful assertion | Phase 4 |
| B-006 | ListTransports SQL fallback returns different structure | T-011 |
| B-007 | GetTableContents: no test for 0-row or pagination boundary | Phase 2 |
| B-008 | Activate: result content never validated (warnings possible) | Phase 3 |
| B-009 | WriteSource: CRLF normalization not round-trip tested | Phase 3 |
| B-010 | GetClass: not all 5 include types validated | Phase 2 |

---

## 7. Test Design Patterns

Good patterns to apply consistently across all new tests:

### 7.1 Object Naming

```go
// Use timestamp suffix to avoid name collisions across parallel runs
func tempObjectName(base string) string {
    return fmt.Sprintf("%s_%05d", base, time.Now().Unix()%100000)
}
// Example: ZTEST_PROG_42317
```

### 7.2 Delay Between Operations

Some operations need a small delay after locking for SAP to process:
```go
// After acquiring a lock, allow SAP processing time
time.Sleep(200 * time.Millisecond)
```

### 7.3 Transport-Free Testing

All test objects go to `$TMP` (local package, no transport needed). For transport-specific tests, use a dedicated test that creates and immediately deletes a transport.

### 7.4 Cleanup Safety

```go
t.Cleanup(func() {
    if os.Getenv("SAP_TEST_NO_CLEANUP") == "true" {
        t.Logf("WARNING: cleanup skipped — delete %s manually", name)
        return
    }
    // ... delete object
})
```

### 7.5 Skip vs Fail

- Use `t.Skip` when the test infrastructure isn't available (env vars missing, object type not on system)
- Use `t.Fatal` / `t.Error` when the feature is expected to work but doesn't
- Use `log.Todo(...)` (which calls `t.Skip`) for genuinely unimplemented features

---

## 8. Summary: Current vs. Target Coverage

| Category | Current | Target | Gap |
|----------|---------|--------|-----|
| Basic Read (PROG, CLAS, INTF, FUGR) | 2/4 | 4/4 | +2 |
| DDIC (TABL, VIEW, STRU) | 1/3 | 3/3 | +2 |
| DDIC Missing (DOMA, DTEL) | 0 (not impl.) | stubs | spec |
| RAP Objects (DDLS, BDEF, SRVD, SRVB) | 3/4 | 4/4 | +1 |
| CRUD Full Lifecycle | PROG, CLAS | +INTF, FUGR, TABL | +3 |
| Class Includes | partial | all 5 types | +3 |
| Code Intelligence | 4/7 | 7/7 | +3 |
| Transport Management | 0/8 | 5/8 (safe ops) | +5 |
| ATC/Quality | 0/4 | 4/4 | +4 |
| Runtime Diagnostics | 0/5 | 5/5 | +5 |
| ExecuteABAP | 0/1 | 1/1 | +1 |
| GrepPackage/Objects | 0/4 | 4/4 | +4 |
| System/Features | 0/3 | 3/3 | +3 |
| WhereUsed/Enhancements | 0 (not impl.) | stubs | spec |
| **TOTAL** | **~35** | **~85** | **+50** |

---

## 9. Quick Start Guide

> Read this section after the tests are implemented. It's a cheat sheet for running tests, reading logs, and diagnosing failures.

### One-Time Setup

```bash
# 1. Create .env.test (do once)
cat > .env.test << 'EOF'
export SAP_URL=http://localhost:50000
export SAP_USER=DEVELOPER
export SAP_PASSWORD=Down1oad
export SAP_CLIENT=001
export SAP_LANGUAGE=EN
export SAP_INSECURE=false
EOF

# 2. Load it
source .env.test

# 3. Verify SAP is reachable
curl -s -u "$SAP_USER:$SAP_PASSWORD" \
  -H "X-CSRF-Token: Fetch" \
  "$SAP_URL/sap/bc/adt/core/discovery" -o /dev/null -w "HTTP %{http_code}\n"
# Should print: HTTP 200
```

### Daily Workflow

```bash
# Start SAP (wait 5-15 min after first pull, ~2 min for restarts)
docker start -ai a4h &
# Wait until ADT responds (poll every 10s)
until curl -s -u DEVELOPER:Down1oad http://localhost:50000/sap/bc/adt/core/discovery \
  -o /dev/null -w "%{http_code}" | grep -q 200; do
  echo "Waiting for SAP..."; sleep 10
done
echo "SAP is ready!"

# Run all unit tests (no SAP needed, always fast)
go test ./...

# Run read-only integration tests (~30s, safe)
source .env.test
go test -tags=integration -v -timeout 120s ./pkg/adt/ \
  -run "TestIntegration_(Search|GetProgram|GetClass|GetInterface|GetView|GetStructure|GetSystem|GetInstalled)" \
  2>&1 | tee reports/test-readonly-$(date +%Y%m%d-%H%M).log

# Run full integration suite (~5-10 min)
go test -tags=integration -v -timeout 600s ./pkg/adt/ \
  2>&1 | tee reports/test-full-$(date +%Y%m%d-%H%M).log

# Stop SAP (CRITICAL: always graceful!)
docker stop --time 7200 a4h
```

### Debug Mode: Maximum Logs

Use this when a test fails and you need to understand why:

```bash
# Full verbose run — logs every HTTP request/response
SAP_TEST_VERBOSE=true \
go test -tags=integration -v -timeout 120s ./pkg/adt/ \
  -run TestIntegration_YourFailingTest \
  2>&1 | tee reports/debug-$(date +%Y%m%d-%H%M).log

# View just the debug output for one test
grep -A 50 "=== RUN.*YourFailingTest" reports/debug-*.log

# Keep objects after test for manual inspection in Eclipse/SAP GUI
SAP_TEST_NO_CLEANUP=true SAP_TEST_VERBOSE=true \
go test -tags=integration -v ./pkg/adt/ \
  -run TestIntegration_YourFailingTest
# Remember to manually delete the test objects afterward!
```

### Reading Test Output

```
=== RUN   TestIntegration_GetInterface
    integration_test.go:XXX: [INFO    +2ms] Connecting to http://localhost:50000 as DEVELOPER (client=001)
    integration_test.go:XXX: [INFO   +45ms] Got interface source: 384 chars
--- PASS:  TestIntegration_GetInterface (0.05s)

=== RUN   TestIntegration_GetDomain
    integration_test.go:XXX: [TODO ] Feature not yet implemented or tested: GetDomain not implemented in client.go
--- SKIP:  TestIntegration_GetDomain (0.00s)

=== RUN   TestIntegration_RunATCCheck
    integration_test.go:XXX: [WARN  +120ms] ATC check timed out — system may not be configured
--- FAIL:  TestIntegration_RunATCCheck (1.20s)
```

- **PASS** = works correctly
- **SKIP** = either missing env vars OR a `TODO` stub (feature not implemented)
- **FAIL** = implemented but broken — this needs fixing
- `[TODO ]` in SKIP output = intentional stub, not a real failure

### Feeding Logs Back to Claude

After a test run, share the log file. Most useful filters:

```bash
# Summary: just PASS/FAIL/SKIP counts
go test -tags=integration ./pkg/adt/ 2>&1 | tail -5

# Only failures
grep -E "^--- FAIL|^\s+.*Error|^\s+.*Fatal" reports/test-full-*.log

# All TODOs (unimplemented features)
grep "\[TODO \]" reports/test-full-*.log

# All warnings
grep "\[WARN " reports/test-full-*.log

# Full output for a specific failing test
awk '/=== RUN.*FailingTest/,/--- (FAIL|PASS|SKIP).*FailingTest/' \
  reports/test-full-*.log

# Generate a summary to paste to Claude
echo "=== Test Run Summary ===" > /tmp/summary.txt
echo "Date: $(date)" >> /tmp/summary.txt
go test -tags=integration ./pkg/adt/ 2>&1 | tail -3 >> /tmp/summary.txt
echo "" >> /tmp/summary.txt
echo "=== Failures ===" >> /tmp/summary.txt
grep -E "^--- FAIL" reports/test-full-*.log >> /tmp/summary.txt
echo "" >> /tmp/summary.txt
echo "=== TODOs (unimplemented) ===" >> /tmp/summary.txt
grep "\[TODO \]" reports/test-full-*.log >> /tmp/summary.txt
cat /tmp/summary.txt
```

### Common Failure Diagnoses

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| All tests SKIP with "SAP_URL required" | Env not loaded | `source .env.test` |
| `connection refused` on all tests | SAP not started | `docker start -ai a4h`, wait 2 min |
| `HTTP 401` | Wrong credentials | Check `SAP_USER`/`SAP_PASSWORD` |
| `HTTP 403 CSRF` | CSRF token stale | Auto-handled by client; retry once |
| `HTTP 404` on specific object | Object doesn't exist on your system | Test skips gracefully |
| `license` error in SAP GUI | 3-month license expired | Renew via [minisap](https://go.support.sap.com/minisap/#/minisap) |
| Test creates object, fails, leaves orphan | Cleanup failed | Run with `SAP_TEST_VERBOSE=true`, check WARN lines; delete manually in Eclipse |
| Test hangs | Timeout too low | Add `-timeout 300s` |

---

*Report created: 2026-03-13*
*Sources:*
- *[ABAP Cloud Developer Trial 2023 Available Now (SAP Community)](https://community.sap.com/t5/technology-blog-posts-by-sap/abap-cloud-developer-trial-2023-available-now/ba-p/14057183)*
- *[ABAP Trial Platform on Docker: FAQ (GitHub)](https://github.com/SAP-docs/abap-platform-trial-image/blob/main/faq-v7.md)*
- *[M-series MacBook Docker guide (SAP Community)](https://community.sap.com/t5/technology-blog-posts-by-members/m-series-apple-chip-macbooks-and-abap-trial-containers-using-docker-and/ba-p/13593215)*
