package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var (
	fatalPatterns = []patternRule{
		{Regex: regexp.MustCompile(`embedded run timeout`), Code: "embedded-run-timeout"},
		{Regex: regexp.MustCompile(`Profile .* timed out`), Code: "profile-timed-out"},
		{Regex: regexp.MustCompile(`lane wait exceeded`), Code: "lane-wait-exceeded"},
		{Regex: regexp.MustCompile(`Slow listener detected`), Code: "slow-listener-detected"},
		{Regex: regexp.MustCompile(`Unhandled promise rejection`), Code: "unhandled-promise-rejection"},
	}
	softPatterns = []patternRule{
		{Regex: regexp.MustCompile(`health-monitor: restarting \(reason: stuck\)`), Code: "health-monitor-stuck"},
		{Regex: regexp.MustCompile(`health-monitor: restarting \(reason: stale-socket\)`), Code: "health-monitor-stale-socket"},
		{Regex: regexp.MustCompile(`health-monitor: restarting \(reason: disconnected\)`), Code: "health-monitor-disconnected"},
		{Regex: regexp.MustCompile(`health-monitor: restarting \(reason: stopped\)`), Code: "health-monitor-stopped"},
		{Regex: regexp.MustCompile(`WebSocket connection closed with code 1006`), Code: "discord-websocket-1006"},
	}
	severeSoftCodes = map[string]struct{}{
		"health-monitor-disconnected": {},
		"health-monitor-stopped":      {},
		"discord-websocket-1006":      {},
	}
	logLinePattern = regexp.MustCompile(`^(\d{4}-\d{2}-\d{2}T\S+)\s+(.*)$`)
)

type patternRule struct {
	Regex *regexp.Regexp
	Code  string
}

type config struct {
	checkOnly            bool
	runOnce              bool
	homeDir              string
	openclawRoot         string
	openclawStateDir     string
	sessionDir           string
	sessionStorePath     string
	gatewayLogPath       string
	watchdogStateDir     string
	watchdogStatePath    string
	gatewayLabel         string
	gatewayPlistPath     string
	loopMs               int
	detectionWindowMs    int
	lockStallMs          int
	restartCooldownMs    int
	commandTimeoutMs     int
	logTailBytes         int64
	softRestartThreshold int
}

type watchdogState struct {
	CreatedAt         string  `json:"createdAt"`
	RestartCount      int     `json:"restartCount"`
	LastRestartAtMs   *int64  `json:"lastRestartAtMs,omitempty"`
	LastRestartReason *string `json:"lastRestartReason,omitempty"`
	LastRestartPid    *int    `json:"lastRestartPid,omitempty"`
	LastHealthyAt     *string `json:"lastHealthyAt,omitempty"`
	LastIssueAt       *string `json:"lastIssueAt,omitempty"`
	LastIssueReason   *string `json:"lastIssueReason,omitempty"`
	LastLoopAt        *string `json:"lastLoopAt,omitempty"`
	LastLoopResult    *string `json:"lastLoopResult,omitempty"`
	MonitoredStateDir string  `json:"monitoredStateDir"`
}

type commandResult struct {
	OK       bool
	Code     *int
	Stdout   string
	Stderr   string
	TimedOut bool
}

type gatewayJob struct {
	Running        bool
	PID            *int    `json:"pid,omitempty"`
	LastExitStatus *int    `json:"lastExitStatus,omitempty"`
	Error          *string `json:"error,omitempty"`
}

type sessionEntry struct {
	Key       string
	ChatType  *string
	UpdatedAt int64
}

type stalledLock struct {
	SessionID   string  `json:"sessionId"`
	Key         *string `json:"key,omitempty"`
	ChatType    *string `json:"chatType,omitempty"`
	UpdatedAtMs *int64  `json:"updatedAtMs,omitempty"`
	LockMtimeMs int64   `json:"lockMtimeMs"`
	AgeMs       int64   `json:"ageMs"`
	LockPath    string  `json:"lockPath"`
}

