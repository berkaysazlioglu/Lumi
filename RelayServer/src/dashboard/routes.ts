import type { IncomingMessage, ServerResponse } from 'node:http'
import type { ServerAccess } from '../access.js'
import { parseAllowlist, parseMode } from '../allowlist.js'
import { isHttps } from '../request.js'
import { isAllowedEmail, type OidcLogin } from './oidc.js'
import {
  FLOW_COOKIE, FLOW_TTL_MS, parseCookies, safeEqual, SESSION_COOKIE, SESSION_TTL_MS,
  signSession, signValue, verifySession, verifyValue,
} from './session.js'
import { dashboardPage, disabledPage, loginPage, type DashboardModel, type RelayStatus } from './views.js'

/** Dashboard girişi (OIDC). Yoksa dashboard kapalıdır — kullanıcı adı/şifre yoktur. */
export interface DashboardLogin {
  oidc: OidcLogin
  /** Giriş butonunda görünen ad ("Sign in with Google"). */
  providerName: string
  /** Girebilecek e-postalar / alan adları; ikisi de boşsa kimse giremez. */
  allowed: { emails: string[]; domains: string[] }
  /** Geri dönüş adresinin kökü; yoksa istekten (`X-Forwarded-Proto` + `Host`) türetilir. */
  publicUrl?: string
}

export interface DashboardOptions {
  access: ServerAccess
  status: () => RelayStatus
  login?: DashboardLogin
  sessionSecret: string
  now?: () => number
}

const MAX_BODY_BYTES = 16 * 1024
const CALLBACK_PATH = '/auth/callback'

type Notice = DashboardModel['notice']

/** `/`, `/login`, `/logout`, `/tokens…`, `/allowlist`. Eşleşmeyen yolda `false`. */
export function createDashboard(opts: DashboardOptions) {
  const now = opts.now ?? Date.now
  const login = opts.login

  async function handle(req: IncomingMessage, res: ServerResponse): Promise<boolean> {
    const url = new URL(req.url ?? '/', 'http://relay')
    const path = url.pathname
    if (!isDashboardPath(path)) return false
    if (!login) { html(res, 503, disabledPage()); return true }
    if (req.method === 'POST' && !sameOrigin(req)) { text(res, 403, 'Cross-origin request rejected'); return true }

    if (req.method === 'GET' && path === '/login') { html(res, 200, loginPage(login.providerName)); return true }
    if (req.method === 'GET' && path === '/auth/start') { await startLogin(req, res, login); return true }
    if (req.method === 'GET' && path === CALLBACK_PATH) { await finishLogin(req, res, url, login); return true }
    const user = verifySession(parseCookies(req.headers.cookie)[SESSION_COOKIE], opts.sessionSecret, now())
    if (!user) {
      if (req.method === 'GET' && path === '/') redirect(res, '/login')
      else text(res, 401, 'Sign in required')
      return true
    }
    if (path === '/logout' && req.method === 'POST') {
      res.setHeader('Set-Cookie', cookie(req, SESSION_COOKIE, '', 0))
      redirect(res, '/login')
      return true
    }
    if (req.method === 'GET' && path === '/') { render(req, res, user); return true }
    if (req.method !== 'POST') { text(res, 405, 'Method not allowed'); return true }
    await mutate(req, res, user, path)
    return true
  }

  /** Sağlayıcının giriş sayfasına yollar; `state`/`nonce`/PKCE imzalı cookie'de bekler. */
  async function startLogin(req: IncomingMessage, res: ServerResponse, login: DashboardLogin): Promise<void> {
    try {
      const request = await login.oidc.begin(callbackUrl(req, login))
      const flow = signValue({ s: request.state, n: request.nonce, v: request.verifier }, FLOW_TTL_MS, opts.sessionSecret, now())
      res.setHeader('Set-Cookie', cookie(req, FLOW_COOKIE, flow, FLOW_TTL_MS / 1000))
      redirect(res, request.url)
    } catch (err) {
      html(res, 502, loginPage(login.providerName, (err as Error).message))
    }
  }

  async function finishLogin(req: IncomingMessage, res: ServerResponse, url: URL, login: DashboardLogin): Promise<void> {
    const fail = (status: number, message: string) => {
      res.setHeader('Set-Cookie', cookie(req, FLOW_COOKIE, '', 0))
      html(res, status, loginPage(login.providerName, message))
    }
    const flow = verifyValue(parseCookies(req.headers.cookie)[FLOW_COOKIE], opts.sessionSecret, now())
    const state = url.searchParams.get('state') ?? ''
    const code = url.searchParams.get('code')
    if (url.searchParams.get('error')) { fail(401, 'Sign-in was cancelled.'); return }
    if (!flow || typeof flow.s !== 'string' || typeof flow.n !== 'string' || typeof flow.v !== 'string'
        || !code || !safeEqual(state, flow.s)) {
      fail(400, 'Sign-in expired. Try again.')
      return
    }
    let email: string
    try {
      email = await login.oidc.finish(code, callbackUrl(req, login), { nonce: flow.n, verifier: flow.v })
    } catch (err) {
      fail(401, (err as Error).message)
      return
    }
    if (!isAllowedEmail(email, login.allowed)) { fail(403, `${email} is not allowed on this server.`); return }
    res.setHeader('Set-Cookie', [
      cookie(req, FLOW_COOKIE, '', 0),
      cookie(req, SESSION_COOKIE, signSession(email, opts.sessionSecret, now()), SESSION_TTL_MS / 1000),
    ])
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

  return { handle }
}

function isDashboardPath(path: string): boolean {
  return path === '/' || path === '/login' || path === '/logout' || path === '/allowlist'
    || path === '/tokens' || path.startsWith('/tokens/') || path === '/auth/start' || path === CALLBACK_PATH
}

function callbackUrl(req: IncomingMessage, login: DashboardLogin): string {
  const base = login.publicUrl?.replace(/\/+$/, '') ?? `${isHttps(req) ? 'https' : 'http'}://${req.headers.host ?? 'localhost'}`
  return base + CALLBACK_PATH
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

/**
 * `SameSite=Lax`: sağlayıcıdan dönüş siteler arası bir yönlendirme zinciridir ve
 * `Strict` cookie o zincirde gönderilmez. POST'lar `sameOrigin` ile ayrıca korunur.
 */
function cookie(req: IncomingMessage, name: string, value: string, maxAgeSeconds: number): string {
  const secure = isHttps(req) ? '; Secure' : ''
  return `${name}=${encodeURIComponent(value)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAgeSeconds}${secure}`
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
