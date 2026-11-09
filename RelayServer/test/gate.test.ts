import { afterEach, expect, test } from 'vitest'
import type WebSocket from 'ws'
import { NoopPushSender } from '../src/push.js'
import { SERVER_CLOSE } from '../src/server.js'
import { openSocket, testServer, type TestServer } from './support.js'

// Sunucu kapısı (docs/design/09): server token'ı ve hub/controller IP allowlist'i.

let server: TestServer | null = null
afterEach(() => { server?.close(); server = null })

function opened(ws: WebSocket): Promise<void> {
  return new Promise((resolve, reject) => { ws.once('open', () => resolve()); ws.once('error', reject) })
}

function rejectedStatus(ws: WebSocket): Promise<number> {
  return new Promise((resolve) => ws.once('unexpected-response', (_req, res) => resolve(res.statusCode ?? 0)))
}

function closeCode(ws: WebSocket): Promise<number> {
  return new Promise((resolve) => ws.once('close', (code) => resolve(code)))
}

function nextType(ws: WebSocket): Promise<string> {
  return new Promise((resolve) => ws.once('message', (d) => resolve(JSON.parse(d.toString()).type)))
}

function send(ws: WebSocket, type: string, payload: Record<string, unknown>): void {
  ws.send(JSON.stringify({ v: 1, type, payload }))
}

const HUB_HELLO = { role: 'hub', hubId: 'hub-0000-build', hubKey: 'hub-secret-key-1234567890', name: 'Build Mac' }
const ROOM = 'room-token-1234567890'

test('token\'sız ya da yanlış token\'lı bağlantı el sıkışmada 401 alır', async () => {
  server = await testServer({ push: new NoopPushSender() })
  expect(await rejectedStatus(openSocket(null))).toBe(401)
  expect(await rejectedStatus(openSocket('lrs_yanlis-token'))).toBe(401)
})

test('çok sayıda yanlış deneme IP\'yi 429 ile durdurur', async () => {
  server = await testServer({ push: new NoopPushSender() })
  for (let i = 0; i < 10; i++) await rejectedStatus(openSocket('lrs_yanlis'))
  expect(await rejectedStatus(openSocket())).toBe(429)
})

test('iptal edilen token\'ın açık bağlantısı 4007 ile kapanır', async () => {
  server = await testServer({ push: new NoopPushSender() })
  const mac = openSocket()
  await opened(mac)
  send(mac, 'hello', { role: 'mac', token: ROOM })
  expect(await nextType(mac)).toBe('welcome')
  const id = server.access.tokens()[0]!.id
  const code = closeCode(mac)
  await server.access.revokeToken(id)
  expect(await code).toBe(SERVER_CLOSE.tokenRevoked)
})

test('enforce modunda listede olmayan IP\'den hub 4006 ile kapanır, telefon odası etkilenmez', async () => {
  server = await testServer({ push: new NoopPushSender(), allowlist: '203.0.113.7', mode: 'enforce' })

  const hub = openSocket()
  await opened(hub)
  const hubClosed = closeCode(hub)
  send(hub, 'hello', HUB_HELLO)
  expect(await hubClosed).toBe(SERVER_CLOSE.networkNotAllowed)

  const phone = openSocket()
  await opened(phone)
  send(phone, 'hello', { role: 'phone', token: ROOM })
  expect(await nextType(phone)).toBe('welcome')
  phone.close()
})

test('IP, X-Forwarded-For\'un en sağdaki girdisinden okunur (baştaki girdi taklit edilemez)', async () => {
  server = await testServer({ push: new NoopPushSender(), allowlist: '203.0.113.7', mode: 'enforce' })

  const spoofed = openSocket(undefined, { 'X-Forwarded-For': '203.0.113.7, 198.51.100.9' })
  await opened(spoofed)
  const spoofClosed = closeCode(spoofed)
  send(spoofed, 'hello', HUB_HELLO)
  expect(await spoofClosed).toBe(SERVER_CLOSE.networkNotAllowed)

  const office = openSocket(undefined, { 'X-Forwarded-For': '198.51.100.9, 203.0.113.7' })
  await opened(office)
  send(office, 'hello', HUB_HELLO)
  expect(await nextType(office)).toBe('welcome')
  office.close()
})

test('report modunda hub bağlanır ve olay kaydedilir', async () => {
  server = await testServer({ push: new NoopPushSender(), allowlist: '203.0.113.7', mode: 'report' })
  const hub = openSocket()
  await opened(hub)
  send(hub, 'hello', HUB_HELLO)
  expect(await nextType(hub)).toBe('welcome')
  expect(server.access.networkEvents()[0]).toMatchObject({ role: 'hub', verdict: 'would_block' })
  hub.close()
})

test('/health kimlik doğrulamasız 200 döner', async () => {
  server = await testServer({ push: new NoopPushSender() })
  const res = await fetch(`http://127.0.0.1:${server.port()}/health`)
  expect(res.status).toBe(200)
  expect(await res.json()).toEqual({ ok: true })
})