type gatewayEvent struct {
	Level       string
	Code        string
	TimestampMs int64
	Line        string
}

type inspection struct {
	NowMs   int64          `json:"nowMs"`
	Healthy bool           `json:"healthy"`
	Action  string         `json:"action"`
	Reason  string         `json:"reason"`
	Details map[string]any `json:"details"`
}

type runCycleOutput struct {
	OK         bool          `json:"ok"`
	Inspection inspection    `json:"inspection"`
	State      watchdogState `json:"state"`
}

func main() {
	cfg, err := loadConfig()
	if err != nil {
		fatalf("load watchdog config failed: %v", err)
	}
	if err := ensureDir(cfg.watchdogStateDir); err != nil {
		fatalf("prepare watchdog state dir failed: %v", err)
	}

	if cfg.runOnce {
		if err := runCycle(cfg); err != nil {
			fatalf("watchdog cycle failed: %v", err)
		}
		return
	}

	logLine("info", "watchdog started", map[string]any{
		"gatewayLabel":      cfg.gatewayLabel,
		"loopMs":            cfg.loopMs,
		"detectionWindowMs": cfg.detectionWindowMs,
		"lockStallMs":       cfg.lockStallMs,
		"restartCooldownMs": cfg.restartCooldownMs,
		"monitoredStateDir": cfg.openclawStateDir,
		"watchdogStatePath": cfg.watchdogStatePath,
	})

	ticker := time.NewTicker(time.Duration(cfg.loopMs) * time.Millisecond)
	defer ticker.Stop()

	for {
		if err := runCycle(cfg); err != nil {
			logLine("error", "watchdog cycle failed", map[string]any{
				"error": err.Error(),
			})
		}
		<-ticker.C
	}
}

func loadConfig() (config, error) {
	args := os.Args[1:]
	checkOnly := false
	runOnce := false
	for _, arg := range args {
		if arg == "--check-only" {
			checkOnly = true
		}
		if arg == "--once" || arg == "--check-only" {
			runOnce = true
		}
	}

	homeDir, err := os.UserHomeDir()
	if err != nil {
		return config{}, err
	}

	openclawRoot := strings.TrimSpace(os.Getenv("OPENCLAW_WATCHDOG_OPENCLAW_ROOT"))
	if openclawRoot == "" {
		openclawRoot = homeDir
	}
	openclawStateDir := strings.TrimSpace(os.Getenv("OPENCLAW_STATE_DIR"))
	if openclawStateDir == "" {
		openclawStateDir = filepath.Join(openclawRoot, ".openclaw")
	}

	watchdogStateDir := strings.TrimSpace(os.Getenv("OPENCLAW_WATCHDOG_STATE_DIR"))
	if watchdogStateDir == "" {
		watchdogStateDir = filepath.Join(homeDir, "Library", "Application Support", "OpenClaw Manager Native", "watchdog")
	}

	gatewayLabel := strings.TrimSpace(os.Getenv("OPENCLAW_WATCHDOG_TARGET_LABEL"))
	if gatewayLabel == "" {
		gatewayLabel = "ai.openclaw.gateway"
	}

	gatewayPlistPath := strings.TrimSpace(os.Getenv("OPENCLAW_WATCHDOG_GATEWAY_PLIST"))
	if gatewayPlistPath == "" {
		gatewayPlistPath = filepath.Join(homeDir, "Library", "LaunchAgents", gatewayLabel+".plist")
	}

	return config{
		checkOnly:            checkOnly,
		runOnce:              runOnce,
		homeDir:              homeDir,
		openclawRoot:         openclawRoot,
		openclawStateDir:     openclawStateDir,
		sessionDir:           filepath.Join(openclawStateDir, "agents", "main", "sessions"),
		sessionStorePath:     filepath.Join(openclawStateDir, "agents", "main", "sessions", "sessions.json"),
		gatewayLogPath:       filepath.Join(openclawStateDir, "logs", "gateway.log"),
		watchdogStateDir:     watchdogStateDir,
		watchdogStatePath:    filepath.Join(watchdogStateDir, "state.json"),
		gatewayLabel:         gatewayLabel,
		gatewayPlistPath:     gatewayPlistPath,
		loopMs:               clampEnvInt("OPENCLAW_WATCHDOG_LOOP_MS", 30_000, 10_000, 10*60_000),
		detectionWindowMs:    clampEnvInt("OPENCLAW_WATCHDOG_DETECTION_WINDOW_MS", 15*60_000, 60_000, 60*60_000),
		lockStallMs:          clampEnvInt("OPENCLAW_WATCHDOG_LOCK_STALL_MS", 6*60_000, 60_000, 60*60_000),
		restartCooldownMs:    clampEnvInt("OPENCLAW_WATCHDOG_RESTART_COOLDOWN_MS", 5*60_000, 30_000, 60*60_000),
		commandTimeoutMs:     clampEnvInt("OPENCLAW_WATCHDOG_COMMAND_TIMEOUT_MS", 15_000, 1_000, 60_000),
		logTailBytes:         int64(clampEnvInt("OPENCLAW_WATCHDOG_LOG_TAIL_BYTES", 512*1024, 16*1024, 4*1024*1024)),
		softRestartThreshold: clampEnvInt("OPENCLAW_WATCHDOG_SOFT_RESTART_THRESHOLD", 3, 1, 20),
	}, nil
}

