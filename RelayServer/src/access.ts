import { createHash, randomBytes, randomUUID } from 'node:crypto'
import {
  buildNetworkPolicy, DEFAULT_ALLOWLIST, parseAllowlist, parseMode,
  type AllowlistSettings, type NetworkPolicy, type NetworkVerdict,
} from './allowlist.js'
import type { RelayStore, TokenRecord } from './store.js'

/**
 * Sunucuya giriş kapısı (docs/design/09): server token'ları ve hub/controller
 * IP allowlist'i. Token'lar ve ayarlar açılışta store'dan belleğe yüklenir;
 * bağlantı yolunda veritabanına gidilmez.
 */

export const TOKEN_PREFIX = 'lrs_'
const ALLOWLIST_KEY = 'network_allowlist'
/** `last_used_at` en çok bu sıklıkla yazılır. */
const TOUCH_INTERVAL_MS = 60_000
const MAX_TOKEN_NAME = 64
const MAX_EVENTS = 50

export interface AuthenticatedToken {
  id: string
  name: string
}

export interface NetworkEvent {
  at: number
  ip: string
  role: string
  verdict: Exclude<NetworkVerdict, 'allowed'>
  tokenName: string
}

export interface AccessSeed {
  /** `NETWORK_ALLOWLIST` — yalnız store'da ayar yoksa (ilk açılış) kullanılır. */
  allowlist?: string
  mode?: string
}

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex')
}

export class ServerAccess {
  private byHash = new Map<string, TokenRecord>()
  private records: TokenRecord[] = []
  private policy: NetworkPolicy = buildNetworkPolicy({ mode: 'off', entries: [] })
  private events: NetworkEvent[] = []
  private revokeListeners = new Set<(tokenId: string) => void>()

  constructor(private store: RelayStore, private now: () => number = Date.now) {}

  static async load(store: RelayStore, seed: AccessSeed = {}, now?: () => number): Promise<ServerAccess> {
    const access = new ServerAccess(store, now)
    await store.init()
    await access.reloadTokens()
    const saved = parseSavedAllowlist(await store.getSetting(ALLOWLIST_KEY))
    if (saved) access.policy = buildNetworkPolicy(saved)
    else await access.setAllowlist(parseMode(seed.mode), parseAllowlist(seed.allowlist ?? DEFAULT_ALLOWLIST).entries)
    return access
  }

  // MARK: - Token'lar

  /** Geçerli (iptal edilmemiş) token'ın sahibi; değilse `null`. */
  authenticate(raw: string | null): AuthenticatedToken | null {
    if (!raw || !raw.startsWith(TOKEN_PREFIX) || raw.length > 256) return null
    const record = this.byHash.get(hashToken(raw))
    if (!record || record.revokedAt !== null) return null
    const at = this.now()
    if (record.lastUsedAt === null || at - record.lastUsedAt > TOUCH_INTERVAL_MS) {
      record.lastUsedAt = at
      this.store.touchToken(record.id, at).catch((err) => console.error('[access] touch:', err.message))
    }
    return { id: record.id, name: record.name }
  }

  /** Yeni token; düz değer yalnız bu dönüşte görünür. */
  async createToken(name: string): Promise<{ token: string; record: TokenRecord }> {
    const trimmed = name.trim().slice(0, MAX_TOKEN_NAME)
    if (!trimmed) throw new Error('Token adı boş olamaz')
    const token = TOKEN_PREFIX + randomBytes(32).toString('base64url')
    const record: TokenRecord = {
      id: randomUUID(),
      name: trimmed,
      hash: hashToken(token),
      prefix: token.slice(0, TOKEN_PREFIX.length + 6),
      createdAt: this.now(),
      lastUsedAt: null,
      revokedAt: null,
    }
    await this.store.insertToken(record)
    await this.reloadTokens()
    return { token, record }
  }

  /** İptal eder ve bu token'la açık bütün bağlantıları kapattırır. */
  async revokeToken(id: string): Promise<boolean> {
    if (!this.records.some((r) => r.id === id && r.revokedAt === null)) return false
    await this.store.revokeToken(id, this.now())
    await this.reloadTokens()
    for (const listener of this.revokeListeners) listener(id)
    return true
  }

  onRevoke(listener: (tokenId: string) => void): () => void {
    this.revokeListeners.add(listener)
    return () => this.revokeListeners.delete(listener)
  }

  tokens(): TokenRecord[] {
    return this.records.map((r) => ({ ...r }))
  }

  private async reloadTokens(): Promise<void> {
    this.records = await this.store.listTokens()
    this.byHash = new Map(this.records.map((r) => [r.hash, r]))
  }

  // MARK: - IP allowlist

  allowlist(): AllowlistSettings {
    return this.policy.settings
  }

  async setAllowlist(mode: AllowlistSettings['mode'], entries: AllowlistSettings['entries']): Promise<void> {
    const settings: AllowlistSettings = { mode, entries }
    await this.store.setSetting(ALLOWLIST_KEY, settings)
    this.policy = buildNetworkPolicy(settings)
  }

  /** Hub/controller hello'sunda çağrılır; listede olmayan bağlantı kaydedilir. */
  checkNetwork(ip: string, role: string, token: AuthenticatedToken): NetworkVerdict {
    const verdict = this.policy.verdict(ip)
    if (verdict !== 'allowed') {
      this.events.unshift({ at: this.now(), ip, role, verdict, tokenName: token.name })
      this.events.length = Math.min(this.events.length, MAX_EVENTS)
    }
    return verdict
  }

  matchLabel(ip: string): string | null {
    return this.policy.match(ip)
  }

  networkEvents(): NetworkEvent[] {
    return [...this.events]
  }
}

function parseSavedAllowlist(value: unknown): AllowlistSettings | null {
  if (typeof value !== 'object' || value === null) return null
  const v = value as { mode?: unknown; entries?: unknown }
  if (!Array.isArray(v.entries)) return null
  const raw = v.entries
    .filter((e): e is { cidr: string; label?: string } => typeof e === 'object' && e !== null && typeof e.cidr === 'string')
    .map((e) => `${e.cidr}=${e.label ?? ''}`)
    .join(',')
  return { mode: parseMode(typeof v.mode === 'string' ? v.mode : undefined), entries: parseAllowlist(raw).entries }
}
