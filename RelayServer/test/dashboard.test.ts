import { afterEach, expect, test } from 'vitest'
import { NoopPushSender } from '../src/push.js'
import { testServer, type TestServer } from './support.js'

let server: TestServer | null = null
afterEach(() => { server?.close(); server = null })

const ADMIN = { username: 'admin', password: 'correct horse', sessionSecret: 'test-secret' }

function url(path: string): string {
  return `http://127.0.0.1:${server!.port()}${path}`
}

function post(path: string, form: Record<string, string>, headers: Record<string, string> = {}): Promise<Response> {
  return fetch(url(path), {
    method: 'POST',
    redirect: 'manual',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', ...headers },
    body: new URLSearchParams(form).toString(),
  })
}

async function login(): Promise<string> {
  const res = await post('/login', { username: ADMIN.username, password: ADMIN.password })
  expect(res.status).toBe(303)
  return res.headers.get('set-cookie')!.split(';')[0]!
}

test('kullanıcı adı/şifre tanımlı değilse dashboard kapalıdır', async () => {
  server = await testServer({ push: new NoopPushSender() })
  expect((await fetch(url('/'))).status).toBe(503)
})

test('oturumsuz istek login\'e yönlenir, POST 401 alır', async () => {
  server = await testServer({ push: new NoopPushSender(), admin: ADMIN })
  const res = await fetch(url('/'), { redirect: 'manual' })
  expect(res.status).toBe(303)
  expect(res.headers.get('location')).toBe('/login')
  expect((await post('/tokens', { name: 'x' })).status).toBe(401)
})

test('yanlış şifre reddedilir, 5 hatadan sonra 429', async () => {
  server = await testServer({ push: new NoopPushSender(), admin: ADMIN })
  for (let i = 0; i < 5; i++) expect((await post('/login', { username: 'admin', password: 'yanlış' })).status).toBe(401)
  expect((await post('/login', { username: 'admin', password: ADMIN.password })).status).toBe(429)
})

test('girişten sonra token üretilir ve yalnız bir kez gösterilir, iptal edilebilir', async () => {
  server = await testServer({ push: new NoopPushSender(), admin: ADMIN })
  const cookie = await login()

  const created = await post('/tokens', { name: 'Ali – iPhone' }, { Cookie: cookie })
  const page = await created.text()
  const token = /<code id="new-token">([^<]+)<\/code>/.exec(page)?.[1]
  expect(token).toBeDefined()
  expect(server.access.authenticate(token!)?.name).toBe('Ali – iPhone')

  const home = await (await fetch(url('/'), { headers: { Cookie: cookie } })).text()
  expect(home).toContain('Ali – iPhone')
  expect(home).not.toContain(token!)

  const record = server.access.tokens().find((t) => t.name === 'Ali – iPhone')!
  await post(`/tokens/${record.id}/revoke`, {}, { Cookie: cookie })
  expect(server.access.authenticate(token!)).toBeNull()
})

test('allowlist kaydedilir; bozuk satırlar bildirilir', async () => {
  server = await testServer({ push: new NoopPushSender(), admin: ADMIN })
  const cookie = await login()
  const page = await (await post('/allowlist', { mode: 'report', entries: '1.2.3.4 = Ev\nbozuk' }, { Cookie: cookie })).text()
  expect(page).toContain('bozuk')
  expect(server.access.allowlist()).toEqual({ mode: 'report', entries: [{ cidr: '1.2.3.4', label: 'Ev' }] })
})

test('başka kökenden gelen POST reddedilir', async () => {
  server = await testServer({ push: new NoopPushSender(), admin: ADMIN })
  const cookie = await login()
  const res = await post('/tokens', { name: 'x' }, { Cookie: cookie, Origin: 'https://evil.example' })
  expect(res.status).toBe(403)
})

test('tarayıcının kendi formu (Sec-Fetch-Site: same-origin, Origin: null) kabul edilir; cross-site reddedilir', async () => {
  server = await testServer({ push: new NoopPushSender(), admin: ADMIN })
  const form = { username: ADMIN.username, password: ADMIN.password }
  expect((await post('/login', form, { 'Sec-Fetch-Site': 'same-origin', Origin: 'null' })).status).toBe(303)
  expect((await post('/login', form, { 'Sec-Fetch-Site': 'cross-site', Origin: 'https://evil.example' })).status).toBe(403)
  expect((await post('/login', form, { Origin: 'null' })).status).toBe(403)
})

test('kullanıcı adı ve token adı HTML olarak kaçışlanır', async () => {
  server = await testServer({ push: new NoopPushSender(), admin: ADMIN })
  const cookie = await login()
  const page = await (await post('/tokens', { name: '<script>x</script>' }, { Cookie: cookie })).text()
  expect(page).not.toContain('<script>x</script>')
  expect(page).toContain('&lt;script&gt;')
})