func runCycle(cfg config) error {
	state := readJSONFile(cfg.watchdogStatePath, watchdogState{
		CreatedAt:         isoNow(),
		RestartCount:      0,
		MonitoredStateDir: cfg.openclawStateDir,
	})
	if strings.TrimSpace(state.CreatedAt) == "" {
		state.CreatedAt = isoNow()
	}
	state.MonitoredStateDir = cfg.openclawStateDir

	inspection, err := inspect(cfg, state)
	if err != nil {
		return err
	}

	loopAt := isoNow()
	state.LastLoopAt = &loopAt
	state.LastLoopResult = &inspection.Reason

	if inspection.Healthy {
		state.LastHealthyAt = &loopAt
		if err := writeJSONFile(cfg.watchdogStatePath, state); err != nil {
			return err
		}
		if cfg.runOnce {
			printRunOnce(runCycleOutput{OK: true, Inspection: inspection, State: state})
		}
		return nil
	}

	state.LastIssueAt = &loopAt
	state.LastIssueReason = &inspection.Reason

	if inspection.Action == "restart" && !cfg.checkOnly {
		restartedPID, err := restartGateway(cfg, inspection.Reason, inspection.Details)
		if err != nil {
			return err
		}
		state.RestartCount++
		nowMs := time.Now().UnixMilli()
		state.LastRestartAtMs = &nowMs
		state.LastRestartReason = &inspection.Reason
		state.LastRestartPid = restartedPID
	} else if inspection.Action == "cooldown" {
		logLine("warn", "detected issue but restart is cooling down", map[string]any{
			"reason":          inspection.Reason,
			"details":         inspection.Details,
			"lastRestartAtMs": state.LastRestartAtMs,
		})
	} else if cfg.checkOnly {
		logLine("info", "check-only detected issue", map[string]any{
			"reason":  inspection.Reason,
			"details": inspection.Details,
		})
	}

	if err := writeJSONFile(cfg.watchdogStatePath, state); err != nil {
		return err
	}

	if cfg.runOnce {
		ok := inspection.Action != "restart" || !cfg.checkOnly
		printRunOnce(runCycleOutput{OK: ok, Inspection: inspection, State: state})
	}
	return nil
}

