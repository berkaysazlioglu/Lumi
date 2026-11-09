import { createHash } from 'node:crypto'
import { createServer, type Server } from 'node:http'
import { afterEach, expect, test } from 'vitest'
import { exportJWK, generateKeyPair, SignJWT } from 'jose'
import { OidcLogin } from '../src/dashboard/oidc.js'
import { NoopPushSender } from '../src/push.js'
import { MemoryStore } from '../src/store.js'
import { testServer, type TestServer } from './support.js'

// Dashboard girişi: OIDC kod akışı + PKCE, sahte sağlayıcıya karşı uçtan uca (docs/design/09).

let server: TestServer | null = null
let issuer: FakeIssuer | null = null
afterEach(() => {
  server?.close(); server = null
  issuer?.close(); issuer = null
})

/** unco-forge gibi davranan sağlayıcı: yalnız RFC 8414 keşfi, dynamic registration, ES256 id_token, sub = e-posta. */
interface FakeIssuer {
  url: string
  registrations: number
  /** Kullanıcının sağlayıcıda girişini taklit eder: authorize adresinden kod üretir. */
  authorize(authorizeUrl: string, email: string, opts?: { nonce?: string }): string
  close(): void
}

async function startIssuer(): Promise<FakeIssuer> {
  const { privateKey, publicKey } = await generateKeyPair('ES256')
  const jwk = { ...(await exportJWK(publicKey)), kid: 'k1', alg: 'ES256', use: 'sig' }
  const codes = new Map<string, { email: string; nonce: string; challenge: string; clientId: string; redirectUri: string }>()
  let url = ''
  const state = { registrations: 0 }
  const http: Server = createServer(async (req, res) => {
    const path = new URL(req.url ?? '/', 'http://x').pathname
    const json = (status: number, body: unknown) => { res.writeHead(status, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(body)) }
    let raw = ''
    for await (const chunk of req) raw += chunk
    if (path === '/.well-known/oauth-authorization-server') {
      json(200, { issuer: url, authorization_endpoint: `${url}/authorize`, token_endpoint: `${url}/token`, jwks_uri: `${url}/jwks`, registration_endpoint: `${url}/register` })
    } else if (path === '/jwks') {
      json(200, { keys: [jwk] })
    } else if (path === '/register') {
      state.registrations += 1
      const body = JSON.parse(raw) as { redirect_uris: string[]; token_endpoint_auth_method: string }
      expect(body.token_endpoint_auth_method).toBe('none')
      json(201, { client_id: `client-${state.registrations}`, redirect_uris: body.redirect_uris })
    } else if (path === '/token') {
      const form = new URLSearchParams(raw)
      const entry = codes.get(form.get('code') ?? '')
      const challenge = createHash('sha256').update(form.get('code_verifier') ?? '').digest('base64url')
      if (!entry || entry.challenge !== challenge || entry.clientId !== form.get('client_id') || entry.redirectUri !== form.get('redirect_uri')) {
        json(400, { error: 'invalid_grant' })
        return
      }
      codes.delete(form.get('code')!)
      const idToken = await new SignJWT({ nonce: entry.nonce })
        .setProtectedHeader({ alg: 'ES256', kid: 'k1' })
        .setIssuer(url).setAudience(entry.clientId).setSubject(entry.email)
        .setIssuedAt().setExpirationTime('5m').sign(privateKey)
      json(200, { access_token: 'ignored', token_type: 'Bearer', id_token: idToken })
    } else {
      json(404, {})
    }
  })
  await new Promise<void>((resolve) => http.listen(0, '127.0.0.1', () => resolve()))
  const addr = http.address()
  url = `http://127.0.0.1:${typeof addr === 'object' && addr ? addr.port : 0}`
  return {
    url,
    get registrations() { return state.registrations },
    authorize(authorizeUrl, email, opts = {}) {
      const params = new URL(authorizeUrl).searchParams
      expect(params.get('code_challenge_method')).toBe('S256')
      const code = `code-${codes.size + 1}-${Math.random()}`
      codes.set(code, {
        email, nonce: opts.nonce ?? params.get('nonce')!, challenge: params.get('code_challenge')!,
        clientId: params.get('client_id')!, redirectUri: params.get('redirect_uri')!,
      })
      return `${params.get('redirect_uri')}?code=${encodeURIComponent(code)}&state=${encodeURIComponent(params.get('state')!)}`
    },
    close: () => http.close(),
  }
}

async function start(allowed = { emails: [] as string[], domains: ['uncosoft.com'] }): Promise<void> {
  issuer = await startIssuer()
  const login = { oidc: new OidcLogin({ issuer: issuer.url, store: new MemoryStore() }), providerName: 'Google', allowed }
  server = await testServer({ push: new NoopPushSender(), dashboard: { login, sessionSecret: 'test-secret' } })
}

function url(path: string): string {
  return path.startsWith('http') ? path : `http://127.0.0.1:${server!.port()}${path}`
}

function setCookies(res: Response): string[] {
  return res.headers.getSetCookie().map((c) => c.split(';')[0]!).filter((c) => !c.endsWith('='))
}

/** Tarayıcının yapacağını yapar: start → sağlayıcı → callback. Callback yanıtını döner. */
async function signIn(email: string, opts: { nonce?: string } = {}): Promise<{ res: Response; cookie: string }> {
  const started = await fetch(url('/auth/start'), { redirect: 'manual' })
  expect(started.status).toBe(303)
  const flowCookie = setCookies(started).join('; ')
  const callback = issuer!.authorize(started.headers.get('location')!, email, opts)
  const res = await fetch(callback, { redirect: 'manual', headers: { Cookie: flowCookie } })
  return { res, cookie: setCookies(res).filter((c) => c.startsWith('lumi_relay_session=')).join('; ') }
}

