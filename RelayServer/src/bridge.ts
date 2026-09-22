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
      const proj = (room.projects as { projects?: unknown; addable?: unknown } | null) ?? null
      client.send(envelope('welcome', {
        sessions: room.sessions ?? [],
        repos: room.repos ?? [],
        projects: proj?.projects ?? [],
        addable: proj?.addable ?? [],
        macOnline: room.mac !== null,
        lastSeenAt: room.lastSeenAt,
      }))
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
    switch (env.type) {
      case 'sessions': {
        // Cache the sessions list from the payload (payload.sessions is the array;
        // symmetric with welcome payload which also uses the `sessions` key)
        const list = Array.isArray(env.payload.sessions) ? env.payload.sessions : null
        room.sessions = list
        this.broadcast(room, envelope('sessions', env.payload))
        break
      }
      case 'repos': {
        // Cache the repo list (symmetric with sessions) so phones that connect
        // later receive it in their welcome; broadcast to already-connected phones.
        const list = Array.isArray(env.payload.repos) ? env.payload.repos : null
        room.repos = list
        this.broadcast(room, envelope('repos', env.payload))
        break
      }
      case 'projects': {
        room.projects = env.payload
        this.broadcast(room, envelope('projects', env.payload))
        break
      }
      case 'scrollback':
        this.broadcast(room, envelope('scrollback', env.payload))
        break
      case 'data':
        this.broadcast(room, envelope('data', env.payload))
        break
      case 'chat':
        this.broadcast(room, envelope('chat', env.payload))
        break
      case 'chat_append':
        this.broadcast(room, envelope('chat_append', env.payload))
        break
      case 'chat_status':
        this.broadcast(room, envelope('chat_status', env.payload))
        break
      case 'prompt':
        this.broadcast(room, envelope('prompt', env.payload))
        break
      case 'command_result':
        this.broadcast(room, envelope('command_result', env.payload))
        break
    }
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
