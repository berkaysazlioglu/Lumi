import { envelope, parseHello, type Envelope, type Role } from './protocol.js'
import { Registry, type ClientLike, type Room } from './registry.js'

export interface PushSender {
  send(deviceTokens: string[], title: string, body: string): Promise<void>
}

export interface Session {
  client: ClientLike
  role: Role
  room: Room
}

/** Mac'in yayınlayıp relay'in cache'lediği anlık görüntüler (oda ya da hub başına). */
export interface SnapshotCache {
  sessions: unknown[] | null
  repos: unknown[] | null
  projects: unknown | null
  usage: unknown | null
  tasks: unknown | null
}

/**
 * Telefonun (ve hub'a bağlanan controller'ın — docs/design/08) `welcome` gövdesi.
 * İki kanal aynı şekli alır ki istemci tarafındaki çözümleme ortak kalsın.
 */
export function welcomePayload(cache: SnapshotCache, macOnline: boolean, lastSeenAt: number | null): Record<string, unknown> {
  const proj = (cache.projects as {
    projects?: unknown; others?: unknown; addable?: unknown; looseLocations?: unknown; display?: unknown
  } | null) ?? null
  return {
    sessions: cache.sessions ?? [],
    repos: cache.repos ?? [],
    projects: proj?.projects ?? [],
    addable: proj?.addable ?? [],
    // Projects ▸ Other (Mac karar 108/114) — additive; eski Mac'te boş.
    others: proj?.others ?? [],
    // Serbest terminal konumları + Mac terminal fontu (2026-10-23) — additive.
    looseLocations: proj?.looseLocations ?? [],
    display: proj?.display ?? {},
    // Kota göstergeleri (Mac top bar paritesi) — additive; Mac henüz göndermediyse null.
    usage: cache.usage ?? null,
    // Tasks (karar 137 mobil ek) — additive; Mac henüz göndermediyse null.
    tasks: cache.tasks ?? null,
    macOnline,
    lastSeenAt,
  }
}

/** Mac'ten kontrol tarafına (telefon / controller) aynen yayınlanan akış frame'leri. */
const STREAM_FRAMES = new Set([
  'scrollback', 'data', 'chat', 'chat_append', 'chat_status', 'prompt', 'command_result',
])

/**
 * Mac'in yayın frame'ini işler: anlık görüntüleri cache'ler (sonradan bağlanan
 * `welcome`'da bulsun) ve frame'i `broadcast` ile iletir. Tanınmayan tip
 * düşer (`false`). Telefon odası ve hub kanalı (docs/design/08) ortak kullanır.
 */
export function relayMacFrame(cache: SnapshotCache, env: Envelope, broadcast: (data: string) => void): boolean {
  switch (env.type) {
    case 'sessions':
      // payload.sessions dizidir (welcome ile simetrik `sessions` anahtarı)
      cache.sessions = Array.isArray(env.payload.sessions) ? env.payload.sessions : null
      break
    case 'repos':
      cache.repos = Array.isArray(env.payload.repos) ? env.payload.repos : null
      break
    case 'projects':
      cache.projects = env.payload
      break
    case 'usage':
      cache.usage = env.payload
      break
    case 'tasks':
      cache.tasks = env.payload
      break
    default:
      if (!STREAM_FRAMES.has(env.type)) return false
  }
  broadcast(envelope(env.type, env.payload))
  return true
}

export class Bridge {
  constructor(private registry: Registry, private push: PushSender) {}

  handleHello(client: ClientLike, env: Envelope): Session | null {
    if (env.type !== 'hello') return null
    const hello = parseHello(env.payload)
    if (!hello) return null
    const room = hello.role === 'mac'
      ? this.registry.attachMac(hello.token, client)
      : this.registry.attachPhone(hello.token, client)
    if (hello.role === 'phone') {
      client.send(envelope('welcome', welcomePayload(room, room.mac !== null, room.lastSeenAt)))
    } else {
      client.send(envelope('welcome', { phoneCount: room.phones.size }))
    }
    return { client, role: hello.role, room }
  }

  handleMessage(session: Session, env: Envelope): void {
    if (env.type === 'ping') {
      session.client.send(envelope('pong', {}))
      return
    }
    if (session.role === 'mac') this.fromMac(session, env)
    else this.fromPhone(session, env)
  }

  private fromMac(session: Session, env: Envelope): void {
    const { room } = session
    relayMacFrame(room, env, (data) => this.broadcast(room, data))
  }

  private fromPhone(session: Session, env: Envelope): void {
    const { room } = session
    switch (env.type) {
      case 'subscribe':
      case 'unsubscribe':
      case 'input':
      case 'prompt_respond':
      case 'chat_send':
        if (room.mac) {
          room.mac.send(envelope(env.type, env.payload))
        }
        // silently drop if mac offline
        break
      case 'command':
        if (room.mac) {
          room.mac.send(envelope('command', env.payload))
        } else {
          session.client.send(envelope('command_result', {
            commandId: env.payload.commandId ?? null,
            ok: false,
            error: 'mac_offline',
          }))
        }
        break
      case 'register_push':
        if (typeof env.payload.deviceToken === 'string' && env.payload.deviceToken.length > 0) {
          room.pushTokens.add(env.payload.deviceToken)
        }
        break
      case 'unregister_push':
        if (typeof env.payload.deviceToken === 'string' && env.payload.deviceToken.length > 0) {
          room.pushTokens.delete(env.payload.deviceToken)
        }
        break
    }
  }

  private broadcast(room: Room, data: string): void {
    for (const phone of room.phones) phone.send(data)
  }

  handleClose(session: Session): void {
    this.registry.detach(session.client)
  }
}