func inspect(cfg config, state watchdogState) (inspection, error) {
	nowMs := time.Now().UnixMilli()
	minTimestampMs := nowMs - int64(cfg.detectionWindowMs)
	if state.LastRestartAtMs != nil && *state.LastRestartAtMs > minTimestampMs {
		minTimestampMs = *state.LastRestartAtMs
	}

	job := getGatewayJob(cfg)
	if !job.Running {
		action := "cooldown"
		if restartAllowed(cfg, state, nowMs, "gateway-not-running") {
			action = "restart"
		}
		return inspection{
			NowMs:   nowMs,
			Healthy: false,
			Action:  action,
			Reason:  "gateway-not-running",
			Details: map[string]any{"job": job},
		}, nil
	}

	sessionsByID := loadSessionsByID(cfg)
	stalls := findStalledLocks(cfg, nowMs, sessionsByID)
	if len(stalls) > 0 {
		action := "cooldown"
		if restartAllowed(cfg, state, nowMs, "stalled-session-lock") {
			action = "restart"
		}
		return inspection{
			NowMs:   nowMs,
			Healthy: false,
			Action:  action,
			Reason:  "stalled-session-lock",
			Details: map[string]any{"stalledLocks": stalls},
		}, nil
	}

	logText, _ := readTail(cfg.gatewayLogPath, cfg.logTailBytes)
	events := extractRecentGatewayEvents(logText, minTimestampMs)
	fatalEvents := filterEventsByLevel(events, "fatal")
	if len(fatalEvents) > 0 {
		action := "cooldown"
		if restartAllowed(cfg, state, nowMs, fatalEvents[0].Code) {
			action = "restart"
		}
		return inspection{
			NowMs:   nowMs,
			Healthy: false,
			Action:  action,
			Reason:  fatalEvents[0].Code,
			Details: map[string]any{
				"events": summarizeEvents(events),
				"sample": sampleEventLines(fatalEvents, 3),
			},
		}, nil
	}

	softEvents := filterEventsByLevel(events, "soft")
	severeSoftEvents := make([]gatewayEvent, 0)
	for _, event := range softEvents {
		if _, ok := severeSoftCodes[event.Code]; ok {
			severeSoftEvents = append(severeSoftEvents, event)
		}
	}
	if len(severeSoftEvents) >= 2 {
		action := "cooldown"
		if restartAllowed(cfg, state, nowMs, "discord-link-unstable") {
			action = "restart"
		}
		return inspection{
			NowMs:   nowMs,
			Healthy: false,
			Action:  action,
			Reason:  "discord-link-unstable",
			Details: map[string]any{
				"events": summarizeEvents(events),
				"sample": sampleEventLines(severeSoftEvents, 3),
			},
		}, nil
	}
	if len(softEvents) >= cfg.softRestartThreshold {
		action := "cooldown"
		if restartAllowed(cfg, state, nowMs, "repeated-health-monitor-restarts") {
			action = "restart"
		}
		return inspection{
			NowMs:   nowMs,
			Healthy: false,
			Action:  action,
			Reason:  "repeated-health-monitor-restarts",
			Details: map[string]any{
				"events": summarizeEvents(events),
				"sample": sampleEventLines(softEvents, 3),
			},
		}, nil
	}

	return inspection{
		NowMs:   nowMs,
		Healthy: true,
		Action:  "none",
		Reason:  "healthy",
		Details: map[string]any{
			"pid":            job.PID,
			"lastExitStatus": job.LastExitStatus,
			"recentEvents":   summarizeEvents(events),
		},
	}, nil
}

