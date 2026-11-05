import { createHash, randomUUID, timingSafeEqual } from 'node:crypto'
import { envelope, type Envelope } from './protocol.js'
import { relayMacFrame, welcomePayload, type SnapshotCache } from './bridge.js'
import type { ClientLike } from './registry.js'

/**
 * Mac'ten Mac'e remote (docs/design/08-mac-remote.md).
 *
 * Telefonun token'lı odalarından AYRI bir kanal: aynı ağ token'ıyla bağlanan
 * hub'lar bir directory'de listelenir, aynı token'la bağlanan controller'lar
 * listeyi görür ve şifreyle bir hub'a bağlanır. Şifreyi relay değil hub
 * doğrular; relay yalnız `attach_request` / `attach_result` taşır.
 */

export const HUB_CLOSE = {
  replaced: 4000,
  unauthorized: 4003,
  hubOffline: 4004,
  attachTimeout: 4005,
} as const

const MIN_NETWORK_LENGTH = 16
const MAX_TOKEN_LENGTH = 256
const MIN_ID_LENGTH = 8
const MAX_ID_LENGTH = 128
const MAX_NAME_LENGTH = 64
const MAX_PASSWORD_LENGTH = 256
const MAX_HUBS_PER_NETWORK = 50
const MAX_CONTROLLERS_PER_HUB = 20
/** Çevrimdışı hub directory'de bu kadar süre `online:false` olarak durur. */
export const OFFLINE_HUB_TTL_MS = 24 * 60 * 60 * 1000
export const DEFAULT_ATTACH_TIMEOUT_MS = 10_000

/** Controller'dan hub'a iletilen frame'ler (telefonun `fromPhone` kümesi). */
const CONTROLLER_FRAMES = new Set(['subscribe', 'unsubscribe', 'input', 'prompt_respond', 'chat_send', 'command'])

/** Sunucunun bağlantıya bağladığı uç: mesajlar ve kapanış buraya akar. */
export interface Conn {
  message(env: Envelope): void
  close(): void
}

interface Hub extends SnapshotCache {
  hubId: string
  /** Hub kimliğinin sahibi: ilk kayıttaki `hubKey`'in SHA-256'sı. Farklı anahtar kimliği alamaz. */
  keyHash: Buffer
  name: string
  client: ClientLike | null
  lastSeenAt: number
  /** Kabul edilmiş controller soketleri — bağlantı kimliği (`from`) → soket. */
  controllers: Map<string, ClientLike>
  /** Hub'ın cevabını bekleyen bağlanma istekleri — requestId → istek. */
  pending: Map<string, PendingAttach>
}

interface PendingAttach {
  connId: string
  client: ClientLike
  timer: ReturnType<typeof setTimeout>
  onRejected: () => void
}

interface Network {
  hubs: Map<string, Hub>
  /** Yalnız directory'yi izleyen controller soketleri. */
  browsers: Set<ClientLike>
}

export interface HubBridgeOptions {
  now?: () => number
  attachTimeoutMs?: number
}

type HubHello = { role: 'hub'; network: string; hubId: string; hubKey: string; name: string }
type ControllerHello = {
  role: 'controller'; network: string; controllerId: string; name: string
  attach: { hubId: string; password: string } | null
}

export class HubBridge {
  private networks = new Map<string, Network>()
  private now: () => number
  private attachTimeoutMs: number

  constructor(opts: HubBridgeOptions = {}) {
    this.now = opts.now ?? Date.now
    this.attachTimeoutMs = opts.attachTimeoutMs ?? DEFAULT_ATTACH_TIMEOUT_MS
  }

  /** `hello`'nun rolü bu kanala mı ait? (Telefon odası `mac`/`phone` kalır.) */
  static claims(env: Envelope): boolean {
    return env.type === 'hello' && (env.payload.role === 'hub' || env.payload.role === 'controller')
  }

  /**
   * Geçersiz hello'da `null` (sunucu başarısızlık sayar ve kapatır).
   * `onAuthFailure`, hub şifreyi reddettiğinde IP sayacını artırmak içindir.
   */
  handleHello(client: ClientLike, env: Envelope, onAuthFailure: () => void): Conn | null {
    const hello = parseHubHello(env.payload)
    if (!hello) return null
    if (hello.role === 'hub') return this.attachHub(client, hello)
    if (hello.attach) return this.attachController(client, hello, hello.attach, onAuthFailure)
    return this.attachBrowser(client, hello.network)
  }

  // MARK: - Hub

