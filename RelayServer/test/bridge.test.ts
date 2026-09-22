import { expect, test, describe, it } from 'vitest'
import { Bridge, type PushSender } from '../src/bridge.js'
import { Registry } from '../src/registry.js'
import { parseEnvelope, envelope, type Envelope } from '../src/protocol.js'

export class FakeClient {
  sent: Envelope[] = []
  closed = false
  send(data: string) { this.sent.push(parseEnvelope(data)!) }
  close() { this.closed = true }
  last(): Envelope { return this.sent[this.sent.length - 1] }
}

export class FakePush implements PushSender {
  calls: { tokens: string[]; title: string; body: string }[] = []
  async send(tokens: string[], title: string, body: string) {
    this.calls.push({ tokens, title, body })
  }
}

export const TOKEN = 'secret-token-1234567890'

export function env(type: string, payload: Record<string, unknown>): Envelope {
  return { v: 1, type, payload }
}

export function setup() {
  const registry = new Registry(() => 5000)
  const push = new FakePush()
  const bridge = new Bridge(registry, push)
  return { registry, push, bridge }
}

test('geçersiz hello null döner', () => {
  const { bridge } = setup()
  expect(bridge.handleHello(new FakeClient(), env('hello', { role: 'mac', token: 'kısa' }))).toBeNull()
  expect(bridge.handleHello(new FakeClient(), env('ping', {}))).toBeNull()
})

test('telefon hello → welcome içinde sessions ve macOnline gelir', () => {
  const { bridge } = setup()
  const mac = new FakeClient()
  const macSession = bridge.handleHello(mac, env('hello', { role: 'mac', token: TOKEN }))!
  macSession.room.sessions = [{ id: 's1' }]

  const phone = new FakeClient()
  bridge.handleHello(phone, env('hello', { role: 'phone', token: TOKEN }))
  expect(phone.last().type).toBe('welcome')
  expect(phone.last().payload.sessions).toEqual([{ id: 's1' }])
  expect(phone.last().payload.macOnline).toBe(true)
  expect(phone.last().payload.lastSeenAt).toBe(5000)
})

test('telefon hello → welcome içinde repos gelir (mac önce cache etmişse)', () => {
  const { bridge } = setup()
  const mac = new FakeClient()
  const macSession = bridge.handleHello(mac, env('hello', { role: 'mac', token: TOKEN }))!
  macSession.room.repos = [{ name: 'lumi', path: '/a/lumi' }]

  const phone = new FakeClient()
  bridge.handleHello(phone, env('hello', { role: 'phone', token: TOKEN }))
  expect(phone.last().payload.repos).toEqual([{ name: 'lumi', path: '/a/lumi' }])
})

test('mac repos mesajı → cache + bağlı telefonlara yayınlanır', () => {
  const { bridge } = setup()
  const phone = new FakeClient()
  bridge.handleHello(phone, env('hello', { role: 'phone', token: TOKEN }))
  const macSession = bridge.handleHello(new FakeClient(), env('hello', { role: 'mac', token: TOKEN }))!

  const repos = [{ name: 'lumi', path: '/a/lumi' }]
  bridge.handleMessage(macSession, env('repos', { repos }))

  expect(macSession.room.repos).toEqual(repos)      // cache
  expect(phone.last().type).toBe('repos')            // broadcast
  expect(phone.last().payload.repos).toEqual(repos)
})

test('mac hello → welcome içinde phoneCount gelir', () => {
  const { bridge } = setup()
  const mac = new FakeClient()
  bridge.handleHello(mac, env('hello', { role: 'mac', token: TOKEN }))
  expect(mac.last().type).toBe('welcome')
  expect(mac.last().payload).toEqual({ phoneCount: 0 })
})

test('ping → pong', () => {
  const { bridge } = setup()
  const phone = new FakeClient()
  const session = bridge.handleHello(phone, env('hello', { role: 'phone', token: TOKEN }))!
  bridge.handleMessage(session, env('ping', {}))
  expect(phone.last().type).toBe('pong')
})

test('handleClose istemciyi odadan düşürür', () => {
  const { bridge, registry } = setup()
  const mac = new FakeClient()
  const session = bridge.handleHello(mac, env('hello', { role: 'mac', token: TOKEN }))!
  bridge.handleClose(session)
  expect(registry.get(TOKEN)).toBeUndefined()
})