func getGatewayJob(cfg config) gatewayJob {
	result := runCommand("launchctl", []string{"list"}, cfg.commandTimeoutMs)
	if !result.OK {
		return gatewayJob{
			Running: false,
			Error:   cleanOutput(result.Stdout, result.Stderr),
		}
	}

	var matched string
	for _, line := range strings.Split(result.Stdout, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasSuffix(line, "\t"+cfg.gatewayLabel) || strings.HasSuffix(line, " "+cfg.gatewayLabel) {
			matched = line
			break
		}
	}
	if matched == "" {
		return gatewayJob{
			Running: false,
			Error:   stringPtr("gateway_label_missing"),
		}
	}

	parts := strings.Fields(matched)
	pidToken := "-"
	exitToken := "-"
	if len(parts) >= 1 {
		pidToken = parts[0]
	}
	if len(parts) >= 2 {
		exitToken = parts[1]
	}

	var pid *int
	if pidToken != "-" {
		if parsed, err := strconvAtoi(pidToken); err == nil {
			pid = &parsed
		}
	}
	var exitStatus *int
	if exitToken != "-" {
		if parsed, err := strconvAtoi(exitToken); err == nil {
			exitStatus = &parsed
		}
	}
	return gatewayJob{
		Running:        pid != nil && *pid > 0,
		PID:            pid,
		LastExitStatus: exitStatus,
	}
}

func loadSessionsByID(cfg config) map[string]sessionEntry {
	raw := readJSONFile(cfg.sessionStorePath, map[string]map[string]any{})
	out := make(map[string]sessionEntry)
	for key, value := range raw {
		sessionID := strings.TrimSpace(anyString(value["sessionId"]))
		if sessionID == "" {
			continue
		}
		entry := sessionEntry{Key: key}
		if chatType := strings.TrimSpace(anyString(value["chatType"])); chatType != "" {
			entry.ChatType = &chatType
		}
		if updatedAt, ok := anyInt64(value["updatedAt"]); ok {
			entry.UpdatedAt = updatedAt
		}
		out[sessionID] = entry
	}
	return out
}

func findStalledLocks(cfg config, nowMs int64, sessionsByID map[string]sessionEntry) []stalledLock {
	names, err := os.ReadDir(cfg.sessionDir)
	if err != nil {
		return nil
	}
	out := make([]stalledLock, 0)
	for _, entry := range names {
		name := entry.Name()
		if !strings.HasSuffix(name, ".jsonl.lock") {
			continue
		}
		lockPath := filepath.Join(cfg.sessionDir, name)
		stat, err := os.Stat(lockPath)
		if err != nil {
			continue
		}
		sessionID := strings.TrimSuffix(name, ".jsonl.lock")
		session := sessionsByID[sessionID]
		updatedAtMs := session.UpdatedAt
		lastTouchMs := stat.ModTime().UnixMilli()
		if updatedAtMs > lastTouchMs {
			lastTouchMs = updatedAtMs
		}
		ageMs := nowMs - lastTouchMs
		if ageMs < int64(cfg.lockStallMs) {
			continue
		}

		var updatedAtPtr *int64
		if updatedAtMs > 0 {
			updatedAtPtr = &updatedAtMs
		}
		var keyPtr *string
		if strings.TrimSpace(session.Key) != "" {
			keyPtr = &session.Key
		}
		out = append(out, stalledLock{
			SessionID:   sessionID,
			Key:         keyPtr,
			ChatType:    session.ChatType,
			UpdatedAtMs: updatedAtPtr,
			LockMtimeMs: stat.ModTime().UnixMilli(),
			AgeMs:       ageMs,
			LockPath:    lockPath,
		})
	}
	return out
}

func extractRecentGatewayEvents(logText string, minTimestampMs int64) []gatewayEvent {
	events := make([]gatewayEvent, 0)
	for _, line := range strings.Split(logText, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		match := logLinePattern.FindStringSubmatch(line)
		if len(match) != 3 {
			continue
		}
		timestampMs, err := parseLogTime(match[1])
		if err != nil || timestampMs < minTimestampMs {
			continue
		}
		body := match[2]
		for _, rule := range fatalPatterns {
			if rule.Regex.MatchString(body) {
				events = append(events, gatewayEvent{Level: "fatal", Code: rule.Code, TimestampMs: timestampMs, Line: line})
				goto nextLine
			}
		}
		for _, rule := range softPatterns {
			if rule.Regex.MatchString(body) {
				events = append(events, gatewayEvent{Level: "soft", Code: rule.Code, TimestampMs: timestampMs, Line: line})
				goto nextLine
			}
		}
	nextLine:
	}
	return events
}

