#!/usr/bin/env node
import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import { spawn } from 'node:child_process'

const args = new Set(process.argv.slice(2))
const checkOnly = args.has('--check-only')
const runOnce = args.has('--once') || checkOnly

const HOME = os.homedir()
const OPENCLAW_STATE_DIR = process.env.OPENCLAW_STATE_DIR?.trim() || path.join(HOME, '.openclaw')
const SESSION_DIR = path.join(OPENCLAW_STATE_DIR, 'agents', 'main', 'sessions')
const SESSION_STORE_PATH = path.join(SESSION_DIR, 'sessions.json')
const GATEWAY_LOG_PATH = path.join(OPENCLAW_STATE_DIR, 'logs', 'gateway.log')
const WATCHDOG_STATE_DIR =
  process.env.OPENCLAW_WATCHDOG_STATE_DIR?.trim() ||
  path.join(HOME, 'Library', 'Application Support', 'OpenClaw Manager Native', 'watchdog')
const WATCHDOG_STATE_PATH = path.join(WATCHDOG_STATE_DIR, 'state.json')
const GATEWAY_LABEL = process.env.OPENCLAW_WATCHDOG_TARGET_LABEL?.trim() || 'ai.openclaw.gateway'
const GATEWAY_PLIST_PATH =
  process.env.OPENCLAW_WATCHDOG_GATEWAY_PLIST?.trim() ||
  path.join(HOME, 'Library', 'LaunchAgents', `${GATEWAY_LABEL}.plist`)
const LOOP_MS = clampNumber(process.env.OPENCLAW_WATCHDOG_LOOP_MS, 30_000, 10_000, 10 * 60_000)
const DETECTION_WINDOW_MS = clampNumber(
  process.env.OPENCLAW_WATCHDOG_DETECTION_WINDOW_MS,
  15 * 60_000,
  60_000,
  60 * 60_000
)
const LOCK_STALL_MS = clampNumber(process.env.OPENCLAW_WATCHDOG_LOCK_STALL_MS, 6 * 60_000, 60_000, 60 * 60_000)
const RESTART_COOLDOWN_MS = clampNumber(
  process.env.OPENCLAW_WATCHDOG_RESTART_COOLDOWN_MS,
  5 * 60_000,
  30_000,
  60 * 60_000
)
const COMMAND_TIMEOUT_MS = clampNumber(process.env.OPENCLAW_WATCHDOG_COMMAND_TIMEOUT_MS, 15_000, 1_000, 60_000)
const LOG_TAIL_BYTES = clampNumber(
  process.env.OPENCLAW_WATCHDOG_LOG_TAIL_BYTES,
  512 * 1024,
  16 * 1024,
  4 * 1024 * 1024
)
const SOFT_RESTART_THRESHOLD = clampNumber(process.env.OPENCLAW_WATCHDOG_SOFT_RESTART_THRESHOLD, 3, 1, 20)

const fatalPatterns = [
  { regex: /embedded run timeout/i, code: 'embedded-run-timeout' },
  { regex: /Profile .* timed out/i, code: 'profile-timed-out' },
  { regex: /lane wait exceeded/i, code: 'lane-wait-exceeded' },
  { regex: /Slow listener detected/i, code: 'slow-listener-detected' },
  { regex: /Unhandled promise rejection/i, code: 'unhandled-promise-rejection' }
]

const softPatterns = [
  { regex: /health-monitor: restarting \(reason: stuck\)/i, code: 'health-monitor-stuck' },
  { regex: /health-monitor: restarting \(reason: stale-socket\)/i, code: 'health-monitor-stale-socket' },
  { regex: /health-monitor: restarting \(reason: disconnected\)/i, code: 'health-monitor-disconnected' },
  { regex: /health-monitor: restarting \(reason: stopped\)/i, code: 'health-monitor-stopped' },
  { regex: /WebSocket connection closed with code 1006/i, code: 'discord-websocket-1006' }
]

const severeSoftCodes = new Set([
  'health-monitor-disconnected',
  'health-monitor-stopped',
  'discord-websocket-1006'
])

function clampNumber(rawValue, fallback, min, max) {
  const parsed = Number(rawValue)
  if (!Number.isFinite(parsed)) return fallback
  return Math.max(min, Math.min(max, Math.round(parsed)))
}

