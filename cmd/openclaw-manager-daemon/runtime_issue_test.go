package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestReadRecentRuntimeFailureSignalPrefersRateLimit(t *testing.T) {
	rootDir := t.TempDir()
	app := &App{openclawHomeDir: rootDir}

	now := time.Now().UTC()
	lastActivatedAt := now.Add(-5 * time.Minute).Format(time.RFC3339)
	writeGatewayErrLog(t, rootDir, []string{
		runtimeLogLine(now.Add(-20*time.Minute), "LLM request timed out."),
		runtimeLogLine(now.Add(-3*time.Minute), "LLM request timed out."),
		runtimeLogLine(now.Add(-1*time.Minute), "⚠️ API rate limit reached. Please try again later."),
	})

	issue := app.readRecentRuntimeFailureSignal(&lastActivatedAt)
	if issue == nil {
		t.Fatalf("expected runtime issue")
	}
	if issue.Kind != "rate_limit" {
		t.Fatalf("expected rate_limit, got %s", issue.Kind)
	}
	if !strings.Contains(issue.Message, "API rate limit reached") {
		t.Fatalf("unexpected issue message: %s", issue.Message)
	}
}

func TestReadRecentRuntimeFailureSignalIgnoresEventsBeforeActivation(t *testing.T) {
	rootDir := t.TempDir()
	app := &App{openclawHomeDir: rootDir}

	now := time.Now().UTC()
	lastActivatedAt := now.Add(-2 * time.Minute).Format(time.RFC3339)
	writeGatewayErrLog(t, rootDir, []string{
		runtimeLogLine(now.Add(-3*time.Minute), "⚠️ API rate limit reached. Please try again later."),
	})

	issue := app.readRecentRuntimeFailureSignal(&lastActivatedAt)
	if issue != nil {
		t.Fatalf("expected issue before activation to be ignored, got %+v", *issue)
	}
}

func TestApplyRecentRuntimeIssueMarksActiveAccountAndMirrorCooldown(t *testing.T) {
	rootDir := t.TempDir()
	app := &App{openclawHomeDir: rootDir}

	now := time.Now().UTC()
	activeProfile := "acct-g"
	lastActivatedAt := now.Add(-5 * time.Minute).Format(time.RFC3339)
	writeGatewayErrLog(t, rootDir, []string{
		runtimeLogLine(now.Add(-90*time.Second), "⚠️ API rate limit reached. Please try again later."),
	})

	state := NormalizedManagerState{
		ActiveProfileName: ptr(activeProfile),
		LastActivatedAt:   ptr(lastActivatedAt),
	}
	snapshots := []ManagedProfileSnapshot{
		{
			Name:         defaultProfileName,
			IsDefault:    true,
			AccountID:    ptr("acct-1"),
			Status:       "healthy",
			StatusReason: "额度可用",
			Quota:        usageSnapshotForTest(84, 95),
		},
		{
			Name:         "acct-f",
			AccountID:    ptr("acct-2"),
			Status:       "healthy",
			StatusReason: "额度可用",
			Quota:        usageSnapshotForTest(80, 88),
		},
		{
			Name:         activeProfile,
			AccountID:    ptr("acct-1"),
			Status:       "healthy",
			StatusReason: "额度可用",
			Quota:        usageSnapshotForTest(91, 93),
		},
	}

	updated := app.applyRecentRuntimeIssue(state, snapshots)
	if updated[0].Status != "cooldown" {
		t.Fatalf("expected default mirror cooldown, got %s", updated[0].Status)
	}
	if updated[2].Status != "cooldown" {
		t.Fatalf("expected active profile cooldown, got %s", updated[2].Status)
	}
	if updated[1].Status != "healthy" {
		t.Fatalf("expected unrelated profile to stay healthy, got %s", updated[1].Status)
	}
	if updated[0].LastError == nil || updated[2].LastError == nil {
		t.Fatalf("expected runtime error copied onto active account snapshots")
	}

	recommended := pickRecommendedProfile(updated)
	if recommended == nil || *recommended != "acct-f" {
		t.Fatalf("expected acct-f to become recommendation, got %v", recommended)
	}
}