func summarizeEvents(events []gatewayEvent) map[string]int {
	summary := make(map[string]int)
	for _, event := range events {
		summary[event.Code]++
	}
	return summary
}

func restartAllowed(cfg config, state watchdogState, nowMs int64, reason string) bool {
	cooldownMs := restartCooldownMsForReason(cfg, reason)
	return state.LastRestartAtMs == nil || nowMs-*state.LastRestartAtMs >= int64(cooldownMs)
}

func restartCooldownMsForReason(cfg config, reason string) int {
	switch reason {
	case "gateway-not-running":
		return 30_000
	case "stalled-session-lock", "discord-link-unstable":
		return 90_000
	default:
		return cfg.restartCooldownMs
	}
}

func restartGateway(cfg config, reason string, details map[string]any) (*int, error) {
	uid := os.Getuid()
	target := cfg.gatewayLabel
	if uid > 0 {
		target = fmt.Sprintf("gui/%d/%s", uid, cfg.gatewayLabel)
	}

	result := runCommand("launchctl", []string{"kickstart", "-k", target}, cfg.commandTimeoutMs)
	if !result.OK && pathExists(cfg.gatewayPlistPath) && uid > 0 {
		_ = runCommand("launchctl", []string{"bootout", fmt.Sprintf("gui/%d", uid), cfg.gatewayPlistPath}, cfg.commandTimeoutMs)
		time.Sleep(time.Second)
		result = runCommand("launchctl", []string{"bootstrap", fmt.Sprintf("gui/%d", uid), cfg.gatewayPlistPath}, cfg.commandTimeoutMs)
		if result.OK {
			result = runCommand("launchctl", []string{"kickstart", "-k", target}, cfg.commandTimeoutMs)
		}
	}
	if !result.OK {
		return nil, fmt.Errorf("restart_failed %s", strings.TrimSpace(firstNonEmpty(result.Stderr, result.Stdout, "unknown")))
	}

	logLine("warn", "restarted "+cfg.gatewayLabel, map[string]any{
		"reason":  reason,
		"details": details,
	})
	time.Sleep(3 * time.Second)
	job := getGatewayJob(cfg)
	return job.PID, nil
}

func runCommand(command string, args []string, timeoutMs int) commandResult {
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeoutMs)*time.Millisecond)
	defer cancel()

	cmd := exec.CommandContext(ctx, command, args...)
	cmd.Env = os.Environ()
	if !envHasPath(cmd.Env) {
		cmd.Env = append(cmd.Env, "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
	}

	stdout, _ := cmd.StdoutPipe()
	stderr, _ := cmd.StderrPipe()
	if err := cmd.Start(); err != nil {
		return commandResult{Stderr: err.Error()}
	}

	stdoutBytes, _ := io.ReadAll(stdout)
	stderrBytes, _ := io.ReadAll(stderr)
	err := cmd.Wait()

	result := commandResult{
		Stdout: string(stdoutBytes),
		Stderr: string(stderrBytes),
	}
	if ctx.Err() == context.DeadlineExceeded {
		result.TimedOut = true
		return result
	}
	if err == nil {
		result.OK = true
		code := 0
		result.Code = &code
		return result
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		code := exitErr.ExitCode()
		result.Code = &code
	}
	return result
}

func envHasPath(env []string) bool {
	for _, item := range env {
		if strings.HasPrefix(item, "PATH=") {
			return true
		}
	}
	return false
}