async function pathExists(targetPath) {
  try {
    await fs.access(targetPath)
    return true
  } catch {
    return false
  }
}

async function ensureDir(targetPath) {
  await fs.mkdir(targetPath, { recursive: true })
}

async function readJsonFile(targetPath, fallback) {
  try {
    const raw = await fs.readFile(targetPath, 'utf8')
    return JSON.parse(raw)
  } catch {
    return fallback
  }
}

async function writeJsonFile(targetPath, value) {
  await ensureDir(path.dirname(targetPath))
  await fs.writeFile(targetPath, `${JSON.stringify(value, null, 2)}
`, { mode: 0o600 })
}

function isoNow() {
  return new Date().toISOString()
}

function log(level, message, details) {
  const suffix = details ? ` ${JSON.stringify(details)}` : ''
  console.log(`${isoNow()} [watchdog:${level}] ${message}${suffix}`)
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function runCommand(command, commandArgs, timeoutMs = COMMAND_TIMEOUT_MS) {
  return new Promise((resolve) => {
    const child = spawn(command, commandArgs, {
      env: {
        ...process.env,
        PATH: process.env.PATH || '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'
      },
      stdio: ['ignore', 'pipe', 'pipe']
    })

    let stdout = ''
    let stderr = ''
    let finished = false
    const timer = setTimeout(() => {
      if (finished) return
      finished = true
      child.kill('SIGKILL')
      resolve({ ok: false, code: null, stdout, stderr, timedOut: true })
    }, timeoutMs)

    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString()
    })
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString()
    })
    child.on('error', (error) => {
      if (finished) return
      finished = true
      clearTimeout(timer)
      stderr += error instanceof Error ? error.message : String(error)
      resolve({ ok: false, code: null, stdout, stderr, timedOut: false })
    })
    child.on('close', (code) => {
      if (finished) return
      finished = true
      clearTimeout(timer)
      resolve({ ok: code === 0, code, stdout, stderr, timedOut: false })
    })
  })
}

async function readTail(targetPath, maxBytes = LOG_TAIL_BYTES) {
  const handle = await fs.open(targetPath, 'r')
  try {
    const stat = await handle.stat()
    const length = Math.min(stat.size, maxBytes)
    if (length <= 0) return ''
    const buffer = Buffer.alloc(length)
    await handle.read(buffer, 0, length, stat.size - length)
    return buffer.toString('utf8')
  } finally {
    await handle.close()
  }
}

async function getGatewayJob() {
  const result = await runCommand('launchctl', ['list'])
  if (!result.ok) {
    return {
      running: false,
      pid: null,
      lastExitStatus: null,
      error: result.stderr.trim() || result.stdout.trim() || 'launchctl_list_failed'
    }
  }

  const line = result.stdout
    .split(/\r?\n/)
    .map((entry) => entry.trim())
    .find((entry) => entry.endsWith(`	${GATEWAY_LABEL}`) || entry.endsWith(` ${GATEWAY_LABEL}`))

  if (!line) {
    return {
      running: false,
      pid: null,
      lastExitStatus: null,
      error: 'gateway_label_missing'
    }
  }

  const parts = line.split(/\s+/)
  const pidToken = parts[0] ?? '-'
  const exitToken = parts[1] ?? '-'
  const pid = pidToken === '-' ? null : Number(pidToken)
  const lastExitStatus = exitToken === '-' ? null : Number(exitToken)

  return {
    running: Number.isFinite(pid) && pid > 0,
    pid: Number.isFinite(pid) ? pid : null,
    lastExitStatus: Number.isFinite(lastExitStatus) ? lastExitStatus : null,
    error: null
  }
}

async function loadSessionsById() {
  const raw = await readJsonFile(SESSION_STORE_PATH, {})
  const bySessionId = new Map()
  for (const [key, value] of Object.entries(raw)) {
    if (!value || typeof value !== 'object') continue
    const sessionId = typeof value.sessionId === 'string' ? value.sessionId : null
    if (!sessionId) continue
    bySessionId.set(sessionId, { key, ...value })
  }
  return bySessionId
}

