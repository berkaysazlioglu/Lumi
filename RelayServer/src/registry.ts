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
  /** Mac'in son kullanım/kota raporu (Claude/Codex/DeepSeek) — welcome'a iliştirilir. */
  usage: unknown | null
  /** Mac'in son Tasks anlık görüntüsü (karar 137 mobil ek) — welcome'a iliştirilir. */
  tasks: unknown | null
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

  /** Dashboard durumu: çevrimiçi Mac ve bağlı telefon sayısı. */
  stats(): { macsOnline: number; phones: number } {
    let macsOnline = 0
    let phones = 0
    for (const room of this.rooms.values()) {
      if (room.mac) macsOnline += 1
      phones += room.phones.size
    }
    return { macsOnline, phones }
  }

  get(token: string): Room | undefined {
    return this.rooms.get(token)
  }

  private ensure(token: string): Room {
    let room = this.rooms.get(token)
    if (!room) {
      room = { token, mac: null, phones: new Set(), sessions: null, repos: null, projects: null, usage: null, tasks: null, lastSeenAt: null, pushTokens: new Set() }
      this.rooms.set(token, room)
    }
    return room
  }
}
