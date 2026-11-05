import { afterEach, expect, test } from 'vitest'
import WebSocket from 'ws'
import { startServer } from '../src/server.js'
import { NoopPushSender } from '../src/push.js'

// Mac'ten Mac'e kanal gerçek WebSocket sunucusuna karşı (docs/design/08).

const NET = 'network-token-A-1234567890'
const HUB_ID = 'hub-0000-build-machine'

let server: ReturnType<typeof startServer> | null = null
afterEach(() => { server?.close(); server = null })

type Sock = WebSocket & { inbox: { type: string; payload: Record<string, unknown> }[] }

function port(): number {
  const addr = server!.wss.address()
  if (typeof addr === 'object' && addr) return addr.port
  throw new Error('port alınamadı')
}

function connect(): Promise<Sock> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${port()}`) as Sock
    ws.inbox = []
    ws.on('message', (d) => ws.inbox.push(JSON.parse(d.toString())))
    ws.on('open', () => resolve(ws))
    ws.on('error', reject)
  })
}

function send(ws: WebSocket, type: string, payload: Record<string, unknown>): void {
  ws.send(JSON.stringify({ v: 1, type, payload }))
}

/** Belirli tipte bir mesaj gelene kadar bekler (gelmişse hemen döner). */
async function waitFor(ws: Sock, type: string): Promise<Record<string, unknown>> {
  for (let i = 0; i < 100; i++) {
    const found = ws.inbox.find((m) => m.type === type)
    if (found) return found.payload
    await new Promise((r) => setTimeout(r, 10))
  }
  throw new Error(`${type} gelmedi`)
}

function closeCode(ws: WebSocket): Promise<number> {
  return new Promise((resolve) => ws.once('close', (code) => resolve(code)))
}

async function startHub(): Promise<Sock> {
  const hub = await connect()
  send(hub, 'hello', { role: 'hub', network: NET, hubId: HUB_ID, hubKey: 'hub-secret-key-1234567890', name: 'Build Mac' })
  await waitFor(hub, 'welcome')
  return hub
}

function controllerHello(password: string) {
  return { role: 'controller', network: NET, controllerId: 'ctrl-0001-laptop', name: 'Laptop', attach: { hubId: HUB_ID, password } }
}

test('controller hub\'ı listede görür, şifreyle bağlanır, terminal verisi iki yönlü akar', async () => {
  server = startServer({ port: 0, push: new NoopPushSender() })
  const hub = await startHub()

  const browser = await connect()
  send(browser, 'hello', { role: 'controller', network: NET, controllerId: 'ctrl-0001-laptop', name: 'Laptop' })
  const list = await waitFor(browser, 'hubs')
  expect(list.hubs).toMatchObject([{ hubId: HUB_ID, name: 'Build Mac', online: true }])

  const controller = await connect()
  send(controller, 'hello', controllerHello('doğru'))
  const request = await waitFor(hub, 'attach_request')
  expect(request.password).toBe('doğru')
  send(hub, 'attach_result', { requestId: request.requestId, ok: true })
  const welcome = await waitFor(controller, 'welcome')
  expect(welcome.hub).toEqual({ hubId: HUB_ID, name: 'Build Mac' })

  send(hub, 'data', { sessionId: 's1', seq: 1, data: Buffer.from('LIVE').toString('base64') })
  expect(Buffer.from(String((await waitFor(controller, 'data')).data), 'base64').toString()).toBe('LIVE')

  send(controller, 'command', { commandId: 'c1', action: 'send_text', sessionId: 's1', text: 'merhaba' })
  const command = await waitFor(hub, 'command')
  expect(command.text).toBe('merhaba')
  expect(command.from).toBe(welcome.connectionId)
})

test('hub ve telefon odası aynı token\'ı kullansa da birbirine karışmaz', async () => {
  server = startServer({ port: 0, push: new NoopPushSender() })
  const hub = await startHub()
  const mac = await connect()
  send(mac, 'hello', { role: 'mac', token: NET })
  await waitFor(mac, 'welcome')
  const phone = await connect()
  send(phone, 'hello', { role: 'phone', token: NET })
  await waitFor(phone, 'welcome')

  send(hub, 'sessions', { sessions: [{ id: 'hub-session' }] })
  send(mac, 'sessions', { sessions: [{ id: 'mac-session' }] })
  const sessions = await waitFor(phone, 'sessions')
  expect(sessions.sessions).toEqual([{ id: 'mac-session' }])
  // Hub bağlantısı telefon odasının mac yerini almadı.
  expect(mac.readyState).toBe(WebSocket.OPEN)
  expect(hub.readyState).toBe(WebSocket.OPEN)
})

test('yanlış şifre 4003 ile kapanır ve IP sınırına sayılır', async () => {
  server = startServer({ port: 0, push: new NoopPushSender() })
  const hub = await startHub()
  for (let i = 0; i < 5; i++) {
    const controller = await connect()
    const closed = closeCode(controller)
    send(controller, 'hello', controllerHello('yanlış'))
    const request = await waitFor(hub, 'attach_request')
    hub.inbox = hub.inbox.filter((m) => m.type !== 'attach_request')
    send(hub, 'attach_result', { requestId: request.requestId, ok: false, error: 'wrong_password' })
    expect(await closed).toBe(4003)
  }
  // Altıncı deneme hub'a hiç ulaşmadan kapanır.
  const blocked = await connect()
  const closed = closeCode(blocked)
  send(blocked, 'hello', controllerHello('doğru'))
  await closed
  expect(hub.inbox.some((m) => m.type === 'attach_request')).toBe(false)
})
