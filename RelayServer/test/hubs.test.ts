import { afterEach, describe, expect, test, vi } from 'vitest'
import { HubBridge, HUB_CLOSE, OFFLINE_HUB_TTL_MS, type Conn } from '../src/hubs.js'
import { parseEnvelope, type Envelope } from '../src/protocol.js'

// Mac'ten Mac'e remote kanalı (docs/design/08-mac-remote.md).

class Client {
  sent: Envelope[] = []
  closedWith: { code?: number; reason?: string } | null = null
  conn: Conn | null = null
  send(data: string) { this.sent.push(parseEnvelope(data)!) }
  close(code?: number, reason?: string) {
    if (this.closedWith) return
    this.closedWith = { code, reason }
    this.conn?.close() // gerçek sunucuda ws 'close' olayı uçtaki close'u çağırır
  }
  last(type?: string): Envelope | undefined {
    const list = type ? this.sent.filter((e) => e.type === type) : this.sent
    return list[list.length - 1]
  }
  ofType(type: string): Envelope[] { return this.sent.filter((e) => e.type === type) }
}

const NET = 'network-token-A-1234567890'
const OTHER_NET = 'network-token-B-0987654321'
const HUB_ID = 'hub-0000-build-machine'

function env(type: string, payload: Record<string, unknown>): Envelope {
  return { v: 1, type, payload }
}

let clock = 1_000
function makeBridge(attachTimeoutMs = 10_000) {
  clock = 1_000
  return new HubBridge({ now: () => clock, attachTimeoutMs })
}

function connect(bridge: HubBridge, payload: Record<string, unknown>, onAuthFailure = () => {}): Client {
  const client = new Client()
  client.conn = bridge.handleHello(client, env('hello', payload), onAuthFailure)
  return client
}

const HUB_KEY = 'hub-secret-key-1234567890'

function hub(bridge: HubBridge, opts: { network?: string; hubId?: string; hubKey?: string; name?: string } = {}): Client {
  return connect(bridge, {
    role: 'hub', network: opts.network ?? NET, hubId: opts.hubId ?? HUB_ID,
    hubKey: opts.hubKey ?? HUB_KEY, name: opts.name ?? 'Build Mac',
  })
}

function browser(bridge: HubBridge, network = NET): Client {
  return connect(bridge, { role: 'controller', network, controllerId: 'ctrl-0001-laptop', name: 'Laptop' })
}

function controller(
  bridge: HubBridge,
  password = 'pw',
  onAuthFailure = () => {},
  opts: { hubId?: string; controllerId?: string } = {},
): Client {
  return connect(bridge, {
    role: 'controller', network: NET, controllerId: opts.controllerId ?? 'ctrl-0001-laptop', name: 'Laptop',
    attach: { hubId: opts.hubId ?? HUB_ID, password },
  }, onAuthFailure)
}

/** Hub'a gelen son bağlanma isteğini kabul/ret eder. */
function answer(h: Client, ok: boolean, error?: string) {
  const request = h.last('attach_request')!
  h.conn!.message(env('attach_result', { requestId: request.payload.requestId, ok, ...(error ? { error } : {}) }))
}

function attached(bridge: HubBridge, h: Client, opts: { controllerId?: string } = {}): Client {
  const c = controller(bridge, 'pw', () => {}, opts)
  answer(h, true)
  return c
}

afterEach(() => { vi.useRealTimers() })

describe('hello doğrulaması', () => {
  test('rol bu kanala aitse claims true, telefon rolleri değil', () => {
    expect(HubBridge.claims(env('hello', { role: 'hub' }))).toBe(true)
    expect(HubBridge.claims(env('hello', { role: 'controller' }))).toBe(true)
    expect(HubBridge.claims(env('hello', { role: 'mac' }))).toBe(false)
    expect(HubBridge.claims(env('hello', { role: 'phone' }))).toBe(false)
  })

  test('kısa ağ token\'ı, eksik ad, kısa kimlik ve bozuk attach reddedilir', () => {
    const bridge = makeBridge()
    const bad: Record<string, unknown>[] = [
      { role: 'hub', network: 'kısa', hubId: HUB_ID, hubKey: HUB_KEY, name: 'x' },
      { role: 'hub', network: NET, hubId: HUB_ID, hubKey: HUB_KEY, name: '   ' },
      { role: 'hub', network: NET, hubId: 'kısa', hubKey: HUB_KEY, name: 'x' },
      { role: 'hub', network: NET, hubId: HUB_ID, name: 'x' },
      { role: 'hub', network: NET, hubId: HUB_ID, hubKey: 'kısa', name: 'x' },
      { role: 'controller', network: NET, controllerId: 'kısa', name: 'x' },
      { role: 'controller', network: NET, controllerId: 'ctrl-0001-laptop', name: 'x', attach: 'hub' },
      { role: 'controller', network: NET, controllerId: 'ctrl-0001-laptop', name: 'x', attach: { hubId: HUB_ID } },
    ]
    for (const payload of bad) {
      expect(bridge.handleHello(new Client(), env('hello', payload), () => {})).toBeNull()
    }
  })
})