function post(path: string, form: Record<string, string>, headers: Record<string, string> = {}): Promise<Response> {
  return fetch(url(path), {
    method: 'POST',
    redirect: 'manual',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', ...headers },
    body: new URLSearchParams(form).toString(),
  })
}

test('giriş sağlayıcısı tanımlı değilse dashboard kapalıdır; kullanıcı adı/şifre girişi yoktur', async () => {
  server = await testServer({ push: new NoopPushSender() })
  expect((await fetch(url('/'))).status).toBe(503)
  expect((await post('/login', { username: 'admin', password: 'x' })).status).toBe(503)
})

test('oturumsuz istek login\'e yönlenir; login sayfası sağlayıcı butonunu gösterir', async () => {
  await start()
  const res = await fetch(url('/'), { redirect: 'manual' })
  expect(res.status).toBe(303)
  expect(res.headers.get('location')).toBe('/login')
  // Giriş bir bağlantıdır: CSP `form-action 'self'` formun sağlayıcıya yönlenmesini engeller.
  const loginPage = await (await fetch(url('/login'))).text()
  expect(loginPage).toMatch(/<a class="button" href="\/auth\/start">Sign in with Google<\/a>/)
  expect(loginPage).not.toContain('<form')
  expect((await post('/tokens', { name: 'x' })).status).toBe(401)
})

test('izinli alan adındaki e-posta girer; istemci bir kez kaydedilir', async () => {
  await start()
  const { res, cookie } = await signIn('Berkay@uncosoft.com')
  expect(res.status).toBe(303)
  expect(res.headers.get('location')).toBe('/')
  const home = await (await fetch(url('/'), { headers: { Cookie: cookie } })).text()
  expect(home).toContain('berkay@uncosoft.com')

  await signIn('ali@uncosoft.com')
  expect(issuer!.registrations).toBe(1)
})

test('izinli olmayan alan adı reddedilir, oturum açılmaz', async () => {
  await start()
  const { res, cookie } = await signIn('someone@gmail.com')
  expect(res.status).toBe(403)
  expect(await res.text()).toContain('someone@gmail.com is not allowed')
  expect(cookie).toBe('')
})

test('tam e-posta listesi alan adı olmadan da girer', async () => {
  await start({ emails: ['guest@gmail.com'], domains: [] })
  expect((await signIn('guest@gmail.com')).res.status).toBe(303)
  expect((await signIn('other@gmail.com')).res.status).toBe(403)
})

test('state ya da nonce tutmazsa, akış cookie\'si yoksa giriş reddedilir', async () => {
  await start()
  const started = await fetch(url('/auth/start'), { redirect: 'manual' })
  const callback = issuer!.authorize(started.headers.get('location')!, 'berkay@uncosoft.com')
  // Akış cookie'si yok (başka tarayıcıdan gelen geri dönüş).
  expect((await fetch(callback, { redirect: 'manual' })).status).toBe(400)
  // Nonce değiştirilmiş id_token.
  expect((await signIn('berkay@uncosoft.com', { nonce: 'baska' })).res.status).toBe(401)
})

test('girişten sonra token üretilir, yalnız bir kez gösterilir ve iptal edilebilir', async () => {
  await start()
  const { cookie } = await signIn('berkay@uncosoft.com')

  const page = await (await post('/tokens', { name: 'Ali – iPhone' }, { Cookie: cookie })).text()
  const token = /<code id="new-token">([^<]+)<\/code>/.exec(page)?.[1]
  expect(token).toBeDefined()
  expect(server!.access.authenticate(token!)?.name).toBe('Ali – iPhone')

  const home = await (await fetch(url('/'), { headers: { Cookie: cookie } })).text()
  expect(home).toContain('Ali – iPhone')
  expect(home).not.toContain(token!)

  const record = server!.access.tokens().find((t) => t.name === 'Ali – iPhone')!
  await post(`/tokens/${record.id}/revoke`, {}, { Cookie: cookie })
  expect(server!.access.authenticate(token!)).toBeNull()
})

test('allowlist kaydedilir; bozuk satırlar bildirilir', async () => {
  await start()
  const { cookie } = await signIn('berkay@uncosoft.com')
  const page = await (await post('/allowlist', { mode: 'report', entries: '1.2.3.4 = Ev\nbozuk' }, { Cookie: cookie })).text()
  expect(page).toContain('bozuk')
  expect(server!.access.allowlist()).toEqual({ mode: 'report', entries: [{ cidr: '1.2.3.4', label: 'Ev' }] })
})

test('tarayıcının kendi formu kabul edilir; başka kökenden gelen POST reddedilir', async () => {
  await start()
  const { cookie } = await signIn('berkay@uncosoft.com')
  const same = await post('/tokens', { name: 'x' }, { Cookie: cookie, 'Sec-Fetch-Site': 'same-origin', Origin: 'null' })
  expect(same.status).toBe(200)
  expect((await post('/tokens', { name: 'x' }, { Cookie: cookie, 'Sec-Fetch-Site': 'cross-site' })).status).toBe(403)
  expect((await post('/tokens', { name: 'x' }, { Cookie: cookie, Origin: 'https://evil.example' })).status).toBe(403)
})

test('token adı HTML olarak kaçışlanır', async () => {
  await start()
  const { cookie } = await signIn('berkay@uncosoft.com')
  const page = await (await post('/tokens', { name: '<script>x</script>' }, { Cookie: cookie })).text()
  expect(page).not.toContain('<script>x</script>')
  expect(page).toContain('&lt;script&gt;')
})