function paired() {
  const s = setup()
  const mac = new FakeClient()
  const phone = new FakeClient()
  const macSession = s.bridge.handleHello(mac, env('hello', { role: 'mac', token: TOKEN }))!
  const phoneSession = s.bridge.handleHello(phone, env('hello', { role: 'phone', token: TOKEN }))!
  return { ...s, mac, phone, macSession, phoneSession }
}

test('sessions odada saklanır ve telefonlara yayınlanır', () => {
  const { bridge, mac, phone, macSession, registry } = paired()
  bridge.handleMessage(macSession, env('sessions', { sessions: [{ id: 's1' }] }))
  expect(registry.get(TOKEN)?.sessions).toEqual([{ id: 's1' }])
  expect(phone.last().type).toBe('sessions')
  expect(phone.last().payload).toEqual({ sessions: [{ id: 's1' }] })
  expect(mac.sent.filter((m) => m.type === 'sessions')).toHaveLength(0)
})

test('scrollback telefonlara yayınlanır', () => {
  const { bridge, phone, macSession } = paired()
  bridge.handleMessage(macSession, env('scrollback', { sessionId: 's1', data: 'YQ==' }))
  expect(phone.last().type).toBe('scrollback')
  expect(phone.last().payload).toEqual({ sessionId: 's1', data: 'YQ==' })
})

test('data telefonlara yayınlanır', () => {
  const { bridge, phone, macSession } = paired()
  bridge.handleMessage(macSession, env('data', { sessionId: 's1', seq: 1, data: 'YQ==' }))
  expect(phone.last().type).toBe('data')
  expect(phone.last().payload).toEqual({ sessionId: 's1', seq: 1, data: 'YQ==' })
})

test('command_result telefonlara iletilir', () => {
  const { bridge, phone, macSession } = paired()
  bridge.handleMessage(macSession, env('command_result', { commandId: 'c1', ok: true }))
  expect(phone.last().type).toBe('command_result')
  expect(phone.last().payload).toEqual({ commandId: 'c1', ok: true })
})

test('command mac\'e iletilir', () => {
  const { bridge, mac, phoneSession } = paired()
  bridge.handleMessage(phoneSession, env('command', { commandId: 'c1', action: 'send_text', sessionId: 's1', text: 'devam et' }))
  expect(mac.last().type).toBe('command')
  expect(mac.last().payload).toEqual({ commandId: 'c1', action: 'send_text', sessionId: 's1', text: 'devam et' })
})

test('mac offline iken command anında hata döner', () => {
  const { bridge, mac, phone, macSession, phoneSession } = paired()
  bridge.handleClose(macSession)
  bridge.handleMessage(phoneSession, env('command', { commandId: 'c2', action: 'press_key', sessionId: 's1', key: 'enter' }))
  expect(phone.last().type).toBe('command_result')
  expect(phone.last().payload).toEqual({ commandId: 'c2', ok: false, error: 'mac_offline' })
  expect(mac.sent.filter((m) => m.type === 'command')).toHaveLength(0)
})

test('register_push cihaz token\'ını odaya ekler; geçersizi yok sayar', () => {
  const { bridge, phoneSession, registry } = paired()
  bridge.handleMessage(phoneSession, env('register_push', { deviceToken: 'device-token-abc' }))
  bridge.handleMessage(phoneSession, env('register_push', { deviceToken: '' }))
  bridge.handleMessage(phoneSession, env('register_push', {}))
  expect([...registry.get(TOKEN)!.pushTokens]).toEqual(['device-token-abc'])
})

test('register_push sonra unregister_push token odadan silinir', () => {
  const { bridge, phoneSession, registry } = paired()
  bridge.handleMessage(phoneSession, env('register_push', { deviceToken: 'device-token-abc' }))
  expect([...registry.get(TOKEN)!.pushTokens]).toEqual(['device-token-abc'])
  bridge.handleMessage(phoneSession, env('unregister_push', { deviceToken: 'device-token-abc' }))
  expect(registry.get(TOKEN)!.pushTokens.size).toBe(0)
})