  private attachHub(client: ClientLike, hello: HubHello): Conn | null {
    const network = this.ensureNetwork(hello.network)
    this.prune(network)
    const keyHash = hashKey(hello.hubKey)
    let hub = network.hubs.get(hello.hubId)
    if (hub && !timingSafeEqual(hub.keyHash, keyHash)) {
      // Başka biri listede gördüğü kimliği sahiplenemez (controller şifreleri ona gitmesin).
      return null
    }
    if (!hub) {
      if (network.hubs.size >= MAX_HUBS_PER_NETWORK) return null
      hub = {
        hubId: hello.hubId, keyHash, name: hello.name, client: null, lastSeenAt: this.now(),
        controllers: new Map(), pending: new Map(),
        sessions: null, repos: null, projects: null, usage: null, tasks: null,
      }
      network.hubs.set(hello.hubId, hub)
    } else if (hub.client && hub.client !== client) {
      // Aynı hub kimliğiyle ikinci bağlantı: öncekini ve onun controller'larını düşür.
      // Controller'lar yeni bağlantıya kendiliğinden geçmez — şifre yeniden doğrulanmalı.
      this.dropControllers(hub, HUB_CLOSE.replaced, 'hub_replaced')
      hub.client.close(HUB_CLOSE.replaced, 'replaced')
    }
    hub.client = client
    hub.name = hello.name
    hub.lastSeenAt = this.now()
    client.send(envelope('welcome', { controllerCount: hub.controllers.size }))
    this.broadcastHubs(network)

    const owner = hub
    return {
      message: (env) => this.fromHub(network, owner, client, env),
      close: () => {
        if (owner.client !== client) return
        owner.client = null
        owner.lastSeenAt = this.now()
        this.dropControllers(owner, HUB_CLOSE.hubOffline, 'hub_offline')
        this.broadcastHubs(network)
      },
    }
  }

  private fromHub(network: Network, hub: Hub, client: ClientLike, env: Envelope): void {
    if (hub.client !== client) return
    if (env.type === 'ping') { client.send(envelope('pong', {})); return }
    switch (env.type) {
      case 'attach_result':
        this.resolveAttach(network, hub, env.payload)
        return
      case 'hub_update': {
        const name = parseName(env.payload.name)
        if (name) { hub.name = name; this.broadcastHubs(network) }
        return
      }
      case 'revoke_controllers':
        this.dropControllers(hub, HUB_CLOSE.unauthorized, 'revoked')
        this.broadcastHubs(network)
        return
    }
    // Hedefli frame (`to` = controller bağlantı kimliği) yalnız ona gider; yoksa hepsine.
    const to = typeof env.payload.to === 'string' ? env.payload.to : null
    relayMacFrame(hub, env, (data) => {
      if (to) { hub.controllers.get(to)?.send(data); return }
      for (const controller of hub.controllers.values()) controller.send(data)
    })
  }

  private resolveAttach(network: Network, hub: Hub, payload: Record<string, unknown>): void {
    const requestId = typeof payload.requestId === 'string' ? payload.requestId : null
    const request = requestId ? hub.pending.get(requestId) : undefined
    if (!requestId || !request) return
    hub.pending.delete(requestId)
    clearTimeout(request.timer)
    if (payload.ok !== true || hub.controllers.size >= MAX_CONTROLLERS_PER_HUB) {
      request.onRejected()
      const reason = typeof payload.error === 'string' ? payload.error.slice(0, 64) : 'unauthorized'
      request.client.close(HUB_CLOSE.unauthorized, reason)
      return
    }
    hub.controllers.set(request.connId, request.client)
    request.client.send(envelope('welcome', {
      ...welcomePayload(hub, true, hub.lastSeenAt),
      hub: { hubId: hub.hubId, name: hub.name },
      connectionId: request.connId,
    }))
    this.broadcastHubs(network)
  }

  /** Hub'ın bütün controller'larını (bekleyenler dahil) kapatır. */
  private dropControllers(hub: Hub, code: number, reason: string): void {
    for (const request of hub.pending.values()) {
      clearTimeout(request.timer)
      request.client.close(code, reason)
    }
    hub.pending.clear()
    const controllers = [...hub.controllers.values()]
    hub.controllers.clear()
    for (const controller of controllers) controller.close(code, reason)
  }

  // MARK: - Controller

  private attachController(
    client: ClientLike,
    hello: ControllerHello,
    attach: { hubId: string; password: string },
    onAuthFailure: () => void,
  ): Conn {
    const network = this.networks.get(hello.network)
    const hub = network?.hubs.get(attach.hubId)
    const connId = randomUUID()
    if (!network || !hub?.client) {
      client.close(HUB_CLOSE.hubOffline, 'hub_offline')
      return { message: () => {}, close: () => {} }
    }
    const requestId = randomUUID()
    const timer = setTimeout(() => {
      if (!hub.pending.delete(requestId)) return
      client.close(HUB_CLOSE.attachTimeout, 'attach_timeout')
    }, this.attachTimeoutMs)
    hub.pending.set(requestId, { connId, client, timer, onRejected: onAuthFailure })
    hub.client.send(envelope('attach_request', {
      requestId,
      // Kabulde hub bu kimliği controller listesine yazar; `from` ve `controller_left` aynı kimliği taşır.
      connectionId: connId,
      controllerId: hello.controllerId,
      controllerName: hello.name,
      password: attach.password,
    }))

    return {
      message: (env) => {
        if (env.type === 'ping') { client.send(envelope('pong', {})); return }
        // Kabulden önce (ya da hub düştükten sonra) gelen frame'ler hub'a ulaşmaz.
        if (hub.controllers.get(connId) !== client) return
        // Hub düşünce controller'ları kapatılır (`dropControllers`), yani burada hub bağlıdır.
        if (!CONTROLLER_FRAMES.has(env.type)) return
        hub.client?.send(envelope(env.type, { ...env.payload, from: connId }))
      },
      close: () => {
        for (const [id, request] of hub.pending) {
          if (request.client !== client) continue
          clearTimeout(request.timer)
          hub.pending.delete(id)
        }
        if (hub.controllers.get(connId) !== client) return
        hub.controllers.delete(connId)
        hub.client?.send(envelope('controller_left', { from: connId }))
        this.broadcastHubs(network)
      },
    }
  }

