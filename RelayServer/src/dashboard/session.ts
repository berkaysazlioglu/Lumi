import { createHash, createHmac, timingSafeEqual } from 'node:crypto'

/** Dashboard oturumu: `base64url(JSON{u,exp}).HMAC-SHA256` — sunucu tarafında durum yok. */

export const SESSION_COOKIE = 'lumi_relay_session'
export const SESSION_TTL_MS = 12 * 60 * 60 * 1000

export function signSession(username: string, secret: string, now: number): string {
  const body = Buffer.from(JSON.stringify({ u: username, exp: now + SESSION_TTL_MS })).toString('base64url')
  return `${body}.${mac(body, secret)}`
}

export function verifySession(value: string | undefined, secret: string, now: number): string | null {
  if (!value) return null
  const [body, signature] = value.split('.')
  if (!body || !signature || !safeEqual(signature, mac(body, secret))) return null
  try {
    const data = JSON.parse(Buffer.from(body, 'base64url').toString()) as { u?: unknown; exp?: unknown }
    if (typeof data.u !== 'string' || typeof data.exp !== 'number' || data.exp < now) return null
    return data.u
  } catch {
    return null
  }
}

/** Uzunluk sızdırmadan sabit zamanlı karşılaştırma (iki tarafın da özeti karşılaştırılır). */
export function safeEqual(a: string, b: string): boolean {
  const ha = createHash('sha256').update(a).digest()
  const hb = createHash('sha256').update(b).digest()
  return timingSafeEqual(ha, hb)
}

function mac(body: string, secret: string): string {
  return createHmac('sha256', secret).update(body).digest('base64url')
}

export function parseCookies(header: string | undefined): Record<string, string> {
  const out: Record<string, string> = {}
  for (const part of (header ?? '').split(';')) {
    const eq = part.indexOf('=')
    if (eq === -1) continue
    out[part.slice(0, eq).trim()] = decodeURIComponent(part.slice(eq + 1).trim())
  }
  return out
}