async function findStalledLocks(nowMs, sessionsById) {
  let names = []
  try {
    names = await fs.readdir(SESSION_DIR)
  } catch {
    return []
  }

  const stalls = []
  for (const name of names) {
    if (!name.endsWith('.jsonl.lock')) continue

    const lockPath = path.join(SESSION_DIR, name)
    let stat = null
    try {
      stat = await fs.stat(lockPath)
    } catch {
      continue
    }

    const sessionId = name.replace(/\.jsonl\.lock$/, '')
    const session = sessionsById.get(sessionId) ?? null
    const updatedAtMs = typeof session?.updatedAt === 'number' ? session.updatedAt : 0
    const lastTouchMs = Math.max(stat.mtimeMs, updatedAtMs)
    const ageMs = nowMs - lastTouchMs

    if (ageMs < LOCK_STALL_MS) continue

    stalls.push({
      sessionId,
      key: session?.key ?? null,
      chatType: session?.chatType ?? null,
      updatedAtMs: updatedAtMs || null,
      lockMtimeMs: stat.mtimeMs,
      ageMs,
      lockPath
    })
  }

  return stalls
}

function extractRecentGatewayEvents(logText, minTimestampMs) {
  const events = []
  for (const line of logText.split(/\r?\n/)) {
    const match = line.match(/^(\d{4}-\d{2}-\d{2}T\S+)\s+(.*)$/)
    if (!match) continue

    const timestampMs = Date.parse(match[1])
    if (!Number.isFinite(timestampMs) || timestampMs < minTimestampMs) continue

    const body = match[2]

    for (const pattern of fatalPatterns) {
      if (pattern.regex.test(body)) {
        events.push({ level: 'fatal', code: pattern.code, timestampMs, line })
        break
      }
    }

    for (const pattern of softPatterns) {
      if (pattern.regex.test(body)) {
        events.push({ level: 'soft', code: pattern.code, timestampMs, line })
        break
      }
    }
  }

  return events
}

function summarizeEvents(events) {
  const summary = {}
  for (const event of events) {
    summary[event.code] = (summary[event.code] ?? 0) + 1
  }
  return summary
}

function restartCooldownMsForReason(reason) {
  if (reason === 'gateway-not-running') return 30_000
  if (reason === 'stalled-session-lock') return 90_000
  if (reason === 'discord-link-unstable') return 90_000
  return RESTART_COOLDOWN_MS
}

function restartAllowed(state, nowMs, reason) {
  const cooldownMs = restartCooldownMsForReason(reason)
  return !state.lastRestartAtMs || nowMs - state.lastRestartAtMs >= cooldownMs
}

async function restartGateway(reason, details) {
  const uid = typeof process.getuid === 'function' ? process.getuid() : null
  const target = uid ? `gui/${uid}/${GATEWAY_LABEL}` : GATEWAY_LABEL
  let result = await runCommand('launchctl', ['kickstart', '-k', target])

  if (!result.ok && (await pathExists(GATEWAY_PLIST_PATH)) && uid) {
    await runCommand('launchctl', ['bootout', `gui/${uid}`, GATEWAY_PLIST_PATH])
    await sleep(1_000)
    result = await runCommand('launchctl', ['bootstrap', `gui/${uid}`, GATEWAY_PLIST_PATH])
    if (result.ok) {
      result = await runCommand('launchctl', ['kickstart', '-k', target])
    }
  }

  if (!result.ok) {
    throw new Error(`restart_failed ${result.stderr.trim() || result.stdout.trim() || 'unknown'}`.trim())
  }

  log('warn', `restarted ${GATEWAY_LABEL}`, { reason, details })
  await sleep(3_000)
  const job = await getGatewayJob()
  return { pid: job.pid ?? null }
}