  private attachBrowser(client: ClientLike, token: string): Conn {
    const network = this.ensureNetwork(token)
    network.browsers.add(client)
    this.prune(network)
    client.send(envelope('hubs', { hubs: this.listHubs(network) }))
    return {
      message: (env) => {
        if (env.type === 'ping') client.send(envelope('pong', {}))
      },
      close: () => {
        network.browsers.delete(client)
        this.dropNetworkIfEmpty(token, network)
      },
    }
  }

  // MARK: - Directory

  private listHubs(network: Network): Record<string, unknown>[] {
    return [...network.hubs.values()]
      .map((hub) => ({
        hubId: hub.hubId,
        name: hub.name,
        online: hub.client !== null,
        lastSeenAt: hub.lastSeenAt,
        controllerCount: hub.controllers.size,
      }))
      .sort((a, b) => a.name.localeCompare(b.name))
  }

  private broadcastHubs(network: Network): void {
    if (network.browsers.size === 0) return
    const data = envelope('hubs', { hubs: this.listHubs(network) })
    for (const browser of network.browsers) browser.send(data)
  }

  /** Süresi dolan çevrimdışı hub'ları düşürür. */
  private prune(network: Network): void {
    const cutoff = this.now() - OFFLINE_HUB_TTL_MS
    for (const [hubId, hub] of network.hubs) {
      if (!hub.client && hub.lastSeenAt < cutoff) network.hubs.delete(hubId)
    }
  }

  private ensureNetwork(token: string): Network {
    let network = this.networks.get(token)
    if (!network) {
      network = { hubs: new Map(), browsers: new Set() }
      this.networks.set(token, network)
    }
    return network
  }

  private dropNetworkIfEmpty(token: string, network: Network): void {
    this.prune(network)
    if (network.hubs.size === 0 && network.browsers.size === 0) this.networks.delete(token)
  }

  /** Süresi dolan hub'ları ve boş kalan ağları düşürür (sunucu heartbeat'inden çağrılır). */
  sweep(): void {
    for (const [token, network] of this.networks) this.dropNetworkIfEmpty(token, network)
  }

  /** Test görünürlüğü. */
  hubCount(token: string): number {
    return this.networks.get(token)?.hubs.size ?? 0
  }
}

// MARK: - Doğrulama

function parseHubHello(p: Record<string, unknown>): HubHello | ControllerHello | null {
  const network = parseToken(p.network)
  const name = parseName(p.name)
  if (!network || !name) return null
  if (p.role === 'hub') {
    const hubId = parseId(p.hubId)
    const hubKey = parseToken(p.hubKey)
    return hubId && hubKey ? { role: 'hub', network, hubId, hubKey, name } : null
  }
  if (p.role !== 'controller') return null
  const controllerId = parseId(p.controllerId)
  if (!controllerId) return null
  if (p.attach === undefined) return { role: 'controller', network, controllerId, name, attach: null }
  if (typeof p.attach !== 'object' || p.attach === null || Array.isArray(p.attach)) return null
  const raw = p.attach as Record<string, unknown>
  const hubId = parseId(raw.hubId)
  if (!hubId || typeof raw.password !== 'string' || raw.password.length > MAX_PASSWORD_LENGTH) return null
  return { role: 'controller', network, controllerId, name, attach: { hubId, password: raw.password } }
}

function hashKey(key: string): Buffer {
  return createHash('sha256').update(key).digest()
}

function parseToken(value: unknown): string | null {
  if (typeof value !== 'string') return null
  return value.length >= MIN_NETWORK_LENGTH && value.length <= MAX_TOKEN_LENGTH ? value : null
}

function parseId(value: unknown): string | null {
  if (typeof value !== 'string') return null
  return value.length >= MIN_ID_LENGTH && value.length <= MAX_ID_LENGTH ? value : null
}

function parseName(value: unknown): string | null {
  if (typeof value !== 'string') return null
  const trimmed = value.trim().slice(0, MAX_NAME_LENGTH)
  return trimmed.length > 0 ? trimmed : null
}
