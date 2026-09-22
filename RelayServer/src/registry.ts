export interface ClientLike {
  send(data: string): void
  close(code?: number, reason?: string): void
}

export interface Room {
  token: string
  mac: ClientLike | null
  phones: Set<ClientLike>
  sessions: unknown[] | null
  repos: unknown[] | null
  projects: unknown | null
  lastSeenAt: number | null
  pushTokens: Set<string>
}

export class Registry {
  private rooms = new Map<string, Room>()

  constructor(private now: () => number = Date.now) {}

  attachMac(token: string, client: ClientLike): Room {
    const room = this.ensure(token)
    if (room.mac && room.mac !== client) room.mac.close(4000, 'replaced')
    room.mac = client
    room.lastSeenAt = this.now()
    return room
  }

  attachPhone(token: string, client: ClientLike): Room {
    const room = this.ensure(token)
    room.phones.add(client)
    return room
  }

  detach(client: ClientLike): void {
    for (const [token, room] of this.rooms) {
      if (room.mac === client) {
        room.mac = null
        room.lastSeenAt = this.now()
      }
      room.phones.delete(client)
      if (!room.mac && room.phones.size === 0 && !room.sessions) this.rooms.delete(token)
    }
  }

  get(token: string): Room | undefined {
    return this.rooms.get(token)
  }

  private ensure(token: string): Room {
    let room = this.rooms.get(token)
    if (!room) {
      room = { token, mac: null, phones: new Set(), sessions: null, repos: null, projects: null, lastSeenAt: null, pushTokens: new Set() }
      this.rooms.set(token, room)
    }
    return room
  }
}