func TestApplyPersistedRuntimeCooldownKeepsRateLimitedAccountOffRecommendation(t *testing.T) {
	expiresAt := time.Now().UTC().Add(5 * time.Minute).Format(time.RFC3339)
	snapshots := []ManagedProfileSnapshot{
		{
			Name:         defaultProfileName,
			IsDefault:    true,
			AccountID:    ptr("acct-1"),
			Status:       "healthy",
			StatusReason: "额度可用",
			Quota:        usageSnapshotForTest(88, 92),
		},
		{
			Name:         "acct-f",
			AccountID:    ptr("acct-2"),
			Status:       "draining",
			StatusReason: "额度偏低，建议切换",
			Quota:        usageSnapshotForTest(22, 86),
		},
		{
			Name:         "acct-g",
			AccountID:    ptr("acct-1"),
			Status:       "healthy",
			StatusReason: "额度可用",
			Quota:        usageSnapshotForTest(91, 95),
		},
	}

	updated := applyPersistedRuntimeCooldowns([]runtimeCooldownEntry{
		{
			Kind:        "rate_limit",
			ProfileName: "acct-g",
			AccountID:   "acct-1",
			Message:     "⚠️ API rate limit reached. Please try again later.",
			OccurredAt:  time.Now().UTC().Add(-1 * time.Minute).Format(time.RFC3339),
			ExpiresAt:   expiresAt,
		},
	}, snapshots)

	if updated[0].Status != "cooldown" || updated[2].Status != "cooldown" {
		t.Fatalf("expected same-account snapshots to stay in cooldown, got default=%s acct-g=%s", updated[0].Status, updated[2].Status)
	}

	recommended := pickRecommendedProfile(updated)
	if recommended == nil || *recommended != "acct-f" {
		t.Fatalf("expected acct-f to remain recommendation during cooldown, got %v", recommended)
	}
}

func TestPersistRecentRuntimeCooldownStoresActiveAccount(t *testing.T) {
	rootDir := t.TempDir()
	app := &App{openclawHomeDir: rootDir}

	now := time.Now().UTC()
	lastActivatedAt := now.Add(-5 * time.Minute).Format(time.RFC3339)
	writeGatewayErrLog(t, rootDir, []string{
		runtimeLogLine(now.Add(-90*time.Second), "⚠️ API rate limit reached. Please try again later."),
	})

	state := NormalizedManagerState{
		ActiveProfileName: ptr("acct-g"),
		LastActivatedAt:   ptr(lastActivatedAt),
		Runtime:           defaultRuntimeTelemetryState(),
	}
	summary := ManagerSummary{
		ActiveProfileName: ptr("acct-g"),
		Profiles: []ManagedProfileSnapshot{
			{
				Name:      "acct-g",
				AccountID: ptr("acct-1"),
			},
		},
	}

	changed := app.persistRecentRuntimeCooldown(&state, summary)
	if !changed {
		t.Fatalf("expected runtime cooldown to be stored")
	}
	if len(state.Runtime.RuntimeCooldowns) != 1 {
		t.Fatalf("expected one cooldown entry, got %d", len(state.Runtime.RuntimeCooldowns))
	}
	entry := state.Runtime.RuntimeCooldowns[0]
	if entry.Kind != "rate_limit" || entry.AccountID != "acct-1" || entry.ProfileName != "acct-g" {
		t.Fatalf("unexpected cooldown entry: %+v", entry)
	}
	if _, ok := parseRFC3339Time(entry.ExpiresAt); !ok {
		t.Fatalf("expected valid expiry timestamp, got %q", entry.ExpiresAt)
	}
}

func writeGatewayErrLog(t *testing.T, rootDir string, lines []string) {
	t.Helper()
	logDir := filepath.Join(rootDir, ".openclaw", "logs")
	if err := os.MkdirAll(logDir, 0o755); err != nil {
		t.Fatalf("mkdir log dir: %v", err)
	}
	content := strings.Join(lines, "\n") + "\n"
	if err := os.WriteFile(filepath.Join(logDir, "gateway.err.log"), []byte(content), 0o600); err != nil {
		t.Fatalf("write gateway.err.log: %v", err)
	}
}

func runtimeLogLine(ts time.Time, message string) string {
	return ts.UTC().Format(time.RFC3339) + " [agent/embedded] embedded run agent end: runId=test-run isError=true error=" + message
}

func usageSnapshotForTest(fiveHourLeft int, weekLeft int) UsageSnapshot {
	return UsageSnapshot{
		FiveHour: &UsageWindow{
			Label:       "5h",
			UsedPercent: 100 - fiveHourLeft,
			LeftPercent: fiveHourLeft,
		},
		Week: &UsageWindow{
			Label:       "week",
			UsedPercent: 100 - weekLeft,
			LeftPercent: weekLeft,
		},
	}
}