test('unregister_push bilinmeyen token no-op, hata vermez', () => {
  const { bridge, phoneSession, registry } = paired()
  bridge.handleMessage(phoneSession, env('unregister_push', { deviceToken: 'yok' }))
  expect(registry.get(TOKEN)!.pushTokens.size).toBe(0)
})

test('mac chat/chat_append → telefonlara broadcast', () => {
  const { bridge } = setup()
  const phone = new FakeClient()
  bridge.handleHello(phone, env('hello', { role: 'phone', token: TOKEN }))
  const macSession = bridge.handleHello(new FakeClient(), env('hello', { role: 'mac', token: TOKEN }))!

  bridge.handleMessage(macSession, env('chat', { sessionId: 's1', messages: [{ id: 'm1' }] }))
  expect(phone.last().type).toBe('chat')
  expect(phone.last().payload.sessionId).toBe('s1')

  bridge.handleMessage(macSession, env('chat_append', { sessionId: 's1', messages: [{ id: 'm2' }] }))
  expect(phone.last().type).toBe('chat_append')
})

test('mac prompt → telefon broadcast; telefon prompt_respond → mac forward', () => {
  const { bridge } = setup()
  const phone = new FakeClient()
  const phoneSession = bridge.handleHello(phone, env('hello', { role: 'phone', token: TOKEN }))!
  const mac = new FakeClient()
  const macSession = bridge.handleHello(mac, env('hello', { role: 'mac', token: TOKEN }))!

  bridge.handleMessage(macSession, env('prompt', { sessionId: 's1', itemId: 'i1', kind: 'approval', state: 'pending' }))
  expect(phone.last().type).toBe('prompt')
  expect(phone.last().payload.itemId).toBe('i1')

  bridge.handleMessage(phoneSession, env('prompt_respond', { sessionId: 's1', itemId: 'i1', expectedRevision: 0, optionId: 'allow' }))
  expect(mac.last().type).toBe('prompt_respond')
  expect(mac.last().payload.optionId).toBe('allow')
})

test('telefon chat_send → mac forward (regresyon: relay bunu düşürüyordu → mesaj Mac\'e ulaşmıyordu)', () => {
  const { bridge } = setup()
  const phone = new FakeClient()
  const phoneSession = bridge.handleHello(phone, env('hello', { role: 'phone', token: TOKEN }))!
  const mac = new FakeClient()
  bridge.handleHello(mac, env('hello', { role: 'mac', token: TOKEN }))

  bridge.handleMessage(phoneSession, env('chat_send', { sessionId: 's1', text: 'merhaba' }))
  expect(mac.last().type).toBe('chat_send')
  expect(mac.last().payload.sessionId).toBe('s1')
  expect(mac.last().payload.text).toBe('merhaba')
})

test('mac chat_status → telefonlara broadcast', () => {
  const { bridge } = setup()
  const phone = new FakeClient()
  bridge.handleHello(phone, env('hello', { role: 'phone', token: TOKEN }))
  const macSession = bridge.handleHello(new FakeClient(), env('hello', { role: 'mac', token: TOKEN }))!

  bridge.handleMessage(macSession, env('chat_status', {
    sessionId: 's1', working: true, startedAtMs: 42, tool: 'Bash',
  }))
  expect(phone.last().type).toBe('chat_status')
  expect(phone.last().payload.sessionId).toBe('s1')
  expect(phone.last().payload.tool).toBe('Bash')
})

test('subscribe mode alanı opak geçer (phone→mac)', () => {
  const { bridge } = setup()
  const mac = new FakeClient()
  bridge.handleHello(mac, env('hello', { role: 'mac', token: TOKEN }))
  const phoneSession = bridge.handleHello(new FakeClient(), env('hello', { role: 'phone', token: TOKEN }))!
  bridge.handleMessage(phoneSession, env('subscribe', { sessionId: 's1', mode: 'chat' }))
  expect(mac.last().type).toBe('subscribe')
  expect(mac.last().payload.mode).toBe('chat')
})

test('mac projects → odada saklanır ve telefonlara yayınlanır', () => {
  const { bridge, registry, mac, phone, macSession } = paired()
  const payload = { projects: [{ name: 'p', path: '/p', checkouts: [] }], addable: [{ name: 'orca', path: '/p/orca' }] }
  bridge.handleMessage(macSession, env('projects', payload))
  expect(registry.get(TOKEN)?.projects).toEqual(payload)
  expect(phone.last().type).toBe('projects')
  expect(phone.last().payload).toEqual(payload)
})