async function inspect(state) {
  const nowMs = Date.now()
  const minTimestampMs = Math.max(nowMs - DETECTION_WINDOW_MS, state.lastRestartAtMs ?? 0)
  const job = await getGatewayJob()
  if (!job.running) {
    return {
      nowMs,
      healthy: false,
      action: restartAllowed(state, nowMs, 'gateway-not-running') ? 'restart' : 'cooldown',
      reason: 'gateway-not-running',
      details: { job }
    }
  }

  const sessionsById = await loadSessionsById()
  const stalledLocks = await findStalledLocks(nowMs, sessionsById)
  if (stalledLocks.length > 0) {
    return {
      nowMs,
      healthy: false,
      action: restartAllowed(state, nowMs, 'stalled-session-lock') ? 'restart' : 'cooldown',
      reason: 'stalled-session-lock',
      details: { stalledLocks }
    }
  }

  const logText = await readTail(GATEWAY_LOG_PATH).catch(() => '')
  const events = extractRecentGatewayEvents(logText, minTimestampMs)
  const fatalEvents = events.filter((event) => event.level === 'fatal')
  if (fatalEvents.length > 0) {
    return {
      nowMs,
      healthy: false,
      action: restartAllowed(state, nowMs, fatalEvents[0].code) ? 'restart' : 'cooldown',
      reason: fatalEvents[0].code,
      details: {
        events: summarizeEvents(events),
        sample: fatalEvents.slice(0, 3).map((event) => event.line)
      }
    }
  }

  const softEvents = events.filter((event) => event.level === 'soft')
  const severeSoftEvents = softEvents.filter((event) => severeSoftCodes.has(event.code))
  if (severeSoftEvents.length >= 2) {
    return {
      nowMs,
      healthy: false,
      action: restartAllowed(state, nowMs, 'discord-link-unstable') ? 'restart' : 'cooldown',
      reason: 'discord-link-unstable',
      details: {
        events: summarizeEvents(events),
        sample: severeSoftEvents.slice(0, 3).map((event) => event.line)
      }
    }
  }

  if (softEvents.length >= SOFT_RESTART_THRESHOLD) {
    return {
      nowMs,
      healthy: false,
      action: restartAllowed(state, nowMs, 'repeated-health-monitor-restarts') ? 'restart' : 'cooldown',
      reason: 'repeated-health-monitor-restarts',
      details: {
        events: summarizeEvents(events),
        sample: softEvents.slice(0, 3).map((event) => event.line)
      }
    }
  }

  return {
    nowMs,
    healthy: true,
    action: 'none',
    reason: 'healthy',
    details: {
      pid: job.pid,
      lastExitStatus: job.lastExitStatus,
      recentEvents: summarizeEvents(events)
    }
  }
}

async function runCycle() {
  const state = await readJsonFile(WATCHDOG_STATE_PATH, {
    createdAt: isoNow(),
    restartCount: 0,
    lastRestartAtMs: null,
    lastRestartReason: null,
    lastRestartPid: null,
    lastHealthyAt: null,
    lastIssueAt: null,
    lastIssueReason: null,
    lastLoopAt: null,
    lastLoopResult: null
  })

  const inspection = await inspect(state)
  state.lastLoopAt = isoNow()
  state.lastLoopResult = inspection.reason

  if (inspection.healthy) {
    state.lastHealthyAt = state.lastLoopAt
    await writeJsonFile(WATCHDOG_STATE_PATH, state)
    if (runOnce) {
      console.log(JSON.stringify({ ok: true, inspection, state }, null, 2))
    }
    return
  }

  state.lastIssueAt = state.lastLoopAt
  state.lastIssueReason = inspection.reason

  if (inspection.action === 'restart' && !checkOnly) {
    const restarted = await restartGateway(inspection.reason, inspection.details)
    state.restartCount = Number(state.restartCount || 0) + 1
    state.lastRestartAtMs = Date.now()
    state.lastRestartReason = inspection.reason
    state.lastRestartPid = restarted.pid
  } else if (inspection.action === 'cooldown') {
    log('warn', 'detected issue but restart is cooling down', {
      reason: inspection.reason,
      details: inspection.details,
      lastRestartAtMs: state.lastRestartAtMs
    })
  } else if (checkOnly) {
    log('info', 'check-only detected issue', { reason: inspection.reason, details: inspection.details })
  }

  await writeJsonFile(WATCHDOG_STATE_PATH, state)

  if (runOnce) {
    console.log(JSON.stringify({ ok: inspection.action !== 'restart' || !checkOnly, inspection, state }, null, 2))
  }
}

async function main() {
  await ensureDir(WATCHDOG_STATE_DIR)
  if (runOnce) {
    await runCycle()
    return
  }

  log('info', 'watchdog started', {
    gatewayLabel: GATEWAY_LABEL,
    loopMs: LOOP_MS,
    detectionWindowMs: DETECTION_WINDOW_MS,
    lockStallMs: LOCK_STALL_MS,
    restartCooldownMs: RESTART_COOLDOWN_MS
  })

  while (true) {
    try {
      await runCycle()
    } catch (error) {
      log('error', 'watchdog cycle failed', { error: error instanceof Error ? error.message : String(error) })
    }
    await sleep(LOOP_MS)
  }
}

await main()
