import { afterEach, expect, test } from 'vitest'
import WebSocket from 'ws'
import { testServer, openSocket, type TestServer } from './support.js'
import { NoopPushSender } from '../src/push.js'

const TOKEN = 'secret-token-1234567890'
let server: TestServer | null = null

afterEach(() => { server?.close(); server = null })

function serverPort(): number {
  return server!.port()
}

function connect(): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const ws = openSocket()
    ws.on('open', () => resolve(ws))
    ws.on('error', reject)
  })
}

function nextMessage(ws: WebSocket): Promise<{ v: number; type: string; payload: Record<string, unknown> }> {
  return new Promise((resolve) => ws.once('message', (d) => resolve(JSON.parse(d.toString()))))
}

function closed(ws: WebSocket): Promise<void> {
  return new Promise((resolve) => ws.once('close', () => resolve()))
}

function send(ws: WebSocket, type: string, payload: Record<string, unknown>): void {
  ws.send(JSON.stringify({ v: 1, type, payload }))
}

test('mac ve telefon eşleşir; sessions ve command çift yönlü akar', async () => {
  server = await testServer({ push: new NoopPushSender() })
  const mac = await connect()
  send(mac, 'hello', { role: 'mac', token: TOKEN })
  expect((await nextMessage(mac)).type).toBe('welcome')

  const phone = await connect()
  send(phone, 'hello', { role: 'phone', token: TOKEN })
  const welcome = await nextMessage(phone)
  expect(welcome.payload.macOnline).toBe(true)

  send(mac, 'sessions', { sessions: [{ id: 's1' }] })
  const snap = await nextMessage(phone)
  expect(snap.type).toBe('sessions')

  send(phone, 'command', { commandId: 'c1', action: 'send_text', sessionId: 's1', text: 'merhaba' })
  const cmd = await nextMessage(mac)
  expect(cmd.type).toBe('command')
  expect(cmd.payload.text).toBe('merhaba')
})

test('geçersiz ilk mesaj bağlantıyı kapatır', async () => {
  server = await testServer({ push: new NoopPushSender() })
  const ws = await connect()
  send(ws, 'hello', { role: 'mac', token: 'kısa' })
  await closed(ws)
})

test('hello gelmezse timeout ile kapanır', async () => {
  server = await testServer({ push: new NoopPushSender(), helloTimeoutMs: 50 })
  const ws = await connect()
  await closed(ws)
})

test('aynı IP 5 başarısız hello sonrası reddedilir', async () => {
  server = await testServer({ push: new NoopPushSender() })
  for (let i = 0; i < 5; i++) {
    const ws = await connect()
    send(ws, 'hello', { role: 'mac', token: 'kısa' })
    await closed(ws)
  }
  const ws = await connect()
  send(ws, 'hello', { role: 'mac', token: TOKEN }) // geçerli token bile olsa
  await closed(ws)
})

test('1 MB üzeri mesaj bağlantıyı kapatır', async () => {
  server = await testServer({ push: new NoopPushSender() })
  const ws = await connect()
  send(ws, 'hello', { role: 'mac', token: TOKEN })
  await nextMessage(ws) // welcome
  // maxPayload limiti aşan mesaj: sunucu bağlantıyı kapatır.
  // İstemci tarafında ws Receiver RangeError fırlatabilir; bunu promise'te yakalarız.
  await new Promise<void>((resolve) => {
    ws.on('error', () => resolve())
    ws.on('close', () => resolve())
    ws.send(JSON.stringify({ v: 1, type: 'data', payload: { blob: 'x'.repeat(1_100_000) } }))
  })
})
