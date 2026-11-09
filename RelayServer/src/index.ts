import { randomBytes } from 'node:crypto'
import { ServerAccess } from './access.js'
import { OidcLogin, parseList } from './dashboard/oidc.js'
import { startServer } from './server.js'
import { ApnsPushSender, NoopPushSender } from './push.js'
import { PgStore } from './pg-store.js'
import { MemoryStore } from './store.js'

const env = process.env
const port = Number(env.PORT ?? 8080)

const push = env.APNS_KEY_P8 && env.APNS_KEY_ID && env.APNS_TEAM_ID && env.APNS_BUNDLE_ID
  ? new ApnsPushSender({
      keyP8: env.APNS_KEY_P8.replace(/\\n/g, '\n'),
      keyId: env.APNS_KEY_ID,
      teamId: env.APNS_TEAM_ID,
      bundleId: env.APNS_BUNDLE_ID,
      host: env.APNS_HOST ?? 'https://api.push.apple.com',
    })
  : new NoopPushSender()

if (!env.DATABASE_URL) console.warn('DATABASE_URL yok — token\'lar ve allowlist bellekte, yeniden başlatmada silinir')
if (!env.SESSION_SECRET) console.warn('SESSION_SECRET yok — dashboard oturumları her yeniden başlatmada düşer')

const store = env.DATABASE_URL ? new PgStore(env.DATABASE_URL) : new MemoryStore()
const access = await ServerAccess.load(store, { allowlist: env.NETWORK_ALLOWLIST, mode: env.NETWORK_ALLOWLIST_MODE })

const allowed = { emails: parseList(env.ALLOWED_EMAILS), domains: parseList(env.ALLOWED_EMAIL_DOMAINS) }
const login = env.OIDC_ISSUER && (allowed.emails.length > 0 || allowed.domains.length > 0)
  ? {
      oidc: new OidcLogin({
        issuer: env.OIDC_ISSUER,
        clientId: env.OIDC_CLIENT_ID,
        clientSecret: env.OIDC_CLIENT_SECRET,
        store,
      }),
      providerName: env.OIDC_PROVIDER_NAME ?? new URL(env.OIDC_ISSUER).host,
      allowed,
      publicUrl: env.PUBLIC_URL,
    }
  : undefined
if (env.OIDC_ISSUER && !login) console.warn('OIDC_ISSUER var ama ALLOWED_EMAIL_DOMAINS / ALLOWED_EMAILS yok — dashboard kapalı')

startServer({
  port,
  push,
  access,
  dashboard: { login, sessionSecret: env.SESSION_SECRET ?? randomBytes(32).toString('hex') },
})

const dashboard = login ? `açık (${login.providerName})` : 'kapalı'
console.log(`lumi-relay :${port} dinliyor (push: ${push instanceof NoopPushSender ? 'kapalı' : 'APNs'}, dashboard: ${dashboard}, allowlist: ${access.allowlist().mode})`)
