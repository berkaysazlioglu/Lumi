/**
 * Relay'in kalıcı durumu: server token'ları ve ayarlar (allowlist).
 * Oda/hub durumu bilerek bellekte kalır — burada yalnız yönetim verisi var.
 */

export interface TokenRecord {
  id: string
  name: string
  /** SHA-256 (hex) — düz token hiçbir yerde saklanmaz. */
  hash: string
  /** Dashboard'da tanımak için ilk karakterler (`lrs_AbC1…`). */
  prefix: string
  createdAt: number
  lastUsedAt: number | null
  revokedAt: number | null
}

export interface RelayStore {
  init(): Promise<void>
  listTokens(): Promise<TokenRecord[]>
  insertToken(record: TokenRecord): Promise<void>
  revokeToken(id: string, at: number): Promise<void>
  touchToken(id: string, at: number): Promise<void>
  getSetting(key: string): Promise<unknown | null>
  setSetting(key: string, value: unknown): Promise<void>
  close(): Promise<void>
}

/** Test ve `DATABASE_URL`'siz yerel çalışma için; yeniden başlatmada her şey silinir. */
export class MemoryStore implements RelayStore {
  private tokens = new Map<string, TokenRecord>()
  private settings = new Map<string, unknown>()

  async init(): Promise<void> {}

  async listTokens(): Promise<TokenRecord[]> {
    return [...this.tokens.values()].map((t) => ({ ...t }))
  }

  async insertToken(record: TokenRecord): Promise<void> {
    this.tokens.set(record.id, { ...record })
  }

  async revokeToken(id: string, at: number): Promise<void> {
    const t = this.tokens.get(id)
    if (t && t.revokedAt === null) t.revokedAt = at
  }

  async touchToken(id: string, at: number): Promise<void> {
    const t = this.tokens.get(id)
    if (t) t.lastUsedAt = at
  }

  async getSetting(key: string): Promise<unknown | null> {
    return this.settings.has(key) ? structuredClone(this.settings.get(key)) : null
  }

  async setSetting(key: string, value: unknown): Promise<void> {
    this.settings.set(key, structuredClone(value))
  }

  async close(): Promise<void> {}
}
