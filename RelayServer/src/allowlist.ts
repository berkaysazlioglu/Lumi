/**
 * IP allowlist — yalnız hub/controller (Mac'ten Mac'e) bağlantılarına uygulanır;
 * telefon odası (`mac`/`phone`) her ağdan bağlanır (docs/design/09).
 *
 * Modlar:
 *   off     — kontrol yok.
 *   report  — engel yok; listede olmayan bağlantı dashboard'da "would block" diye görünür.
 *   enforce — listede olmayan hub/controller bağlantısı 4006 ile kapanır.
 */

export type NetworkMode = 'off' | 'report' | 'enforce'
export type NetworkVerdict = 'allowed' | 'would_block' | 'blocked'

export interface AllowlistEntry {
  /** Tam IP ya da IPv4 CIDR. */
  cidr: string
  label: string
}

export interface AllowlistSettings {
  mode: NetworkMode
  entries: AllowlistEntry[]
}

/** İlk açılıştaki liste — unco-forge'un varsayılanlarıyla aynı (ofis + GlobalProtect çıkışları). */
export const DEFAULT_ALLOWLIST = [
  '89.145.191.82=Office + GlobalProtect (Istanbul egress)',
  '95.0.243.64/28=Besiktas branch',
  '74.114.8.0/21=GlobalProtect Helsinki (Take-Two)',
  '213.139.29.112/28=GlobalProtect Small Giant (Take-Two)',
  '176.236.63.224/28=GlobalProtect Istanbul (Take-Two)',
].join(',')

export function ipv4ToInt(ip: string): number | null {
  const parts = ip.split('.')
  if (parts.length !== 4) return null
  let n = 0
  for (const p of parts) {
    if (!/^\d{1,3}$/.test(p)) return null
    const v = Number(p)
    if (v > 255) return null
    n = n * 256 + v
  }
  return n
}

/** Heroku IPv4'ü IPv6'ya gömülü verebilir ("::ffff:1.2.3.4"). */
export function normalizeIp(ip: string): string {
  const t = ip.trim().toLowerCase()
  return t.startsWith('::ffff:') && t.includes('.') ? t.slice(7) : t
}

function isValidCidr(cidr: string): boolean {
  const [addr, bits] = cidr.split('/')
  if (!addr) return false
  if (bits === undefined) return ipv4ToInt(addr) !== null || addr.includes(':')
  const b = Number(bits)
  return ipv4ToInt(addr) !== null && Number.isInteger(b) && b >= 0 && b <= 32
}

/**
 * `"1.2.3.4=Etiket,10.0.0.0/8"` ya da satır satır `"1.2.3.4 = Etiket"` → kayıtlar.
 * Bozuk kayıt listeyi genişletmek yerine düşer; `invalid` dashboard'da gösterilir.
 */
export function parseAllowlist(raw: string): { entries: AllowlistEntry[]; invalid: string[] } {
  const entries: AllowlistEntry[] = []
  const invalid: string[] = []
  for (const item of raw.split(/[,\n]/).map((s) => s.trim()).filter(Boolean)) {
    const eq = item.indexOf('=')
    const cidr = (eq === -1 ? item : item.slice(0, eq)).trim()
    const label = (eq === -1 ? '' : item.slice(eq + 1)).trim() || cidr
    if (isValidCidr(cidr)) entries.push({ cidr, label: label.slice(0, 120) })
    else invalid.push(item)
  }
  return { entries, invalid }
}

export function parseMode(raw: string | undefined): NetworkMode {
  const m = (raw ?? '').trim().toLowerCase()
  return m === 'off' || m === 'report' || m === 'enforce' ? m : 'enforce'
}

export interface NetworkPolicy {
  readonly settings: AllowlistSettings
  /** Eşleşen kaydın etiketi; listede değilse `null`. */
  match(ip: string): string | null
  verdict(ip: string): NetworkVerdict
}

export function buildNetworkPolicy(settings: AllowlistSettings): NetworkPolicy {
  // Boş liste `enforce`'ta herkesi kilitlerdi — boş liste kapalı sayılır.
  const mode: NetworkMode = settings.entries.length === 0 ? 'off' : settings.mode
  const exact = new Map<string, string>()
  const ranges: { base: number; mask: number; label: string }[] = []
  for (const e of settings.entries) {
    const [addr, bits] = e.cidr.split('/')
    if (bits === undefined) { exact.set(normalizeIp(e.cidr), e.label); continue }
    const b = Number(bits)
    const mask = b === 0 ? 0 : (~0 << (32 - b)) >>> 0
    ranges.push({ base: (ipv4ToInt(addr!)! & mask) >>> 0, mask, label: e.label })
  }

  const match = (rawIp: string): string | null => {
    const ip = normalizeIp(rawIp)
    const hit = exact.get(ip)
    if (hit !== undefined) return hit
    const n = ipv4ToInt(ip)
    if (n === null) return null
    return ranges.find((r) => ((n & r.mask) >>> 0) === r.base)?.label ?? null
  }

  return {
    settings: { mode, entries: settings.entries },
    match,
    verdict(ip) {
      if (mode === 'off' || match(ip) !== null) return 'allowed'
      return mode === 'enforce' ? 'blocked' : 'would_block'
    },
  }
}
