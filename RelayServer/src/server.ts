import { WebSocketServer, WebSocket } from 'ws'
import { Bridge, type PushSender } from './bridge.js'
import { HubBridge, type Conn } from './hubs.js'
import { Registry, type ClientLike } from './registry.js'
import { parseEnvelope, type Envelope } from './protocol.js'

export interface ServerOptions {
  port: number
  push: PushSender
  helloTimeoutMs?: number
  heartbeatMs?: number
  attachTimeoutMs?: number
}

const MAX_FAILED_HELLOS = 5
const FAILURE_WINDOW_MS = 60_000

export function startServer(opts: ServerOptions): { wss: WebSocketServer; close(): void } {
  const registry = new Registry()
  const bridge = new Bridge(registry, opts.push)
  const hubs = new HubBridge({ attachTimeoutMs: opts.attachTimeoutMs })
  const wss = new WebSocketServer({ port: opts.port, maxPayload: 1_000_000 })
  const failedHellos = new Map<string, { count: number; resetAt: number }>()

  wss.on('connection', (ws: WebSocket & { isAlive?: boolean }, req) => {
    const forwarded = req.headers['x-forwarded-for']
    const ip = (typeof forwarded === 'string' ? forwarded.split(',')[0]!.trim() : '')
      || req.socket.remoteAddress
      || 'unknown'
    const client = {
      send: (d: string) => { if (ws.readyState === WebSocket.OPEN) ws.send(d) },
      close: (c?: number, r?: string) => ws.close(c, r),
    }
    let session: Conn | null = null
    ws.isAlive = true

    const helloTimer = setTimeout(() => {
      if (!session) ws.close(4001, 'hello timeout')
    }, opts.helloTimeoutMs ?? 5000)

    ws.on('error', () => { /* maxPayload veya diğer ws hataları; bağlantı zaten kapanıyor */ })
    ws.on('pong', () => { ws.isAlive = true })
    ws.on('message', (data) => {
      const env = parseEnvelope(data.toString())
      if (!env) { ws.close(4002, 'bad message'); return }
      if (!session) {
        if (tooManyFailures(ip)) { ws.close(); return }
        session = hello(client, env, ip)
        if (session) clearTimeout(helloTimer)
        else { recordFailure(ip); ws.close() }
        return
      }
      session.message(env)
    })
    ws.on('close', () => {
      clearTimeout(helloTimer)
      session?.close()
    })
  })

  const heartbeat = setInterval(() => {
    for (const ws of wss.clients as Set<WebSocket & { isAlive?: boolean }>) {
      if (ws.isAlive === false) { ws.terminate(); continue }
      ws.isAlive = false
      ws.ping()
    }
    hubs.sweep()
  }, opts.heartbeatMs ?? 30_000)

  /** `hub`/`controller` rolleri Mac'ten Mac'e kanala (docs/design/08), diğerleri telefon odasına. */
  function hello(client: ClientLike, env: Envelope, ip: string): Conn | null {
    if (HubBridge.claims(env)) return hubs.handleHello(client, env, () => recordFailure(ip))
    const session = bridge.handleHello(client, env)
    if (!session) return null
    return { message: (e) => bridge.handleMessage(session, e), close: () => bridge.handleClose(session) }
  }

  function tooManyFailures(ip: string): boolean {
    const entry = failedHellos.get(ip)
    return !!entry && entry.resetAt > Date.now() && entry.count >= MAX_FAILED_HELLOS
  }

  function recordFailure(ip: string): void {
    const now = Date.now()
    const entry = failedHellos.get(ip)
    if (!entry || entry.resetAt < now) failedHellos.set(ip, { count: 1, resetAt: now + FAILURE_WINDOW_MS })
    else entry.count += 1
  }

  return {
    wss,
    close: () => {
      clearInterval(heartbeat)
      for (const ws of wss.clients) ws.terminate()
      wss.close()
    },
  }
}