func readTail(targetPath string, maxBytes int64) (string, error) {
	file, err := os.Open(targetPath)
	if err != nil {
		return "", err
	}
	defer file.Close()

	stat, err := file.Stat()
	if err != nil {
		return "", err
	}
	length := stat.Size()
	if length <= 0 {
		return "", nil
	}
	if length > maxBytes {
		length = maxBytes
	}
	if _, err := file.Seek(-length, io.SeekEnd); err != nil {
		if _, err := file.Seek(0, io.SeekStart); err != nil {
			return "", err
		}
	}
	data, err := io.ReadAll(file)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

func ensureDir(targetPath string) error {
	return os.MkdirAll(targetPath, 0o755)
}

func writeJSONFile(targetPath string, value any) error {
	if err := ensureDir(filepath.Dir(targetPath)); err != nil {
		return err
	}
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return os.WriteFile(targetPath, data, 0o600)
}

func readJSONFile[T any](targetPath string, fallback T) T {
	data, err := os.ReadFile(targetPath)
	if err != nil {
		return fallback
	}
	var decoded T
	if err := json.Unmarshal(data, &decoded); err != nil {
		return fallback
	}
	return decoded
}

func pathExists(targetPath string) bool {
	_, err := os.Stat(targetPath)
	return err == nil
}

func printRunOnce(payload runCycleOutput) {
	data, _ := json.MarshalIndent(payload, "", "  ")
	fmt.Println(string(data))
}

func logLine(level, message string, details map[string]any) {
	suffix := ""
	if len(details) > 0 {
		data, _ := json.Marshal(details)
		suffix = " " + string(data)
	}
	fmt.Printf("%s [watchdog:%s] %s%s\n", isoNow(), level, message, suffix)
}

func isoNow() string {
	return time.Now().UTC().Format(time.RFC3339)
}

func clampEnvInt(key string, fallback, minValue, maxValue int) int {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback
	}
	value, err := strconvAtoi(raw)
	if err != nil {
		return fallback
	}
	value = int(math.Round(float64(value)))
	if value < minValue {
		return minValue
	}
	if value > maxValue {
		return maxValue
	}
	return value
}

func strconvAtoi(value string) (int, error) {
	return strconv.Atoi(strings.TrimSpace(value))
}

func parseLogTime(value string) (int64, error) {
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		parsed, err = time.Parse(time.RFC3339Nano, value)
		if err != nil {
			return 0, err
		}
	}
	return parsed.UnixMilli(), nil
}

func filterEventsByLevel(events []gatewayEvent, level string) []gatewayEvent {
	out := make([]gatewayEvent, 0)
	for _, event := range events {
		if event.Level == level {
			out = append(out, event)
		}
	}
	return out
}

func sampleEventLines(events []gatewayEvent, limit int) []string {
	out := make([]string, 0, limit)
	for idx, event := range events {
		if idx >= limit {
			break
		}
		out = append(out, event.Line)
	}
	return out
}

func cleanOutput(stdout, stderr string) *string {
	text := strings.TrimSpace(strings.Join(nonEmptyStrings(stdout, stderr), "\n"))
	if text == "" {
		return nil
	}
	if len(text) > 4000 {
		text = text[:4000] + "\n..."
	}
	return &text
}

func nonEmptyStrings(values ...string) []string {
	out := make([]string, 0, len(values))
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			out = append(out, strings.TrimSpace(value))
		}
	}
	return out
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func anyString(value any) string {
	switch typed := value.(type) {
	case string:
		return typed
	default:
		return ""
	}
}

func anyInt64(value any) (int64, bool) {
	switch typed := value.(type) {
	case int64:
		return typed, true
	case int:
		return int64(typed), true
	case float64:
		return int64(typed), true
	case json.Number:
		parsed, err := typed.Int64()
		return parsed, err == nil
	default:
		return 0, false
	}
}

func stringPtr(value string) *string {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	return &value
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
