import type { IncomingMessage } from 'node:http'

/**
 * İstemci IP'si. Heroku router'ı kendi gördüğü adresi `X-Forwarded-For`'un
 * SONUNA ekler; baştaki girdileri istemci istediği gibi yazabilir, o yüzden
 * en sağdaki girdi esas alınır.
 */
export function clientIp(req: IncomingMessage): string {
  const forwarded = req.headers['x-forwarded-for']
  const header = Array.isArray(forwarded) ? forwarded.join(',') : forwarded
  const last = header?.split(',').map((s) => s.trim()).filter(Boolean).pop()
  return last || req.socket.remoteAddress || 'unknown'
}

/** `Authorization: Bearer <token>` değeri. */
export function bearerToken(req: IncomingMessage): string | null {
  const header = req.headers.authorization
  if (!header) return null
  const match = /^Bearer\s+(\S+)$/i.exec(header)
  return match?.[1] ?? null
}

/** İstek HTTPS'ten mi geldi (Heroku TLS'i router'da bitirir). */
export function isHttps(req: IncomingMessage): boolean {
  return req.headers['x-forwarded-proto'] === 'https'
}

/** IP başına sabit pencereli başarısızlık sayacı; süresi dolan girdiler `sweep` ile silinir. */
export class FailureLimiter {
  private entries = new Map<string, { count: number; resetAt: number }>()

  constructor(private max: number, private windowMs: number, private now: () => number = Date.now) {}

  blocked(key: string): boolean {
    const entry = this.entries.get(key)
    return !!entry && entry.resetAt > this.now() && entry.count >= this.max
  }

  record(key: string): void {
    const now = this.now()
    const entry = this.entries.get(key)
    if (!entry || entry.resetAt < now) this.entries.set(key, { count: 1, resetAt: now + this.windowMs })
    else entry.count += 1
  }

  reset(key: string): void {
    this.entries.delete(key)
  }

  sweep(): void {
    const now = this.now()
    for (const [key, entry] of this.entries) if (entry.resetAt < now) this.entries.delete(key)
  }
}