test('telefon hello → welcome içinde projects ve addable gelir (mac önce cache etmişse)', () => {
  const { bridge } = setup()
  const mac = new FakeClient()
  const macSession = bridge.handleHello(mac, env('hello', { role: 'mac', token: TOKEN }))!
  macSession.room.projects = { projects: [{ name: 'p', path: '/p', checkouts: [] }], addable: [] }

  const phone = new FakeClient()
  bridge.handleHello(phone, env('hello', { role: 'phone', token: TOKEN }))
  expect(phone.last().type).toBe('welcome')
  expect(phone.last().payload.projects).toEqual([{ name: 'p', path: '/p', checkouts: [] }])
  expect(phone.last().payload.addable).toEqual([])
})

test('telefon command add_project → mac\'e forward edilir', () => {
  const { bridge, mac, phoneSession } = paired()
  bridge.handleMessage(phoneSession, env('command', { commandId: 'c1', action: 'add_project', path: '/p/orca' }))
  const forwarded = mac.sent.find((m) => m.type === 'command')
  expect(forwarded?.payload.action).toBe('add_project')
})

// --- Terminal-stream routing tests (brief Step 7) ---

function fakeClient() {
  const sent: string[] = []
  return { sent, send: (d: string) => sent.push(d), close: () => {} }
}
const noPush = { send: async () => {} }

describe('bridge terminal routing', () => {
  it('forwards subscribe/input from phone to mac', () => {
    const reg = new Registry(); const bridge = new Bridge(reg, noPush)
    const mac = fakeClient(); const phone = fakeClient()
    const macS = bridge.handleHello(mac as any, JSON.parse(envelope('hello', { role: 'mac', token: 'x'.repeat(16) })))!
    const phoneS = bridge.handleHello(phone as any, JSON.parse(envelope('hello', { role: 'phone', token: 'x'.repeat(16) })))!
    bridge.handleMessage(phoneS, JSON.parse(envelope('subscribe', { sessionId: 's1' })))
    bridge.handleMessage(phoneS, JSON.parse(envelope('input', { sessionId: 's1', data: 'YQ==' })))
    expect(mac.sent.some(m => m.includes('"subscribe"'))).toBe(true)
    expect(mac.sent.some(m => m.includes('"input"'))).toBe(true)
  })
  it('broadcasts scrollback/data from mac to phones', () => {
    const reg = new Registry(); const bridge = new Bridge(reg, noPush)
    const mac = fakeClient(); const phone = fakeClient()
    bridge.handleHello(mac as any, JSON.parse(envelope('hello', { role: 'mac', token: 'x'.repeat(16) })))
    const phoneS = bridge.handleHello(phone as any, JSON.parse(envelope('hello', { role: 'phone', token: 'x'.repeat(16) })))!
    const macS = { client: mac, role: 'mac' as const, room: reg.get('x'.repeat(16))! }
    bridge.handleMessage(macS as any, JSON.parse(envelope('data', { sessionId: 's1', seq: 1, data: 'YQ==' })))
    expect(phone.sent.some(m => m.includes('"data"'))).toBe(true)
  })
  it('subscribe/unsubscribe/input from phone silently dropped if mac offline', () => {
    const reg = new Registry(); const bridge = new Bridge(reg, noPush)
    const phone = fakeClient()
    const phoneS = bridge.handleHello(phone as any, JSON.parse(envelope('hello', { role: 'phone', token: 'x'.repeat(16) })))!
    // mac is offline — subscribe/unsubscribe/input should be silently dropped
    bridge.handleMessage(phoneS, JSON.parse(envelope('subscribe', { sessionId: 's1' })))
    bridge.handleMessage(phoneS, JSON.parse(envelope('unsubscribe', { sessionId: 's1' })))
    bridge.handleMessage(phoneS, JSON.parse(envelope('input', { sessionId: 's1', data: 'YQ==' })))
    // no command_result error for subscribe/unsubscribe/input (only for command)
    expect(phone.sent.filter(m => m.includes('"command_result"'))).toHaveLength(0)
  })
})
