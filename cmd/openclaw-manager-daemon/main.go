package main

import (
	"bytes"
	"context"
	crand "crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"math/big"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

const (
	defaultProfileName          = "default"
	openAIClientID              = "app_EMoamEEZ73f0CkXaXp7hrann"
	openAIAuthorizeURL          = "https://auth.openai.com/oauth/authorize"
	openAITokenURL              = "https://auth.openai.com/oauth/token"
	openAIScope                 = "openid profile email offline_access"
	openAIAuthClaim             = "https://api.openai.com/auth"
	openAIProfileClaim          = "https://api.openai.com/profile"
	usageURL                    = "https://chatgpt.com/backend-api/wham/usage"
	httpTimeout                 = 15 * time.Second
	commandTimeout              = 20 * time.Second
	logTailBytes                = 512 * 1024
	refreshSkew                 = 5 * time.Minute
	usageCacheTTL               = 45 * time.Second
	staleUsageCacheTTL          = 10 * time.Minute
	stateDirCacheTTL            = 45 * time.Second
	supportSummaryCacheTTL      = 10 * time.Second
	supportGatewayCacheTTL      = 45 * time.Second
	supportEventsCacheTTL       = 45 * time.Second
	supportEnvironmentCacheTTL  = 2 * time.Minute
	supportMaintenanceCacheTTL  = 2 * time.Minute
	machineSummaryCacheTTL      = 3 * time.Second
	oauthTimeout                = 10 * time.Minute
	legacyDefaultPollIntervalMs = 60_000
	minProbeIntervalMs          = 30_000
	maxProbeIntervalMs          = 60 * 60_000
	defaultProbeIntervalMinMs   = 90_000
	defaultProbeIntervalMaxMs   = 3 * 60_000
	defaultFiveHourDrainPercent = 20
	defaultWeekDrainPercent     = 10
	managerSettingsVersion      = 3
	openclawDiscoveryMaxDepth   = 3
	gatewayLabel                = "ai.openclaw.gateway"
	runtimeModeNative           = "native"
)

var (
	defaultDevWebOrigins = []string{"http://localhost:5173", "http://127.0.0.1:5173"}
	defaultAutoStatuses  = []string{"draining", "cooldown", "exhausted", "reauth_required", "unknown"}
	validStatuses        = map[string]struct{}{
		"healthy": {}, "draining": {}, "cooldown": {}, "exhausted": {}, "reauth_required": {}, "unknown": {},
	}
	profileNamePattern = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]{0,31}$`)
	timestampPattern   = regexp.MustCompile(`^(\d{4}-\d{2}-\d{2}T\S+)`)
	pmsetPattern       = regexp.MustCompile(`^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4})\s+(Sleep|Wake|DarkWake)`)
	psProcessPattern   = regexp.MustCompile(`^\s*(\d+)\s+([0-9.]+)\s+(\d+)\s+(\S+)\s+(.*)$`)
	vmStatLinePattern  = regexp.MustCompile(`^([^:]+):\s+([0-9]+)\.`)
	swapUsagePattern   = regexp.MustCompile(`(?i)(total|used|free)\s*=\s*([0-9.]+)([KMGT])`)
	topCPUPattern      = regexp.MustCompile(`CPU usage:\s+([0-9.]+)% user,\s+([0-9.]+)% sys,\s+([0-9.]+)% idle`)
)

type App struct {
	host                    string
	port                    int
	homeDir                 string
	openclawHomeDir         string
	codexHomeDir            string
	managerDir              string
	managerStatePath        string
	backupDir               string
	defaultOpenClawState    string
	defaultCodexHome        string
	oauthCallbackPort       int
	oauthCallbackBindHost   string
	oauthCallbackPublicHost string
	oauthRedirectURL        string
	authOpenMode            string
	startedAt               time.Time
	executablePath          string
	server                  *http.Server

	opMu sync.Mutex
	mu   sync.Mutex

	loginFlows               map[string]*PendingLoginFlow
	loginFlowIDsByState      map[string]string
	callbackServer           *http.Server
	automationTimer          *time.Timer
	automationRunning        bool
	usageCache               map[string]cachedUsageSnapshot
	stateDirCache            map[string]string
	stateDirCacheAt          time.Time
	supportSummaryCache      *cachedSupportSummary
	supportGatewayCache      *cachedSupportGateway
	supportEventsCache       *cachedSupportEvents
	supportEnvironmentCache  *cachedSupportEnvironment
	supportMaintenanceCache  *cachedSupportMaintenance
	machineSummaryCache      *cachedMachineSummary
	supportSummaryRefreshing bool
	machineSummaryRefreshing bool
	lastNetworkSample        *machineNetworkCounters
}

type cachedUsageSnapshot struct {
	Quota     UsageSnapshot
	FetchedAt time.Time
}

type cachedSupportSummary struct {
	Summary   SupportSummary
	FetchedAt time.Time
}

type cachedSupportGateway struct {
	Gateway   SupportGateway
	FetchedAt time.Time
}

type cachedSupportEvents struct {
	Events    []SupportLogEvent
	FetchedAt time.Time
}

type cachedSupportEnvironment struct {
	Environment SupportEnvironment
	FetchedAt   time.Time
}

type cachedSupportMaintenance struct {
	Maintenance SupportMaintenance
	FetchedAt   time.Time
}

type cachedMachineSummary struct {
	Summary   MachineSummary
	FetchedAt time.Time
}

type machineNetworkCounters struct {
	Interface   string
	Received    uint64
	Sent        uint64
	CollectedAt time.Time
}

type machineInterfaceCounters struct {
	Received uint64
	Sent     uint64
}

type ManagerStateFile struct {
	ActiveProfileName *string                   `json:"activeProfileName,omitempty"`
	LastActivatedAt   *string                   `json:"lastActivatedAt,omitempty"`
	SettingsVersion   *int                      `json:"settingsVersion,omitempty"`
	Settings          *PersistedManagerSettings `json:"settings,omitempty"`
	Automation        *AutomationRuntimeState   `json:"automation,omitempty"`
	Runtime           *RuntimeTelemetryState    `json:"runtime,omitempty"`
}

type PersistedManagerSettings struct {
	AutoActivateEnabled  *bool    `json:"autoActivateEnabled,omitempty"`
	PollIntervalMs       *int     `json:"pollIntervalMs,omitempty"`
	ProbeIntervalMinMs   *int     `json:"probeIntervalMinMs,omitempty"`
	ProbeIntervalMaxMs   *int     `json:"probeIntervalMaxMs,omitempty"`
	FiveHourDrainPercent *int     `json:"fiveHourDrainPercent,omitempty"`
	WeekDrainPercent     *int     `json:"weekDrainPercent,omitempty"`
	AutoSwitchStatuses   []string `json:"autoSwitchStatuses,omitempty"`
}

type AutomationRuntimeState struct {
	LastProbeAt              *string `json:"lastProbeAt,omitempty"`
	NextProbeAt              *string `json:"nextProbeAt,omitempty"`
	LastScheduledDelayMs     *int    `json:"lastScheduledDelayMs,omitempty"`
	LastAutoActivationAt     *string `json:"lastAutoActivationAt,omitempty"`
	LastAutoActivationFrom   *string `json:"lastAutoActivationFrom,omitempty"`
	LastAutoActivationTo     *string `json:"lastAutoActivationTo,omitempty"`
	LastAutoActivationReason *string `json:"lastAutoActivationReason,omitempty"`
	LastTickError            *string `json:"lastTickError,omitempty"`
}

type RuntimeTelemetryState struct {
	TotalActivations            *int    `json:"totalActivations,omitempty"`
	ManualActivations           *int    `json:"manualActivations,omitempty"`
	AutoActivations             *int    `json:"autoActivations,omitempty"`
	RecommendedActivations      *int    `json:"recommendedActivations,omitempty"`
	LastActivationAt            *string `json:"lastActivationAt,omitempty"`
	LastActivationDurationMs    *int    `json:"lastActivationDurationMs,omitempty"`
	AverageActivationDurationMs *int    `json:"averageActivationDurationMs,omitempty"`
	LastActivationTrigger       *string `json:"lastActivationTrigger,omitempty"`
	LastActivationReason        *string `json:"lastActivationReason,omitempty"`
	LastSyncedAt                *string `json:"lastSyncedAt,omitempty"`
}

type ManagerSettings struct {
	AutoActivateEnabled  bool
	ProbeIntervalMinMs   int
	ProbeIntervalMaxMs   int
	FiveHourDrainPercent int
	WeekDrainPercent     int
	AutoSwitchStatuses   []string
}

type NormalizedManagerState struct {
	ActiveProfileName *string
	LastActivatedAt   *string
	Settings          ManagerSettings
	Automation        AutomationRuntimeState
	Runtime           RuntimeTelemetryState
}

type UsageWindow struct {
	Label       string  `json:"label"`
	UsedPercent int     `json:"usedPercent"`
	LeftPercent int     `json:"leftPercent"`
	ResetAt     *string `json:"resetAt,omitempty"`
	ResetInMs   *int    `json:"resetInMs,omitempty"`
}

type UsageSnapshot struct {
	Plan     *string      `json:"plan,omitempty"`
	FiveHour *UsageWindow `json:"fiveHour,omitempty"`
	Week     *UsageWindow `json:"week,omitempty"`
}

type ManagedProfileSnapshot struct {
	Name                  string        `json:"name"`
	IsDefault             bool          `json:"isDefault"`
	IsActive              bool          `json:"isActive"`
	IsRecommended         bool          `json:"isRecommended"`
	StateDir              string        `json:"stateDir"`
	AuthStorePath         string        `json:"authStorePath"`
	HasConfig             bool          `json:"hasConfig"`
	HasAuthStore          bool          `json:"hasAuthStore"`
	AuthMode              string        `json:"authMode"`
	ProfileID             *string       `json:"profileId,omitempty"`
	AccountEmail          *string       `json:"accountEmail,omitempty"`
	AccountID             *string       `json:"accountId,omitempty"`
	PrimaryProviderID     *string       `json:"primaryProviderId,omitempty"`
	PrimaryModelID        *string       `json:"primaryModelId,omitempty"`
	ConfiguredProviderIDs []string      `json:"configuredProviderIds"`
	SupportsQuota         bool          `json:"supportsQuota"`
	SupportsLogin         bool          `json:"supportsLogin"`
	LoginKind             *string       `json:"loginKind,omitempty"`
	CompanionRuntimeKind  *string       `json:"companionRuntimeKind,omitempty"`
	CodexHome             string        `json:"codexHome"`
	CodexConfigPath       string        `json:"codexConfigPath"`
	CodexAuthPath         string        `json:"codexAuthPath"`
	HasCodexConfig        bool          `json:"hasCodexConfig"`
	HasCodexAuth          bool          `json:"hasCodexAuth"`
	CodexAuthMode         *string       `json:"codexAuthMode,omitempty"`
	CodexAccountID        *string       `json:"codexAccountId,omitempty"`
	CodexLastRefreshAt    *string       `json:"codexLastRefreshAt,omitempty"`
	TokenExpiresAt        *string       `json:"tokenExpiresAt,omitempty"`
	TokenExpiresInMs      *int          `json:"tokenExpiresInMs,omitempty"`
	Status                string        `json:"status"`
	StatusReason          string        `json:"statusReason"`
	Quota                 UsageSnapshot `json:"quota"`
	LastError             *string       `json:"lastError,omitempty"`
}

type AutomationSnapshot struct {
	Enabled                  bool     `json:"enabled"`
	ProbeIntervalMinMs       int      `json:"probeIntervalMinMs"`
	ProbeIntervalMaxMs       int      `json:"probeIntervalMaxMs"`
	PollIntervalMs           int      `json:"pollIntervalMs"`
	FiveHourDrainPercent     int      `json:"fiveHourDrainPercent"`
	WeekDrainPercent         int      `json:"weekDrainPercent"`
	AutoSwitchStatuses       []string `json:"autoSwitchStatuses"`
	LastProbeAt              *string  `json:"lastProbeAt,omitempty"`
	NextProbeAt              *string  `json:"nextProbeAt,omitempty"`
	LastScheduledDelayMs     *int     `json:"lastScheduledDelayMs,omitempty"`
	LastAutoActivationAt     *string  `json:"lastAutoActivationAt,omitempty"`
	LastAutoActivationFrom   *string  `json:"lastAutoActivationFrom,omitempty"`
	LastAutoActivationTo     *string  `json:"lastAutoActivationTo,omitempty"`
	LastAutoActivationReason *string  `json:"lastAutoActivationReason,omitempty"`
	LastTickError            *string  `json:"lastTickError,omitempty"`
	WrapperCommand           string   `json:"wrapperCommand"`
	CodexWrapperCommand      string   `json:"codexWrapperCommand"`
}

type RuntimeOverview struct {
	GeneratedAt   string               `json:"generatedAt"`
	Mode          string               `json:"mode"`
	Roots         RuntimeRoots         `json:"roots"`
	Daemon        RuntimeDaemon        `json:"daemon"`
	Switching     RuntimeSwitching     `json:"switching"`
	Compatibility RuntimeCompatibility `json:"compatibility"`
}

var errLoginNotSupported = errors.New("login not supported")

type RuntimeRoots struct {
	OpenclawHomeDir         string `json:"openclawHomeDir"`
	CodexHomeDir            string `json:"codexHomeDir"`
	ManagerDir              string `json:"managerDir"`
	DefaultOpenClawStateDir string `json:"defaultOpenClawStateDir"`
	DefaultCodexHome        string `json:"defaultCodexHome"`
	OAuthCallbackURL        string `json:"oauthCallbackUrl"`
	OAuthCallbackBindHost   string `json:"oauthCallbackBindHost"`
}

type RuntimeDaemon struct {
	PID                 int     `json:"pid"`
	Host                string  `json:"host"`
	Port                *int    `json:"port,omitempty"`
	APIBaseURL          *string `json:"apiBaseUrl,omitempty"`
	StartedAt           string  `json:"startedAt"`
	UptimeMs            int     `json:"uptimeMs"`
	ProbeIntervalMinMs  int     `json:"probeIntervalMinMs"`
	ProbeIntervalMaxMs  int     `json:"probeIntervalMaxMs"`
	PollIntervalMs      int     `json:"pollIntervalMs"`
	NextProbeAt         *string `json:"nextProbeAt,omitempty"`
	AutoActivateEnabled bool    `json:"autoActivateEnabled"`
	LoopScheduled       bool    `json:"loopScheduled"`
	LoopRunning         bool    `json:"loopRunning"`
}

type RuntimeSwitching struct {
	ActiveProfileName           *string `json:"activeProfileName,omitempty"`
	RecommendedProfileName      *string `json:"recommendedProfileName,omitempty"`
	TotalProfiles               int     `json:"totalProfiles"`
	HealthyProfiles             int     `json:"healthyProfiles"`
	DrainingProfiles            int     `json:"drainingProfiles"`
	RiskyProfiles               int     `json:"riskyProfiles"`
	TotalActivations            int     `json:"totalActivations"`
	ManualActivations           int     `json:"manualActivations"`
	AutoActivations             int     `json:"autoActivations"`
	RecommendedActivations      int     `json:"recommendedActivations"`
	LastActivationAt            *string `json:"lastActivationAt,omitempty"`
	LastActivationDurationMs    *int    `json:"lastActivationDurationMs,omitempty"`
	AverageActivationDurationMs *int    `json:"averageActivationDurationMs,omitempty"`
	LastActivationTrigger       *string `json:"lastActivationTrigger,omitempty"`
	LastActivationReason        *string `json:"lastActivationReason,omitempty"`
	LastSyncedAt                *string `json:"lastSyncedAt,omitempty"`
}

type RuntimeCompatibility struct {
	AllowedOrigins         []string `json:"allowedOrigins"`
	AllowLocalhostDev      bool     `json:"allowLocalhostDev"`
	BrowserShellSupported  bool     `json:"browserShellSupported"`
	NativeShellRecommended bool     `json:"nativeShellRecommended"`
	WrapperCommand         string   `json:"wrapperCommand"`
	CodexWrapperCommand    string   `json:"codexWrapperCommand"`
}

type ManagerSummary struct {
	GeneratedAt            string                   `json:"generatedAt"`
	ActiveProfileName      *string                  `json:"activeProfileName,omitempty"`
	RecommendedProfileName *string                  `json:"recommendedProfileName,omitempty"`
	Automation             AutomationSnapshot       `json:"automation"`
	Runtime                RuntimeOverview          `json:"runtime"`
	Profiles               []ManagedProfileSnapshot `json:"profiles"`
}

type AutomationTickResult struct {
	Switched        bool           `json:"switched"`
	FromProfileName *string        `json:"fromProfileName,omitempty"`
	ToProfileName   *string        `json:"toProfileName,omitempty"`
	Reason          string         `json:"reason"`
	Summary         ManagerSummary `json:"summary"`
}

type LoginFlowSnapshot struct {
	ID            string  `json:"id"`
	ProfileName   string  `json:"profileName"`
	Status        string  `json:"status"`
	AuthURL       string  `json:"authUrl"`
	BrowserOpened bool    `json:"browserOpened"`
	StartedAt     string  `json:"startedAt"`
	ExpiresAt     string  `json:"expiresAt"`
	CompletedAt   *string `json:"completedAt,omitempty"`
	Error         *string `json:"error,omitempty"`
}

type PendingLoginFlow struct {
	LoginFlowSnapshot
	Verifier   string
	OAuthState string
}

type SupportLogEvent struct {
	Timestamp string `json:"timestamp"`
	Kind      string `json:"kind"`
	Line      string `json:"line"`
}

type SupportSummary struct {
	CollectedAt string             `json:"collectedAt"`
	Gateway     SupportGateway     `json:"gateway"`
	Discord     SupportDiscord     `json:"discord"`
	Watchdog    SupportWatchdog    `json:"watchdog"`
	Environment SupportEnvironment `json:"environment"`
	Maintenance SupportMaintenance `json:"maintenance"`
}

type SupportGateway struct {
	Reachable        bool    `json:"reachable"`
	URL              *string `json:"url,omitempty"`
	ConnectLatencyMs *int    `json:"connectLatencyMs,omitempty"`
	Version          *string `json:"version,omitempty"`
	Host             *string `json:"host,omitempty"`
	Error            *string `json:"error,omitempty"`
}

type SupportDiscord struct {
	Status             string            `json:"status"`
	LastLoggedInAt     *string           `json:"lastLoggedInAt,omitempty"`
	LastDisconnectAt   *string           `json:"lastDisconnectAt,omitempty"`
	DisconnectCount15m int               `json:"disconnectCount15m"`
	DisconnectCount60m int               `json:"disconnectCount60m"`
	RecentEvents       []SupportLogEvent `json:"recentEvents"`
	Recommendation     string            `json:"recommendation"`
}

type SupportWatchdog struct {
	Installed         bool    `json:"installed"`
	MonitoredStateDir *string `json:"monitoredStateDir,omitempty"`
	LastLoopResult    *string `json:"lastLoopResult,omitempty"`
	LastHealthyAt     *string `json:"lastHealthyAt,omitempty"`
	LastRestartAt     *string `json:"lastRestartAt,omitempty"`
	RestartCount      *int    `json:"restartCount,omitempty"`
	StatePath         string  `json:"statePath"`
	LogPath           string  `json:"logPath"`
	StatusLine        string  `json:"statusLine"`
}

type SupportEnvironment struct {
	PrimaryInterface   *string  `json:"primaryInterface,omitempty"`
	GatewayAddress     *string  `json:"gatewayAddress,omitempty"`
	VPNLikelyActive    bool     `json:"vpnLikelyActive"`
	VPNServiceNames    []string `json:"vpnServiceNames"`
	ProxyLikelyEnabled bool     `json:"proxyLikelyEnabled"`
	ProxySummary       *string  `json:"proxySummary,omitempty"`
	LastSleepAt        *string  `json:"lastSleepAt,omitempty"`
	LastWakeAt         *string  `json:"lastWakeAt,omitempty"`
	SleepWakeCount60m  int      `json:"sleepWakeCount60m"`
	RiskLevel          string   `json:"riskLevel"`
	RiskySignals       []string `json:"riskySignals"`
	Recommendation     string   `json:"recommendation"`
}

type SupportMaintenance struct {
	CLIPath               *string               `json:"cliPath,omitempty"`
	StateDir              string                `json:"stateDir"`
	Config                SupportConfigCheck    `json:"config"`
	GatewayService        SupportGatewayService `json:"gatewayService"`
	DoctorCommand         string                `json:"doctorCommand"`
	DoctorFixCommand      string                `json:"doctorFixCommand"`
	GatewayInstallCommand string                `json:"gatewayInstallCommand"`
}

type SupportConfigCheck struct {
	Path   string `json:"path"`
	Exists bool   `json:"exists"`
	Valid  bool   `json:"valid"`
	Detail string `json:"detail"`
}

type SupportGatewayService struct {
	Installed         bool    `json:"installed"`
	Status            string  `json:"status"`
	ServiceFile       *string `json:"serviceFile,omitempty"`
	CLIConfigPath     *string `json:"cliConfigPath,omitempty"`
	ServiceConfigPath *string `json:"serviceConfigPath,omitempty"`
	LogPath           *string `json:"logPath,omitempty"`
	Command           *string `json:"command,omitempty"`
	RuntimeStatus     *string `json:"runtimeStatus,omitempty"`
	ProbeStatus       *string `json:"probeStatus,omitempty"`
	Issue             *string `json:"issue,omitempty"`
	Recommendation    *string `json:"recommendation,omitempty"`
}

type SupportRepairResult struct {
	OK      bool           `json:"ok"`
	Action  string         `json:"action"`
	Message string         `json:"message"`
	Output  *string        `json:"output,omitempty"`
	Summary SupportSummary `json:"summary"`
}

type MachineSummary struct {
	CollectedAt  string              `json:"collectedAt"`
	OpenClaw     MachineOpenClaw     `json:"openclaw"`
	CPU          MachineCPU          `json:"cpu"`
	Memory       MachineMemory       `json:"memory"`
	Swap         MachineSwap         `json:"swap"`
	Disk         MachineDisk         `json:"disk"`
	Network      MachineNetwork      `json:"network"`
	Processes    MachineProcessGroup `json:"processes"`
	TopProcesses []MachineTopProcess `json:"topProcesses"`
}

type MachineOpenClaw struct {
	Available bool    `json:"available"`
	Path      *string `json:"path,omitempty"`
	Source    string  `json:"source"`
}

type MachineCPU struct {
	ActivePercent int `json:"activePercent"`
	UserPercent   int `json:"userPercent"`
	SystemPercent int `json:"systemPercent"`
	IdlePercent   int `json:"idlePercent"`
	LogicalCores  int `json:"logicalCores"`
}

type MachineMemory struct {
	TotalBytes      int64  `json:"totalBytes"`
	UsedBytes       int64  `json:"usedBytes"`
	AvailableBytes  int64  `json:"availableBytes"`
	WiredBytes      int64  `json:"wiredBytes"`
	ActiveBytes     int64  `json:"activeBytes"`
	CachedBytes     int64  `json:"cachedBytes"`
	FreeBytes       int64  `json:"freeBytes"`
	OtherBytes      int64  `json:"otherBytes"`
	CompressedBytes int64  `json:"compressedBytes"`
	UsedPercent     int    `json:"usedPercent"`
	PressurePercent int    `json:"pressurePercent"`
	Pressure        string `json:"pressure"`
}

type MachineSwap struct {
	TotalBytes  int64 `json:"totalBytes"`
	UsedBytes   int64 `json:"usedBytes"`
	FreeBytes   int64 `json:"freeBytes"`
	UsedPercent int   `json:"usedPercent"`
}

type MachineDisk struct {
	Path        string `json:"path"`
	TotalBytes  int64  `json:"totalBytes"`
	UsedBytes   int64  `json:"usedBytes"`
	FreeBytes   int64  `json:"freeBytes"`
	UsedPercent int    `json:"usedPercent"`
}

type MachineNetwork struct {
	PrimaryInterface    *string `json:"primaryInterface,omitempty"`
	ReceivedBytesPerSec *int64  `json:"receivedBytesPerSec,omitempty"`
	SentBytesPerSec     *int64  `json:"sentBytesPerSec,omitempty"`
	TotalReceivedBytes  int64   `json:"totalReceivedBytes"`
	TotalSentBytes      int64   `json:"totalSentBytes"`
}

type MachineProcessGroup struct {
	Manager  MachineProcessSnapshot `json:"manager"`
	Watchdog MachineProcessSnapshot `json:"watchdog"`
}

type MachineProcessSnapshot struct {
	Running       bool     `json:"running"`
	PID           *int     `json:"pid,omitempty"`
	CPUPercent    *float64 `json:"cpuPercent,omitempty"`
	RSSBytes      *int64   `json:"rssBytes,omitempty"`
	UptimeSeconds *int     `json:"uptimeSeconds,omitempty"`
	Command       *string  `json:"command,omitempty"`
}

type MachineTopProcess struct {
	Name          string  `json:"name"`
	PID           int     `json:"pid"`
	CPUPercent    float64 `json:"cpuPercent"`
	RSSBytes      int64   `json:"rssBytes"`
	UptimeSeconds int     `json:"uptimeSeconds"`
	Command       string  `json:"command"`
}

type AuthStore struct {
	Version    int                       `json:"version"`
	Profiles   map[string]map[string]any `json:"profiles"`
	LastGood   map[string]string         `json:"lastGood"`
	UsageStats map[string]map[string]any `json:"usageStats"`
}

type OpenClawConfigFile struct {
	Auth struct {
		Profiles map[string]OpenClawAuthProfileConfig `json:"profiles"`
	} `json:"auth"`
	Agents struct {
		Defaults struct {
			Model struct {
				Primary string `json:"primary"`
			} `json:"model"`
		} `json:"defaults"`
	} `json:"agents"`
}

type OpenClawAuthProfileConfig struct {
	Provider string `json:"provider"`
	Mode     string `json:"mode"`
}

type OpenClawConfigSnapshot struct {
	PrimaryProviderID     *string
	PrimaryModelID        *string
	ConfiguredProviderIDs []string
	AuthModes             map[string]string
}

type OAuthCredential struct {
	Type      string
	Provider  string
	Access    string
	Refresh   string
	Expires   int64
	AccountID string
}

type OAuthTokens struct {
	Access    string
	Refresh   string
	IDToken   string
	Expires   int64
	AccountID string
	Email     string
}

type CodexAuthFile struct {
	AuthMode     string  `json:"auth_mode"`
	OpenAIAPIKey *string `json:"OPENAI_API_KEY"`
	Tokens       struct {
		IDToken      string `json:"id_token"`
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
		AccountID    string `json:"account_id"`
	} `json:"tokens"`
	LastRefresh string `json:"last_refresh"`
}

type CodexMetadataSnapshot struct {
	CodexHome          string
	CodexConfigPath    string
	CodexAuthPath      string
	HasCodexConfig     bool
	HasCodexAuth       bool
	CodexAuthMode      *string
	CodexAccountID     *string
	CodexLastRefreshAt *string
}

type CommandResult struct {
	OK       bool
	Code     *int
	Stdout   string
	Stderr   string
	TimedOut bool
}

type openclawStatusPayload struct {
	Gateway struct {
		Reachable        bool   `json:"reachable"`
		URL              string `json:"url"`
		ConnectLatencyMs *int   `json:"connectLatencyMs"`
		Error            string `json:"error"`
		Self             struct {
			Version string `json:"version"`
			Host    string `json:"host"`
		} `json:"self"`
	} `json:"gateway"`
}

type usagePayload struct {
	PlanType  string `json:"plan_type"`
	RateLimit struct {
		PrimaryWindow *struct {
			UsedPercent *float64 `json:"used_percent"`
			ResetAt     *int64   `json:"reset_at"`
		} `json:"primary_window"`
		SecondaryWindow *struct {
			UsedPercent *float64 `json:"used_percent"`
			ResetAt     *int64   `json:"reset_at"`
		} `json:"secondary_window"`
	} `json:"rate_limit"`
}

type loginTokenPayload struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	IDToken      string `json:"id_token"`
	ExpiresIn    int64  `json:"expires_in"`
}

type activationOptions struct {
	State            *NormalizedManagerState
	Reason           string
	IsAutoActivation bool
	FromProfileName  *string
	Trigger          string
}

func main() {
	app, err := newApp()
	if err != nil {
		fatalf("init failed: %v", err)
	}
	if err := app.start(); err != nil {
		fatalf("daemon failed: %v", err)
	}
}

func newApp() (*App, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}

	openclawHome := strings.TrimSpace(os.Getenv("OPENCLAW_HOME_DIR"))
	if openclawHome == "" {
		openclawHome = homeDir
	}
	codexHome := strings.TrimSpace(os.Getenv("OPENCLAW_CODEX_HOME_DIR"))
	if codexHome == "" {
		codexHome = homeDir
	}
	managerDir := strings.TrimSpace(os.Getenv("OPENCLAW_MANAGER_DIR"))
	if managerDir == "" {
		managerDir = filepath.Join(codexHome, ".codex-pool-manager")
	}
	host := strings.TrimSpace(os.Getenv("HOST"))
	if host == "" {
		host = "127.0.0.1"
	}
	port := envInt("PORT", 3311)
	if port <= 0 {
		port = 3311
	}
	callbackPort := envInt("OPENCLAW_OAUTH_CALLBACK_PORT", 1455)
	bindHost := strings.TrimSpace(os.Getenv("OPENCLAW_OAUTH_CALLBACK_BIND_HOST"))
	if bindHost == "" {
		bindHost = "127.0.0.1"
	}
	publicHost := strings.TrimSpace(os.Getenv("OPENCLAW_OAUTH_CALLBACK_PUBLIC_HOST"))
	if publicHost == "" {
		publicHost = "localhost"
	}
	exePath, _ := os.Executable()

	app := &App{
		host:                    host,
		port:                    port,
		homeDir:                 homeDir,
		openclawHomeDir:         openclawHome,
		codexHomeDir:            codexHome,
		managerDir:              managerDir,
		managerStatePath:        filepath.Join(managerDir, "state.json"),
		backupDir:               filepath.Join(managerDir, "backups"),
		defaultOpenClawState:    filepath.Join(openclawHome, ".openclaw"),
		defaultCodexHome:        filepath.Join(codexHome, ".codex"),
		oauthCallbackPort:       callbackPort,
		oauthCallbackBindHost:   bindHost,
		oauthCallbackPublicHost: publicHost,
		oauthRedirectURL:        fmt.Sprintf("http://%s:%d/auth/callback", publicHost, callbackPort),
		authOpenMode:            strings.ToLower(strings.TrimSpace(os.Getenv("OPENCLAW_AUTH_OPEN_MODE"))),
		startedAt:               time.Now().UTC(),
		executablePath:          exePath,
		loginFlows:              map[string]*PendingLoginFlow{},
		loginFlowIDsByState:     map[string]string{},
		usageCache:              map[string]cachedUsageSnapshot{},
		stateDirCache:           map[string]string{},
	}
	if app.authOpenMode == "" {
		app.authOpenMode = "auto"
	}
	return app, ensureDir(app.managerDir)
}

func (app *App) start() error {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/health", app.handleHealth)
	mux.HandleFunc("GET /api/openclaw/manager", app.handleManagerSummary)
	mux.HandleFunc("GET /api/openclaw/system", app.handleRuntimeOverview)
	mux.HandleFunc("GET /api/machine/summary", app.handleMachineSummary)
	mux.HandleFunc("PATCH /api/openclaw/settings", app.handleUpdateSettings)
	mux.HandleFunc("POST /api/openclaw/automation/tick", app.handleAutomationTick)
	mux.HandleFunc("POST /api/openclaw/profiles", app.handleCreateProfile)
	mux.HandleFunc("POST /api/openclaw/profiles/{profileName}/probe", app.handleProbeProfile)
	mux.HandleFunc("POST /api/openclaw/profiles/{profileName}/login", app.handleLoginProfile)
	mux.HandleFunc("GET /api/openclaw/login-flows/{flowId}", app.handleGetLoginFlow)
	mux.HandleFunc("POST /api/openclaw/profiles/{profileName}/activate", app.handleActivateProfile)
	mux.HandleFunc("POST /api/openclaw/activate-recommended", app.handleActivateRecommended)
	mux.HandleFunc("GET /api/support/summary", app.handleSupportSummary)
	mux.HandleFunc("POST /api/support/repair", app.handleSupportRepair)

	app.server = &http.Server{
		Addr:              fmt.Sprintf("%s:%d", app.host, app.port),
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
	}

	shutdownCtx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		<-shutdownCtx.Done()
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = app.server.Shutdown(ctx)
		app.stopCallbackServer()
	}()

	go func() {
		time.Sleep(200 * time.Millisecond)
		app.startAutomationLoop()
	}()

	fmt.Fprintf(os.Stdout, "[go-daemon] listening on http://%s:%d\n", app.host, app.port)
	err := app.server.ListenAndServe()
	if err != nil && !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

func (app *App) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (app *App) handleManagerSummary(w http.ResponseWriter, _ *http.Request) {
	summary, err := app.getManagerSummary()
	if err != nil {
		writeAPIError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, summary)
}

func (app *App) handleRuntimeOverview(w http.ResponseWriter, _ *http.Request) {
	overview, err := app.getRuntimeOverview()
	if err != nil {
		writeAPIError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, overview)
}

func (app *App) handleMachineSummary(w http.ResponseWriter, r *http.Request) {
	summary, err := app.buildMachineSummary(r.URL.Query().Get("fresh") == "1")
	if err != nil {
		writeAPIError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, summary)
}

func (app *App) handleUpdateSettings(w http.ResponseWriter, r *http.Request) {
	var patch PersistedManagerSettings
	if err := decodeJSONBody(r, &patch); err != nil {
		writeAPIMessage(w, http.StatusBadRequest, "settings patch is invalid")
		return
	}
	summary, err := app.updateManagerSettings(patch)
	if err != nil {
		writeAPIMessage(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, summary)
}

func (app *App) handleAutomationTick(w http.ResponseWriter, _ *http.Request) {
	result, err := app.runAutomationTick("manual")
	if err != nil {
		writeAPIMessage(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (app *App) handleCreateProfile(w http.ResponseWriter, r *http.Request) {
	var body struct {
		ProfileName string `json:"profileName"`
	}
	if err := decodeJSONBody(r, &body); err != nil || strings.TrimSpace(body.ProfileName) == "" {
		writeAPIMessage(w, http.StatusBadRequest, "profileName is invalid")
		return
	}
	profile, err := app.createManagedProfile(body.ProfileName)
	if err != nil {
		writeAPIMessage(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, profile)
}

func (app *App) handleProbeProfile(w http.ResponseWriter, r *http.Request) {
	profileName := r.PathValue("profileName")
	profile, err := app.probeManagedProfile(profileName)
	if err != nil {
		writeAPIMessage(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, profile)
}

func (app *App) handleLoginProfile(w http.ResponseWriter, r *http.Request) {
	profileName := r.PathValue("profileName")
	flow, err := app.loginManagedProfile(profileName)
	if err != nil {
		if errors.Is(err, errLoginNotSupported) {
			writeAPIMessage(w, http.StatusBadRequest, err.Error())
			return
		}
		writeAPIMessage(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusAccepted, flow)
}

func (app *App) handleGetLoginFlow(w http.ResponseWriter, r *http.Request) {
	flowID := r.PathValue("flowId")
	flow := app.getLoginFlow(flowID)
	if flow == nil {
		writeAPIMessage(w, http.StatusNotFound, "login flow not found")
		return
	}
	writeJSON(w, http.StatusOK, flow)
}

func (app *App) handleActivateProfile(w http.ResponseWriter, r *http.Request) {
	profileName := r.PathValue("profileName")
	summary, err := app.activateManagedProfile(profileName, activationOptions{})
	if err != nil {
		writeAPIMessage(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, summary)
}

func (app *App) handleActivateRecommended(w http.ResponseWriter, _ *http.Request) {
	summary, err := app.activateRecommendedProfile()
	if err != nil {
		writeAPIMessage(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, summary)
}

func (app *App) handleSupportSummary(w http.ResponseWriter, r *http.Request) {
	fresh := r.URL.Query().Get("fresh") == "1"
	summary, err := app.buildSupportSummary(fresh)
	if err != nil {
		writeAPIMessage(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, summary)
}

func (app *App) handleSupportRepair(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Action string `json:"action"`
	}
	if err := decodeJSONBody(r, &body); err != nil {
		writeAPIMessage(w, http.StatusBadRequest, "repair action is invalid")
		return
	}
	result, err := app.performSupportRepair(body.Action)
	if err != nil {
		writeAPIMessage(w, http.StatusInternalServerError, err.Error())
		return
	}
	if result.OK {
		writeJSON(w, http.StatusOK, result)
		return
	}
	writeJSON(w, http.StatusInternalServerError, result)
}

func (app *App) getManagerSummary() (ManagerSummary, error) {
	state, err := app.loadNormalizedManagerState()
	if err != nil {
		return ManagerSummary{}, err
	}
	return app.getManagerSummaryFromState(state)
}

func (app *App) getRuntimeOverview() (RuntimeOverview, error) {
	summary, err := app.getManagerSummary()
	if err != nil {
		return RuntimeOverview{}, err
	}
	return summary.Runtime, nil
}

func (app *App) updateManagerSettings(patch PersistedManagerSettings) (ManagerSummary, error) {
	app.opMu.Lock()
	defer app.opMu.Unlock()

	state, err := app.loadNormalizedManagerState()
	if err != nil {
		return ManagerSummary{}, err
	}

	nextSettings, err := validateSettingsPatch(patch)
	if err != nil {
		return ManagerSummary{}, err
	}

	if nextSettings.AutoActivateEnabled != nil {
		state.Settings.AutoActivateEnabled = *nextSettings.AutoActivateEnabled
	}
	if nextSettings.ProbeIntervalMinMs != nil {
		state.Settings.ProbeIntervalMinMs = *nextSettings.ProbeIntervalMinMs
	}
	if nextSettings.ProbeIntervalMaxMs != nil {
		state.Settings.ProbeIntervalMaxMs = *nextSettings.ProbeIntervalMaxMs
	}
	if nextSettings.FiveHourDrainPercent != nil {
		state.Settings.FiveHourDrainPercent = *nextSettings.FiveHourDrainPercent
	}
	if nextSettings.WeekDrainPercent != nil {
		state.Settings.WeekDrainPercent = *nextSettings.WeekDrainPercent
	}
	if nextSettings.AutoSwitchStatuses != nil {
		state.Settings.AutoSwitchStatuses = append([]string(nil), nextSettings.AutoSwitchStatuses...)
	}
	if state.Settings.ProbeIntervalMaxMs < state.Settings.ProbeIntervalMinMs {
		state.Settings.ProbeIntervalMaxMs = state.Settings.ProbeIntervalMinMs
	}

	if err := app.saveManagerState(state); err != nil {
		return ManagerSummary{}, err
	}
	app.restartAutomationLoop()
	return app.getManagerSummaryFromState(state)
}

func (app *App) runAutomationTick(trigger string) (AutomationTickResult, error) {
	app.opMu.Lock()
	defer app.opMu.Unlock()
	return app.runAutomationTickUnlocked(trigger)
}

func (app *App) runAutomationTickUnlocked(trigger string) (AutomationTickResult, error) {
	state, err := app.loadNormalizedManagerState()
	if err != nil {
		return AutomationTickResult{}, err
	}
	now := nowISO()
	state.Automation.LastProbeAt = &now
	state.Automation.LastTickError = nil
	if err := app.saveManagerState(state); err != nil {
		return AutomationTickResult{}, err
	}

	summary, err := app.getManagerSummaryFromState(state)
	if err != nil {
		message := err.Error()
		state.Automation.LastTickError = &message
		_ = app.saveManagerState(state)
		return AutomationTickResult{}, err
	}

	decision := shouldAutoSwitch(summary)
	if !decision.ShouldSwitch || decision.TargetProfileName == nil {
		reason := fmt.Sprintf("%s: %s", trigger, decision.Reason)
		state.Automation.LastAutoActivationReason = &reason
		if err := app.saveManagerState(state); err != nil {
			return AutomationTickResult{}, err
		}
		nextSummary, err := app.getManagerSummaryFromState(state)
		if err != nil {
			return AutomationTickResult{}, err
		}
		return AutomationTickResult{
			Switched:        false,
			FromProfileName: summary.ActiveProfileName,
			ToProfileName:   nil,
			Reason:          decision.Reason,
			Summary:         nextSummary,
		}, nil
	}

	activated, err := app.activateManagedProfileUnlocked(*decision.TargetProfileName, activationOptions{
		State:            &state,
		Reason:           fmt.Sprintf("%s: %s", trigger, decision.Reason),
		IsAutoActivation: true,
		FromProfileName:  summary.ActiveProfileName,
		Trigger:          "auto",
	})
	if err != nil {
		message := err.Error()
		state.Automation.LastTickError = &message
		_ = app.saveManagerState(state)
		return AutomationTickResult{}, err
	}

	return AutomationTickResult{
		Switched:        true,
		FromProfileName: summary.ActiveProfileName,
		ToProfileName:   decision.TargetProfileName,
		Reason:          decision.Reason,
		Summary:         activated,
	}, nil
}

func (app *App) createManagedProfile(rawProfileName string) (ManagedProfileSnapshot, error) {
	app.opMu.Lock()
	defer app.opMu.Unlock()

	profileName, err := normalizeProfileName(rawProfileName, false)
	if err != nil {
		return ManagedProfileSnapshot{}, err
	}
	if err := app.ensureProfileScaffold(profileName); err != nil {
		return ManagedProfileSnapshot{}, err
	}
	state, err := app.loadNormalizedManagerState()
	if err != nil {
		return ManagedProfileSnapshot{}, err
	}
	return app.readProfileSnapshot(profileName, state.Settings, false)
}

func (app *App) probeManagedProfile(rawProfileName string) (ManagedProfileSnapshot, error) {
	profileName, err := normalizeProfileName(rawProfileName, true)
	if err != nil {
		return ManagedProfileSnapshot{}, err
	}
	state, err := app.loadNormalizedManagerState()
	if err != nil {
		return ManagedProfileSnapshot{}, err
	}
	return app.readProfileSnapshot(profileName, state.Settings, true)
}

func (app *App) loginManagedProfile(rawProfileName string) (LoginFlowSnapshot, error) {
	app.opMu.Lock()
	defer app.opMu.Unlock()

	profileName, err := normalizeProfileName(rawProfileName, true)
	if err != nil {
		return LoginFlowSnapshot{}, err
	}
	if err := app.ensureProfileScaffold(profileName); err != nil {
		return LoginFlowSnapshot{}, err
	}
	configPath, err := app.resolveConfigPath(profileName)
	if err != nil {
		return LoginFlowSnapshot{}, err
	}
	config := readOpenClawConfigSnapshot(configPath)
	loginKind := profileLoginKind(config)
	if loginKind == nil || *loginKind != "codex-oauth" {
		if config.PrimaryProviderID != nil {
			label := providerDisplayName(*config.PrimaryProviderID)
			return LoginFlowSnapshot{}, fmt.Errorf("%w: %s 当前不支持内置登录，请在 OpenClaw 配置里完成认证", errLoginNotSupported, label)
		}
		return LoginFlowSnapshot{}, fmt.Errorf("%w: 当前 profile 不支持内置登录", errLoginNotSupported)
	}

	if flow := app.findPendingLoginFlow(profileName); flow != nil {
		return flow.LoginFlowSnapshot, nil
	}
	if err := app.ensureOAuthCallbackServer(); err != nil {
		return LoginFlowSnapshot{}, err
	}

	authURL, verifier, oauthState, err := app.buildAuthorizationURL()
	if err != nil {
		return LoginFlowSnapshot{}, err
	}

	flow := &PendingLoginFlow{
		LoginFlowSnapshot: LoginFlowSnapshot{
			ID:            newUUID(),
			ProfileName:   profileName,
			Status:        "pending",
			AuthURL:       authURL,
			BrowserOpened: false,
			StartedAt:     nowISO(),
			ExpiresAt:     time.Now().Add(oauthTimeout).UTC().Format(time.RFC3339),
		},
		Verifier:   verifier,
		OAuthState: oauthState,
	}

	app.mu.Lock()
	app.loginFlows[flow.ID] = flow
	app.loginFlowIDsByState[oauthState] = flow.ID
	app.mu.Unlock()

	opened, openErr := app.openAuthBrowser(authURL)
	if openErr != nil {
		now := nowISO()
		flow.Status = "failed"
		flow.CompletedAt = &now
		errText := openErr.Error()
		flow.Error = &errText
	} else {
		flow.BrowserOpened = opened
	}

	return flow.LoginFlowSnapshot, nil
}

func (app *App) getLoginFlow(flowID string) *LoginFlowSnapshot {
	app.mu.Lock()
	defer app.mu.Unlock()
	app.expirePendingLoginFlowsLocked()
	flow := app.loginFlows[flowID]
	if flow == nil {
		return nil
	}
	snapshot := flow.LoginFlowSnapshot
	return &snapshot
}

func (app *App) activateManagedProfile(rawProfileName string, options activationOptions) (ManagerSummary, error) {
	app.opMu.Lock()
	defer app.opMu.Unlock()
	return app.activateManagedProfileUnlocked(rawProfileName, options)
}

func (app *App) activateManagedProfileUnlocked(rawProfileName string, options activationOptions) (ManagerSummary, error) {
	profileName, err := normalizeProfileName(rawProfileName, true)
	if err != nil {
		return ManagerSummary{}, err
	}
	if err := app.syncProfileToDefault(profileName); err != nil {
		return ManagerSummary{}, err
	}

	baseState := options.State
	if baseState == nil {
		state, err := app.loadNormalizedManagerState()
		if err != nil {
			return ManagerSummary{}, err
		}
		baseState = &state
	}

	nextState := *baseState
	activatedAt := nowISO()
	nextState.ActiveProfileName = ptr(profileName)
	nextState.LastActivatedAt = &activatedAt
	nextState.Settings.AutoSwitchStatuses = append([]string(nil), baseState.Settings.AutoSwitchStatuses...)

	if options.Reason != "" {
		nextState.Automation.LastAutoActivationReason = &options.Reason
	}
	if options.IsAutoActivation {
		nextState.Automation.LastAutoActivationAt = &activatedAt
		nextState.Automation.LastAutoActivationFrom = options.FromProfileName
		nextState.Automation.LastAutoActivationTo = ptr(profileName)
	}

	trigger := options.Trigger
	if trigger == "" {
		if options.IsAutoActivation {
			trigger = "auto"
		} else {
			trigger = "manual"
		}
	}
	recordActivationTelemetry(&nextState, trigger, 0, options.Reason)

	if err := app.saveManagerState(nextState); err != nil {
		return ManagerSummary{}, err
	}
	return app.getManagerSummaryFromState(nextState)
}

func (app *App) activateRecommendedProfile() (ManagerSummary, error) {
	app.opMu.Lock()
	defer app.opMu.Unlock()

	summary, err := app.getManagerSummary()
	if err != nil {
		return ManagerSummary{}, err
	}
	if summary.RecommendedProfileName == nil {
		return ManagerSummary{}, errors.New("no healthy or draining profile available to activate")
	}
	return app.activateManagedProfileUnlocked(*summary.RecommendedProfileName, activationOptions{
		Reason:  "manual: activate recommended profile",
		Trigger: "recommended",
	})
}

func (app *App) startAutomationLoop() {
	app.mu.Lock()
	if app.automationTimer != nil {
		app.mu.Unlock()
		return
	}
	app.mu.Unlock()

	state, err := app.loadNormalizedManagerState()
	if err != nil {
		fmt.Fprintf(os.Stderr, "[go-daemon] automation init failed: %v\n", err)
		return
	}
	if state.Settings.AutoActivateEnabled {
		if _, err := app.runAutomationTick("startup"); err != nil {
			fmt.Fprintf(os.Stderr, "[go-daemon] startup automation tick failed: %v\n", err)
		}
	}
	app.scheduleAutomationLoop()
}

func (app *App) scheduleAutomationLoop() {
	state, err := app.loadNormalizedManagerState()
	if err != nil {
		fmt.Fprintf(os.Stderr, "[go-daemon] schedule loop failed: %v\n", err)
		return
	}
	if !state.Settings.AutoActivateEnabled {
		if state.Automation.NextProbeAt != nil || state.Automation.LastScheduledDelayMs != nil {
			state.Automation.NextProbeAt = nil
			state.Automation.LastScheduledDelayMs = nil
			_ = app.saveManagerState(state)
		}
		app.mu.Lock()
		app.automationTimer = nil
		app.mu.Unlock()
		return
	}

	delay := pickRandomProbeDelayMs(state.Settings)
	nextProbe := time.Now().Add(time.Duration(delay) * time.Millisecond).UTC().Format(time.RFC3339)
	state.Automation.NextProbeAt = &nextProbe
	state.Automation.LastScheduledDelayMs = &delay
	if err := app.saveManagerState(state); err != nil {
		fmt.Fprintf(os.Stderr, "[go-daemon] save loop state failed: %v\n", err)
	}

	app.mu.Lock()
	app.automationTimer = time.AfterFunc(time.Duration(delay)*time.Millisecond, func() {
		app.mu.Lock()
		if app.automationRunning {
			app.mu.Unlock()
			app.scheduleAutomationLoop()
			return
		}
		app.automationRunning = true
		app.automationTimer = nil
		app.mu.Unlock()

		func() {
			defer func() {
				app.mu.Lock()
				app.automationRunning = false
				app.mu.Unlock()
			}()

			state, err := app.loadNormalizedManagerState()
			if err == nil {
				state.Automation.NextProbeAt = nil
				_ = app.saveManagerState(state)
			}
			if _, err := app.runAutomationTick("interval"); err != nil {
				fmt.Fprintf(os.Stderr, "[go-daemon] interval automation tick failed: %v\n", err)
			}
		}()

		app.scheduleAutomationLoop()
	})
	app.mu.Unlock()
}

func (app *App) restartAutomationLoop() {
	app.mu.Lock()
	if app.automationTimer != nil {
		app.automationTimer.Stop()
		app.automationTimer = nil
	}
	running := app.automationRunning
	app.mu.Unlock()
	if running {
		return
	}
	app.scheduleAutomationLoop()
}

func (app *App) stopCallbackServer() {
	app.mu.Lock()
	server := app.callbackServer
	app.callbackServer = nil
	app.mu.Unlock()
	if server == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_ = server.Shutdown(ctx)
}

func (app *App) loadManagerState() ManagerStateFile {
	return readJSONFile(app.managerStatePath, ManagerStateFile{})
}

func (app *App) saveManagerState(state NormalizedManagerState) error {
	settingsVersion := managerSettingsVersion
	payload := ManagerStateFile{
		ActiveProfileName: state.ActiveProfileName,
		LastActivatedAt:   state.LastActivatedAt,
		SettingsVersion:   &settingsVersion,
		Settings: &PersistedManagerSettings{
			AutoActivateEnabled:  ptr(state.Settings.AutoActivateEnabled),
			ProbeIntervalMinMs:   ptr(state.Settings.ProbeIntervalMinMs),
			ProbeIntervalMaxMs:   ptr(state.Settings.ProbeIntervalMaxMs),
			FiveHourDrainPercent: ptr(state.Settings.FiveHourDrainPercent),
			WeekDrainPercent:     ptr(state.Settings.WeekDrainPercent),
			AutoSwitchStatuses:   append([]string(nil), state.Settings.AutoSwitchStatuses...),
		},
		Automation: &state.Automation,
		Runtime:    &state.Runtime,
	}
	return writeJSONFile(app.managerStatePath, payload)
}

func (app *App) loadNormalizedManagerState() (NormalizedManagerState, error) {
	raw := app.loadManagerState()
	normalized := normalizeManagerState(raw)
	if raw.SettingsVersion == nil || *raw.SettingsVersion < managerSettingsVersion || shouldMigrateLegacyDisabledAutomation(raw) {
		if err := app.saveManagerState(normalized); err != nil {
			return NormalizedManagerState{}, err
		}
	}
	return normalized, nil
}

func normalizeManagerState(state ManagerStateFile) NormalizedManagerState {
	defaults := defaultManagerSettings()
	runtimeDefaults := defaultRuntimeTelemetryState()
	probeMin, probeMax := normalizeProbeWindow(state.Settings, defaults)

	autoEnabled := defaults.AutoActivateEnabled
	if state.Settings != nil && state.Settings.AutoActivateEnabled != nil {
		autoEnabled = *state.Settings.AutoActivateEnabled
	}
	if shouldMigrateLegacyDisabledAutomation(state) {
		autoEnabled = true
	}

	fiveHour := defaults.FiveHourDrainPercent
	if state.Settings != nil && state.Settings.FiveHourDrainPercent != nil {
		fiveHour = clampPercentFloat(float64(*state.Settings.FiveHourDrainPercent))
	}
	week := defaults.WeekDrainPercent
	if state.Settings != nil && state.Settings.WeekDrainPercent != nil {
		week = clampPercentFloat(float64(*state.Settings.WeekDrainPercent))
	}

	automation := AutomationRuntimeState{}
	if state.Automation != nil {
		automation = *state.Automation
		if automation.LastScheduledDelayMs != nil && *automation.LastScheduledDelayMs < 0 {
			automation.LastScheduledDelayMs = nil
		}
	}

	runtimeState := runtimeDefaults
	if state.Runtime != nil {
		runtimeState = mergeRuntimeTelemetry(runtimeDefaults, *state.Runtime)
	}

	return NormalizedManagerState{
		ActiveProfileName: state.ActiveProfileName,
		LastActivatedAt:   state.LastActivatedAt,
		Settings: ManagerSettings{
			AutoActivateEnabled:  autoEnabled,
			ProbeIntervalMinMs:   probeMin,
			ProbeIntervalMaxMs:   probeMax,
			FiveHourDrainPercent: fiveHour,
			WeekDrainPercent:     week,
			AutoSwitchStatuses:   normalizeAutoSwitchStatuses(valueOrDefaultStatuses(state.Settings)),
		},
		Automation: automation,
		Runtime:    runtimeState,
	}
}

func defaultManagerSettings() ManagerSettings {
	return ManagerSettings{
		AutoActivateEnabled:  true,
		ProbeIntervalMinMs:   defaultProbeIntervalMinMs,
		ProbeIntervalMaxMs:   defaultProbeIntervalMaxMs,
		FiveHourDrainPercent: defaultFiveHourDrainPercent,
		WeekDrainPercent:     defaultWeekDrainPercent,
		AutoSwitchStatuses:   append([]string(nil), defaultAutoStatuses...),
	}
}

func defaultRuntimeTelemetryState() RuntimeTelemetryState {
	return RuntimeTelemetryState{
		TotalActivations:       ptr(0),
		ManualActivations:      ptr(0),
		AutoActivations:        ptr(0),
		RecommendedActivations: ptr(0),
	}
}

func mergeRuntimeTelemetry(defaults RuntimeTelemetryState, current RuntimeTelemetryState) RuntimeTelemetryState {
	out := defaults
	if current.TotalActivations != nil {
		out.TotalActivations = ptr(max(0, *current.TotalActivations))
	}
	if current.ManualActivations != nil {
		out.ManualActivations = ptr(max(0, *current.ManualActivations))
	}
	if current.AutoActivations != nil {
		out.AutoActivations = ptr(max(0, *current.AutoActivations))
	}
	if current.RecommendedActivations != nil {
		out.RecommendedActivations = ptr(max(0, *current.RecommendedActivations))
	}
	out.LastActivationAt = current.LastActivationAt
	if current.LastActivationDurationMs != nil {
		out.LastActivationDurationMs = ptr(max(0, *current.LastActivationDurationMs))
	}
	if current.AverageActivationDurationMs != nil {
		out.AverageActivationDurationMs = ptr(max(0, *current.AverageActivationDurationMs))
	}
	if current.LastActivationTrigger != nil && isValidTrigger(*current.LastActivationTrigger) {
		out.LastActivationTrigger = current.LastActivationTrigger
	}
	out.LastActivationReason = current.LastActivationReason
	out.LastSyncedAt = current.LastSyncedAt
	return out
}

func valueOrDefaultStatuses(settings *PersistedManagerSettings) []string {
	if settings == nil || settings.AutoSwitchStatuses == nil {
		return append([]string(nil), defaultAutoStatuses...)
	}
	return settings.AutoSwitchStatuses
}

func normalizeProbeWindow(settings *PersistedManagerSettings, defaults ManagerSettings) (int, int) {
	if settings != nil && (settings.ProbeIntervalMinMs != nil || settings.ProbeIntervalMaxMs != nil) {
		rawMin := defaults.ProbeIntervalMinMs
		if settings.ProbeIntervalMinMs != nil {
			rawMin = *settings.ProbeIntervalMinMs
		} else if settings.ProbeIntervalMaxMs != nil {
			rawMin = *settings.ProbeIntervalMaxMs
		}
		rawMax := defaults.ProbeIntervalMaxMs
		if settings.ProbeIntervalMaxMs != nil {
			rawMax = *settings.ProbeIntervalMaxMs
		}
		min := clampProbeIntervalMs(rawMin)
		maxValue := max(min, clampProbeIntervalMs(rawMax))
		return min, maxValue
	}
	if settings != nil && settings.PollIntervalMs != nil {
		return deriveProbeWindowFromLegacyPollInterval(*settings.PollIntervalMs)
	}
	return defaults.ProbeIntervalMinMs, defaults.ProbeIntervalMaxMs
}

func deriveProbeWindowFromLegacyPollInterval(pollIntervalMs int) (int, int) {
	minValue := clampProbeIntervalMs(pollIntervalMs)
	maxValue := max(minValue, clampProbeIntervalMs(minValue*2))
	return minValue, maxValue
}

func normalizeAutoSwitchStatuses(statuses []string) []string {
	if len(statuses) == 0 {
		return append([]string(nil), defaultAutoStatuses...)
	}
	seen := map[string]struct{}{}
	out := make([]string, 0, len(statuses))
	for _, status := range statuses {
		status = strings.TrimSpace(status)
		if _, ok := validStatuses[status]; !ok {
			continue
		}
		if _, exists := seen[status]; exists {
			continue
		}
		seen[status] = struct{}{}
		out = append(out, status)
	}
	if len(out) == 0 {
		return append([]string(nil), defaultAutoStatuses...)
	}
	return out
}

func shouldMigrateLegacyDisabledAutomation(state ManagerStateFile) bool {
	if state.SettingsVersion != nil && *state.SettingsVersion >= managerSettingsVersion {
		return false
	}
	if state.Settings == nil || state.Settings.AutoActivateEnabled == nil || *state.Settings.AutoActivateEnabled != false {
		return false
	}
	poll := legacyDefaultPollIntervalMs
	if state.Settings.PollIntervalMs != nil {
		poll = *state.Settings.PollIntervalMs
	}
	fiveHour := defaultFiveHourDrainPercent
	if state.Settings.FiveHourDrainPercent != nil {
		fiveHour = *state.Settings.FiveHourDrainPercent
	}
	week := defaultWeekDrainPercent
	if state.Settings.WeekDrainPercent != nil {
		week = *state.Settings.WeekDrainPercent
	}
	statuses := normalizeAutoSwitchStatuses(state.Settings.AutoSwitchStatuses)
	return poll == legacyDefaultPollIntervalMs &&
		fiveHour == defaultFiveHourDrainPercent &&
		week == defaultWeekDrainPercent &&
		sameStrings(statuses, defaultAutoStatuses)
}

func validateSettingsPatch(patch PersistedManagerSettings) (PersistedManagerSettings, error) {
	next := PersistedManagerSettings{}
	if patch.AutoActivateEnabled != nil {
		next.AutoActivateEnabled = ptr(*patch.AutoActivateEnabled)
	}
	if patch.PollIntervalMs != nil {
		minValue, maxValue := deriveProbeWindowFromLegacyPollInterval(*patch.PollIntervalMs)
		next.ProbeIntervalMinMs = ptr(minValue)
		next.ProbeIntervalMaxMs = ptr(maxValue)
	}
	if patch.ProbeIntervalMinMs != nil {
		next.ProbeIntervalMinMs = ptr(clampProbeIntervalMs(*patch.ProbeIntervalMinMs))
	}
	if patch.ProbeIntervalMaxMs != nil {
		next.ProbeIntervalMaxMs = ptr(clampProbeIntervalMs(*patch.ProbeIntervalMaxMs))
	}
	if patch.FiveHourDrainPercent != nil {
		value := clampPercentFloat(float64(*patch.FiveHourDrainPercent))
		next.FiveHourDrainPercent = ptr(value)
	}
	if patch.WeekDrainPercent != nil {
		value := clampPercentFloat(float64(*patch.WeekDrainPercent))
		next.WeekDrainPercent = ptr(value)
	}
	if patch.AutoSwitchStatuses != nil {
		next.AutoSwitchStatuses = normalizeAutoSwitchStatuses(patch.AutoSwitchStatuses)
	}
	return next, nil
}

func shouldAutoSwitch(summary ManagerSummary) autoSwitchDecision {
	if !summary.Automation.Enabled {
		return autoSwitchDecision{Reason: "Auto activation is disabled"}
	}
	if summary.RecommendedProfileName == nil {
		return autoSwitchDecision{Reason: "No healthy or draining profile available"}
	}
	var active *ManagedProfileSnapshot
	if summary.ActiveProfileName != nil {
		for idx := range summary.Profiles {
			if summary.Profiles[idx].Name == *summary.ActiveProfileName {
				active = &summary.Profiles[idx]
				break
			}
		}
	}
	if active == nil {
		return autoSwitchDecision{ShouldSwitch: true, Reason: "No active profile set", TargetProfileName: summary.RecommendedProfileName}
	}
	if *summary.RecommendedProfileName == active.Name {
		return autoSwitchDecision{Reason: "Active profile already matches recommendation"}
	}
	if !containsString(summary.Automation.AutoSwitchStatuses, active.Status) {
		return autoSwitchDecision{Reason: fmt.Sprintf("Active profile status %s is not in auto-switch list", active.Status)}
	}
	return autoSwitchDecision{
		ShouldSwitch:      true,
		Reason:            fmt.Sprintf("Active profile %s is %s; switching to %s", active.Name, active.Status, *summary.RecommendedProfileName),
		TargetProfileName: summary.RecommendedProfileName,
	}
}

type autoSwitchDecision struct {
	ShouldSwitch      bool
	Reason            string
	TargetProfileName *string
}

func (app *App) getManagerSummaryFromState(state NormalizedManagerState) (ManagerSummary, error) {
	if err := app.ensureDefaultProfileMirrorsActive(state.ActiveProfileName); err != nil {
		return ManagerSummary{}, err
	}

	profileNames, err := app.discoverProfileNames(state.ActiveProfileName)
	if err != nil {
		return ManagerSummary{}, err
	}

	type profileSnapshotResult struct {
		index    int
		snapshot ManagedProfileSnapshot
		err      error
	}

	results := make(chan profileSnapshotResult, len(profileNames))
	for idx, name := range profileNames {
		go func(index int, profileName string) {
			snapshot, err := app.readProfileSnapshot(profileName, state.Settings, false)
			results <- profileSnapshotResult{
				index:    index,
				snapshot: snapshot,
				err:      err,
			}
		}(idx, name)
	}

	snapshots := make([]ManagedProfileSnapshot, len(profileNames))
	for range profileNames {
		result := <-results
		if result.err != nil {
			return ManagerSummary{}, result.err
		}
		snapshots[result.index] = result.snapshot
	}

	recommended := pickRecommendedProfile(snapshots)
	for idx := range snapshots {
		snapshots[idx].IsActive = state.ActiveProfileName != nil && snapshots[idx].Name == *state.ActiveProfileName
		snapshots[idx].IsRecommended = recommended != nil && snapshots[idx].Name == *recommended
	}

	generatedAt := nowISO()
	return ManagerSummary{
		GeneratedAt:            generatedAt,
		ActiveProfileName:      state.ActiveProfileName,
		RecommendedProfileName: recommended,
		Automation:             buildAutomationSnapshot(state),
		Runtime:                app.buildRuntimeOverview(generatedAt, state, snapshots, recommended),
		Profiles:               snapshots,
	}, nil
}

func buildAutomationSnapshot(state NormalizedManagerState) AutomationSnapshot {
	return AutomationSnapshot{
		Enabled:                  state.Settings.AutoActivateEnabled,
		ProbeIntervalMinMs:       state.Settings.ProbeIntervalMinMs,
		ProbeIntervalMaxMs:       state.Settings.ProbeIntervalMaxMs,
		PollIntervalMs:           averageProbeIntervalMs(state.Settings),
		FiveHourDrainPercent:     state.Settings.FiveHourDrainPercent,
		WeekDrainPercent:         state.Settings.WeekDrainPercent,
		AutoSwitchStatuses:       append([]string(nil), state.Settings.AutoSwitchStatuses...),
		LastProbeAt:              state.Automation.LastProbeAt,
		NextProbeAt:              state.Automation.NextProbeAt,
		LastScheduledDelayMs:     state.Automation.LastScheduledDelayMs,
		LastAutoActivationAt:     state.Automation.LastAutoActivationAt,
		LastAutoActivationFrom:   state.Automation.LastAutoActivationFrom,
		LastAutoActivationTo:     state.Automation.LastAutoActivationTo,
		LastAutoActivationReason: state.Automation.LastAutoActivationReason,
		LastTickError:            state.Automation.LastTickError,
		WrapperCommand:           "npm run openclaw:managed -- ",
		CodexWrapperCommand:      "npm run codex:managed -- ",
	}
}

func (app *App) buildRuntimeOverview(generatedAt string, state NormalizedManagerState, profiles []ManagedProfileSnapshot, recommended *string) RuntimeOverview {
	healthy := 0
	draining := 0
	risky := 0
	for _, profile := range profiles {
		switch profile.Status {
		case "healthy":
			healthy++
		case "draining":
			draining++
		default:
			risky++
		}
	}

	apiBaseURL := ptr(fmt.Sprintf("http://%s:%d/api", app.host, app.port))
	app.mu.Lock()
	loopScheduled := app.automationTimer != nil
	loopRunning := app.automationRunning
	app.mu.Unlock()

	automation := buildAutomationSnapshot(state)
	return RuntimeOverview{
		GeneratedAt: generatedAt,
		Mode:        runtimeModeNative,
		Roots: RuntimeRoots{
			OpenclawHomeDir:         app.openclawHomeDir,
			CodexHomeDir:            app.codexHomeDir,
			ManagerDir:              app.managerDir,
			DefaultOpenClawStateDir: app.defaultOpenClawState,
			DefaultCodexHome:        app.defaultCodexHome,
			OAuthCallbackURL:        app.oauthRedirectURL,
			OAuthCallbackBindHost:   app.oauthCallbackBindHost,
		},
		Daemon: RuntimeDaemon{
			PID:                 os.Getpid(),
			Host:                app.host,
			Port:                ptr(app.port),
			APIBaseURL:          apiBaseURL,
			StartedAt:           app.startedAt.UTC().Format(time.RFC3339),
			UptimeMs:            int(time.Since(app.startedAt).Milliseconds()),
			ProbeIntervalMinMs:  state.Settings.ProbeIntervalMinMs,
			ProbeIntervalMaxMs:  state.Settings.ProbeIntervalMaxMs,
			PollIntervalMs:      averageProbeIntervalMs(state.Settings),
			NextProbeAt:         state.Automation.NextProbeAt,
			AutoActivateEnabled: state.Settings.AutoActivateEnabled,
			LoopScheduled:       loopScheduled,
			LoopRunning:         loopRunning,
		},
		Switching: RuntimeSwitching{
			ActiveProfileName:           state.ActiveProfileName,
			RecommendedProfileName:      recommended,
			TotalProfiles:               len(profiles),
			HealthyProfiles:             healthy,
			DrainingProfiles:            draining,
			RiskyProfiles:               risky,
			TotalActivations:            derefInt(state.Runtime.TotalActivations),
			ManualActivations:           derefInt(state.Runtime.ManualActivations),
			AutoActivations:             derefInt(state.Runtime.AutoActivations),
			RecommendedActivations:      derefInt(state.Runtime.RecommendedActivations),
			LastActivationAt:            state.Runtime.LastActivationAt,
			LastActivationDurationMs:    state.Runtime.LastActivationDurationMs,
			AverageActivationDurationMs: state.Runtime.AverageActivationDurationMs,
			LastActivationTrigger:       state.Runtime.LastActivationTrigger,
			LastActivationReason:        state.Runtime.LastActivationReason,
			LastSyncedAt:                state.Runtime.LastSyncedAt,
		},
		Compatibility: RuntimeCompatibility{
			AllowedOrigins:         getAllowedWebOrigins(),
			AllowLocalhostDev:      true,
			BrowserShellSupported:  true,
			NativeShellRecommended: runtime.GOOS == "darwin",
			WrapperCommand:         automation.WrapperCommand,
			CodexWrapperCommand:    automation.CodexWrapperCommand,
		},
	}
}

func (app *App) discoverProfileNames(activeProfileName *string) ([]string, error) {
	discovered, err := app.discoverStateDirs()
	if err != nil {
		return nil, err
	}
	set := map[string]struct{}{}
	for name := range discovered {
		set[name] = struct{}{}
	}
	if activeProfileName != nil {
		set[*activeProfileName] = struct{}{}
	}
	if len(set) == 0 {
		set[defaultProfileName] = struct{}{}
	}
	names := make([]string, 0, len(set))
	for name := range set {
		names = append(names, name)
	}
	sort.Slice(names, func(i, j int) bool {
		return profileSortKey(names[i]) < profileSortKey(names[j])
	})
	return names, nil
}

func cloneStringMap(input map[string]string) map[string]string {
	cloned := make(map[string]string, len(input))
	for key, value := range input {
		cloned[key] = value
	}
	return cloned
}

func cloneSupportEvents(input []SupportLogEvent) []SupportLogEvent {
	if len(input) == 0 {
		return nil
	}
	cloned := make([]SupportLogEvent, len(input))
	copy(cloned, input)
	return cloned
}

func (app *App) invalidateStateDirCache() {
	app.mu.Lock()
	defer app.mu.Unlock()
	app.stateDirCache = map[string]string{}
	app.stateDirCacheAt = time.Time{}
}

func (app *App) invalidateSupportCaches() {
	app.mu.Lock()
	defer app.mu.Unlock()
	app.supportSummaryCache = nil
	app.supportGatewayCache = nil
	app.supportEventsCache = nil
	app.supportEnvironmentCache = nil
	app.supportMaintenanceCache = nil
}

func (app *App) discoverStateDirs() (map[string]string, error) {
	app.mu.Lock()
	if len(app.stateDirCache) > 0 && time.Since(app.stateDirCacheAt) <= stateDirCacheTTL {
		cached := cloneStringMap(app.stateDirCache)
		app.mu.Unlock()
		return cached, nil
	}
	app.mu.Unlock()

	found := map[string]string{}
	if pathExists(app.defaultOpenClawState) {
		found[defaultProfileName] = app.defaultOpenClawState
	}
	app.walkForStateDirs(app.openclawHomeDir, 0, found)

	app.mu.Lock()
	app.stateDirCache = cloneStringMap(found)
	app.stateDirCacheAt = time.Now()
	app.mu.Unlock()

	return found, nil
}

func (app *App) walkForStateDirs(root string, depth int, found map[string]string) {
	entries, err := os.ReadDir(root)
	if err != nil {
		return
	}
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		name := entry.Name()
		fullPath := filepath.Join(root, name)
		if profileName := profileNameFromStateDirName(name); profileName != "" {
			found[profileName] = preferDiscoveredStateDir(found[profileName], fullPath)
			continue
		}
		if depth >= openclawDiscoveryMaxDepth || shouldSkipDiscoveryDir(name) {
			continue
		}
		app.walkForStateDirs(fullPath, depth+1, found)
	}
}

func (app *App) resolveStateDir(profileName string) (string, error) {
	discovered, err := app.discoverStateDirs()
	if err != nil {
		return "", err
	}
	if value, ok := discovered[profileName]; ok {
		return value, nil
	}
	return expectedStateDir(profileName, app.openclawHomeDir), nil
}

func (app *App) resolveStateDirForCreate(profileName string) (string, error) {
	discovered, err := app.discoverStateDirs()
	if err != nil {
		return "", err
	}
	rootDir := app.openclawHomeDir
	if defaultState, ok := discovered[defaultProfileName]; ok {
		rootDir = filepath.Dir(defaultState)
	}
	return expectedStateDir(profileName, rootDir), nil
}

func (app *App) resolveAuthStorePath(profileName string) (string, error) {
	stateDir, err := app.resolveStateDir(profileName)
	if err != nil {
		return "", err
	}
	return filepath.Join(stateDir, "agents", "main", "agent", "auth-profiles.json"), nil
}

func (app *App) resolveConfigPath(profileName string) (string, error) {
	stateDir, err := app.resolveStateDir(profileName)
	if err != nil {
		return "", err
	}
	return filepath.Join(stateDir, "openclaw.json"), nil
}

func expectedStateDir(profileName, rootDir string) string {
	if profileName == defaultProfileName {
		return filepath.Join(rootDir, ".openclaw")
	}
	return filepath.Join(rootDir, ".openclaw-"+profileName)
}

func resolveCodexHome(profileName, codexHomeRoot string) string {
	if profileName == defaultProfileName {
		return filepath.Join(codexHomeRoot, ".codex")
	}
	return filepath.Join(codexHomeRoot, ".codex-"+profileName)
}

func resolveCodexAuthPath(profileName, codexHomeRoot string) string {
	return filepath.Join(resolveCodexHome(profileName, codexHomeRoot), "auth.json")
}

func resolveCodexConfigPath(profileName, codexHomeRoot string) string {
	return filepath.Join(resolveCodexHome(profileName, codexHomeRoot), "config.toml")
}

func usageCacheKey(profileName string, tokens OAuthTokens) string {
	accountID := strings.TrimSpace(tokens.AccountID)
	if accountID == "" {
		accountID = "unknown"
	}
	return profileName + "|" + accountID
}

func (app *App) loadCachedUsage(profileName string, tokens OAuthTokens, maxAge time.Duration) (UsageSnapshot, bool) {
	key := usageCacheKey(profileName, tokens)
	app.mu.Lock()
	cached, ok := app.usageCache[key]
	app.mu.Unlock()
	if !ok || time.Since(cached.FetchedAt) > maxAge {
		return UsageSnapshot{}, false
	}
	return cached.Quota, true
}

func (app *App) storeCachedUsage(profileName string, tokens OAuthTokens, quota UsageSnapshot) {
	key := usageCacheKey(profileName, tokens)
	app.mu.Lock()
	app.usageCache[key] = cachedUsageSnapshot{
		Quota:     quota,
		FetchedAt: time.Now(),
	}
	app.mu.Unlock()
}

func readOpenClawConfigSnapshot(configPath string) OpenClawConfigSnapshot {
	snapshot := OpenClawConfigSnapshot{
		ConfiguredProviderIDs: []string{},
		AuthModes:             map[string]string{},
	}
	if !pathExists(configPath) {
		return snapshot
	}

	file := readJSONFile(configPath, OpenClawConfigFile{})
	if primaryModel := strings.TrimSpace(file.Agents.Defaults.Model.Primary); primaryModel != "" {
		snapshot.PrimaryModelID = ptr(primaryModel)
		snapshot.PrimaryProviderID = providerIDFromModelID(primaryModel)
	}

	providerSet := map[string]struct{}{}
	if snapshot.PrimaryProviderID != nil {
		providerSet[*snapshot.PrimaryProviderID] = struct{}{}
	}
	for _, authProfile := range file.Auth.Profiles {
		providerID := strings.TrimSpace(authProfile.Provider)
		if providerID == "" {
			continue
		}
		providerSet[providerID] = struct{}{}
		if mode := strings.TrimSpace(authProfile.Mode); mode != "" {
			snapshot.AuthModes[providerID] = mode
		}
	}

	configured := make([]string, 0, len(providerSet))
	for providerID := range providerSet {
		configured = append(configured, providerID)
	}
	sort.Strings(configured)
	snapshot.ConfiguredProviderIDs = configured
	return snapshot
}

func providerIDFromModelID(modelID string) *string {
	modelID = strings.TrimSpace(modelID)
	if modelID == "" {
		return nil
	}
	parts := strings.SplitN(modelID, "/", 2)
	if len(parts) != 2 || strings.TrimSpace(parts[0]) == "" {
		return nil
	}
	return ptr(strings.TrimSpace(parts[0]))
}

func providerDisplayName(providerID string) string {
	switch strings.TrimSpace(providerID) {
	case "openai-codex":
		return "Codex"
	case "openai":
		return "OpenAI"
	case "anthropic":
		return "Anthropic"
	case "openrouter":
		return "OpenRouter"
	case "ollama":
		return "Ollama"
	case "gemini", "google":
		return "Gemini"
	default:
		if providerID == "" {
			return "未配置"
		}
		return providerID
	}
}

func providerUsesLocalRuntime(providerID string) bool {
	switch strings.TrimSpace(providerID) {
	case "ollama":
		return true
	default:
		return false
	}
}

func authStoreHasProvider(store AuthStore, providerID string) bool {
	providerID = strings.TrimSpace(providerID)
	if providerID == "" {
		return false
	}
	for _, credential := range store.Profiles {
		if oauth := oauthCredentialFromMap(credential); oauth != nil && oauth.Provider == providerID {
			return true
		}
		if strings.TrimSpace(anyString(credential["provider"])) == providerID {
			return true
		}
	}
	return false
}

func profileLoginKind(config OpenClawConfigSnapshot) *string {
	if config.PrimaryProviderID == nil {
		if config.PrimaryModelID == nil && len(config.ConfiguredProviderIDs) == 0 {
			return ptr("codex-oauth")
		}
		if containsString(config.ConfiguredProviderIDs, "openai-codex") {
			return ptr("codex-oauth")
		}
		return nil
	}
	if *config.PrimaryProviderID == "openai-codex" {
		return ptr("codex-oauth")
	}
	return nil
}

func companionRuntimeKind(config OpenClawConfigSnapshot, codex CodexMetadataSnapshot) *string {
	if codex.HasCodexAuth || codex.HasCodexConfig {
		return ptr("codex")
	}
	if containsString(config.ConfiguredProviderIDs, "openai-codex") {
		return ptr("codex")
	}
	if config.PrimaryProviderID != nil && *config.PrimaryProviderID == "openai-codex" {
		return ptr("codex")
	}
	return nil
}

func resolveAuthMode(config OpenClawConfigSnapshot) string {
	if config.PrimaryProviderID != nil {
		if mode := strings.TrimSpace(config.AuthModes[*config.PrimaryProviderID]); mode != "" {
			return mode
		}
		if *config.PrimaryProviderID == "openai-codex" {
			return "chatgpt-oauth"
		}
	}
	return "configured"
}

func classifyGenericProfileStatus(config OpenClawConfigSnapshot, store AuthStore, hasConfig bool) (string, string) {
	if config.PrimaryProviderID == nil {
		if len(config.ConfiguredProviderIDs) > 0 {
			return "unknown", "已配置 provider，当前不探测额度"
		}
		if hasConfig {
			return "unknown", "未识别当前模型 provider"
		}
		return "reauth_required", "未发现可用 provider"
	}

	providerID := *config.PrimaryProviderID
	label := providerDisplayName(providerID)
	if providerUsesLocalRuntime(providerID) {
		return "healthy", label + " 已配置"
	}
	if authStoreHasProvider(store, providerID) {
		return "healthy", label + " 已配置"
	}
	if mode := strings.TrimSpace(config.AuthModes[providerID]); mode != "" {
		return "healthy", label + " 已配置"
	}
	if hasConfig {
		return "unknown", label + " 已配置，当前不探测额度"
	}
	return "reauth_required", label + " 未配置"
}

func (app *App) ensureProfileScaffold(profileName string) error {
	stateDir, err := app.resolveStateDirForCreate(profileName)
	if err != nil {
		return err
	}
	configPath := filepath.Join(stateDir, "openclaw.json")
	authStorePath := filepath.Join(stateDir, "agents", "main", "agent", "auth-profiles.json")

	if err := ensureDir(filepath.Dir(authStorePath)); err != nil {
		return err
	}
	if err := app.ensureCodexProfileScaffold(profileName); err != nil {
		return err
	}

	if !pathExists(configPath) {
		defaultConfigPath, err := app.resolveConfigPath(defaultProfileName)
		if err != nil {
			return err
		}
		if profileName != defaultProfileName && pathExists(defaultConfigPath) {
			if err := ensureDir(filepath.Dir(configPath)); err != nil {
				return err
			}
			if err := copyFile(defaultConfigPath, configPath); err != nil {
				return err
			}
		} else if err := writeJSONFile(configPath, buildMinimalConfig()); err != nil {
			return err
		}
	}

	if !pathExists(authStorePath) {
		if err := writeJSONFile(authStorePath, defaultAuthStore()); err != nil {
			return err
		}
	}

	if err := ensureDir(filepath.Join(stateDir, "agents", "main", "agent")); err != nil {
		return err
	}
	app.invalidateStateDirCache()
	return nil
}

func buildMinimalConfig() map[string]any {
	return map[string]any{
		"meta": map[string]any{
			"managedBy": "codex-pool-management",
			"createdAt": nowISO(),
		},
		"auth": map[string]any{
			"profiles": map[string]any{},
		},
		"agents": map[string]any{
			"defaults": map[string]any{},
		},
	}
}

func defaultAuthStore() AuthStore {
	return AuthStore{
		Version:    1,
		Profiles:   map[string]map[string]any{},
		LastGood:   map[string]string{},
		UsageStats: map[string]map[string]any{},
	}
}

func (app *App) ensureCodexProfileScaffold(profileName string) error {
	codexHome := resolveCodexHome(profileName, app.codexHomeDir)
	configPath := resolveCodexConfigPath(profileName, app.codexHomeDir)
	if err := ensureDir(codexHome); err != nil {
		return err
	}
	if pathExists(configPath) {
		return nil
	}
	defaultConfigPath := resolveCodexConfigPath(defaultProfileName, app.codexHomeDir)
	if profileName != defaultProfileName && pathExists(defaultConfigPath) {
		return copyFile(defaultConfigPath, configPath)
	}
	return writeTextFile(configPath, buildMinimalCodexConfig())
}

func buildMinimalCodexConfig() string {
	return "# Managed by codex-pool-management\n"
}

func buildCodexAuthFile(tokens OAuthTokens) (CodexAuthFile, error) {
	if strings.TrimSpace(tokens.IDToken) == "" {
		return CodexAuthFile{}, errors.New("id_token_missing_for_codex_auth")
	}
	var file CodexAuthFile
	file.AuthMode = "chatgpt"
	file.OpenAIAPIKey = nil
	file.Tokens.IDToken = tokens.IDToken
	file.Tokens.AccessToken = tokens.Access
	file.Tokens.RefreshToken = tokens.Refresh
	file.Tokens.AccountID = tokens.AccountID
	file.LastRefresh = nowISO()
	return file, nil
}

func (app *App) saveCodexAuth(profileName string, tokens OAuthTokens) error {
	if err := app.ensureCodexProfileScaffold(profileName); err != nil {
		return err
	}
	file, err := buildCodexAuthFile(tokens)
	if err != nil {
		return err
	}
	return writeJSONFile(resolveCodexAuthPath(profileName, app.codexHomeDir), file)
}

func (app *App) readCodexMetadata(profileName string) CodexMetadataSnapshot {
	codexHome := resolveCodexHome(profileName, app.codexHomeDir)
	codexConfigPath := resolveCodexConfigPath(profileName, app.codexHomeDir)
	codexAuthPath := resolveCodexAuthPath(profileName, app.codexHomeDir)
	hasCodexConfig := pathExists(codexConfigPath)
	hasCodexAuth := pathExists(codexAuthPath)

	var authMode *string
	var accountID *string
	var lastRefresh *string
	if hasCodexAuth {
		file := readJSONFile(codexAuthPath, CodexAuthFile{})
		if strings.TrimSpace(file.AuthMode) != "" {
			authMode = ptr(file.AuthMode)
		}
		if strings.TrimSpace(file.LastRefresh) != "" {
			lastRefresh = ptr(file.LastRefresh)
		}
		if strings.TrimSpace(file.Tokens.AccountID) != "" {
			accountID = ptr(file.Tokens.AccountID)
		}
	}

	return CodexMetadataSnapshot{
		CodexHome:          codexHome,
		CodexConfigPath:    codexConfigPath,
		CodexAuthPath:      codexAuthPath,
		HasCodexConfig:     hasCodexConfig,
		HasCodexAuth:       hasCodexAuth,
		CodexAuthMode:      authMode,
		CodexAccountID:     accountID,
		CodexLastRefreshAt: lastRefresh,
	}
}

func (app *App) loadAuthStore(profileName string) (AuthStore, error) {
	authStorePath, err := app.resolveAuthStorePath(profileName)
	if err != nil {
		return AuthStore{}, err
	}
	store := readJSONFile(authStorePath, defaultAuthStore())
	if store.Version == 0 {
		store.Version = 1
	}
	if store.Profiles == nil {
		store.Profiles = map[string]map[string]any{}
	}
	if store.LastGood == nil {
		store.LastGood = map[string]string{}
	}
	if store.UsageStats == nil {
		store.UsageStats = map[string]map[string]any{}
	}
	return store, nil
}

func (app *App) saveAuthStore(profileName string, store AuthStore) error {
	authStorePath, err := app.resolveAuthStorePath(profileName)
	if err != nil {
		return err
	}
	return writeJSONFile(authStorePath, store)
}

func oauthCredentialFromMap(value map[string]any) *OAuthCredential {
	if value == nil {
		return nil
	}
	credential := &OAuthCredential{
		Type:      anyString(value["type"]),
		Provider:  anyString(value["provider"]),
		Access:    anyString(value["access"]),
		Refresh:   anyString(value["refresh"]),
		AccountID: anyString(value["accountId"]),
	}
	if expires, ok := anyInt64(value["expires"]); ok {
		credential.Expires = expires
	}
	return credential
}

func upsertOpenAICodexCredential(store *AuthStore, profileID string, tokens OAuthTokens) {
	if store.Version == 0 {
		store.Version = 1
	}
	if store.Profiles == nil {
		store.Profiles = map[string]map[string]any{}
	}
	store.Profiles[profileID] = map[string]any{
		"type":      "oauth",
		"provider":  "openai-codex",
		"access":    tokens.Access,
		"refresh":   tokens.Refresh,
		"expires":   tokens.Expires,
		"accountId": tokens.AccountID,
	}
	if store.LastGood == nil {
		store.LastGood = map[string]string{}
	}
	store.LastGood["openai-codex"] = profileID
	if store.UsageStats == nil {
		store.UsageStats = map[string]map[string]any{}
	}
	store.UsageStats[profileID] = map[string]any{
		"errorCount": 0,
		"lastUsed":   time.Now().UnixMilli(),
	}
}

func pickCodexProfileID(store AuthStore) *string {
	if preferred := strings.TrimSpace(store.LastGood["openai-codex"]); preferred != "" {
		if credential := oauthCredentialFromMap(store.Profiles[preferred]); credential != nil && credential.Provider == "openai-codex" && credential.Type == "oauth" {
			return ptr(preferred)
		}
	}
	keys := make([]string, 0, len(store.Profiles))
	for key := range store.Profiles {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		if credential := oauthCredentialFromMap(store.Profiles[key]); credential != nil && credential.Provider == "openai-codex" && credential.Type == "oauth" {
			return ptr(key)
		}
	}
	return nil
}

func (app *App) materializeCodexAuthIfMissing(profileName, profileID string, store *AuthStore, credential OAuthCredential, tokens OAuthTokens) (OAuthTokens, error) {
	codexAuthPath := resolveCodexAuthPath(profileName, app.codexHomeDir)
	if strings.TrimSpace(tokens.IDToken) != "" {
		if err := app.saveCodexAuth(profileName, tokens); err != nil {
			return tokens, err
		}
		return tokens, nil
	}
	if pathExists(codexAuthPath) || strings.TrimSpace(credential.Refresh) == "" {
		return tokens, nil
	}
	refreshed, err := app.refreshCodexTokens(credential.Refresh)
	if err != nil {
		return tokens, err
	}
	upsertOpenAICodexCredential(store, profileID, refreshed)
	if err := app.saveAuthStore(profileName, *store); err != nil {
		return tokens, err
	}
	if err := app.saveCodexAuth(profileName, refreshed); err != nil {
		return tokens, err
	}
	return refreshed, nil
}

func buildEmptyUsage() UsageSnapshot {
	return UsageSnapshot{}
}

func (app *App) readProfileSnapshot(profileName string, settings ManagerSettings, forceUsageRefresh bool) (ManagedProfileSnapshot, error) {
	stateDir, err := app.resolveStateDir(profileName)
	if err != nil {
		return ManagedProfileSnapshot{}, err
	}
	authStorePath, err := app.resolveAuthStorePath(profileName)
	if err != nil {
		return ManagedProfileSnapshot{}, err
	}
	configPath, err := app.resolveConfigPath(profileName)
	if err != nil {
		return ManagedProfileSnapshot{}, err
	}
	codex := app.readCodexMetadata(profileName)
	hasConfig := pathExists(configPath)
	hasAuthStore := pathExists(authStorePath)
	config := readOpenClawConfigSnapshot(configPath)
	authMode := resolveAuthMode(config)
	loginKind := profileLoginKind(config)
	companionKind := companionRuntimeKind(config, codex)

	store := defaultAuthStore()
	if hasAuthStore {
		store, err = app.loadAuthStore(profileName)
		if err != nil {
			return ManagedProfileSnapshot{}, err
		}
	}

	baseSnapshot := func() ManagedProfileSnapshot {
		return ManagedProfileSnapshot{
			Name:                  profileName,
			IsDefault:             profileName == defaultProfileName,
			StateDir:              stateDir,
			AuthStorePath:         authStorePath,
			HasConfig:             hasConfig,
			HasAuthStore:          hasAuthStore,
			AuthMode:              authMode,
			PrimaryProviderID:     config.PrimaryProviderID,
			PrimaryModelID:        config.PrimaryModelID,
			ConfiguredProviderIDs: append([]string{}, config.ConfiguredProviderIDs...),
			SupportsQuota:         false,
			SupportsLogin:         loginKind != nil,
			LoginKind:             loginKind,
			CompanionRuntimeKind:  companionKind,
			CodexHome:             codex.CodexHome,
			CodexConfigPath:       codex.CodexConfigPath,
			CodexAuthPath:         codex.CodexAuthPath,
			HasCodexConfig:        codex.HasCodexConfig,
			HasCodexAuth:          codex.HasCodexAuth,
			CodexAuthMode:         codex.CodexAuthMode,
			CodexAccountID:        codex.CodexAccountID,
			CodexLastRefreshAt:    codex.CodexLastRefreshAt,
			Quota:                 buildEmptyUsage(),
		}
	}

	profileID := pickCodexProfileID(store)
	isCodexPrimary := config.PrimaryProviderID != nil && *config.PrimaryProviderID == "openai-codex"
	if isCodexPrimary && (!hasAuthStore || profileID == nil) {
		snapshot := baseSnapshot()
		snapshot.Status = "reauth_required"
		if hasAuthStore {
			snapshot.StatusReason = "未找到 Codex 认证"
		} else {
			snapshot.StatusReason = "未找到认证信息"
		}
		return snapshot, nil
	}
	if profileID == nil && !isCodexPrimary {
		snapshot := baseSnapshot()
		snapshot.Status, snapshot.StatusReason = classifyGenericProfileStatus(config, store, hasConfig)
		return snapshot, nil
	}

	credential := oauthCredentialFromMap(store.Profiles[*profileID])
	if credential == nil || credential.Provider != "openai-codex" || credential.Type != "oauth" {
		snapshot := baseSnapshot()
		if isCodexPrimary {
			snapshot.Status = "reauth_required"
			snapshot.StatusReason = "未找到 Codex 认证"
		} else {
			snapshot.Status, snapshot.StatusReason = classifyGenericProfileStatus(config, store, hasConfig)
		}
		return snapshot, nil
	}

	accountID := credential.AccountID
	if accountID == "" {
		accountID = extractAccountID(credential.Access)
	}
	tokens := OAuthTokens{
		Access:    credential.Access,
		Refresh:   credential.Refresh,
		Expires:   credential.Expires,
		AccountID: accountID,
		Email:     extractEmail(credential.Access),
	}

	var lastError *string
	authBroken := false
	refreshIfNeeded := func() error {
		if strings.TrimSpace(credential.Refresh) == "" {
			return nil
		}
		if credential.Expires > time.Now().Add(refreshSkew).UnixMilli() {
			return nil
		}
		refreshed, err := app.refreshCodexTokens(credential.Refresh)
		if err != nil {
			return err
		}
		tokens = refreshed
		upsertOpenAICodexCredential(&store, *profileID, refreshed)
		if err := app.saveAuthStore(profileName, store); err != nil {
			return err
		}
		return app.saveCodexAuth(profileName, refreshed)
	}

	if err := refreshIfNeeded(); err != nil {
		authBroken = true
		lastError = ptr(err.Error())
	} else if hydrated, err := app.materializeCodexAuthIfMissing(profileName, *profileID, &store, *credential, tokens); err != nil {
		authBroken = true
		lastError = ptr(err.Error())
	} else {
		tokens = hydrated
	}

	quota := buildEmptyUsage()
	if !authBroken {
		if !forceUsageRefresh {
			if cached, ok := app.loadCachedUsage(profileName, tokens, usageCacheTTL); ok {
				quota = cached
			}
		}

		if quota.FiveHour == nil && quota.Week == nil {
			fetched, err := app.fetchCodexUsage(tokens)
			if err != nil {
				message := err.Error()
				lastError = &message
				if cached, ok := app.loadCachedUsage(profileName, tokens, staleUsageCacheTTL); ok {
					quota = cached
				}
				if strings.Contains(message, "usage_failed 401") || strings.Contains(message, "usage_failed 403") {
					if strings.TrimSpace(credential.Refresh) != "" {
						refreshed, refreshErr := app.refreshCodexTokens(credential.Refresh)
						if refreshErr != nil {
							authBroken = true
							lastError = ptr(refreshErr.Error())
						} else {
							tokens = refreshed
							upsertOpenAICodexCredential(&store, *profileID, refreshed)
							if err := app.saveAuthStore(profileName, store); err != nil {
								return ManagedProfileSnapshot{}, err
							}
							if err := app.saveCodexAuth(profileName, refreshed); err != nil {
								return ManagedProfileSnapshot{}, err
							}
							if retried, retryErr := app.fetchCodexUsage(tokens); retryErr != nil {
								authBroken = true
								lastError = ptr(retryErr.Error())
							} else {
								quota = retried
								app.storeCachedUsage(profileName, tokens, retried)
								lastError = nil
							}
						}
					} else {
						authBroken = true
					}
				}
			} else {
				quota = fetched
				app.storeCachedUsage(profileName, tokens, fetched)
			}
		}
	}

	status, statusReason := classifyProfileStatus(quota, true, authBroken, settings)
	tokenExpiresAt := nullableTimeFromMillis(tokens.Expires)
	tokenExpiresInMs := nullableDurationUntilMillis(tokens.Expires)
	codex = app.readCodexMetadata(profileName)

	return ManagedProfileSnapshot{
		Name:                  profileName,
		IsDefault:             profileName == defaultProfileName,
		StateDir:              stateDir,
		AuthStorePath:         authStorePath,
		HasConfig:             hasConfig,
		HasAuthStore:          hasAuthStore,
		AuthMode:              "chatgpt-oauth",
		ProfileID:             profileID,
		AccountEmail:          nullableString(tokens.Email),
		AccountID:             nullableString(tokens.AccountID),
		PrimaryProviderID:     config.PrimaryProviderID,
		PrimaryModelID:        config.PrimaryModelID,
		ConfiguredProviderIDs: append([]string{}, config.ConfiguredProviderIDs...),
		SupportsQuota:         true,
		SupportsLogin:         loginKind != nil,
		LoginKind:             loginKind,
		CompanionRuntimeKind:  companionKind,
		CodexHome:             codex.CodexHome,
		CodexConfigPath:       codex.CodexConfigPath,
		CodexAuthPath:         codex.CodexAuthPath,
		HasCodexConfig:        codex.HasCodexConfig,
		HasCodexAuth:          codex.HasCodexAuth,
		CodexAuthMode:         codex.CodexAuthMode,
		CodexAccountID:        codex.CodexAccountID,
		CodexLastRefreshAt:    codex.CodexLastRefreshAt,
		TokenExpiresAt:        tokenExpiresAt,
		TokenExpiresInMs:      tokenExpiresInMs,
		Status:                status,
		StatusReason:          statusReason,
		Quota:                 quota,
		LastError:             lastError,
	}, nil
}

func classifyProfileStatus(quota UsageSnapshot, hasAuth, authBroken bool, settings ManagerSettings) (string, string) {
	if !hasAuth || authBroken {
		if hasAuth {
			return "reauth_required", "认证失效，需重新登录"
		}
		return "reauth_required", "未找到认证信息"
	}
	var fiveHourLeft *int
	if quota.FiveHour != nil {
		fiveHourLeft = ptr(quota.FiveHour.LeftPercent)
	}
	var weekLeft *int
	if quota.Week != nil {
		weekLeft = ptr(quota.Week.LeftPercent)
	}
	if weekLeft != nil && *weekLeft <= 0 {
		return "exhausted", "周额度已耗尽"
	}
	if fiveHourLeft != nil && *fiveHourLeft <= 0 {
		return "cooldown", "5 小时额度已耗尽"
	}
	if (fiveHourLeft != nil && *fiveHourLeft <= settings.FiveHourDrainPercent) || (weekLeft != nil && *weekLeft <= settings.WeekDrainPercent) {
		return "draining", "额度偏低，建议切换"
	}
	if fiveHourLeft != nil || weekLeft != nil {
		return "healthy", "额度可用"
	}
	return "unknown", "未返回额度窗口"
}

func pickRecommendedProfile(profiles []ManagedProfileSnapshot) *string {
	candidates := make([]ManagedProfileSnapshot, 0)
	for _, profile := range profiles {
		if profile.Status == "healthy" || profile.Status == "draining" {
			candidates = append(candidates, profile)
		}
	}
	if len(candidates) == 0 {
		return nil
	}
	deduped := map[string]ManagedProfileSnapshot{}
	for _, candidate := range candidates {
		key := "profile:" + candidate.Name
		if candidate.AccountID != nil {
			key = *candidate.AccountID
		}
		existing, ok := deduped[key]
		if !ok {
			deduped[key] = candidate
			continue
		}
		if existing.IsDefault && !candidate.IsDefault {
			deduped[key] = candidate
			continue
		}
		if scoreProfile(candidate) > scoreProfile(existing) {
			deduped[key] = candidate
		}
	}
	unique := make([]ManagedProfileSnapshot, 0, len(deduped))
	for _, value := range deduped {
		unique = append(unique, value)
	}
	sort.Slice(unique, func(i, j int) bool {
		scoreDiff := scoreProfile(unique[j]) - scoreProfile(unique[i])
		if math.Abs(scoreDiff) > 0.0001 {
			return scoreDiff < 0
		}
		return profileSortKey(unique[i].Name) < profileSortKey(unique[j].Name)
	})
	return ptr(unique[0].Name)
}

func scoreProfile(profile ManagedProfileSnapshot) float64 {
	fiveHour := -1
	if profile.Quota.FiveHour != nil {
		fiveHour = profile.Quota.FiveHour.LeftPercent
	}
	week := -1
	if profile.Quota.Week != nil {
		week = profile.Quota.Week.LeftPercent
	}
	base := math.Max(0, float64(fiveHour))*0.65 + math.Max(0, float64(week))*0.35
	switch profile.Status {
	case "healthy":
		return base + 1000
	case "draining":
		return base + 500
	case "cooldown":
		return base + 100
	default:
		return base
	}
}

func (app *App) syncProfileToDefault(profileName string) error {
	if profileName == defaultProfileName {
		return nil
	}
	if err := app.ensureProfileScaffold(defaultProfileName); err != nil {
		return err
	}

	sourceStore, err := app.loadAuthStore(profileName)
	if err != nil {
		return err
	}
	targetStore, err := app.loadAuthStore(defaultProfileName)
	if err != nil {
		return err
	}
	profileID := pickCodexProfileID(sourceStore)
	nextStore := sourceStore
	nextStore.Version = max(sourceStore.Version, targetStore.Version)

	targetPath, err := app.resolveAuthStorePath(defaultProfileName)
	if err != nil {
		return err
	}
	currentData, _ := json.MarshalIndent(targetStore, "", "  ")
	nextData, _ := json.MarshalIndent(nextStore, "", "  ")
	if !bytes.Equal(currentData, nextData) {
		_ = app.backupFile(targetPath, "default-auth-store")
		if err := app.saveAuthStore(defaultProfileName, nextStore); err != nil {
			return err
		}
	}

	sourceConfigPath, err := app.resolveConfigPath(profileName)
	if err != nil {
		return err
	}
	defaultConfigPath, err := app.resolveConfigPath(defaultProfileName)
	if err != nil {
		return err
	}
	if err := app.copyFileIfDifferent(sourceConfigPath, defaultConfigPath, "default-openclaw-config"); err != nil {
		return err
	}

	if profileID == nil {
		return nil
	}

	sourceCredential := oauthCredentialFromMap(sourceStore.Profiles[*profileID])
	if sourceCredential != nil && sourceCredential.Provider == "openai-codex" && sourceCredential.Type == "oauth" {
		sourceTokens := OAuthTokens{
			Access:    sourceCredential.Access,
			Refresh:   sourceCredential.Refresh,
			Expires:   sourceCredential.Expires,
			AccountID: firstNonEmpty(sourceCredential.AccountID, extractAccountID(sourceCredential.Access)),
			Email:     extractEmail(sourceCredential.Access),
		}
		hydrated, err := app.materializeCodexAuthIfMissing(profileName, *profileID, &sourceStore, *sourceCredential, sourceTokens)
		if err != nil {
			return err
		}
		sourceTokens = hydrated
		sourceCodexAuthPath := resolveCodexAuthPath(profileName, app.codexHomeDir)
		defaultCodexAuthPath := resolveCodexAuthPath(defaultProfileName, app.codexHomeDir)
		if err := app.ensureCodexProfileScaffold(defaultProfileName); err != nil {
			return err
		}
		if !pathExists(sourceCodexAuthPath) {
			if strings.TrimSpace(sourceTokens.IDToken) == "" {
				return errors.New("source profile has no Codex auth file to sync")
			}
			if err := app.saveCodexAuth(profileName, sourceTokens); err != nil {
				return err
			}
		}
		if err := app.copyFileIfDifferent(sourceCodexAuthPath, defaultCodexAuthPath, "default-codex-auth"); err != nil {
			return err
		}

		sourceCodexConfigPath := resolveCodexConfigPath(profileName, app.codexHomeDir)
		defaultCodexConfigPath := resolveCodexConfigPath(defaultProfileName, app.codexHomeDir)
		if !pathExists(defaultCodexConfigPath) && pathExists(sourceCodexConfigPath) {
			if err := ensureDir(filepath.Dir(defaultCodexConfigPath)); err != nil {
				return err
			}
			if err := copyFile(sourceCodexConfigPath, defaultCodexConfigPath); err != nil {
				return err
			}
		}
	}
	return nil
}

func (app *App) ensureDefaultProfileMirrorsActive(activeProfileName *string) error {
	if activeProfileName == nil || *activeProfileName == defaultProfileName {
		return nil
	}
	return app.syncProfileToDefault(*activeProfileName)
}

func (app *App) backupFile(sourcePath, label string) error {
	if !pathExists(sourcePath) {
		return nil
	}
	if err := ensureDir(app.backupDir); err != nil {
		return err
	}
	stamp := strings.ReplaceAll(time.Now().UTC().Format("20060102T150405"), ":", "")
	destination := filepath.Join(app.backupDir, fmt.Sprintf("%s.%s.json", label, stamp))
	return copyFile(sourcePath, destination)
}

func (app *App) copyFileIfDifferent(sourcePath, targetPath, backupLabel string) error {
	if !pathExists(sourcePath) {
		return nil
	}
	sourceBuffer, err := os.ReadFile(sourcePath)
	if err != nil {
		return err
	}
	targetBuffer, err := os.ReadFile(targetPath)
	if err == nil && bytes.Equal(sourceBuffer, targetBuffer) {
		return nil
	}
	if backupLabel != "" && pathExists(targetPath) {
		_ = app.backupFile(targetPath, backupLabel)
	}
	if err := ensureDir(filepath.Dir(targetPath)); err != nil {
		return err
	}
	return os.WriteFile(targetPath, sourceBuffer, 0o600)
}

func (app *App) refreshCodexTokens(refreshToken string) (OAuthTokens, error) {
	form := url.Values{
		"grant_type":    {"refresh_token"},
		"refresh_token": {refreshToken},
		"client_id":     {openAIClientID},
	}
	payload, err := postTokenRequest(form)
	if err != nil {
		return OAuthTokens{}, err
	}
	accountID := extractAccountID(payload.AccessToken)
	if accountID == "" {
		return OAuthTokens{}, errors.New("refresh_account_id_missing")
	}
	return OAuthTokens{
		Access:    payload.AccessToken,
		Refresh:   payload.RefreshToken,
		IDToken:   payload.IDToken,
		Expires:   time.Now().Add(time.Duration(payload.ExpiresIn) * time.Second).UnixMilli(),
		AccountID: accountID,
		Email:     extractEmail(payload.AccessToken),
	}, nil
}

func (app *App) exchangeAuthorizationCode(code, verifier string) (OAuthTokens, error) {
	form := url.Values{
		"grant_type":    {"authorization_code"},
		"client_id":     {openAIClientID},
		"code":          {code},
		"code_verifier": {verifier},
		"redirect_uri":  {app.oauthRedirectURL},
	}
	payload, err := postTokenRequest(form)
	if err != nil {
		return OAuthTokens{}, err
	}
	accountID := extractAccountID(payload.AccessToken)
	if accountID == "" {
		return OAuthTokens{}, errors.New("token_account_id_missing")
	}
	return OAuthTokens{
		Access:    payload.AccessToken,
		Refresh:   payload.RefreshToken,
		IDToken:   payload.IDToken,
		Expires:   time.Now().Add(time.Duration(payload.ExpiresIn) * time.Second).UnixMilli(),
		AccountID: accountID,
		Email:     extractEmail(payload.AccessToken),
	}, nil
}

func postTokenRequest(form url.Values) (loginTokenPayload, error) {
	ctx, cancel := context.WithTimeout(context.Background(), httpTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, openAITokenURL, strings.NewReader(form.Encode()))
	if err != nil {
		return loginTokenPayload{}, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return loginTokenPayload{}, err
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return loginTokenPayload{}, fmt.Errorf("token_exchange_failed %d %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	var payload loginTokenPayload
	if err := json.Unmarshal(body, &payload); err != nil {
		return loginTokenPayload{}, err
	}
	if payload.AccessToken == "" || payload.RefreshToken == "" || payload.ExpiresIn == 0 {
		return loginTokenPayload{}, errors.New("token_response_missing_fields")
	}
	return payload, nil
}

func (app *App) fetchCodexUsage(tokens OAuthTokens) (UsageSnapshot, error) {
	ctx, cancel := context.WithTimeout(context.Background(), httpTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, usageURL, nil)
	if err != nil {
		return UsageSnapshot{}, err
	}
	req.Header.Set("Authorization", "Bearer "+tokens.Access)
	req.Header.Set("User-Agent", "CodexBar")
	req.Header.Set("Accept", "application/json")
	if strings.TrimSpace(tokens.AccountID) != "" {
		req.Header.Set("ChatGPT-Account-Id", tokens.AccountID)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return UsageSnapshot{}, err
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return UsageSnapshot{}, fmt.Errorf("usage_failed %d %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	var payload usagePayload
	if err := json.Unmarshal(body, &payload); err != nil {
		return UsageSnapshot{}, err
	}

	buildWindow := func(label string, usedPercent *float64, resetAtSeconds *int64) *UsageWindow {
		if usedPercent == nil && resetAtSeconds == nil {
			return nil
		}
		used := clampPercentFloat(derefFloat64(usedPercent))
		var resetAt *string
		var resetInMs *int
		if resetAtSeconds != nil && *resetAtSeconds > 0 {
			resetTime := time.Unix(*resetAtSeconds, 0).UTC()
			resetAt = ptr(resetTime.Format(time.RFC3339))
			resetInMs = ptr(max(0, int(time.Until(resetTime).Milliseconds())))
		}
		return &UsageWindow{
			Label:       label,
			UsedPercent: used,
			LeftPercent: 100 - used,
			ResetAt:     resetAt,
			ResetInMs:   resetInMs,
		}
	}

	return UsageSnapshot{
		Plan:     nullableString(payload.PlanType),
		FiveHour: buildWindow("5h", payload.RateLimit.PrimaryWindow.UsedPercent, payload.RateLimit.PrimaryWindow.ResetAt),
		Week:     buildWindow("week", payload.RateLimit.SecondaryWindow.UsedPercent, payload.RateLimit.SecondaryWindow.ResetAt),
	}, nil
}

func (app *App) buildAuthorizationURL() (authURL, verifier, state string, err error) {
	verifierBytes := make([]byte, 32)
	if _, err = io.ReadFull(crand.Reader, verifierBytes); err != nil {
		return "", "", "", err
	}
	verifier = base64.RawURLEncoding.EncodeToString(verifierBytes)
	hash := sha256.Sum256([]byte(verifier))
	challenge := base64.RawURLEncoding.EncodeToString(hash[:])

	stateBytes := make([]byte, 16)
	if _, err = io.ReadFull(crand.Reader, stateBytes); err != nil {
		return "", "", "", err
	}
	state = fmt.Sprintf("%x", stateBytes)

	u, _ := url.Parse(openAIAuthorizeURL)
	query := u.Query()
	query.Set("response_type", "code")
	query.Set("client_id", openAIClientID)
	query.Set("redirect_uri", app.oauthRedirectURL)
	query.Set("scope", openAIScope)
	query.Set("code_challenge", challenge)
	query.Set("code_challenge_method", "S256")
	query.Set("state", state)
	query.Set("id_token_add_organizations", "true")
	query.Set("codex_cli_simplified_flow", "true")
	query.Set("originator", "pi")
	query.Set("prompt", "login")
	u.RawQuery = query.Encode()
	return u.String(), verifier, state, nil
}

func (app *App) openAuthBrowser(authURL string) (bool, error) {
	mode := app.authOpenMode
	if mode == "manual" || mode == "off" || mode == "false" || mode == "0" {
		return false, nil
	}
	if mode == "auto" && runtime.GOOS != "darwin" {
		return false, nil
	}
	if runtime.GOOS != "darwin" {
		return false, nil
	}

	chromePath := "/Applications/Google Chrome.app"
	if pathExists(chromePath) {
		cmd := exec.Command("open", "-na", "Google Chrome", "--args", "--guest", "--new-window", authURL)
		if err := cmd.Start(); err == nil {
			_ = cmd.Process.Release()
			return true, nil
		}
	}

	cmd := exec.Command("open", authURL)
	if err := cmd.Start(); err != nil {
		return false, err
	}
	_ = cmd.Process.Release()
	return true, nil
}

func (app *App) ensureOAuthCallbackServer() error {
	app.mu.Lock()
	if app.callbackServer != nil {
		app.mu.Unlock()
		return nil
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/auth/callback", app.handleOAuthCallback)
	server := &http.Server{
		Addr:              fmt.Sprintf("%s:%d", app.oauthCallbackBindHost, app.oauthCallbackPort),
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
	}
	app.callbackServer = server
	app.mu.Unlock()

	go func() {
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			fmt.Fprintf(os.Stderr, "[go-daemon] callback server error: %v\n", err)
		}
	}()
	return nil
}

func (app *App) handleOAuthCallback(w http.ResponseWriter, r *http.Request) {
	app.mu.Lock()
	app.expirePendingLoginFlowsLocked()
	oauthState := r.URL.Query().Get("state")
	code := r.URL.Query().Get("code")
	authErr := r.URL.Query().Get("error")
	flowID := app.loginFlowIDsByState[oauthState]
	flow := app.loginFlows[flowID]
	app.mu.Unlock()

	if oauthState == "" || flow == nil {
		http.Error(w, "Unknown or expired login flow", http.StatusBadRequest)
		return
	}
	if flow.Status != "pending" {
		http.Error(w, "Login flow already completed", http.StatusConflict)
		return
	}
	if authErr != "" {
		now := nowISO()
		app.mu.Lock()
		flow.Status = "failed"
		flow.CompletedAt = &now
		flow.Error = &authErr
		delete(app.loginFlowIDsByState, flow.OAuthState)
		app.mu.Unlock()
		http.Error(w, "Authentication failed", http.StatusBadRequest)
		return
	}
	if code == "" {
		now := nowISO()
		message := "missing_authorization_code"
		app.mu.Lock()
		flow.Status = "failed"
		flow.CompletedAt = &now
		flow.Error = &message
		delete(app.loginFlowIDsByState, flow.OAuthState)
		app.mu.Unlock()
		http.Error(w, "Missing authorization code", http.StatusBadRequest)
		return
	}

	tokens, err := app.exchangeAuthorizationCode(code, flow.Verifier)
	if err != nil {
		now := nowISO()
		message := err.Error()
		app.mu.Lock()
		flow.Status = "failed"
		flow.CompletedAt = &now
		flow.Error = &message
		delete(app.loginFlowIDsByState, flow.OAuthState)
		app.mu.Unlock()
		http.Error(w, "Authentication failed", http.StatusInternalServerError)
		return
	}
	if err := app.persistLoginTokens(flow.ProfileName, tokens); err != nil {
		now := nowISO()
		message := err.Error()
		app.mu.Lock()
		flow.Status = "failed"
		flow.CompletedAt = &now
		flow.Error = &message
		delete(app.loginFlowIDsByState, flow.OAuthState)
		app.mu.Unlock()
		http.Error(w, "Authentication failed", http.StatusInternalServerError)
		return
	}

	now := nowISO()
	app.mu.Lock()
	flow.Status = "completed"
	flow.CompletedAt = &now
	flow.Error = nil
	delete(app.loginFlowIDsByState, flow.OAuthState)
	app.mu.Unlock()

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = io.WriteString(w, "<!doctype html><html><body><p>Authentication successful. You can close this tab.</p></body></html>")
}

func (app *App) persistLoginTokens(profileName string, tokens OAuthTokens) error {
	store, err := app.loadAuthStore(profileName)
	if err != nil {
		return err
	}
	profileID := "openai-codex:default"
	upsertOpenAICodexCredential(&store, profileID, tokens)
	if err := app.saveAuthStore(profileName, store); err != nil {
		return err
	}
	if strings.TrimSpace(tokens.IDToken) != "" {
		return app.saveCodexAuth(profileName, tokens)
	}
	return nil
}

func (app *App) findPendingLoginFlow(profileName string) *PendingLoginFlow {
	app.mu.Lock()
	defer app.mu.Unlock()
	app.expirePendingLoginFlowsLocked()
	for _, flow := range app.loginFlows {
		if flow.ProfileName == profileName && flow.Status == "pending" {
			return flow
		}
	}
	return nil
}

func (app *App) expirePendingLoginFlowsLocked() {
	now := time.Now()
	for _, flow := range app.loginFlows {
		if flow.Status != "pending" {
			continue
		}
		expiresAt, err := time.Parse(time.RFC3339, flow.ExpiresAt)
		if err != nil || expiresAt.After(now) {
			continue
		}
		flow.Status = "expired"
		completedAt := nowISO()
		flow.CompletedAt = &completedAt
		message := "oauth_timeout_no_callback"
		flow.Error = &message
		delete(app.loginFlowIDsByState, flow.OAuthState)
	}
}

func (app *App) buildMachineSummary(fresh bool) (MachineSummary, error) {
	if fresh {
		return app.computeMachineSummary(true)
	}

	var cached *cachedMachineSummary
	shouldRefresh := false
	app.mu.Lock()
	if app.machineSummaryCache != nil {
		copy := *app.machineSummaryCache
		cached = &copy
		if time.Since(app.machineSummaryCache.FetchedAt) > machineSummaryCacheTTL && !app.machineSummaryRefreshing {
			app.machineSummaryRefreshing = true
			shouldRefresh = true
		}
	}
	app.mu.Unlock()

	if shouldRefresh {
		go app.refreshMachineSummaryCache()
	}
	if cached != nil {
		return cached.Summary, nil
	}

	return app.computeMachineSummary(false)
}

func (app *App) computeMachineSummary(fresh bool) (MachineSummary, error) {
	now := time.Now()
	var openclaw MachineOpenClaw
	var cpu MachineCPU
	var memory MachineMemory
	var swap MachineSwap
	var disk MachineDisk
	var network MachineNetwork
	var processes MachineProcessGroup
	var topProcesses []MachineTopProcess

	var wg sync.WaitGroup
	wg.Add(5)
	go func() {
		defer wg.Done()
		openclaw = app.inspectOpenClawAvailability()
	}()
	go func() {
		defer wg.Done()
		cpu, processes, topProcesses = app.collectMachineProcessMetrics()
	}()
	go func() {
		defer wg.Done()
		memory, swap = app.collectMachineMemoryMetrics()
	}()
	go func() {
		defer wg.Done()
		disk = app.collectMachineDiskMetrics()
	}()
	go func() {
		defer wg.Done()
		network = app.collectMachineNetworkMetrics(now)
	}()
	wg.Wait()

	memory.Pressure = machinePressureLevel(memory.PressurePercent, swap.UsedPercent)
	summary := MachineSummary{
		CollectedAt:  now.UTC().Format(time.RFC3339),
		OpenClaw:     openclaw,
		CPU:          cpu,
		Memory:       memory,
		Swap:         swap,
		Disk:         disk,
		Network:      network,
		Processes:    processes,
		TopProcesses: topProcesses,
	}

	app.mu.Lock()
	app.machineSummaryCache = &cachedMachineSummary{
		Summary:   summary,
		FetchedAt: time.Now(),
	}
	app.mu.Unlock()

	return summary, nil
}

func (app *App) refreshMachineSummaryCache() {
	defer func() {
		app.mu.Lock()
		app.machineSummaryRefreshing = false
		app.mu.Unlock()
	}()

	_, _ = app.computeMachineSummary(false)
}

func (app *App) inspectOpenClawAvailability() MachineOpenClaw {
	explicit := strings.TrimSpace(os.Getenv("OPENCLAW_BIN"))
	if explicit != "" {
		if resolved, ok := resolveBinaryPath(explicit); ok {
			return MachineOpenClaw{Available: true, Path: &resolved, Source: "env"}
		}
		return MachineOpenClaw{Available: false, Path: nullableString(explicit), Source: "env"}
	}

	local := filepath.Join(app.homeDir, ".local", "bin", "openclaw")
	if pathExists(local) {
		return MachineOpenClaw{Available: true, Path: &local, Source: "local"}
	}

	if resolved, ok := resolveBinaryPath("openclaw"); ok {
		return MachineOpenClaw{Available: true, Path: &resolved, Source: "path"}
	}

	return MachineOpenClaw{Available: false, Source: "missing"}
}

func (app *App) collectTopCPU(logicalCores int) MachineCPU {
	cpu := MachineCPU{
		ActivePercent: 0,
		UserPercent:   0,
		SystemPercent: 0,
		IdlePercent:   0,
		LogicalCores:  logicalCores,
	}

	result := runCommand("top", []string{"-l", "1", "-n", "0"}, 8*time.Second)
	line := ""
	for _, rawLine := range strings.Split(result.Stdout, "\n") {
		rawLine = strings.TrimSpace(rawLine)
		if strings.HasPrefix(rawLine, "CPU usage:") {
			line = rawLine
			break
		}
	}
	if line == "" {
		return cpu
	}

	matches := topCPUPattern.FindStringSubmatch(line)
	if len(matches) != 4 {
		return cpu
	}
	userPercent, errUser := strconv.ParseFloat(matches[1], 64)
	systemPercent, errSystem := strconv.ParseFloat(matches[2], 64)
	idlePercent, errIdle := strconv.ParseFloat(matches[3], 64)
	if errUser != nil || errSystem != nil || errIdle != nil {
		return cpu
	}

	cpu.UserPercent = clampPercentFloat(userPercent)
	cpu.SystemPercent = clampPercentFloat(systemPercent)
	cpu.IdlePercent = clampPercentFloat(idlePercent)
	cpu.ActivePercent = clampPercentFloat(userPercent + systemPercent)
	return cpu
}

func (app *App) collectMachineProcessMetrics() (MachineCPU, MachineProcessGroup, []MachineTopProcess) {
	logicalCores := 1
	if parsed, err := syscall.SysctlUint32("hw.logicalcpu"); err == nil && parsed > 0 {
		logicalCores = int(parsed)
	}

	cpu := app.collectTopCPU(logicalCores)
	result := runCommand("ps", []string{"-axo", "pid=,pcpu=,rss=,etime=,command="}, 8*time.Second)
	if !result.OK && strings.TrimSpace(result.Stdout) == "" {
		return cpu, MachineProcessGroup{}, nil
	}

	var manager MachineProcessSnapshot
	var watchdog MachineProcessSnapshot
	topProcesses := make([]MachineTopProcess, 0, 32)
	for _, rawLine := range strings.Split(result.Stdout, "\n") {
		pid, processCPU, rssBytes, uptimeSeconds, command, ok := parseMachineProcessLine(rawLine)
		if !ok {
			continue
		}

		snapshot := MachineProcessSnapshot{
			Running:       true,
			PID:           ptr(pid),
			CPUPercent:    nullableFloat64(processCPU),
			RSSBytes:      nullableInt64(rssBytes),
			UptimeSeconds: nullableInt(uptimeSeconds),
			Command:       nullableString(command),
		}

		switch {
		case matchesProcessCommand(command, "openclaw-manager-daemon"):
			if shouldReplaceProcessSnapshot(manager, snapshot) {
				manager = snapshot
			}
		case matchesProcessCommand(command, "openclaw-watchdog"):
			if shouldReplaceProcessSnapshot(watchdog, snapshot) {
				watchdog = snapshot
			}
		}

		topProcesses = append(topProcesses, MachineTopProcess{
			Name:          processDisplayName(command),
			PID:           pid,
			CPUPercent:    processCPU,
			RSSBytes:      rssBytes,
			UptimeSeconds: uptimeSeconds,
			Command:       command,
		})
	}

	sort.Slice(topProcesses, func(i, j int) bool {
		if math.Abs(topProcesses[i].CPUPercent-topProcesses[j].CPUPercent) > 0.001 {
			return topProcesses[i].CPUPercent > topProcesses[j].CPUPercent
		}
		if topProcesses[i].RSSBytes != topProcesses[j].RSSBytes {
			return topProcesses[i].RSSBytes > topProcesses[j].RSSBytes
		}
		return topProcesses[i].PID < topProcesses[j].PID
	})
	if len(topProcesses) > 10 {
		topProcesses = append([]MachineTopProcess(nil), topProcesses[:10]...)
	}

	return cpu, MachineProcessGroup{
		Manager:  manager,
		Watchdog: watchdog,
	}, topProcesses
}

func (app *App) collectMachineMemoryMetrics() (MachineMemory, MachineSwap) {
	totalBytes, _ := strconv.ParseInt(strings.TrimSpace(syscallString("hw.memsize")), 10, 64)

	pageSize := int64(0)
	pageCounts := map[string]int64{}
	vmStat := runCommand("vm_stat", nil, 8*time.Second)
	for _, rawLine := range strings.Split(vmStat.Stdout, "\n") {
		line := strings.TrimSpace(rawLine)
		if line == "" {
			continue
		}
		if pageSize == 0 {
			pageSize = parseVMStatPageSize(line)
		}
		if key, value, ok := parseVMStatLine(line); ok {
			pageCounts[key] = value
		}
	}
	if pageSize <= 0 {
		pageSize = 4096
	}

	freePages := pageCounts["Pages free"] + pageCounts["Pages speculative"]
	activePages := pageCounts["Pages active"]
	inactivePages := pageCounts["Pages inactive"] + pageCounts["Pages purgeable"]
	wiredPages := pageCounts["Pages wired down"]
	freeBytes := freePages * pageSize
	activeBytes := activePages * pageSize
	cachedBytes := inactivePages * pageSize
	wiredBytes := wiredPages * pageSize
	availableBytes := (freePages + inactivePages) * pageSize
	compressedBytes := pageCounts["Pages occupied by compressor"] * pageSize

	usedBytes := totalBytes - availableBytes
	if usedBytes < 0 {
		usedBytes = 0
	}
	if totalBytes > 0 && usedBytes > totalBytes {
		usedBytes = totalBytes
	}
	if totalBytes > 0 && availableBytes > totalBytes {
		availableBytes = totalBytes - usedBytes
	}
	otherBytes := totalBytes - wiredBytes - activeBytes - cachedBytes - freeBytes
	if otherBytes < 0 {
		otherBytes = 0
	}
	pressureBytes := wiredBytes + activeBytes

	swap := parseSwapUsage(syscallString("vm.swapusage"))
	memory := MachineMemory{
		TotalBytes:      totalBytes,
		UsedBytes:       usedBytes,
		AvailableBytes:  availableBytes,
		WiredBytes:      wiredBytes,
		ActiveBytes:     activeBytes,
		CachedBytes:     cachedBytes,
		FreeBytes:       freeBytes,
		OtherBytes:      otherBytes,
		CompressedBytes: compressedBytes,
		UsedPercent:     percentFromBytes(usedBytes, totalBytes),
		PressurePercent: percentFromBytes(pressureBytes, totalBytes),
	}
	return memory, swap
}

func (app *App) collectMachineDiskMetrics() MachineDisk {
	path := app.homeDir
	if strings.TrimSpace(path) == "" {
		path = "/"
	}

	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil {
		return MachineDisk{Path: path}
	}

	totalBytes := int64(stat.Blocks) * int64(stat.Bsize)
	freeBytes := int64(stat.Bavail) * int64(stat.Bsize)
	usedBytes := totalBytes - freeBytes
	if usedBytes < 0 {
		usedBytes = 0
	}

	return MachineDisk{
		Path:        path,
		TotalBytes:  totalBytes,
		UsedBytes:   usedBytes,
		FreeBytes:   freeBytes,
		UsedPercent: percentFromBytes(usedBytes, totalBytes),
	}
}

func (app *App) collectMachineNetworkMetrics(now time.Time) MachineNetwork {
	result := runCommand("netstat", []string{"-ibn"}, 8*time.Second)
	if !result.OK && strings.TrimSpace(result.Stdout) == "" {
		return MachineNetwork{}
	}

	byInterface := map[string]machineInterfaceCounters{}
	for _, rawLine := range strings.Split(result.Stdout, "\n") {
		fields := strings.Fields(strings.TrimSpace(rawLine))
		if len(fields) < 10 {
			continue
		}
		name := fields[0]
		network := fields[2]
		if name == "Name" || strings.HasPrefix(name, "lo") || strings.HasSuffix(name, "*") {
			continue
		}
		if !strings.HasPrefix(network, "<Link#") {
			continue
		}

		received, errIn := strconv.ParseUint(fields[6], 10, 64)
		sent, errOut := strconv.ParseUint(fields[9], 10, 64)
		if errIn != nil || errOut != nil {
			continue
		}
		byInterface[name] = machineInterfaceCounters{Received: received, Sent: sent}
	}

	selectedInterface, selectedCounters := preferredNetworkInterface(byInterface)
	if selectedInterface == "" {
		return MachineNetwork{}
	}

	summary := MachineNetwork{
		PrimaryInterface:   &selectedInterface,
		TotalReceivedBytes: int64(selectedCounters.Received),
		TotalSentBytes:     int64(selectedCounters.Sent),
	}

	app.mu.Lock()
	previous := app.lastNetworkSample
	app.lastNetworkSample = &machineNetworkCounters{
		Interface:   selectedInterface,
		Received:    selectedCounters.Received,
		Sent:        selectedCounters.Sent,
		CollectedAt: now,
	}
	app.mu.Unlock()

	if previous == nil || previous.Interface != selectedInterface {
		return summary
	}

	elapsedSeconds := now.Sub(previous.CollectedAt).Seconds()
	if elapsedSeconds <= 0.25 {
		return summary
	}

	if selectedCounters.Received >= previous.Received {
		rx := int64(math.Round(float64(selectedCounters.Received-previous.Received) / elapsedSeconds))
		summary.ReceivedBytesPerSec = nullableInt64(rx)
	}
	if selectedCounters.Sent >= previous.Sent {
		tx := int64(math.Round(float64(selectedCounters.Sent-previous.Sent) / elapsedSeconds))
		summary.SentBytesPerSec = nullableInt64(tx)
	}

	return summary
}

func machinePressureLevel(memoryPressurePercent, swapUsedPercent int) string {
	switch {
	case memoryPressurePercent >= 85:
		return "high"
	case memoryPressurePercent >= 65:
		return "watch"
	case memoryPressurePercent >= 45 && swapUsedPercent >= 50:
		return "watch"
	case swapUsedPercent >= 80:
		return "watch"
	default:
		return "normal"
	}
}

func (app *App) buildSupportSummary(fresh bool) (SupportSummary, error) {
	if fresh {
		return app.computeSupportSummary(true)
	}

	var cached *cachedSupportSummary
	shouldRefresh := false
	app.mu.Lock()
	if app.supportSummaryCache != nil {
		copy := *app.supportSummaryCache
		cached = &copy
		if time.Since(app.supportSummaryCache.FetchedAt) > supportSummaryCacheTTL && !app.supportSummaryRefreshing {
			app.supportSummaryRefreshing = true
			shouldRefresh = true
		}
	}
	app.mu.Unlock()

	if shouldRefresh {
		go app.refreshSupportSummaryCache()
	}
	if cached != nil {
		return cached.Summary, nil
	}

	return app.computeSupportSummary(false)
}

func (app *App) computeSupportSummary(fresh bool) (SupportSummary, error) {
	now := time.Now()
	var gateway SupportGateway
	var events []SupportLogEvent
	var watchdogState map[string]any
	var watchdogInstalled bool
	var environment SupportEnvironment
	var maintenance SupportMaintenance

	var wg sync.WaitGroup
	wg.Add(5)
	go func() {
		defer wg.Done()
		gateway = app.getOpenClawStatus(fresh)
	}()
	go func() {
		defer wg.Done()
		events = app.getRecentEvents(fresh)
	}()
	go func() {
		defer wg.Done()
		watchdogState = readJSONFile(app.watchdogStatePath(), map[string]any{})
		watchdogInstalled = pathExists(app.watchdogPlistPath())
	}()
	go func() {
		defer wg.Done()
		environment = app.getEnvironmentSummary(now, fresh)
	}()
	go func() {
		defer wg.Done()
		maintenance = app.getSupportMaintenance(fresh)
	}()
	wg.Wait()

	disconnect15 := 0
	disconnect60 := 0
	recentRestarts := 0
	var lastLogin *string
	var lastDisconnect *string
	for _, event := range events {
		timestamp, err := time.Parse(time.RFC3339, event.Timestamp)
		if err != nil {
			continue
		}
		if event.Kind == "discord_disconnect" && now.Sub(timestamp) <= 15*time.Minute {
			disconnect15++
		}
		if event.Kind == "discord_disconnect" && now.Sub(timestamp) <= time.Hour {
			disconnect60++
		}
		if event.Kind == "discord_restart" && now.Sub(timestamp) <= 15*time.Minute {
			recentRestarts++
		}
		if event.Kind == "discord_login" && lastLogin == nil {
			lastLogin = &event.Timestamp
		}
		if event.Kind == "discord_disconnect" && lastDisconnect == nil {
			lastDisconnect = &event.Timestamp
		}
	}

	discordStatus := "healthy"
	if !gateway.Reachable {
		discordStatus = "offline"
	} else if disconnect15 > 0 || recentRestarts > 0 {
		discordStatus = "unstable"
	}

	recommendation := ""
	switch discordStatus {
	case "offline":
		recommendation = explainGatewayFailure(gateway.Error)
		if len(environment.RiskySignals) > 0 {
			recommendation += " 当前环境因素：" + environment.RiskySignals[0]
		}
	case "unstable":
		recommendation = "最近出现断连，先执行“一键修复”。"
		if len(environment.RiskySignals) > 0 {
			recommendation += " 优先排查：" + environment.RiskySignals[0]
		} else {
			recommendation += " 同时排查网络和睡眠影响。"
		}
	default:
		if watchdogInstalled {
			recommendation = "当前连接正常，watchdog 已在后台运行。"
		} else {
			recommendation = "当前连接正常，建议启用 watchdog。"
		}
	}

	restartCount := nullableInt(anyInt(watchdogState["restartCount"]))
	lastLoopResult := nullableString(anyString(watchdogState["lastLoopResult"]))
	monitoredStateDir := nullableString(anyStringOrDefault(watchdogState["monitoredStateDir"], filepath.Join(app.openclawHomeDir, ".openclaw")))
	lastHealthyAt := nullableString(anyString(watchdogState["lastHealthyAt"]))
	var lastRestartAt *string
	if lastRestartMs, ok := anyInt64(watchdogState["lastRestartAtMs"]); ok && lastRestartMs > 0 {
		lastRestartAt = ptr(time.UnixMilli(lastRestartMs).UTC().Format(time.RFC3339))
	}

	statusLine := "未启用"
	if watchdogInstalled {
		if lastLoopResult != nil {
			statusLine = *lastLoopResult
		} else {
			statusLine = "已启用"
		}
	}

	summary := SupportSummary{
		CollectedAt: now.UTC().Format(time.RFC3339),
		Gateway:     gateway,
		Discord: SupportDiscord{
			Status:             discordStatus,
			LastLoggedInAt:     lastLogin,
			LastDisconnectAt:   lastDisconnect,
			DisconnectCount15m: disconnect15,
			DisconnectCount60m: disconnect60,
			RecentEvents:       truncateEvents(events, 10),
			Recommendation:     recommendation,
		},
		Watchdog: SupportWatchdog{
			Installed:         watchdogInstalled,
			MonitoredStateDir: monitoredStateDir,
			LastLoopResult:    lastLoopResult,
			LastHealthyAt:     lastHealthyAt,
			LastRestartAt:     lastRestartAt,
			RestartCount:      restartCount,
			StatePath:         app.watchdogStatePath(),
			LogPath:           app.watchdogLogPath(),
			StatusLine:        statusLine,
		},
		Environment: environment,
		Maintenance: maintenance,
	}

	app.mu.Lock()
	app.supportSummaryCache = &cachedSupportSummary{
		Summary:   summary,
		FetchedAt: time.Now(),
	}
	app.mu.Unlock()

	return summary, nil
}

func (app *App) refreshSupportSummaryCache() {
	defer func() {
		app.mu.Lock()
		app.supportSummaryRefreshing = false
		app.mu.Unlock()
	}()

	_, _ = app.computeSupportSummary(false)
}

func (app *App) getSupportMaintenance(fresh bool) SupportMaintenance {
	if !fresh {
		app.mu.Lock()
		if app.supportMaintenanceCache != nil && time.Since(app.supportMaintenanceCache.FetchedAt) <= supportMaintenanceCacheTTL {
			cached := app.supportMaintenanceCache.Maintenance
			app.mu.Unlock()
			return cached
		}
		app.mu.Unlock()
	}

	openclawBin := app.resolveOpenClawBin()
	var config SupportConfigCheck
	var gatewayService SupportGatewayService
	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		config = app.inspectOpenClawConfig(openclawBin)
	}()
	go func() {
		defer wg.Done()
		gatewayService = app.inspectGatewayService(openclawBin)
	}()
	wg.Wait()
	maintenance := SupportMaintenance{
		CLIPath:               nullableString(openclawBin),
		StateDir:              app.defaultOpenClawState,
		Config:                config,
		GatewayService:        gatewayService,
		DoctorCommand:         "openclaw doctor --non-interactive",
		DoctorFixCommand:      "openclaw doctor --fix --yes --non-interactive",
		GatewayInstallCommand: "openclaw gateway install --force",
	}

	app.mu.Lock()
	app.supportMaintenanceCache = &cachedSupportMaintenance{
		Maintenance: maintenance,
		FetchedAt:   time.Now(),
	}
	app.mu.Unlock()

	return maintenance
}

func (app *App) inspectOpenClawConfig(openclawBin string) SupportConfigCheck {
	defaultPath := filepath.Join(app.defaultOpenClawState, "openclaw.json")
	result := runCommand(openclawBin, []string{"config", "validate"}, commandTimeout)
	if result.OK {
		reportedPath := strings.TrimSpace(prefixedLine(result.Stdout, "Config valid:"))
		if reportedPath == "" {
			reportedPath = defaultPath
		}
		resolvedPath := expandUserPath(reportedPath, app.homeDir)
		return SupportConfigCheck{
			Path:   resolvedPath,
			Exists: pathExists(resolvedPath),
			Valid:  true,
			Detail: "配置有效",
		}
	}

	output := strings.TrimSpace(derefString(cleanOutput(result.Stdout, result.Stderr)))
	if output == "" {
		output = "配置校验失败"
	}
	return SupportConfigCheck{
		Path:   defaultPath,
		Exists: pathExists(defaultPath),
		Valid:  false,
		Detail: output,
	}
}

func (app *App) inspectGatewayService(openclawBin string) SupportGatewayService {
	result := runCommand(openclawBin, []string{"gateway", "status", "--deep"}, commandTimeout)
	if !result.OK {
		return SupportGatewayService{
			Installed: pathExists(app.gatewayPlistPath()),
			Status:    "读取失败",
			Issue:     cleanOutput(result.Stdout, result.Stderr),
		}
	}

	text := strings.TrimSpace(strings.Join(filterNonEmpty([]string{result.Stdout, result.Stderr}), "\n"))
	status := strings.TrimSpace(prefixedLine(text, "Service:"))
	if status == "" {
		status = "未安装"
	}
	serviceFile := nullableString(expandUserPath(prefixedLine(text, "Service file:"), app.homeDir))
	cliConfigPath := nullableString(expandUserPath(prefixedLine(text, "Config (cli):"), app.homeDir))
	serviceConfigPath := nullableString(expandUserPath(prefixedLine(text, "Config (service):"), app.homeDir))
	logPath := nullableString(expandUserPath(prefixedLine(text, "File logs:"), app.homeDir))
	command := nullableString(prefixedLine(text, "Command:"))
	runtimeStatus := nullableString(prefixedLine(text, "Runtime:"))
	probeStatus := nullableString(prefixedLine(text, "RPC probe:"))
	issue := nullableString(prefixedLine(text, "Service config issue:"))
	recommendation := nullableString(prefixedLine(text, "Recommendation:"))
	installed := pathExists(app.gatewayPlistPath()) || serviceFile != nil

	if issue == nil {
		switch {
		case strings.Contains(strings.ToLower(text), "service not installed"):
			issue = ptr("OpenClaw Gateway 服务未安装。")
		case strings.Contains(strings.ToLower(text), "config is invalid"):
			issue = ptr("OpenClaw 配置无效，需先修复配置。")
		}
	}

	return SupportGatewayService{
		Installed:         installed,
		Status:            status,
		ServiceFile:       serviceFile,
		CLIConfigPath:     cliConfigPath,
		ServiceConfigPath: serviceConfigPath,
		LogPath:           logPath,
		Command:           command,
		RuntimeStatus:     runtimeStatus,
		ProbeStatus:       probeStatus,
		Issue:             issue,
		Recommendation:    recommendation,
	}
}

func (app *App) performSupportRepair(action string) (SupportRepairResult, error) {
	result, err := app.performRepairAction(action)
	if err != nil {
		return SupportRepairResult{}, err
	}
	app.invalidateSupportCaches()
	summary, err := app.buildSupportSummary(true)
	if err != nil {
		return SupportRepairResult{}, err
	}
	message, output := summarizeSupportRepair(action, result, summary)
	return SupportRepairResult{
		OK:      result.OK,
		Action:  action,
		Message: message,
		Output:  output,
		Summary: summary,
	}, nil
}

func summarizeSupportRepair(action string, result CommandResult, summary SupportSummary) (string, *string) {
	rawOutput := cleanOutput(result.Stdout, result.Stderr)
	if !result.OK {
		return supportRepairFailureMessage(action), rawOutput
	}

	switch action {
	case "validate_config":
		message := "OpenClaw 配置校验通过"
		if !summary.Maintenance.Config.Valid {
			message = "OpenClaw 配置仍有问题"
		}
		return message, composeSupportRepairOutput([]string{
			"配置文件: " + summary.Maintenance.Config.Path,
			"当前状态: " + boolLabel(summary.Maintenance.Config.Valid, "有效", "仍有问题"),
			summary.Maintenance.Config.Detail,
			commandExcerptLabel(rawOutput),
		})
	case "run_openclaw_doctor":
		return "OpenClaw 官方体检已完成", composeSupportRepairOutput([]string{
			supportRepairStatusSummary(summary),
			"建议: " + primarySupportRecommendation(summary),
			commandExcerptLabel(rawOutput),
		})
	case "run_openclaw_doctor_fix":
		message := "OpenClaw 官方修复已执行"
		if summary.Maintenance.Config.Valid && strings.TrimSpace(derefString(summary.Maintenance.GatewayService.Issue)) == "" && summary.Gateway.Reachable {
			message = "OpenClaw 官方修复后状态正常"
		}
		return message, composeSupportRepairOutput([]string{
			supportRepairStatusSummary(summary),
			"建议: " + primarySupportRecommendation(summary),
			commandExcerptLabel(rawOutput),
		})
	case "reinstall_gateway_service":
		service := summary.Maintenance.GatewayService
		message := "OpenClaw Gateway 服务已重装"
		if issue := strings.TrimSpace(derefString(service.Issue)); issue != "" {
			message = "Gateway 服务已重装，但仍需继续处理"
		}
		return message, composeSupportRepairOutput([]string{
			"服务状态: " + firstNonEmpty(derefString(service.RuntimeStatus), service.Status, "未提供"),
			"Gateway: " + boolLabel(summary.Gateway.Reachable, "可达", "不可达"),
			firstNonEmpty(derefString(service.Issue), derefString(service.Recommendation)),
			commandExcerptLabel(rawOutput),
		})
	case "run_watchdog_check":
		return "一键修复已执行", composeSupportRepairOutput([]string{
			"守护状态: " + summary.Watchdog.StatusLine,
			"Gateway: " + boolLabel(summary.Gateway.Reachable, "可达", "不可达"),
			"建议: " + primarySupportRecommendation(summary),
			commandExcerptLabel(rawOutput),
		})
	case "restart_gateway":
		return "OpenClaw 服务已重启", composeSupportRepairOutput([]string{
			"Gateway: " + boolLabel(summary.Gateway.Reachable, "可达", "不可达"),
			supportRepairStatusSummary(summary),
			commandExcerptLabel(rawOutput),
		})
	case "reinstall_watchdog":
		return "稳定守护已重新部署", composeSupportRepairOutput([]string{
			"守护状态: " + summary.Watchdog.StatusLine,
			"监控目录: " + firstNonEmpty(derefString(summary.Watchdog.MonitoredStateDir), summary.Maintenance.StateDir),
			"建议: " + primarySupportRecommendation(summary),
			commandExcerptLabel(rawOutput),
		})
	default:
		return "日志已打开", rawOutput
	}
}

func supportRepairFailureMessage(action string) string {
	switch action {
	case "validate_config":
		return "OpenClaw 配置校验失败"
	case "run_openclaw_doctor":
		return "OpenClaw 官方体检失败"
	case "run_openclaw_doctor_fix":
		return "OpenClaw 官方修复失败"
	case "reinstall_gateway_service":
		return "Gateway 服务重装失败"
	case "run_watchdog_check":
		return "一键修复失败"
	case "restart_gateway":
		return "OpenClaw 服务重启失败"
	case "reinstall_watchdog":
		return "稳定守护部署失败"
	default:
		return "操作执行失败"
	}
}

func supportRepairStatusSummary(summary SupportSummary) string {
	parts := []string{
		"配置 " + boolLabel(summary.Maintenance.Config.Valid, "有效", "异常"),
		"Gateway 服务 " + boolLabel(strings.TrimSpace(derefString(summary.Maintenance.GatewayService.Issue)) == "", "正常", "需维护"),
		"Gateway " + boolLabel(summary.Gateway.Reachable, "可达", "不可达"),
	}
	if summary.Discord.Status != "" {
		parts = append(parts, "Discord "+summary.Discord.Status)
	}
	return strings.Join(parts, " | ")
}

func primarySupportRecommendation(summary SupportSummary) string {
	if !summary.Maintenance.Config.Valid {
		return firstNonEmpty(summary.Maintenance.Config.Detail, "先修复 OpenClaw 配置。")
	}
	if issue := strings.TrimSpace(derefString(summary.Maintenance.GatewayService.Issue)); issue != "" {
		return firstNonEmpty(derefString(summary.Maintenance.GatewayService.Recommendation), issue)
	}
	if !summary.Gateway.Reachable {
		return explainGatewayFailure(summary.Gateway.Error)
	}
	if summary.Discord.Status == "offline" || summary.Discord.Status == "unstable" {
		return firstNonEmpty(summary.Discord.Recommendation, "先执行一轮修复，再观察 Discord 是否恢复。")
	}
	if summary.Environment.RiskLevel == "high" || summary.Environment.RiskLevel == "watch" {
		return firstNonEmpty(summary.Environment.Recommendation, "先排除 VPN、代理和睡眠恢复带来的环境波动。")
	}
	return "当前没有明显阻塞，保持自动切换和稳定守护即可。"
}

func commandExcerptLabel(output *string) string {
	excerpt := compactCommandExcerpt(output, 4, 420)
	if excerpt == "" {
		return ""
	}
	return "命令输出摘要:\n" + excerpt
}

func compactCommandExcerpt(output *string, maxLines int, maxChars int) string {
	text := strings.TrimSpace(derefString(output))
	if text == "" {
		return ""
	}
	lines := strings.Split(text, "\n")
	selected := make([]string, 0, maxLines)
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		lower := strings.ToLower(line)
		if strings.Contains(lower, "deprecationwarning") ||
			strings.Contains(lower, "trace-deprecation") ||
			strings.Contains(lower, "the `punycode` module is deprecated") {
			continue
		}
		selected = append(selected, line)
		if len(selected) >= maxLines {
			break
		}
	}
	if len(selected) == 0 {
		return ""
	}
	snippet := strings.Join(selected, "\n")
	if len(snippet) > maxChars {
		snippet = snippet[:maxChars] + "..."
	}
	return snippet
}

func composeSupportRepairOutput(lines []string) *string {
	filtered := make([]string, 0, len(lines))
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		filtered = append(filtered, line)
	}
	if len(filtered) == 0 {
		return nil
	}
	text := strings.Join(filtered, "\n")
	return &text
}

func boolLabel(value bool, yes string, no string) string {
	if value {
		return yes
	}
	return no
}

func (app *App) performRepairAction(action string) (CommandResult, error) {
	openclawBin := app.resolveOpenClawBin()
	switch action {
	case "validate_config":
		return runCommand(openclawBin, []string{"config", "validate"}, commandTimeout), nil
	case "run_openclaw_doctor":
		return runCommand(openclawBin, []string{"doctor", "--non-interactive"}, 90*time.Second), nil
	case "run_openclaw_doctor_fix":
		return runCommand(openclawBin, []string{"doctor", "--fix", "--yes", "--non-interactive"}, 120*time.Second), nil
	case "reinstall_gateway_service":
		return runCommand(openclawBin, []string{"gateway", "install", "--force"}, 90*time.Second), nil
	case "run_watchdog_check":
		watchdogPath, err := app.resolveRuntimeBinary("openclaw-watchdog")
		if err != nil {
			return CommandResult{}, err
		}
		return runCommand(watchdogPath, []string{"--once"}, commandTimeout), nil
	case "restart_gateway":
		return app.restartGateway(), nil
	case "reinstall_watchdog":
		scriptPath, err := app.resolveScriptPath("install-watchdog.sh")
		if err != nil {
			return CommandResult{}, err
		}
		return runCommand("bash", []string{scriptPath}, 60*time.Second), nil
	case "open_gateway_log":
		return runCommand("open", []string{app.gatewayLogPath()}, commandTimeout), nil
	case "open_watchdog_log":
		return runCommand("open", []string{app.watchdogLogPath()}, commandTimeout), nil
	default:
		return CommandResult{}, errors.New("repair action is invalid")
	}
}

func (app *App) restartGateway() CommandResult {
	uid := os.Getuid()
	target := gatewayLabel
	if uid > 0 {
		target = fmt.Sprintf("gui/%d/%s", uid, gatewayLabel)
	}
	result := runCommand("launchctl", []string{"kickstart", "-k", target}, commandTimeout)
	if result.OK || uid <= 0 || !pathExists(app.gatewayPlistPath()) {
		return result
	}
	_ = runCommand("launchctl", []string{"bootout", fmt.Sprintf("gui/%d", uid), app.gatewayPlistPath()}, commandTimeout)
	result = runCommand("launchctl", []string{"bootstrap", fmt.Sprintf("gui/%d", uid), app.gatewayPlistPath()}, commandTimeout)
	if result.OK {
		result = runCommand("launchctl", []string{"kickstart", "-k", target}, commandTimeout)
	}
	return result
}

func (app *App) getOpenClawStatus(fresh bool) SupportGateway {
	if !fresh {
		app.mu.Lock()
		if app.supportGatewayCache != nil && time.Since(app.supportGatewayCache.FetchedAt) <= supportGatewayCacheTTL {
			cached := app.supportGatewayCache.Gateway
			app.mu.Unlock()
			return cached
		}
		app.mu.Unlock()
	}

	openclawBin := app.resolveOpenClawBin()
	result := runCommand(openclawBin, []string{"status", "--json"}, commandTimeout)
	if !result.OK {
		gateway := SupportGateway{
			Reachable: false,
			Error:     cleanOutput(result.Stdout, result.Stderr),
		}
		app.mu.Lock()
		app.supportGatewayCache = &cachedSupportGateway{
			Gateway:   gateway,
			FetchedAt: time.Now(),
		}
		app.mu.Unlock()
		return gateway
	}
	var payload openclawStatusPayload
	if err := json.Unmarshal([]byte(result.Stdout), &payload); err != nil {
		gateway := SupportGateway{
			Reachable: false,
			Error:     ptr("openclaw status returned invalid json"),
		}
		app.mu.Lock()
		app.supportGatewayCache = &cachedSupportGateway{
			Gateway:   gateway,
			FetchedAt: time.Now(),
		}
		app.mu.Unlock()
		return gateway
	}
	gateway := SupportGateway{
		Reachable:        payload.Gateway.Reachable,
		URL:              nullableString(payload.Gateway.URL),
		ConnectLatencyMs: payload.Gateway.ConnectLatencyMs,
		Version:          nullableString(payload.Gateway.Self.Version),
		Host:             nullableString(payload.Gateway.Self.Host),
		Error:            nullableString(payload.Gateway.Error),
	}
	app.mu.Lock()
	app.supportGatewayCache = &cachedSupportGateway{
		Gateway:   gateway,
		FetchedAt: time.Now(),
	}
	app.mu.Unlock()
	return gateway
}

func (app *App) getRecentEvents(fresh bool) []SupportLogEvent {
	if !fresh {
		app.mu.Lock()
		if app.supportEventsCache != nil && time.Since(app.supportEventsCache.FetchedAt) <= supportEventsCacheTTL {
			cached := cloneSupportEvents(app.supportEventsCache.Events)
			app.mu.Unlock()
			return cached
		}
		app.mu.Unlock()
	}

	events := make([]SupportLogEvent, 0)
	gatewayText, _ := readTail(app.gatewayLogPath(), logTailBytes)
	watchdogText, _ := readTail(app.watchdogLogPath(), logTailBytes)

	for _, line := range strings.Split(gatewayText, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		kind := classifyGatewayEvent(line)
		if kind == "" {
			continue
		}
		timestampMs, ok := parseLogTimestamp(line)
		if !ok {
			continue
		}
		message := line
		if idx := strings.IndexByte(line, ' '); idx >= 0 && idx+1 < len(line) {
			message = line[idx+1:]
		}
		events = append(events, SupportLogEvent{
			Timestamp: time.UnixMilli(timestampMs).UTC().Format(time.RFC3339),
			Kind:      kind,
			Line:      message,
		})
	}

	for _, line := range strings.Split(watchdogText, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		kind := classifyWatchdogEvent(line)
		if kind == "" {
			continue
		}
		timestampMs, ok := parseLogTimestamp(line)
		if !ok {
			continue
		}
		message := line
		if idx := strings.IndexByte(line, ' '); idx >= 0 && idx+1 < len(line) {
			message = line[idx+1:]
		}
		events = append(events, SupportLogEvent{
			Timestamp: time.UnixMilli(timestampMs).UTC().Format(time.RFC3339),
			Kind:      kind,
			Line:      message,
		})
	}

	sort.Slice(events, func(i, j int) bool { return events[i].Timestamp > events[j].Timestamp })
	app.mu.Lock()
	app.supportEventsCache = &cachedSupportEvents{
		Events:    cloneSupportEvents(events),
		FetchedAt: time.Now(),
	}
	app.mu.Unlock()
	return events
}

func (app *App) getEnvironmentSummary(now time.Time, fresh bool) SupportEnvironment {
	if !fresh {
		app.mu.Lock()
		if app.supportEnvironmentCache != nil && time.Since(app.supportEnvironmentCache.FetchedAt) <= supportEnvironmentCacheTTL {
			cached := app.supportEnvironmentCache.Environment
			app.mu.Unlock()
			return cached
		}
		app.mu.Unlock()
	}

	var routeResult CommandResult
	var vpnResult CommandResult
	var proxyResult CommandResult
	var interfacesResult CommandResult
	var sleepResult CommandResult

	var wg sync.WaitGroup
	wg.Add(5)
	go func() {
		defer wg.Done()
		routeResult = runCommand("route", []string{"-n", "get", "default"}, 8*time.Second)
	}()
	go func() {
		defer wg.Done()
		vpnResult = runCommand("scutil", []string{"--nc", "list"}, 8*time.Second)
	}()
	go func() {
		defer wg.Done()
		proxyResult = runCommand("scutil", []string{"--proxy"}, 8*time.Second)
	}()
	go func() {
		defer wg.Done()
		interfacesResult = runCommand("ifconfig", []string{"-l"}, 8*time.Second)
	}()
	go func() {
		defer wg.Done()
		sleepResult = runCommand("bash", []string{"-lc", "pmset -g log | awk 'match($0,/^[0-9-]+ [0-9:]+ [+-][0-9]{4} (Sleep|Wake|DarkWake)[[:space:]]+\\t/){print}' | tail -n 80"}, 15*time.Second)
	}()
	wg.Wait()

	primaryInterface := firstRegexGroup(routeResult.Stdout, `interface:\s+(\S+)`)
	gatewayAddress := firstRegexGroup(routeResult.Stdout, `gateway:\s+(\S+)`)

	vpnServiceNames := make([]string, 0)
	for _, line := range strings.Split(vpnResult.Stdout, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "Available network connection services") {
			continue
		}
		matches := regexp.MustCompile(`^\*?\s*\(([^)]+)\)\s+(.+)$`).FindStringSubmatch(line)
		if len(matches) != 3 {
			continue
		}
		status := strings.ToLower(strings.TrimSpace(matches[1]))
		name := strings.TrimSpace(matches[2])
		if strings.Contains(status, "connected") || strings.Contains(status, "connecting") {
			vpnServiceNames = append(vpnServiceNames, name)
		}
	}

	interfaceNames := strings.Fields(strings.TrimSpace(interfacesResult.Stdout))
	tunnelInterfaces := make([]string, 0)
	for _, name := range interfaceNames {
		if matched, _ := regexp.MatchString(`^(utun\d+|ipsec\d+|ppp\d+|tun\d+)$`, name); matched {
			tunnelInterfaces = append(tunnelInterfaces, name)
		}
	}
	vpnLikelyActive := len(vpnServiceNames) > 0 || len(tunnelInterfaces) > 0

	proxyEnabled := strings.Contains(proxyResult.Stdout, "HTTPEnable : 1") ||
		strings.Contains(proxyResult.Stdout, "HTTPSEnable : 1") ||
		strings.Contains(proxyResult.Stdout, "SOCKSEnable : 1")
	proxyHost := firstProxyValue(proxyResult.Stdout, "HTTPSProxy")
	if proxyHost == "" {
		proxyHost = firstProxyValue(proxyResult.Stdout, "HTTPProxy")
	}
	if proxyHost == "" {
		proxyHost = firstProxyValue(proxyResult.Stdout, "SOCKSProxy")
	}
	proxyPort := firstProxyValue(proxyResult.Stdout, "HTTPSPort")
	if proxyPort == "" {
		proxyPort = firstProxyValue(proxyResult.Stdout, "HTTPPort")
	}
	if proxyPort == "" {
		proxyPort = firstProxyValue(proxyResult.Stdout, "SOCKSPort")
	}
	proxySummary := ""
	if proxyEnabled {
		proxySummary = strings.Trim(strings.Join([]string{proxyHost, proxyPort}, ":"), ":")
		if proxySummary == "" {
			proxySummary = "系统代理已启用"
		}
	}

	type sleepEvent struct {
		Timestamp time.Time
		Kind      string
	}
	sleepEvents := make([]sleepEvent, 0)
	for _, line := range strings.Split(strings.TrimSpace(sleepResult.Stdout), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		matches := pmsetPattern.FindStringSubmatch(line)
		if len(matches) != 3 {
			continue
		}
		parsed := parsePmsetTimestamp(matches[1])
		if parsed.IsZero() {
			continue
		}
		sleepEvents = append(sleepEvents, sleepEvent{Timestamp: parsed, Kind: matches[2]})
	}
	sort.Slice(sleepEvents, func(i, j int) bool { return sleepEvents[i].Timestamp.After(sleepEvents[j].Timestamp) })

	var lastSleepAt *string
	var lastWakeAt *string
	sleepWakeCount60m := 0
	for _, event := range sleepEvents {
		if lastSleepAt == nil && event.Kind == "Sleep" {
			lastSleepAt = ptr(event.Timestamp.UTC().Format(time.RFC3339))
		}
		if lastWakeAt == nil && (event.Kind == "Wake" || event.Kind == "DarkWake") {
			lastWakeAt = ptr(event.Timestamp.UTC().Format(time.RFC3339))
		}
		if now.Sub(event.Timestamp) <= time.Hour {
			sleepWakeCount60m++
		}
	}

	riskySignals := make([]string, 0)
	if proxyEnabled {
		if proxySummary != "" {
			riskySignals = append(riskySignals, fmt.Sprintf("检测到系统代理（%s），Discord 长连接可能受代理影响。", proxySummary))
		} else {
			riskySignals = append(riskySignals, "检测到系统代理，Discord 长连接可能受代理影响。")
		}
	}
	if vpnLikelyActive {
		detail := ""
		if len(vpnServiceNames) > 0 {
			detail = vpnServiceNames[0]
		} else if len(tunnelInterfaces) > 0 {
			detail = tunnelInterfaces[0]
		} else {
			detail = "隧道接口"
		}
		riskySignals = append(riskySignals, fmt.Sprintf("检测到 VPN/隧道接口（%s），断连时建议先关闭后复测。", detail))
	}
	if lastWakeAt != nil {
		if lastWakeTime, err := time.Parse(time.RFC3339, *lastWakeAt); err == nil && now.Sub(lastWakeTime) <= 30*time.Minute || sleepWakeCount60m >= 3 {
			riskySignals = append(riskySignals, "最近有休眠/唤醒记录，长连接在睡眠恢复后更容易断开。")
		}
	}
	networkAnomaly := primaryInterface == ""
	if primaryInterface == "" {
		riskySignals = append(riskySignals, "未识别到默认网络出口，当前网络环境异常。")
	}

	riskLevel := "none"
	if networkAnomaly {
		riskLevel = "high"
	} else if (proxyEnabled && vpnLikelyActive) || len(riskySignals) >= 2 {
		riskLevel = "watch"
	} else if len(riskySignals) == 1 {
		riskLevel = "notice"
	}

	recommendation := "当前没有检测到明显的环境因素。"
	switch riskLevel {
	case "high":
		recommendation = "当前网络出口识别异常，先检查本机网络连接，再看 Discord 是否恢复。"
	case "watch":
		if proxyEnabled && vpnLikelyActive {
			recommendation = "检测到代理和隧道同时存在。如果继续断连，先关闭其中一个再复测。"
		} else if len(riskySignals) > 0 {
			recommendation = "检测到多条环境信号。如果继续断连，再优先排查：" + riskySignals[0]
		}
	case "notice":
		if len(riskySignals) > 0 {
			recommendation = riskySignals[0]
		}
	}

	environment := SupportEnvironment{
		PrimaryInterface:   nullableString(primaryInterface),
		GatewayAddress:     nullableString(gatewayAddress),
		VPNLikelyActive:    vpnLikelyActive,
		VPNServiceNames:    vpnServiceNames,
		ProxyLikelyEnabled: proxyEnabled,
		ProxySummary:       nullableString(proxySummary),
		LastSleepAt:        lastSleepAt,
		LastWakeAt:         lastWakeAt,
		SleepWakeCount60m:  sleepWakeCount60m,
		RiskLevel:          riskLevel,
		RiskySignals:       riskySignals,
		Recommendation:     recommendation,
	}
	app.mu.Lock()
	app.supportEnvironmentCache = &cachedSupportEnvironment{
		Environment: environment,
		FetchedAt:   time.Now(),
	}
	app.mu.Unlock()
	return environment
}

func (app *App) watchStateDir() string {
	return filepath.Join(app.openclawHomeDir, ".openclaw")
}

func (app *App) gatewayLogPath() string {
	return filepath.Join(app.watchStateDir(), "logs", "gateway.log")
}

func (app *App) watchdogLogPath() string {
	return filepath.Join(app.watchStateDir(), "logs", "watchdog.log")
}

func (app *App) watchdogStatePath() string {
	return filepath.Join(app.homeDir, "Library", "Application Support", "OpenClaw Manager Native", "watchdog", "state.json")
}

func (app *App) watchdogPlistPath() string {
	return filepath.Join(app.homeDir, "Library", "LaunchAgents", "ai.openclaw.watchdog.plist")
}

func (app *App) gatewayPlistPath() string {
	return filepath.Join(app.homeDir, "Library", "LaunchAgents", "ai.openclaw.gateway.plist")
}

func (app *App) resolveOpenClawBin() string {
	if explicit := strings.TrimSpace(os.Getenv("OPENCLAW_BIN")); explicit != "" {
		return explicit
	}
	local := filepath.Join(app.homeDir, ".local", "bin", "openclaw")
	if pathExists(local) {
		return local
	}
	return "openclaw"
}

func (app *App) resolveScriptPath(name string) (string, error) {
	exeDir := filepath.Dir(app.executablePath)
	candidates := []string{
		filepath.Join(exeDir, "..", "scripts", name),
		filepath.Join(exeDir, "scripts", name),
		filepath.Join(exeDir, "..", "..", "scripts", name),
		filepath.Join(exeDir, "..", "..", "..", "scripts", name),
	}
	for _, candidate := range candidates {
		candidate = filepath.Clean(candidate)
		if pathExists(candidate) {
			return candidate, nil
		}
	}
	return "", fmt.Errorf("unable to locate support script: %s", name)
}

func (app *App) resolveRuntimeBinary(name string) (string, error) {
	exeDir := filepath.Dir(app.executablePath)
	candidates := []string{
		filepath.Join(exeDir, name),
		filepath.Join(exeDir, "..", "runtime", name),
		filepath.Join(exeDir, "..", "..", "runtime", name),
		filepath.Join(exeDir, "..", "..", "..", "runtime", name),
	}
	for _, candidate := range candidates {
		candidate = filepath.Clean(candidate)
		if pathExists(candidate) {
			return candidate, nil
		}
	}
	return "", fmt.Errorf("unable to locate runtime binary: %s", name)
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	encoder := json.NewEncoder(w)
	_ = encoder.Encode(payload)
}

func writeAPIError(w http.ResponseWriter, status int, err error) {
	writeAPIMessage(w, status, err.Error())
}

func writeAPIMessage(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"message": message})
}

func decodeJSONBody(r *http.Request, target any) error {
	defer r.Body.Close()
	decoder := json.NewDecoder(r.Body)
	return decoder.Decode(target)
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

func writeTextFile(targetPath, value string) error {
	if err := ensureDir(filepath.Dir(targetPath)); err != nil {
		return err
	}
	return os.WriteFile(targetPath, []byte(value), 0o600)
}

func ensureDir(targetPath string) error {
	return os.MkdirAll(targetPath, 0o755)
}

func copyFile(sourcePath, targetPath string) error {
	data, err := os.ReadFile(sourcePath)
	if err != nil {
		return err
	}
	if err := ensureDir(filepath.Dir(targetPath)); err != nil {
		return err
	}
	return os.WriteFile(targetPath, data, 0o600)
}

func pathExists(targetPath string) bool {
	_, err := os.Stat(targetPath)
	return err == nil
}

func runCommand(command string, args []string, timeout time.Duration) CommandResult {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, command, args...)
	cmd.Env = normalizeCommandEnv(os.Environ())
	cmd.Dir = stableCommandDir()

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	result := CommandResult{
		Stdout: stdout.String(),
		Stderr: stderr.String(),
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

func normalizeCommandEnv(env []string) []string {
	if len(env) == 0 {
		env = os.Environ()
	}
	normalized := make([]string, 0, len(env)+1)
	pathSet := false
	for _, item := range env {
		if strings.HasPrefix(item, "PATH=") {
			normalized = append(normalized, "PATH="+defaultCommandSearchPath(strings.TrimPrefix(item, "PATH=")))
			pathSet = true
			continue
		}
		normalized = append(normalized, item)
	}
	if !pathSet {
		normalized = append(normalized, "PATH="+defaultCommandSearchPath(""))
	}
	return normalized
}

func defaultCommandSearchPath(existing string) string {
	entries := make([]string, 0, 16)
	homeDir := stableCommandDir()
	if homeDir != "" && homeDir != "/" {
		entries = append(entries, filepath.Join(homeDir, ".local", "bin"))
	}
	entries = append(entries,
		"/opt/homebrew/bin",
		"/usr/local/bin",
		"/usr/bin",
		"/bin",
		"/usr/sbin",
		"/sbin",
	)
	if existing != "" {
		entries = append(entries, strings.Split(existing, ":")...)
	}

	seen := map[string]struct{}{}
	merged := make([]string, 0, len(entries))
	for _, entry := range entries {
		entry = strings.TrimSpace(entry)
		if entry == "" {
			continue
		}
		if _, ok := seen[entry]; ok {
			continue
		}
		seen[entry] = struct{}{}
		merged = append(merged, entry)
	}
	return strings.Join(merged, ":")
}

func stableCommandDir() string {
	candidates := []string{
		strings.TrimSpace(os.Getenv("OPENCLAW_HOME_DIR")),
		strings.TrimSpace(os.Getenv("HOME")),
	}
	for _, candidate := range candidates {
		if candidate != "" && pathExists(candidate) {
			return candidate
		}
	}
	if homeDir, err := os.UserHomeDir(); err == nil && homeDir != "" && pathExists(homeDir) {
		return homeDir
	}
	if cwd, err := os.Getwd(); err == nil && cwd != "" && pathExists(cwd) {
		return cwd
	}
	return "/"
}

func envContainsPath(env []string) bool {
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

func classifyGatewayEvent(line string) string {
	switch {
	case strings.Contains(strings.ToLower(line), "logged in to discord"):
		return "discord_login"
	case strings.Contains(line, "WebSocket connection closed with code 1006"):
		return "discord_disconnect"
	case regexp.MustCompile(`health-monitor: restarting \(reason: (disconnected|stopped|stale-socket|stuck)\)`).MatchString(line):
		return "discord_restart"
	case strings.Contains(line, "[gateway] signal SIGTERM received") || strings.Contains(line, "[gateway] received SIGTERM; shutting down"):
		return "gateway_restart"
	default:
		return ""
	}
}

func classifyWatchdogEvent(line string) string {
	if strings.Contains(line, "[watchdog:warn] restarted ai.openclaw.gateway") {
		return "watchdog_restart"
	}
	return ""
}

func parseLogTimestamp(line string) (int64, bool) {
	matches := timestampPattern.FindStringSubmatch(line)
	if len(matches) != 2 {
		return 0, false
	}
	value := matches[1]
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		parsed, err = time.Parse(time.RFC3339Nano, value)
		if err != nil {
			return 0, false
		}
	}
	return parsed.UnixMilli(), true
}

func parsePmsetTimestamp(value string) time.Time {
	normalized := strings.Replace(value, " +", "T", 1)
	if len(value) >= 25 {
		normalized = value[:10] + "T" + value[11:19] + value[20:23] + ":" + value[23:25]
	}
	parsed, err := time.Parse(time.RFC3339, normalized)
	if err != nil {
		return time.Time{}
	}
	return parsed
}

func cleanOutput(stdout, stderr string) *string {
	text := strings.TrimSpace(strings.Join(filterNonEmpty([]string{strings.TrimSpace(stdout), strings.TrimSpace(stderr)}), "\n"))
	if text == "" {
		return nil
	}
	if len(text) > 4000 {
		text = text[:4000] + "\n..."
	}
	return &text
}

func prefixedLine(text, prefix string) string {
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, prefix) {
			return strings.TrimSpace(strings.TrimPrefix(line, prefix))
		}
	}
	return ""
}

func expandUserPath(value, homeDir string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return ""
	}
	if strings.HasPrefix(value, "~/") && homeDir != "" {
		return filepath.Join(homeDir, value[2:])
	}
	return value
}

func explainGatewayFailure(errorText *string) string {
	text := strings.TrimSpace(derefString(errorText))
	normalized := strings.ToLower(text)
	switch {
	case strings.Contains(normalized, "uv_cwd") || strings.Contains(normalized, "getcwd") || strings.Contains(normalized, "cannot access parent directories"):
		return "当前运行中的服务工作目录已经失效。通常是 app 被替换后旧进程还在跑，重启服务或重开 app 即可恢复。"
	case strings.Contains(normalized, "enoent") && strings.Contains(normalized, "openclaw"):
		return "未找到 OpenClaw CLI。先确认已安装，并保证环境包含 ~/.local/bin/openclaw。"
	case strings.Contains(normalized, "invalid json"):
		return "gateway 返回了无效状态。先重启 OpenClaw 服务，再看日志。"
	case strings.Contains(normalized, "timed out"):
		return "OpenClaw 状态检查超时。先重启 OpenClaw 服务。"
	case strings.Contains(normalized, "econnrefused") || strings.Contains(normalized, "connect") || strings.Contains(normalized, "status failed"):
		return "gateway 没有正常响应。先重启 OpenClaw 服务。"
	default:
		if text != "" {
			return text
		}
		return "当前无法连接 OpenClaw gateway。先重启 OpenClaw 服务，再看日志。"
	}
}

func getAllowedWebOrigins() []string {
	origins := append([]string{}, defaultDevWebOrigins...)
	configured := strings.Split(strings.TrimSpace(os.Getenv("OPENCLAW_WEB_ORIGINS")), ",")
	seen := map[string]struct{}{}
	out := make([]string, 0)
	for _, item := range append(origins, configured...) {
		item = strings.TrimSpace(item)
		if item == "" {
			continue
		}
		if _, ok := seen[item]; ok {
			continue
		}
		seen[item] = struct{}{}
		out = append(out, item)
	}
	return out
}

func decodeJWTPayload(token string) map[string]any {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return nil
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil
	}
	var decoded map[string]any
	if err := json.Unmarshal(payload, &decoded); err != nil {
		return nil
	}
	return decoded
}

func extractAccountID(accessToken string) string {
	payload := decodeJWTPayload(accessToken)
	auth, ok := payload[openAIAuthClaim].(map[string]any)
	if !ok {
		return ""
	}
	return anyString(auth["chatgpt_account_id"])
}

func extractEmail(accessToken string) string {
	payload := decodeJWTPayload(accessToken)
	profile, ok := payload[openAIProfileClaim].(map[string]any)
	if !ok {
		return ""
	}
	return anyString(profile["email"])
}

func normalizeProfileName(raw string, allowDefault bool) (string, error) {
	normalized := strings.ToLower(strings.TrimSpace(raw))
	if normalized == "" {
		return "", errors.New("profileName is required")
	}
	if normalized == defaultProfileName && !allowDefault {
		return "", errors.New("default profile is reserved")
	}
	if !profileNamePattern.MatchString(normalized) {
		return "", errors.New("profileName must match ^[a-z0-9][a-z0-9_-]{0,31}$")
	}
	return normalized, nil
}

func profileSortKey(name string) string {
	if name == defaultProfileName {
		return ""
	}
	return name
}

func shouldSkipDiscoveryDir(entryName string) bool {
	switch entryName {
	case "Applications", "Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public", "node_modules", ".cache", ".docker", ".git", ".local", ".npm", ".nvm", ".Trash":
		return true
	default:
		return false
	}
}

func profileNameFromStateDirName(entryName string) string {
	if entryName == ".openclaw" {
		return defaultProfileName
	}
	if strings.HasPrefix(entryName, ".openclaw-") {
		suffix := strings.TrimPrefix(entryName, ".openclaw-")
		if suffix != "" {
			return suffix
		}
	}
	return ""
}

func preferDiscoveredStateDir(current, candidate string) string {
	if current == "" {
		return candidate
	}
	if len(candidate) < len(current) {
		return candidate
	}
	if candidate < current {
		return candidate
	}
	return current
}

func clampProbeIntervalMs(value int) int {
	if value <= 0 {
		return defaultProbeIntervalMinMs
	}
	return max(minProbeIntervalMs, min(maxProbeIntervalMs, value))
}

func averageProbeIntervalMs(settings ManagerSettings) int {
	return (settings.ProbeIntervalMinMs + settings.ProbeIntervalMaxMs) / 2
}

func pickRandomProbeDelayMs(settings ManagerSettings) int {
	if settings.ProbeIntervalMaxMs <= settings.ProbeIntervalMinMs {
		return settings.ProbeIntervalMinMs
	}
	diff := settings.ProbeIntervalMaxMs - settings.ProbeIntervalMinMs + 1
	if diff <= 1 {
		return settings.ProbeIntervalMinMs
	}
	value, err := crand.Int(crand.Reader, big.NewInt(int64(diff)))
	if err != nil {
		return settings.ProbeIntervalMinMs
	}
	return settings.ProbeIntervalMinMs + int(value.Int64())
}

func recordActivationTelemetry(state *NormalizedManagerState, trigger string, durationMs int, reason string) {
	total := derefInt(state.Runtime.TotalActivations) + 1
	prevTotal := derefInt(state.Runtime.TotalActivations)
	prevAverage := derefInt(state.Runtime.AverageActivationDurationMs)
	activatedAt := nowISO()
	if state.LastActivatedAt != nil {
		activatedAt = *state.LastActivatedAt
	}
	state.Runtime.TotalActivations = ptr(total)
	state.Runtime.LastActivationAt = &activatedAt
	state.Runtime.LastActivationDurationMs = ptr(durationMs)
	if prevTotal <= 0 {
		state.Runtime.AverageActivationDurationMs = ptr(durationMs)
	} else {
		state.Runtime.AverageActivationDurationMs = ptr(int(math.Round((float64(prevAverage*prevTotal) + float64(durationMs)) / float64(total))))
	}
	state.Runtime.LastActivationTrigger = &trigger
	state.Runtime.LastSyncedAt = &activatedAt
	if reason != "" {
		state.Runtime.LastActivationReason = &reason
	} else {
		switch trigger {
		case "auto":
			message := "automatic profile activation"
			state.Runtime.LastActivationReason = &message
		case "recommended":
			message := "manual recommended activation"
			state.Runtime.LastActivationReason = &message
		default:
			message := "manual profile activation"
			state.Runtime.LastActivationReason = &message
		}
	}
	switch trigger {
	case "auto":
		state.Runtime.AutoActivations = ptr(derefInt(state.Runtime.AutoActivations) + 1)
	case "recommended":
		state.Runtime.RecommendedActivations = ptr(derefInt(state.Runtime.RecommendedActivations) + 1)
	default:
		state.Runtime.ManualActivations = ptr(derefInt(state.Runtime.ManualActivations) + 1)
	}
}

func truncateEvents(events []SupportLogEvent, limit int) []SupportLogEvent {
	if len(events) <= limit {
		return events
	}
	return append([]SupportLogEvent(nil), events[:limit]...)
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
	case int:
		return int64(typed), true
	case int64:
		return typed, true
	case float64:
		return int64(typed), true
	case json.Number:
		parsed, err := typed.Int64()
		return parsed, err == nil
	default:
		return 0, false
	}
}

func anyInt(value any) int {
	if parsed, ok := anyInt64(value); ok {
		return int(parsed)
	}
	return 0
}

func resolveBinaryPath(value string) (string, bool) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", false
	}
	if pathExists(value) {
		return value, true
	}
	resolved, err := exec.LookPath(value)
	if err != nil {
		return "", false
	}
	return resolved, true
}

func syscallString(name string) string {
	result := runCommand("sysctl", []string{"-n", name}, 8*time.Second)
	if !result.OK && strings.TrimSpace(result.Stdout) == "" {
		return ""
	}
	return strings.TrimSpace(result.Stdout)
}

func parseMachineProcessLine(line string) (pid int, cpuPercent float64, rssBytes int64, uptimeSeconds int, command string, ok bool) {
	matches := psProcessPattern.FindStringSubmatch(line)
	if len(matches) != 6 {
		return 0, 0, 0, 0, "", false
	}

	parsedPID, err := strconv.Atoi(matches[1])
	if err != nil {
		return 0, 0, 0, 0, "", false
	}
	parsedCPU, err := strconv.ParseFloat(matches[2], 64)
	if err != nil {
		return 0, 0, 0, 0, "", false
	}
	parsedRSS, err := strconv.ParseInt(matches[3], 10, 64)
	if err != nil {
		return 0, 0, 0, 0, "", false
	}
	parsedUptime, ok := parseElapsedSeconds(matches[4])
	if !ok {
		return 0, 0, 0, 0, "", false
	}

	command = strings.TrimSpace(matches[5])
	if command == "" {
		return 0, 0, 0, 0, "", false
	}

	return parsedPID, parsedCPU, parsedRSS * 1024, parsedUptime, command, true
}

func processDisplayName(command string) string {
	command = strings.TrimSpace(command)
	if command == "" {
		return "未知进程"
	}
	base := filepath.Base(command)
	if strings.TrimSpace(base) == "" || base == "." || base == "/" {
		return command
	}
	return base
}

func parseElapsedSeconds(value string) (int, bool) {
	value = strings.TrimSpace(value)
	if value == "" {
		return 0, false
	}

	dayParts := strings.SplitN(value, "-", 2)
	days := 0
	clock := value
	if len(dayParts) == 2 {
		parsedDays, err := strconv.Atoi(dayParts[0])
		if err != nil {
			return 0, false
		}
		days = parsedDays
		clock = dayParts[1]
	}

	parts := strings.Split(clock, ":")
	if len(parts) < 2 || len(parts) > 3 {
		return 0, false
	}

	toInt := func(raw string) (int, bool) {
		parsed, err := strconv.Atoi(strings.TrimSpace(raw))
		return parsed, err == nil
	}

	hours := 0
	minutes := 0
	seconds := 0
	if len(parts) == 3 {
		var ok bool
		hours, ok = toInt(parts[0])
		if !ok {
			return 0, false
		}
		minutes, ok = toInt(parts[1])
		if !ok {
			return 0, false
		}
		seconds, ok = toInt(parts[2])
		if !ok {
			return 0, false
		}
	} else {
		var ok bool
		minutes, ok = toInt(parts[0])
		if !ok {
			return 0, false
		}
		seconds, ok = toInt(parts[1])
		if !ok {
			return 0, false
		}
	}

	return (((days * 24) + hours) * 60 * 60) + (minutes * 60) + seconds, true
}

func matchesProcessCommand(command, suffix string) bool {
	command = strings.TrimSpace(command)
	suffix = strings.TrimSpace(suffix)
	if command == "" || suffix == "" {
		return false
	}
	if strings.HasSuffix(command, "/"+suffix) || command == suffix {
		return true
	}
	base := filepath.Base(strings.Fields(command)[0])
	return base == suffix
}

func shouldReplaceProcessSnapshot(current, candidate MachineProcessSnapshot) bool {
	if !candidate.Running {
		return false
	}
	if !current.Running {
		return true
	}
	if derefInt(candidate.UptimeSeconds) != derefInt(current.UptimeSeconds) {
		return derefInt(candidate.UptimeSeconds) > derefInt(current.UptimeSeconds)
	}
	return derefInt64(candidate.RSSBytes) > derefInt64(current.RSSBytes)
}

func parseVMStatPageSize(line string) int64 {
	group := firstRegexGroup(line, `page size of ([0-9]+) bytes`)
	if group == "" {
		return 0
	}
	value, err := strconv.ParseInt(group, 10, 64)
	if err != nil {
		return 0
	}
	return value
}

func parseVMStatLine(line string) (string, int64, bool) {
	matches := vmStatLinePattern.FindStringSubmatch(line)
	if len(matches) != 3 {
		return "", 0, false
	}
	value, err := strconv.ParseInt(matches[2], 10, 64)
	if err != nil {
		return "", 0, false
	}
	return strings.TrimSpace(matches[1]), value, true
}

func parseSwapUsage(value string) MachineSwap {
	swap := MachineSwap{}
	for _, match := range swapUsagePattern.FindAllStringSubmatch(strings.TrimSpace(value), -1) {
		if len(match) != 4 {
			continue
		}
		bytes := parseHumanBytes(match[2], match[3])
		switch strings.ToLower(match[1]) {
		case "total":
			swap.TotalBytes = bytes
		case "used":
			swap.UsedBytes = bytes
		case "free":
			swap.FreeBytes = bytes
		}
	}
	swap.UsedPercent = percentFromBytes(swap.UsedBytes, swap.TotalBytes)
	return swap
}

func parseHumanBytes(value, unit string) int64 {
	parsed, err := strconv.ParseFloat(strings.TrimSpace(value), 64)
	if err != nil {
		return 0
	}
	multiplier := float64(1)
	switch strings.ToUpper(strings.TrimSpace(unit)) {
	case "T":
		multiplier = 1024 * 1024 * 1024 * 1024
	case "G":
		multiplier = 1024 * 1024 * 1024
	case "M":
		multiplier = 1024 * 1024
	case "K":
		multiplier = 1024
	}
	return int64(math.Round(parsed * multiplier))
}

func percentFromBytes(usedBytes, totalBytes int64) int {
	if usedBytes <= 0 || totalBytes <= 0 {
		return 0
	}
	return clampPercentFloat((float64(usedBytes) / float64(totalBytes)) * 100)
}

func preferredNetworkInterface(byInterface map[string]machineInterfaceCounters) (string, machineInterfaceCounters) {
	bestName := ""
	bestCounters := machineInterfaceCounters{}
	bestTotal := uint64(0)
	for name, snapshot := range byInterface {
		total := snapshot.Received + snapshot.Sent
		if total == 0 {
			continue
		}
		if total > bestTotal || (total == bestTotal && name < bestName) {
			bestName = name
			bestCounters = machineInterfaceCounters{
				Received: snapshot.Received,
				Sent:     snapshot.Sent,
			}
			bestTotal = total
		}
	}
	return bestName, bestCounters
}

func anyStringOrDefault(value any, fallback string) string {
	if text := strings.TrimSpace(anyString(value)); text != "" {
		return text
	}
	return fallback
}

func nullableString(value string) *string {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	return &value
}

func nullableInt(value int) *int {
	if value == 0 {
		return nil
	}
	return &value
}

func nullableInt64(value int64) *int64 {
	if value == 0 {
		return nil
	}
	return &value
}

func nullableFloat64(value float64) *float64 {
	if value == 0 {
		return nil
	}
	return &value
}

func nullableTimeFromMillis(value int64) *string {
	if value <= 0 {
		return nil
	}
	timestamp := time.UnixMilli(value).UTC().Format(time.RFC3339)
	return &timestamp
}

func nullableDurationUntilMillis(targetMs int64) *int {
	if targetMs <= 0 {
		return nil
	}
	delta := int(time.Until(time.UnixMilli(targetMs)).Milliseconds())
	if delta < 0 {
		delta = 0
	}
	return &delta
}

func firstRegexGroup(source, pattern string) string {
	matches := regexp.MustCompile(pattern).FindStringSubmatch(source)
	if len(matches) >= 2 {
		return strings.TrimSpace(matches[1])
	}
	return ""
}

func firstProxyValue(source, key string) string {
	for _, line := range strings.Split(source, "\n") {
		if !strings.Contains(line, key+" :") {
			continue
		}
		parts := strings.SplitN(line, ":", 2)
		if len(parts) == 2 {
			return strings.TrimSpace(parts[1])
		}
	}
	return ""
}

func filterNonEmpty(values []string) []string {
	out := make([]string, 0, len(values))
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			out = append(out, value)
		}
	}
	return out
}

func derefString(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}

func derefInt(value *int) int {
	if value == nil {
		return 0
	}
	return *value
}

func derefInt64(value *int64) int64 {
	if value == nil {
		return 0
	}
	return *value
}

func derefFloat64(value *float64) float64 {
	if value == nil {
		return 0
	}
	return *value
}

func clampPercentFloat(value float64) int {
	if math.IsNaN(value) || math.IsInf(value, 0) {
		return 0
	}
	if value < 0 {
		return 0
	}
	if value > 100 {
		return 100
	}
	return int(math.Round(value))
}

func containsString(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}

func sameStrings(left, right []string) bool {
	if len(left) != len(right) {
		return false
	}
	for idx := range left {
		if left[idx] != right[idx] {
			return false
		}
	}
	return true
}

func isValidTrigger(value string) bool {
	return value == "manual" || value == "auto" || value == "recommended"
}

func envInt(key string, fallback int) int {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func nowISO() string {
	return time.Now().UTC().Format(time.RFC3339)
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func ptr[T any](value T) *T {
	return &value
}

func newUUID() string {
	raw := make([]byte, 16)
	if _, err := io.ReadFull(crand.Reader, raw); err != nil {
		return fmt.Sprintf("flow-%d", time.Now().UnixNano())
	}
	raw[6] = (raw[6] & 0x0f) | 0x40
	raw[8] = (raw[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", raw[0:4], raw[4:6], raw[6:8], raw[8:10], raw[10:16])
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
