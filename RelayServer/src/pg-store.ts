import pg from 'pg'
import type { RelayStore, TokenRecord } from './store.js'

const SCHEMA = `
CREATE TABLE IF NOT EXISTS relay_tokens (
  id text PRIMARY KEY,
  name text NOT NULL,
  token_hash text NOT NULL UNIQUE,
  prefix text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz,
  revoked_at timestamptz
);
CREATE TABLE IF NOT EXISTS relay_settings (
  key text PRIMARY KEY,
  value jsonb NOT NULL
);`

interface TokenRow {
  id: string
  name: string
  token_hash: string
  prefix: string
  created_at: Date
  last_used_at: Date | null
  revoked_at: Date | null
}

/** Heroku Postgres — sertifikası self-signed olduğu için doğrulama kapalı TLS. */
export class PgStore implements RelayStore {
  private pool: pg.Pool

  constructor(connectionString: string) {
    const local = /localhost|127\.0\.0\.1/.test(connectionString)
    this.pool = new pg.Pool({
      connectionString,
      ssl: local ? undefined : { rejectUnauthorized: false },
      max: 4,
    })
    this.pool.on('error', (err) => console.error('[pg] boşta bağlantı hatası:', err.message))
  }

  async init(): Promise<void> {
    await this.pool.query(SCHEMA)
  }

  async listTokens(): Promise<TokenRecord[]> {
    const { rows } = await this.pool.query<TokenRow>('SELECT * FROM relay_tokens ORDER BY created_at')
    return rows.map(toRecord)
  }

  async insertToken(r: TokenRecord): Promise<void> {
    await this.pool.query(
      'INSERT INTO relay_tokens (id, name, token_hash, prefix, created_at) VALUES ($1, $2, $3, $4, $5)',
      [r.id, r.name, r.hash, r.prefix, new Date(r.createdAt)],
    )
  }

  async revokeToken(id: string, at: number): Promise<void> {
    await this.pool.query('UPDATE relay_tokens SET revoked_at = $2 WHERE id = $1 AND revoked_at IS NULL', [id, new Date(at)])
  }

  async touchToken(id: string, at: number): Promise<void> {
    await this.pool.query('UPDATE relay_tokens SET last_used_at = $2 WHERE id = $1', [id, new Date(at)])
  }

  async getSetting(key: string): Promise<unknown | null> {
    const { rows } = await this.pool.query<{ value: unknown }>('SELECT value FROM relay_settings WHERE key = $1', [key])
    return rows[0]?.value ?? null
  }

  async setSetting(key: string, value: unknown): Promise<void> {
    await this.pool.query(
      'INSERT INTO relay_settings (key, value) VALUES ($1, $2) ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value',
      [key, JSON.stringify(value)],
    )
  }

  async close(): Promise<void> {
    await this.pool.end()
  }
}

function toRecord(row: TokenRow): TokenRecord {
  return {
    id: row.id,
    name: row.name,
    hash: row.token_hash,
    prefix: row.prefix,
    createdAt: row.created_at.getTime(),
    lastUsedAt: row.last_used_at?.getTime() ?? null,
    revokedAt: row.revoked_at?.getTime() ?? null,
  }
}
