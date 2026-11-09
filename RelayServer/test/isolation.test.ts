import { afterEach, expect, test } from 'vitest'
import WebSocket from 'ws'
import { testServer, openSocket, type TestServer } from './support.js'
import type { PushSender } from '../src/bridge.js'

// İki gerçek kullanıcı (farklı token) aynı relay'e bağlandığında terminal-stream
// mesajlarının karşı odaya SIZMADIĞINI gerçek WebSocket sunucusuna karşı doğrular.
// "Terminal verisi yanlış kişiye gidiyor mu?" sorusunun regresyon testi.

const TOKEN_A = 'user-A-token-1234567890'
const TOKEN_B = 'user-B-token-0987654321'

class CapturingPush implements PushSender {
  calls: { tokens: string[]; title: string; body: string }[] = []
  async send(tokens: string[], title: string, body: string) {
    this.calls.push({ tokens, title, body })
  }
}

let server: TestServer | null = null
let push: CapturingPush

afterEach(() => { server?.close(); server = null })

function serverPort(): number {
  return server!.port()
}

// Her sokete gelen TÜM mesajları biriktirir (yokluk iddiası için gerekli).
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

// Sunucu broadcast'i işlesin diye ağ turu bekler.
const settle = () => new Promise((r) => setTimeout(r, 60))

function typesFor(ws: Sock, type: string): Record<string, unknown>[] {
  return ws.inbox.filter((m) => m.type === type).map((m) => m.payload as Record<string, unknown>)
}

async function pair(token: string): Promise<{ mac: Sock; phone: Sock }> {
  const mac = await connect()
  send(mac, 'hello', { role: 'mac', token })
  const phone = await connect()
  send(phone, 'hello', { role: 'phone', token })
  await settle()
  mac.inbox = []   // welcome'ları temizle, sadece akış mesajlarına bak
  phone.inbox = []
  return { mac, phone }
}

test('iki farklı kullanıcının sessions/data/command_result\'ı odalar arası SIZMAZ', async () => {
  push = new CapturingPush()
  server = await testServer({ push })
  const A = await pair(TOKEN_A)
  const B = await pair(TOKEN_B)

  // Mac A hem sessions hem data hem command_result yayınlıyor
  send(A.mac, 'sessions', { sessions: [{ id: 'A-session' }] })
  send(A.mac, 'data', { sessionId: 'A-session', seq: 1, data: 'GİZLİ-A' })
  send(A.mac, 'command_result', { commandId: 'a1', ok: true })
  await settle()

  // Phone A hepsini almalı
  expect(typesFor(A.phone, 'sessions')).toEqual([{ sessions: [{ id: 'A-session' }] }])
  expect(typesFor(A.phone, 'data')).toEqual([{ sessionId: 'A-session', seq: 1, data: 'GİZLİ-A' }])
  expect(typesFor(A.phone, 'command_result')).toEqual([{ commandId: 'a1', ok: true }])

  // Phone B HİÇBİRİNİ almamalı — sızıntı yok
  expect(B.phone.inbox).toEqual([])
  // Mac B de A'nın hiçbir şeyini almamalı
  expect(B.mac.inbox).toEqual([])
})

test('Phone B\'nin komutu yalnız Mac B\'ye gider, Mac A\'ya sızmaz', async () => {
  push = new CapturingPush()
  server = await testServer({ push })
  const A = await pair(TOKEN_A)
  const B = await pair(TOKEN_B)

  send(B.phone, 'command', { commandId: 'b1', action: 'send_text', sessionId: 'B-session', text: 'B-KOMUT' })
  await settle()

  expect(typesFor(B.mac, 'command')).toEqual([
    { commandId: 'b1', action: 'send_text', sessionId: 'B-session', text: 'B-KOMUT' },
  ])
  // Mac A komutu görmemeli
  expect(typesFor(A.mac, 'command')).toEqual([])
})

test('aynı token\'lı iki telefon (aynı kullanıcı) ikisi de alır — bilinçli mirroring', async () => {
  push = new CapturingPush()
  server = await testServer({ push })
  const A = await pair(TOKEN_A)
  const phone2 = await connect()
  send(phone2, 'hello', { role: 'phone', token: TOKEN_A })
  await settle()
  phone2.inbox = []

  send(A.mac, 'data', { sessionId: 'A-session', seq: 1, data: 'her-iki-cihaz' })
  await settle()

  expect(typesFor(A.phone, 'data')).toHaveLength(1)
  expect(typesFor(phone2, 'data')).toHaveLength(1)
})

test('register_push odaya özel — B\'nin cihazı A\'nın odasına dahil değil', async () => {
  push = new CapturingPush()
  server = await testServer({ push })
  const A = await pair(TOKEN_A)
  const B = await pair(TOKEN_B)

  send(A.phone, 'register_push', { deviceToken: 'device-A' })
  send(B.phone, 'register_push', { deviceToken: 'device-B' })
  await settle()

  // Sadece kayıt olduğunu doğrula — her cihaz sadece kendi odasında
  // (push push.calls listesi boş çünkü event/data push tetiklemez artık)
  expect(push.calls).toHaveLength(0)
  // device-B kesinlikle A'nın push listesinde yer almamalı (implicit — farklı oda)
  expect(push.calls.some((c) => c.tokens.includes('device-B'))).toBe(false)
})

test('ikinci Mac aynı token ile bağlanınca eskisi düşer; farklı token etkilenmez', async () => {
  push = new CapturingPush()
  server = await testServer({ push })
  const A = await pair(TOKEN_A)
  const B = await pair(TOKEN_B)

  const closedA = new Promise<number>((resolve) => A.mac.on('close', (code) => resolve(code)))
  const mac2 = await connect()
  send(mac2, 'hello', { role: 'mac', token: TOKEN_A })
  const code = await closedA
  expect(code).toBe(4000) // 'replaced'

  // B'nin Mac'i etkilenmedi: hâlâ komut alabiliyor
  send(B.phone, 'command', { commandId: 'b9', action: 'press_key', sessionId: 'B-session', key: 'enter' })
  await settle()
  expect(typesFor(B.mac, 'command')).toHaveLength(1)
})