describe('directory', () => {
  test('controller ağdaki hub\'ları görür, hub gelip gidince liste yeniden yayınlanır', () => {
    const bridge = makeBridge()
    const b = browser(bridge)
    expect(b.last('hubs')!.payload.hubs).toEqual([])

    const h = hub(bridge)
    expect(h.last()!.type).toBe('welcome')
    expect(b.last('hubs')!.payload.hubs).toEqual([
      { hubId: HUB_ID, name: 'Build Mac', online: true, lastSeenAt: 1_000, controllerCount: 0 },
    ])

    clock = 2_000
    h.close()
    expect(b.last('hubs')!.payload.hubs).toEqual([
      { hubId: HUB_ID, name: 'Build Mac', online: false, lastSeenAt: 2_000, controllerCount: 0 },
    ])
  })

  test('başka ağ token\'ındaki hub görünmez ve ona bağlanılamaz', () => {
    const bridge = makeBridge()
    hub(bridge, { network: OTHER_NET })
    const b = browser(bridge)
    expect(b.last('hubs')!.payload.hubs).toEqual([])

    const c = controller(bridge)
    expect(c.closedWith?.code).toBe(HUB_CLOSE.hubOffline)
  })

  test('hub_update adı değiştirir ve listeye yansır', () => {
    const bridge = makeBridge()
    const b = browser(bridge)
    const h = hub(bridge)
    h.conn!.message(env('hub_update', { name: '  Ofis Mac  ' }))
    expect((b.last('hubs')!.payload.hubs as { name: string }[])[0]!.name).toBe('Ofis Mac')
  })

  test('çevrimdışı hub 24 saat sonra sweep ile düşer', () => {
    const bridge = makeBridge()
    const h = hub(bridge)
    h.close()
    expect(bridge.hubCount(NET)).toBe(1)
    clock += OFFLINE_HUB_TTL_MS + 1
    bridge.sweep()
    expect(bridge.hubCount(NET)).toBe(0)
  })
})

describe('bağlanma (attach)', () => {
  test('şifre hub\'a iletilir; kabulde controller hub önbelleğiyle welcome alır', () => {
    const bridge = makeBridge()
    const b = browser(bridge)
    const h = hub(bridge)
    h.conn!.message(env('sessions', { sessions: [{ id: 's1' }] }))

    const c = controller(bridge, 'gizli')
    const request = h.last('attach_request')!
    expect(request.payload).toMatchObject({ controllerId: 'ctrl-0001-laptop', controllerName: 'Laptop', password: 'gizli' })
    expect(c.sent).toEqual([]) // hub cevap verene kadar sessiz

    answer(h, true)
    const welcome = c.last('welcome')!
    expect(welcome.payload.sessions).toEqual([{ id: 's1' }])
    expect(welcome.payload.macOnline).toBe(true)
    expect(welcome.payload.hub).toEqual({ hubId: HUB_ID, name: 'Build Mac' })
    expect(typeof welcome.payload.connectionId).toBe('string')
    expect((b.last('hubs')!.payload.hubs as { controllerCount: number }[])[0]!.controllerCount).toBe(1)
  })

  test('ret: 4003 ile kapanır ve IP başarısızlığı sayılır', () => {
    const bridge = makeBridge()
    const h = hub(bridge)
    const onAuthFailure = vi.fn()
    const c = controller(bridge, 'yanlış', onAuthFailure)
    answer(h, false, 'wrong_password')
    expect(c.closedWith).toEqual({ code: HUB_CLOSE.unauthorized, reason: 'wrong_password' })
    expect(onAuthFailure).toHaveBeenCalledOnce()
  })

  test('hub cevap vermezse attach zaman aşımıyla kapanır', () => {
    vi.useFakeTimers()
    const bridge = makeBridge(50)
    const h = hub(bridge)
    const c = controller(bridge)
    vi.advanceTimersByTime(60)
    expect(c.closedWith?.code).toBe(HUB_CLOSE.attachTimeout)
    // Geç gelen kabul hiçbir şey yapmaz.
    answer(h, true)
    expect(c.last('welcome')).toBeUndefined()
  })

  test('çevrimdışı hub\'a bağlanma 4004 ile kapanır', () => {
    const bridge = makeBridge()
    hub(bridge).close()
    expect(controller(bridge).closedWith?.code).toBe(HUB_CLOSE.hubOffline)
  })

  test('kabulden önce gönderilen frame hub\'a ulaşmaz', () => {
    const bridge = makeBridge()
    const h = hub(bridge)
    const c = controller(bridge)
    c.conn!.message(env('input', { sessionId: 's1', data: 'aGk=' }))
    expect(h.last('input')).toBeUndefined()
  })
})

