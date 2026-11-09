import { afterEach, expect, test } from 'vitest'
import WebSocket from 'ws'
import { testServer, openSocket, type TestServer } from './support.js'
import type { PushSender } from '../src/bridge.js'

// Terminal-ayna tam tur E2E testi: gerçek WebSocket sunucusuna karşı
// subscribe → scrollback → data → input yolculuğunu doğrular.

const TOKEN = 'e2e-terminal-mirror-token-12345'

class NullPush implements PushSender {
  async send(_tokens: string[], _title: string, _body: string) {}
}

let server: TestServer | null = null

afterEach(() => { server?.close(); server = null })

function serverPort(): number {
  return server!.port()
}

type Sock = WebSocket & { inbox: Record<string, unknown>[] }

function connect(): Promise<Sock> {
  return new Promise((resolve, reject) => {
    const ws = openSocket() as Sock
    ws.inbox = []
    ws.on('message', (d) => ws.inbox.push(JSON.parse(d.toString())))
    ws.on('open', () => resolve(ws))
    ws.on('error', reject)
  })
}

function send(ws: WebSocket, type: string, payload: Record<string, unknown>): void {
  ws.send(JSON.stringify({ v: 1, type, payload }))
}

/** Sunucu broadcast'lerinin işlenmesini bekler. */
const settle = () => new Promise((r) => setTimeout(r, 80))

function messagesOfType(ws: Sock, type: string): Record<string, unknown>[] {
  return ws.inbox.filter((m) => m.type === type).map((m) => m.payload as Record<string, unknown>)
}

/** Mac ve phone'u aynı token ile bağlar, welcome'ları temizler. */
async function pairRoom(): Promise<{ mac: Sock; phone: Sock }> {
  const mac = await connect()
  send(mac, 'hello', { role: 'mac', token: TOKEN })
  const phone = await connect()
  send(phone, 'hello', { role: 'phone', token: TOKEN })
  await settle()
  mac.inbox = []
  phone.inbox = []
  return { mac, phone }
}

// ---------------------------------------------------------------------------
// Test 1: subscribe iletimi (phone → mac)
// ---------------------------------------------------------------------------

test('phone subscribe → mac alır', async () => {
  server = await testServer({ push: new NullPush() })
  const { mac, phone } = await pairRoom()

  send(phone, 'subscribe', { sessionId: 's1' })
  await settle()

  const subs = messagesOfType(mac, 'subscribe')
  expect(subs).toHaveLength(1)
  expect(subs[0]).toMatchObject({ sessionId: 's1' })
  // phone kendi subscribe'ını geri ALMAZ
  expect(messagesOfType(phone, 'subscribe')).toHaveLength(0)
})

// ---------------------------------------------------------------------------
// Test 2: scrollback iletimi (mac → phone), base64 payload korunur
// ---------------------------------------------------------------------------

test('mac scrollback → phone alır; base64 payload bozulmadan', async () => {
  server = await testServer({ push: new NullPush() })
  const { mac, phone } = await pairRoom()

  // "SCROLL" → base64
  const scrollB64 = Buffer.from('SCROLL').toString('base64')
  send(mac, 'scrollback', { sessionId: 's1', seq: 0, cols: 80, rows: 24, data: scrollB64 })
  await settle()

  const scrollMsgs = messagesOfType(phone, 'scrollback')
  expect(scrollMsgs).toHaveLength(1)
  const p = scrollMsgs[0] as { sessionId: string; seq: number; data: string; cols: number; rows: number }
  expect(p.sessionId).toBe('s1')
  expect(p.seq).toBe(0)
  expect(p.cols).toBe(80)
  expect(p.rows).toBe(24)
  // base64 bozulmadan iletildi mi?
  expect(Buffer.from(p.data, 'base64').toString()).toBe('SCROLL')
})

// ---------------------------------------------------------------------------
// Test 3: data iletimi (mac → phone), base64 payload korunur
// ---------------------------------------------------------------------------

