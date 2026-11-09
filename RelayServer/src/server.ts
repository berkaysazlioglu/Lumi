import { createServer, type IncomingMessage, type Server } from 'node:http'
import type { Duplex } from 'node:stream'
import { WebSocketServer, WebSocket } from 'ws'
import type { AuthenticatedToken, ServerAccess } from './access.js'
import { Bridge, type PushSender } from './bridge.js'
import { createDashboard, text } from './dashboard/routes.js'
import { HubBridge, type Conn } from './hubs.js'
import { Registry, type ClientLike } from './registry.js'
import { parseEnvelope, type Envelope } from './protocol.js'
import { bearerToken, clientIp, FailureLimiter } from './request.js'

export interface ServerOptions {
  port: number
  push: PushSender
  access: ServerAccess
  /** Dashboard girişi; kullanıcı adı/şifre yoksa dashboard kapalıdır. */
  admin?: { username?: string; password?: string; sessionSecret: string }
  helloTimeoutMs?: number
  heartbeatMs?: number
  attachTimeoutMs?: number
}

export interface RunningServer {
  http: Server
  wss: WebSocketServer
  port(): number
  close(): void
}

/** Uygulama kapanış kodları (docs/design/09). 4000–4005 kanalların kendi kodlarıdır. */
export const SERVER_CLOSE = {
  networkNotAllowed: 4006,
  tokenRevoked: 4007,
} as const

const MAX_FAILED_HELLOS = 5
const MAX_FAILED_UPGRADES = 10
const FAILURE_WINDOW_MS = 60_000
const MAX_PAYLOAD_BYTES = 1_000_000

type Socket = WebSocket & { isAlive?: boolean }

export function startServer(opts: ServerOptions): RunningServer {
  const registry = new Registry()
  const bridge = new Bridge(registry, opts.push)
  const hubs = new HubBridge({ attachTimeoutMs: opts.attachTimeoutMs })
  const wss = new WebSocketServer({ noServer: true, maxPayload: MAX_PAYLOAD_BYTES })
  const failedHellos = new FailureLimiter(MAX_FAILED_HELLOS, FAILURE_WINDOW_MS)
  const failedUpgrades = new FailureLimiter(MAX_FAILED_UPGRADES, FAILURE_WINDOW_MS)
  /** İptal edilen token'ın açık bağlantılarını kapatmak için. */
  const socketsByToken = new Map<string, Set<Socket>>()

  const dashboard = createDashboard({
    access: opts.access,
    username: opts.admin?.username,
    password: opts.admin?.password,
    sessionSecret: opts.admin?.sessionSecret ?? '',
    status: () => ({ rooms: registry.stats(), hubs: hubs.directory(), connections: wss.clients.size }),
  })

  const http = createServer((req, res) => {
    if (req.url === '/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ ok: true }))
      return
    }
    dashboard.handle(req, res)
      .then((handled) => { if (!handled) text(res, 404, 'Not found') })
      .catch((err) => {
        console.error('[http]', err)
        if (!res.headersSent) text(res, 500, 'Internal error')
        else res.end()
      })
  })

  http.on('upgrade', (req: IncomingMessage, socket: Duplex, head: Buffer) => {
    const ip = clientIp(req)
    if (failedUpgrades.blocked(ip)) { reject(socket, 429, 'Too Many Requests'); return }
    const token = opts.access.authenticate(bearerToken(req))
    if (!token) {
      failedUpgrades.record(ip)
      reject(socket, 401, 'Unauthorized')
      return
    }
    wss.handleUpgrade(req, socket, head, (ws) => onConnection(ws as Socket, ip, token))
  })

  const stopRevokeListener = opts.access.onRevoke((tokenId) => {
    for (const ws of socketsByToken.get(tokenId) ?? []) ws.close(SERVER_CLOSE.tokenRevoked, 'token_revoked')
  })

  function onConnection(ws: Socket, ip: string, token: AuthenticatedToken): void {
    const client = {
      send: (d: string) => { if (ws.readyState === WebSocket.OPEN) ws.send(d) },
      close: (c?: number, r?: string) => ws.close(c, r),
    }
    let session: Conn | null = null
    ws.isAlive = true
    track(token.id, ws)

    const helloTimer = setTimeout(() => {
      if (!session) ws.close(4001, 'hello timeout')
    }, opts.helloTimeoutMs ?? 5000)

    ws.on('error', () => { /* maxPayload veya diğer ws hataları; bağlantı zaten kapanıyor */ })
    ws.on('pong', () => { ws.isAlive = true })
    ws.on('message', (data) => {
      const env = parseEnvelope(data.toString())
      if (!env) { ws.close(4002, 'bad message'); return }
      if (session) { session.message(env); return }
      if (failedHellos.blocked(ip)) { ws.close(); return }
      if (HubBridge.claims(env) && opts.access.checkNetwork(ip, String(env.payload.role), token) === 'blocked') {
        ws.close(SERVER_CLOSE.networkNotAllowed, 'network_not_allowed')
        return
      }
      session = hello(client, env, ip)
      if (session) clearTimeout(helloTimer)
      else { failedHellos.record(ip); ws.close() }
    })
    ws.on('close', () => {
      clearTimeout(helloTimer)
      untrack(token.id, ws)
      session?.close()
    })
  }

  /** `hub`/`controller` rolleri Mac'ten Mac'e kanala (docs/design/08), diğerleri telefon odasına. */
  function hello(client: ClientLike, env: Envelope, ip: string): Conn | null {
    if (HubBridge.claims(env)) return hubs.handleHello(client, env, () => failedHellos.record(ip))
    const session = bridge.handleHello(client, env)
    if (!session) return null
    return { message: (e) => bridge.handleMessage(session, e), close: () => bridge.handleClose(session) }
  }

  function track(tokenId: string, ws: Socket): void {
    let set = socketsByToken.get(tokenId)
    if (!set) { set = new Set(); socketsByToken.set(tokenId, set) }
    set.add(ws)
  }

  function untrack(tokenId: string, ws: Socket): void {
    const set = socketsByToken.get(tokenId)
    if (!set) return
    set.delete(ws)
    if (set.size === 0) socketsByToken.delete(tokenId)
  }

  const heartbeat = setInterval(() => {
    for (const ws of wss.clients as Set<Socket>) {
      if (ws.isAlive === false) { ws.terminate(); continue }
      ws.isAlive = false
      ws.ping()
    }
    hubs.sweep()
    failedHellos.sweep()
    failedUpgrades.sweep()
    dashboard.sweep()
  }, opts.heartbeatMs ?? 30_000)

  http.listen(opts.port)

  return {
    http,
    wss,
    port: () => {
      const addr = http.address()
      if (typeof addr === 'object' && addr) return addr.port
      throw new Error('sunucu dinlemiyor')
    },
    close: () => {
      clearInterval(heartbeat)
      stopRevokeListener()
      for (const ws of wss.clients) ws.terminate()
      wss.close()
      http.close()
    },
  }
}

function reject(socket: Duplex, status: number, message: string): void {
  socket.end(`HTTP/1.1 ${status} ${message}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`)
}