describe('yönlendirme', () => {
  test('hub yayını tüm controller\'lara, controller frame\'i `from` ile hub\'a gider', () => {
    const bridge = makeBridge()
    const h = hub(bridge)
    const c1 = attached(bridge, h)
    const c2 = attached(bridge, h, { controllerId: 'ctrl-0002-desk' })

    h.conn!.message(env('data', { sessionId: 's1', seq: 1, data: 'TElWRQ==' }))
    expect(c1.last('data')!.payload.data).toBe('TElWRQ==')
    expect(c2.last('data')!.payload.data).toBe('TElWRQ==')

    c1.conn!.message(env('input', { sessionId: 's1', data: 'aGk=' }))
    const input = h.last('input')!
    expect(input.payload).toEqual({ sessionId: 's1', data: 'aGk=', from: c1.last('welcome')!.payload.connectionId })

    // Tanınmayan / telefon-özel frame iletilmez.
    c1.conn!.message(env('register_push', { deviceToken: 'x' }))
    expect(h.last('register_push')).toBeUndefined()
  })

  test('`to` taşıyan frame yalnız o controller\'a gider', () => {
    const bridge = makeBridge()
    const h = hub(bridge)
    const c1 = attached(bridge, h)
    const c2 = attached(bridge, h, { controllerId: 'ctrl-0002-desk' })
    const to = c2.last('welcome')!.payload.connectionId
    h.conn!.message(env('command_result', { commandId: 'k1', ok: true, to }))
    expect(c2.last('command_result')!.payload.commandId).toBe('k1')
    expect(c1.last('command_result')).toBeUndefined()
  })

  test('controller ayrılınca hub controller_left alır', () => {
    const bridge = makeBridge()
    const h = hub(bridge)
    const c = attached(bridge, h)
    const from = c.last('welcome')!.payload.connectionId
    c.close()
    expect(h.last('controller_left')!.payload).toEqual({ from })
  })
})

describe('hub yaşam döngüsü', () => {
  test('hub düşünce controller\'ları 4004 ile kapanır', () => {
    const bridge = makeBridge()
    const h = hub(bridge)
    const c = attached(bridge, h)
    h.close()
    expect(c.closedWith?.code).toBe(HUB_CLOSE.hubOffline)
  })

  test('aynı hub kimliğiyle ikinci bağlantı öncekini ve controller\'larını düşürür', () => {
    const bridge = makeBridge()
    const b = browser(bridge)
    const first = hub(bridge)
    const c = attached(bridge, first)
    const second = hub(bridge)
    expect(first.closedWith?.code).toBe(HUB_CLOSE.replaced)
    expect(c.closedWith?.code).toBe(HUB_CLOSE.replaced)
    // Eski bağlantının kapanışı yeni hub'ı çevrimdışı göstermez.
    expect((b.last('hubs')!.payload.hubs as { online: boolean }[])[0]!.online).toBe(true)
    expect(second.closedWith).toBeNull()
  })

  test('farklı hubKey listede görülen kimliği sahiplenemez (çevrimdışıyken de)', () => {
    const bridge = makeBridge()
    const real = hub(bridge)
    const c = attached(bridge, real)
    const impostor = new Client()
    expect(bridge.handleHello(impostor, env('hello', {
      role: 'hub', network: NET, hubId: HUB_ID, hubKey: 'impostor-key-1234567890', name: 'Build Mac',
    }), () => {})).toBeNull()
    expect(real.closedWith).toBeNull()
    expect(c.closedWith).toBeNull()

    real.close()
    expect(bridge.handleHello(new Client(), env('hello', {
      role: 'hub', network: NET, hubId: HUB_ID, hubKey: 'impostor-key-1234567890', name: 'Build Mac',
    }), () => {})).toBeNull()
    expect(hub(bridge).conn).not.toBeNull() // gerçek sahip geri dönebilir
  })

  test('revoke_controllers bağlı herkesi 4003 ile kapatır', () => {
    const bridge = makeBridge()
    const h = hub(bridge)
    const c = attached(bridge, h)
    h.conn!.message(env('revoke_controllers', {}))
    expect(c.closedWith).toEqual({ code: HUB_CLOSE.unauthorized, reason: 'revoked' })
  })

  test('hub ping\'e pong döner', () => {
    const bridge = makeBridge()
    const h = hub(bridge)
    h.conn!.message(env('ping', {}))
    expect(h.last()!.type).toBe('pong')
  })
})