test('mac data → phone alır; base64 payload bozulmadan', async () => {
  server = await testServer({ push: new NullPush() })
  const { mac, phone } = await pairRoom()

  // "LIVE" → base64
  const liveB64 = Buffer.from('LIVE').toString('base64')
  send(mac, 'data', { sessionId: 's1', seq: 1, data: liveB64 })
  await settle()

  const dataMsgs = messagesOfType(phone, 'data')
  expect(dataMsgs).toHaveLength(1)
  const p = dataMsgs[0] as { sessionId: string; seq: number; data: string }
  expect(p.sessionId).toBe('s1')
  expect(p.seq).toBe(1)
  expect(Buffer.from(p.data, 'base64').toString()).toBe('LIVE')
})

// ---------------------------------------------------------------------------
// Test 4: input iletimi (phone → mac), base64 payload korunur
// ---------------------------------------------------------------------------

test('phone input → mac alır; base64 payload bozulmadan', async () => {
  server = await testServer({ push: new NullPush() })
  const { mac, phone } = await pairRoom()

  // "hi" → base64 ("aGk=")
  const hiB64 = Buffer.from('hi').toString('base64')
  send(phone, 'input', { sessionId: 's1', data: hiB64 })
  await settle()

  const inputMsgs = messagesOfType(mac, 'input')
  expect(inputMsgs).toHaveLength(1)
  const p = inputMsgs[0] as { sessionId: string; data: string }
  expect(p.sessionId).toBe('s1')
  expect(Buffer.from(p.data, 'base64').toString()).toBe('hi')
  // phone kendi input'unu geri ALMAZ
  expect(messagesOfType(phone, 'input')).toHaveLength(0)
})

// ---------------------------------------------------------------------------
// Test 5: tam tur — subscribe → scrollback + data → input (bütünleşik senaryo)
// ---------------------------------------------------------------------------

test('tam terminal-ayna turu: subscribe → scrollback+data → input', async () => {
  server = await testServer({ push: new NullPush() })
  const { mac, phone } = await pairRoom()

  // 1) Phone subscribe gönderir → Mac alır
  send(phone, 'subscribe', { sessionId: 's1' })
  await settle()
  expect(messagesOfType(mac, 'subscribe')).toHaveLength(1)
  mac.inbox = []

  // 2) Mac scrollback + data yayınlar → Phone alır (sırasıyla)
  const scrollB64 = Buffer.from('SCROLL').toString('base64')
  const liveB64 = Buffer.from('LIVE').toString('base64')
  send(mac, 'scrollback', { sessionId: 's1', seq: 0, cols: 80, rows: 24, data: scrollB64 })
  send(mac, 'data', { sessionId: 's1', seq: 1, data: liveB64 })
  await settle()

  const scrollMsgs = messagesOfType(phone, 'scrollback')
  const dataMsgs = messagesOfType(phone, 'data')
  expect(scrollMsgs).toHaveLength(1)
  expect(dataMsgs).toHaveLength(1)
  expect(Buffer.from((scrollMsgs[0] as { data: string }).data, 'base64').toString()).toBe('SCROLL')
  expect(Buffer.from((dataMsgs[0] as { data: string }).data, 'base64').toString()).toBe('LIVE')

  // Sıra testi: inbox'taki terminal mesajlarının varış sırası scrollback → data olmalı
  const terminalMsgs = phone.inbox.filter(
    (m) => m.type === 'scrollback' || m.type === 'data'
  )
  expect(terminalMsgs[0]?.type).toBe('scrollback')
  expect(terminalMsgs[1]?.type).toBe('data')
  phone.inbox = []

  // 3) Phone input gönderir → Mac alır
  const hiB64 = Buffer.from('hi').toString('base64')
  send(phone, 'input', { sessionId: 's1', data: hiB64 })
  await settle()

  const inputMsgs = messagesOfType(mac, 'input')
  expect(inputMsgs).toHaveLength(1)
  expect(Buffer.from((inputMsgs[0] as { data: string }).data, 'base64').toString()).toBe('hi')
})
