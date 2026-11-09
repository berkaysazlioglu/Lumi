import WebSocket from 'ws'
import { ServerAccess } from '../src/access.js'
import { startServer, type ServerOptions, type RunningServer } from '../src/server.js'
import { MemoryStore } from '../src/store.js'

/** Testler için bellekte store + tek server token'ı olan sunucu; allowlist kapalı. */
export interface TestServer extends RunningServer {
  token: string
  access: ServerAccess
}

let current: TestServer | null = null

export async function testServer(opts: Omit<ServerOptions, 'port' | 'access'> & { allowlist?: string; mode?: string }): Promise<TestServer> {
  const access = await ServerAccess.load(new MemoryStore(), { allowlist: opts.allowlist ?? '', mode: opts.mode })
  const { token } = await access.createToken('test')
  const server = startServer({ ...opts, port: 0, access })
  await new Promise<void>((resolve) => server.http.once('listening', () => resolve()))
  current = { ...server, token, access }
  return current
}

/** Son açılan test sunucusuna token'la bağlanan WebSocket (bağlantı açılmadan döner). */
export function openSocket(token: string | null = current?.token ?? null, headers: Record<string, string> = {}): WebSocket {
  if (!current) throw new Error('test sunucusu yok')
  return new WebSocket(`ws://127.0.0.1:${current.port()}`, {
    headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
  })
}
