import type { IncomingMessage, ServerResponse } from 'node:http'
import type { ServerAccess } from '../access.js'
import { parseAllowlist, parseMode } from '../allowlist.js'
import { clientIp, FailureLimiter, isHttps } from '../request.js'
import { parseCookies, safeEqual, SESSION_COOKIE, SESSION_TTL_MS, signSession, verifySession } from './session.js'
import { dashboardPage, disabledPage, loginPage, type DashboardModel, type RelayStatus } from './views.js'

export interface DashboardOptions {
  access: ServerAccess
  status: () => RelayStatus
  /** İkisi de yoksa dashboard kapalıdır. */
  username?: string
  password?: string
  sessionSecret: string
  now?: () => number
}

const MAX_BODY_BYTES = 16 * 1024
const MAX_LOGIN_FAILURES = 5
const LOGIN_WINDOW_MS = 15 * 60 * 1000

type Notice = DashboardModel['notice']

/** `/`, `/login`, `/logout`, `/tokens…`, `/allowlist`. Eşleşmeyen yolda `false`. */
export function createDashboard(opts: DashboardOptions) {
  const now = opts.now ?? Date.now
  const loginFailures = new FailureLimiter(MAX_LOGIN_FAILURES, LOGIN_WINDOW_MS, now)
  const enabled = !!(opts.username && opts.password)

  async function handle(req: IncomingMessage, res: ServerResponse): Promise<boolean> {
    const url = new URL(req.url ?? '/', 'http://relay')
    const path = url.pathname
    if (!isDashboardPath(path)) return false
    if (!enabled) { html(res, 503, disabledPage()); return true }
    if (req.method === 'POST' && !sameOrigin(req)) { text(res, 403, 'Cross-origin request rejected'); return true }

    if (path === '/login') {
      if (req.method === 'POST') await login(req, res)
      else html(res, 200, loginPage())
      return true
    }
    const user = verifySession(parseCookies(req.headers.cookie)[SESSION_COOKIE], opts.sessionSecret, now())
    if (!user) {
      if (req.method === 'GET' && path === '/') redirect(res, '/login')
      else text(res, 401, 'Sign in required')
      return true
    }
    if (path === '/logout' && req.method === 'POST') {
      res.setHeader('Set-Cookie', cookie(req, '', 0))
      redirect(res, '/login')
      return true
    }
    if (req.method === 'GET' && path === '/') { render(req, res, user); return true }
    if (req.method !== 'POST') { text(res, 405, 'Method not allowed'); return true }
    await mutate(req, res, user, path)
    return true
  }

  async function login(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const ip = clientIp(req)
    if (loginFailures.blocked(ip)) { html(res, 429, loginPage('Too many attempts. Try again in 15 minutes.')); return }
    const form = await readForm(req)
    const ok = safeEqual(form.get('username') ?? '', opts.username!) && safeEqual(form.get('password') ?? '', opts.password!)
    if (!ok) {
      loginFailures.record(ip)
      html(res, 401, loginPage('Wrong username or password.'))
      return
    }
    loginFailures.reset(ip)
    res.setHeader('Set-Cookie', cookie(req, signSession(opts.username!, opts.sessionSecret, now()), SESSION_TTL_MS / 1000))
    redirect(res, '/')
  }

  async function mutate(req: IncomingMessage, res: ServerResponse, user: string, path: string): Promise<void> {
    const form = await readForm(req)
    try {
      if (path === '/tokens') {
        const { token, record } = await opts.access.createToken(form.get('name') ?? '')
        render(req, res, user, { createdToken: { name: record.name, token } })
        return
      }
      const revoke = /^\/tokens\/([^/]+)\/revoke$/.exec(path)
      if (revoke) {
        const ok = await opts.access.revokeToken(decodeURIComponent(revoke[1]!))
        render(req, res, user, { notice: ok ? { kind: 'ok', text: 'Token revoked.' } : { kind: 'error', text: 'Token not found.' } })
        return
      }
      if (path === '/allowlist') {
        const { entries, invalid } = parseAllowlist(form.get('entries') ?? '')
        await opts.access.setAllowlist(parseMode(form.get('mode') ?? undefined), entries)
        const notice: Notice = invalid.length > 0
          ? { kind: 'error', text: `Saved, but skipped invalid entries: ${invalid.join(', ')}` }
          : { kind: 'ok', text: entries.length === 0 ? 'Allowlist is empty — the check is off.' : 'Allowlist saved.' }
        render(req, res, user, { notice })
        return
      }
      text(res, 404, 'Not found')
    } catch (err) {
      render(req, res, user, { notice: { kind: 'error', text: (err as Error).message } })
    }
  }

  function render(req: IncomingMessage, res: ServerResponse, user: string, extra: Partial<DashboardModel> = {}): void {
    html(res, 200, dashboardPage({
      username: user,
      status: opts.status(),
      tokens: opts.access.tokens(),
      allowlist: opts.access.allowlist(),
      events: opts.access.networkEvents(),
      serverUrl: `${isHttps(req) ? 'wss' : 'ws'}://${req.headers.host ?? 'localhost'}`,
      ...extra,
    }))
  }

  return { handle, sweep: () => loginFailures.sweep() }
}

