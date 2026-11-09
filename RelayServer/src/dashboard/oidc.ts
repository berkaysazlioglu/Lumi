import { createHash, randomBytes } from 'node:crypto'
import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose'
import type { RelayStore } from '../store.js'

/**
 * Dashboard girişi: OpenID Connect, yetkilendirme kodu + PKCE (docs/design/09).
 *
 * Lumi'nin sunucusunda sağlayıcı unco-forge'dur (girişi Google SSO'ya devreder);
 * başka bir sunucu herhangi bir OIDC sağlayıcısını (`OIDC_ISSUER`) kullanabilir.
 * `OIDC_CLIENT_ID` verilmezse istemci sağlayıcıya kendini kaydeder (dynamic client
 * registration) ve kaydı store'da saklanır. Kimlik `id_token`'dan okunur; e-posta
 * `email` claim'i, yoksa `sub`'dır (unco-forge `sub`'a e-postayı yazar).
 */

export interface OidcOptions {
  issuer: string
  clientId?: string
  clientSecret?: string
  store: RelayStore
}

interface Metadata {
  issuer: string
  authorization_endpoint: string
  token_endpoint: string
  jwks_uri: string
  registration_endpoint?: string
  scopes_supported?: string[]
}

interface Client {
  clientId: string
  clientSecret?: string
}

export interface AuthRequest {
  url: string
  state: string
  nonce: string
  verifier: string
}

const CLIENT_KEY_PREFIX = 'oidc_client:'

export class OidcLogin {
  private metadata: Metadata | null = null
  private jwks: JWTVerifyGetKey | null = null
  private clients = new Map<string, Client>()

  constructor(private opts: OidcOptions) {}

  /** Sağlayıcının giriş sayfasına yönlendirme adresi ve geri dönüşte doğrulanacak değerler. */
  async begin(redirectUri: string): Promise<AuthRequest> {
    const meta = await this.discover()
    const client = await this.client(redirectUri)
    const state = randomToken()
    const nonce = randomToken()
    const verifier = randomToken()
    const url = new URL(meta.authorization_endpoint)
    url.search = new URLSearchParams({
      response_type: 'code',
      client_id: client.clientId,
      redirect_uri: redirectUri,
      scope: requestedScope(meta),
      state,
      nonce,
      code_challenge: createHash('sha256').update(verifier).digest('base64url'),
      code_challenge_method: 'S256',
    }).toString()
    return { url: url.toString(), state, nonce, verifier }
  }

  /** Kodu `id_token`'a çevirir, imzayı/issuer'ı/audience'ı/nonce'u doğrular ve e-postayı döner. */
  async finish(code: string, redirectUri: string, expected: { nonce: string; verifier: string }): Promise<string> {
    const meta = await this.discover()
    const client = await this.client(redirectUri)
    const body = new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      redirect_uri: redirectUri,
      client_id: client.clientId,
      code_verifier: expected.verifier,
    })
    if (client.clientSecret) body.set('client_secret', client.clientSecret)
    const res = await fetch(meta.token_endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' },
      body: body.toString(),
    })
    const json = await res.json().catch(() => ({})) as { id_token?: unknown; error?: unknown }
    if (!res.ok || typeof json.id_token !== 'string') {
      throw new Error(`Sign-in failed at the provider (${typeof json.error === 'string' ? json.error : res.status}).`)
    }
    const { payload } = await jwtVerify(json.id_token, this.keys(meta), {
      issuer: meta.issuer,
      audience: client.clientId,
    })
    if (payload.nonce !== expected.nonce) throw new Error('Sign-in failed: the response did not match the request.')
    if (payload.email_verified === false) throw new Error('Your email address is not verified.')
    const email = typeof payload.email === 'string' ? payload.email : payload.sub
    if (!email || !email.includes('@')) throw new Error('The provider did not return an email address.')
    return email.toLowerCase()
  }

  private async discover(): Promise<Metadata> {
    if (this.metadata) return this.metadata
    const base = this.opts.issuer.replace(/\/+$/, '')
    // OIDC keşfi; olmazsa RFC 8414 (unco-forge yalnız bunu herkese açar).
    for (const path of ['/.well-known/openid-configuration', '/.well-known/oauth-authorization-server']) {
      const res = await fetch(base + path, { headers: { Accept: 'application/json' } }).catch(() => null)
      if (!res?.ok) continue
      const meta = await res.json().catch(() => null) as Partial<Metadata> | null
      if (meta?.authorization_endpoint && meta.token_endpoint && meta.jwks_uri && meta.issuer) {
        this.metadata = meta as Metadata
        return this.metadata
      }
    }
    throw new Error(`Couldn't reach the sign-in provider (${base}).`)
  }

  private keys(meta: Metadata): JWTVerifyGetKey {
    this.jwks ??= createRemoteJWKSet(new URL(meta.jwks_uri))
    return this.jwks
  }

  /** Verilen istemci, yoksa bu geri dönüş adresi için kayıtlı ya da yeni kaydedilen istemci. */
  private async client(redirectUri: string): Promise<Client> {
    if (this.opts.clientId) return { clientId: this.opts.clientId, clientSecret: this.opts.clientSecret }
    const cached = this.clients.get(redirectUri)
    if (cached) return cached
    const key = `${CLIENT_KEY_PREFIX}${this.opts.issuer}|${redirectUri}`
    const saved = await this.opts.store.getSetting(key) as { clientId?: unknown } | null
    if (saved && typeof saved.clientId === 'string') {
      const client = { clientId: saved.clientId }
      this.clients.set(redirectUri, client)
      return client
    }
    const meta = await this.discover()
    if (!meta.registration_endpoint) throw new Error('The provider needs OIDC_CLIENT_ID (no dynamic registration).')
    const res = await fetch(meta.registration_endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        client_name: 'Lumi Relay',
        redirect_uris: [redirectUri],
        application_type: 'web',
        token_endpoint_auth_method: 'none',
        grant_types: ['authorization_code'],
        response_types: ['code'],
      }),
    })
    const json = await res.json().catch(() => ({})) as { client_id?: unknown; error_description?: unknown }
    if (!res.ok || typeof json.client_id !== 'string') {
      throw new Error(`Couldn't register with the sign-in provider (${String(json.error_description ?? res.status)}).`)
    }
    const client = { clientId: json.client_id }
    await this.opts.store.setSetting(key, client)
    this.clients.set(redirectUri, client)
    return client
  }
}

/**
 * `openid` + sağlayıcı destekliyorsa `email`. Desteklenmeyen kapsam istemek, kapsamları
 * otomatik onaylayan sağlayıcıda (unco-forge) onay döngüsüne yol açabilir.
 */
export function requestedScope(meta: { scopes_supported?: string[] }): string {
  const supported = meta.scopes_supported
  return !supported || supported.includes('email') ? 'openid email' : 'openid'
}

/** E-posta izinli mi: tam adres listesi ya da alan adı listesi (ikisi de boşsa kimse giremez). */
export function isAllowedEmail(email: string, allowed: { emails: string[]; domains: string[] }): boolean {
  const normalized = email.trim().toLowerCase()
  if (allowed.emails.includes(normalized)) return true
  const domain = normalized.split('@')[1]
  return !!domain && allowed.domains.includes(domain)
}

export function parseList(raw: string | undefined): string[] {
  return (raw ?? '').split(',').map((s) => s.trim().toLowerCase().replace(/^@/, '')).filter(Boolean)
}

function randomToken(): string {
  return randomBytes(32).toString('base64url')
}
