import { describe, expect, test } from 'vitest'
import { ServerAccess, TOKEN_PREFIX } from '../src/access.js'
import { buildNetworkPolicy, DEFAULT_ALLOWLIST, parseAllowlist } from '../src/allowlist.js'
import { MemoryStore } from '../src/store.js'
import { isAllowedEmail, parseList, requestedScope } from '../src/dashboard/oidc.js'

describe('allowlist', () => {
  test('satır ya da virgülle ayrılmış kayıtlar ve etiketler çözülür, bozuklar ayrılır', () => {
    const { entries, invalid } = parseAllowlist('1.2.3.4 = Ofis\n10.0.0.0/8,bozuk, 1.2.3.0/40')
    expect(entries).toEqual([{ cidr: '1.2.3.4', label: 'Ofis' }, { cidr: '10.0.0.0/8', label: '10.0.0.0/8' }])
    expect(invalid).toEqual(['bozuk', '1.2.3.0/40'])
  })

  test('tam IP, CIDR ve IPv6\'ya gömülü IPv4 eşleşir', () => {
    const policy = buildNetworkPolicy({ mode: 'enforce', entries: parseAllowlist(DEFAULT_ALLOWLIST).entries })
    expect(policy.verdict('89.145.191.82')).toBe('allowed')
    expect(policy.verdict('::ffff:74.114.9.10')).toBe('allowed')
    expect(policy.verdict('95.0.243.79')).toBe('allowed')
    expect(policy.verdict('95.0.243.80')).toBe('blocked')
  })

  test('report modu engellemez; boş liste kontrolü kapatır', () => {
    const entries = parseAllowlist('1.2.3.4').entries
    expect(buildNetworkPolicy({ mode: 'report', entries }).verdict('5.6.7.8')).toBe('would_block')
    expect(buildNetworkPolicy({ mode: 'enforce', entries: [] }).verdict('5.6.7.8')).toBe('allowed')
  })
})

describe('ServerAccess', () => {
  test('üretilen token doğrulanır; iptal edilen ve bilinmeyen reddedilir, dinleyici haber alır', async () => {
    const access = await ServerAccess.load(new MemoryStore())
    const { token, record } = await access.createToken('  Berkay – MacBook  ')
    expect(token.startsWith(TOKEN_PREFIX)).toBe(true)
    expect(record.name).toBe('Berkay – MacBook')
    expect(access.authenticate(token)).toEqual({ id: record.id, name: record.name })
    expect(access.authenticate(token + 'x')).toBeNull()
    expect(access.authenticate(null)).toBeNull()

    const revoked: string[] = []
    access.onRevoke((id) => revoked.push(id))
    expect(await access.revokeToken(record.id)).toBe(true)
    expect(access.authenticate(token)).toBeNull()
    expect(revoked).toEqual([record.id])
    expect(await access.revokeToken(record.id)).toBe(false)
  })

  test('düz token store\'a yazılmaz; yeniden yüklemede token ve allowlist korunur', async () => {
    const store = new MemoryStore()
    const first = await ServerAccess.load(store)
    const { token } = await first.createToken('Mac')
    await first.setAllowlist('report', parseAllowlist('1.2.3.4=Ev').entries)
    expect(JSON.stringify(await store.listTokens())).not.toContain(token)

    const second = await ServerAccess.load(store, { allowlist: '9.9.9.9', mode: 'enforce' })
    expect(second.authenticate(token)?.name).toBe('Mac')
    expect(second.allowlist()).toEqual({ mode: 'report', entries: [{ cidr: '1.2.3.4', label: 'Ev' }] })
  })

  test('ilk açılışta varsayılan liste enforce modunda yüklenir', async () => {
    const access = await ServerAccess.load(new MemoryStore())
    expect(access.allowlist().mode).toBe('enforce')
    expect(access.allowlist().entries.length).toBe(5)
  })

  test('listede olmayan hub/controller bağlantısı kaydedilir', async () => {
    const access = await ServerAccess.load(new MemoryStore(), { allowlist: '1.2.3.4', mode: 'enforce' })
    const who = { id: 't', name: 'Ali' }
    expect(access.checkNetwork('1.2.3.4', 'hub', who)).toBe('allowed')
    expect(access.checkNetwork('5.6.7.8', 'controller', who)).toBe('blocked')
    expect(access.networkEvents()).toMatchObject([{ ip: '5.6.7.8', role: 'controller', verdict: 'blocked', tokenName: 'Ali' }])
  })

  test('boş ad reddedilir', async () => {
    const access = await ServerAccess.load(new MemoryStore())
    await expect(access.createToken('   ')).rejects.toThrow()
  })
})

describe('dashboard girişi', () => {
  test('email kapsamı yalnız sağlayıcı destekliyorsa istenir', () => {
    expect(requestedScope({ scopes_supported: ['openid', 'offline_access', 'mcp'] })).toBe('openid')
    expect(requestedScope({ scopes_supported: ['openid', 'email'] })).toBe('openid email')
    expect(requestedScope({})).toBe('openid email')
  })

  test('alan adı ve e-posta listeleri büyük/küçük harf ve @ önekinden bağımsızdır', () => {
    const allowed = { emails: parseList('Guest@Gmail.com'), domains: parseList(' @UncoSoft.com , rollicgames.com') }
    expect(isAllowedEmail('berkay@uncosoft.com', allowed)).toBe(true)
    expect(isAllowedEmail('X@ROLLICGAMES.COM', allowed)).toBe(true)
    expect(isAllowedEmail('guest@gmail.com', allowed)).toBe(true)
    expect(isAllowedEmail('berkay@uncosoft.com.evil.io', allowed)).toBe(false)
    expect(isAllowedEmail('nobody@gmail.com', allowed)).toBe(false)
  })
})