function isDashboardPath(path: string): boolean {
  return path === '/' || path === '/login' || path === '/logout' || path === '/allowlist' || path === '/tokens' || path.startsWith('/tokens/')
}

/**
 * POST sayfanın kendi kökeninden mi geldi (SameSite=Strict'e ek). Modern tarayıcılar
 * `Sec-Fetch-Site` gönderir — esas o. Yoksa `Origin` (varsa) kendi kökenimiz olmalı.
 * `Origin: null` tek başına reddedilir; Referrer-Policy'ye göre tarayıcı kendi
 * formunda da `null` gönderebildiği için önce `Sec-Fetch-Site`'a bakılır.
 */
function sameOrigin(req: IncomingMessage): boolean {
  const site = req.headers['sec-fetch-site']
  if (typeof site === 'string') return site === 'same-origin' || site === 'none'
  const origin = req.headers.origin
  if (!origin) return true
  return origin === `${isHttps(req) ? 'https' : 'http'}://${req.headers.host}`
}

function cookie(req: IncomingMessage, value: string, maxAgeSeconds: number): string {
  const secure = isHttps(req) ? '; Secure' : ''
  return `${SESSION_COOKIE}=${encodeURIComponent(value)}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${maxAgeSeconds}${secure}`
}

async function readForm(req: IncomingMessage): Promise<URLSearchParams> {
  const chunks: Buffer[] = []
  let size = 0
  for await (const chunk of req) {
    size += (chunk as Buffer).length
    if (size > MAX_BODY_BYTES) throw new Error('Request body too large')
    chunks.push(chunk as Buffer)
  }
  return new URLSearchParams(Buffer.concat(chunks).toString())
}

const SECURITY_HEADERS = {
  'X-Frame-Options': 'DENY',
  'X-Content-Type-Options': 'nosniff',
  // `no-referrer` tarayıcının kendi formunda `Origin: null` göndermesine yol açıyordu.
  'Referrer-Policy': 'same-origin',
  'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'",
  'Cache-Control': 'no-store',
}

function html(res: ServerResponse, status: number, body: string): void {
  res.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8', ...SECURITY_HEADERS })
  res.end(body)
}

export function text(res: ServerResponse, status: number, body: string): void {
  res.writeHead(status, { 'Content-Type': 'text/plain; charset=utf-8', ...SECURITY_HEADERS })
  res.end(body)
}

function redirect(res: ServerResponse, location: string): void {
  res.writeHead(303, { Location: location, ...SECURITY_HEADERS })
  res.end()
}
