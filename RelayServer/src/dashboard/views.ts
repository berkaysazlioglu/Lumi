import type { AllowlistSettings } from '../allowlist.js'
import type { NetworkEvent } from '../access.js'
import type { TokenRecord } from '../store.js'

/** Dashboard'un sunucu tarafında çizilen sayfaları — JS yok (yalnız kopyala butonu). */

export interface RelayStatus {
  rooms: { macsOnline: number; phones: number }
  hubs: { name: string; online: boolean; controllerCount: number; lastSeenAt: number }[]
  connections: number
}

export interface DashboardModel {
  username: string
  status: RelayStatus
  tokens: TokenRecord[]
  allowlist: AllowlistSettings
  events: NetworkEvent[]
  /** Az önce üretilen token — yalnız bu yanıtta görünür. */
  createdToken?: { name: string; token: string }
  notice?: { kind: 'ok' | 'error'; text: string }
  serverUrl: string
}

export function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;')
}

const STYLE = `
:root{--bg:#f6f7f9;--card:#fff;--text:#16181d;--muted:#6b7280;--border:#e3e5e8;--accent:#3b6cf6;--ok:#16a34a;--warn:#d97706;--err:#dc2626;--code:#f1f3f6}
@media (prefers-color-scheme:dark){:root{--bg:#0f1115;--card:#171a21;--text:#e7e9ee;--muted:#8b93a3;--border:#272b35;--accent:#6b8cff;--code:#1f232c}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
main{max-width:920px;margin:0 auto;padding:24px 16px 64px}
header{display:flex;align-items:center;justify-content:space-between;margin-bottom:20px}
h1{font-size:20px;margin:0}h2{font-size:15px;margin:0 0 12px}
.card{background:var(--card);border:1px solid var(--border);border-radius:10px;padding:16px;margin-bottom:16px}
.muted{color:var(--muted)}.stats{display:flex;gap:24px;flex-wrap:wrap}.stat b{font-size:20px;display:block}
table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:8px 6px;border-bottom:1px solid var(--border);vertical-align:middle}
th{font-weight:600;color:var(--muted);font-size:12px}tr:last-child td{border-bottom:0}
code,textarea,input{font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
code{background:var(--code);padding:2px 5px;border-radius:4px;font-size:12px;word-break:break-all}
input,select,textarea{background:var(--bg);color:var(--text);border:1px solid var(--border);border-radius:6px;padding:7px 9px;font-size:13px}
textarea{width:100%;min-height:140px}
button{background:var(--accent);color:#fff;border:0;border-radius:6px;padding:7px 12px;font-size:13px;cursor:pointer}
button.ghost{background:transparent;color:var(--muted);border:1px solid var(--border)}button.danger{background:transparent;color:var(--err);border:1px solid var(--border)}
.row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}.dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:6px}
.notice{padding:10px 12px;border-radius:8px;margin-bottom:16px;border:1px solid var(--border)}.notice.ok{border-color:var(--ok)}.notice.error{border-color:var(--err)}
.secret{border:1px solid var(--warn);border-radius:8px;padding:12px;margin-bottom:16px}
.login{max-width:340px;margin:12vh auto}
/* Bağlantı, form değil: form-action 'self' formun sağlayıcıya yönlenmesini engeller. */
a.button{display:block;text-align:center;text-decoration:none;background:var(--accent);color:#fff;border-radius:6px;padding:9px 12px;font-size:13px}
.scroll{overflow-x:auto}`

function page(title: string, body: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(title)}</title><style>${STYLE}</style></head><body>${body}</body></html>`
}

export function loginPage(providerName: string, error?: string): string {
  return page('Lumi Relay', `<main><div class="card login">
<h1 style="margin-bottom:16px">Lumi Relay</h1>
${error ? `<div class="notice error">${escapeHtml(error)}</div>` : ''}
<a class="button" href="/auth/start">Sign in with ${escapeHtml(providerName)}</a>
</div></main>`)
}

export function disabledPage(): string {
  return page('Lumi Relay', `<main><div class="card login"><h1>Lumi Relay</h1>
<p class="muted">Dashboard is disabled. Set <code>OIDC_ISSUER</code> and <code>ALLOWED_EMAIL_DOMAINS</code> (or <code>ALLOWED_EMAILS</code>) to enable it.</p></div></main>`)
}

function time(ms: number | null): string {
  if (ms === null) return '<span class="muted">—</span>'
  return `<span title="${new Date(ms).toISOString()}">${escapeHtml(new Date(ms).toISOString().replace('T', ' ').slice(0, 16))} UTC</span>`
}

function statusSection(s: RelayStatus): string {
  const hubs = s.hubs.length === 0
    ? '<p class="muted">No hubs yet.</p>'
    : `<div class="scroll"><table><tr><th>Hub</th><th>Status</th><th>Controllers</th><th>Last seen</th></tr>${s.hubs.map((h) => `<tr>
<td>${escapeHtml(h.name)}</td>
<td><span class="dot" style="background:var(${h.online ? '--ok' : '--muted'})"></span>${h.online ? 'Online' : 'Offline'}</td>
<td>${h.controllerCount}</td><td>${time(h.lastSeenAt)}</td></tr>`).join('')}</table></div>`
  return `<section class="card"><h2>Status</h2><div class="stats" style="margin-bottom:12px">
<div class="stat"><b>${s.connections}</b><span class="muted">Connections</span></div>
<div class="stat"><b>${s.rooms.macsOnline}</b><span class="muted">Macs (mobile)</span></div>
<div class="stat"><b>${s.rooms.phones}</b><span class="muted">Phones</span></div>
<div class="stat"><b>${s.hubs.filter((h) => h.online).length}</b><span class="muted">Hubs online</span></div></div>${hubs}</section>`
}

function tokensSection(m: DashboardModel): string {
  const created = m.createdToken ? `<div class="secret"><b>Token for ${escapeHtml(m.createdToken.name)}</b>
<p class="muted" style="margin:4px 0 8px">Copy it now — it won't be shown again. In Lumi: Remote ▸ Server URL + Token.</p>
<div class="row"><code id="new-token">${escapeHtml(m.createdToken.token)}</code>
<button type="button" class="ghost" onclick="navigator.clipboard.writeText(document.getElementById('new-token').textContent)">Copy</button></div>
<p class="muted" style="margin:8px 0 0">Server URL: <code>${escapeHtml(m.serverUrl)}</code></p></div>` : ''
  const rows = m.tokens.length === 0
    ? '<p class="muted">No tokens. Create one to let a Mac or phone connect.</p>'
    : `<div class="scroll"><table><tr><th>Name</th><th>Token</th><th>Created</th><th>Last used</th><th></th></tr>${[...m.tokens].reverse().map((t) => `<tr${t.revokedAt ? ' class="muted"' : ''}>
<td>${escapeHtml(t.name)}</td><td><code>${escapeHtml(t.prefix)}…</code></td><td>${time(t.createdAt)}</td><td>${time(t.lastUsedAt)}</td>
<td>${t.revokedAt ? 'Revoked' : `<form method="post" action="/tokens/${encodeURIComponent(t.id)}/revoke" onsubmit="return confirm('Revoke this token? Its connections will drop.')"><button class="danger">Revoke</button></form>`}</td></tr>`).join('')}</table></div>`
  return `<section class="card"><h2>Tokens</h2>${created}
<form class="row" method="post" action="/tokens" style="margin-bottom:12px"><input name="name" placeholder="Name (e.g. Berkay – MacBook)" maxlength="64" required style="flex:1;min-width:200px"><button>Create token</button></form>${rows}</section>`
}

function allowlistSection(a: AllowlistSettings, events: NetworkEvent[]): string {
  const mode = (value: string, label: string) => `<option value="${value}"${a.mode === value ? ' selected' : ''}>${label}</option>`
  const lines = a.entries.map((e) => (e.label && e.label !== e.cidr ? `${e.cidr} = ${e.label}` : e.cidr)).join('\n')
  const log = events.length === 0 ? '' : `<h2 style="margin-top:16px">Outside the allowlist</h2><div class="scroll"><table><tr><th>Time</th><th>IP</th><th>Role</th><th>Token</th><th>Result</th></tr>${events.map((e) => `<tr>
<td>${time(e.at)}</td><td><code>${escapeHtml(e.ip)}</code></td><td>${escapeHtml(e.role)}</td><td>${escapeHtml(e.tokenName)}</td>
<td style="color:var(${e.verdict === 'blocked' ? '--err' : '--warn'})">${e.verdict === 'blocked' ? 'Blocked' : 'Would block'}</td></tr>`).join('')}</table></div>`
  return `<section class="card"><h2>IP allowlist</h2>
<p class="muted" style="margin-top:0">Applies to Mac-to-Mac (hub / controller) connections only. Phones connect from any network.</p>
<form method="post" action="/allowlist"><div class="row" style="margin-bottom:8px"><label>Mode</label>
<select name="mode">${mode('enforce', 'Enforce — block outside the list')}${mode('report', 'Report — log only')}${mode('off', 'Off')}</select></div>
<textarea name="entries" spellcheck="false" placeholder="203.0.113.7 = Office&#10;198.51.100.0/24 = VPN">${escapeHtml(lines)}</textarea>
<p class="muted" style="margin:6px 0 10px">One per line: IP or IPv4 CIDR, optional <code>= label</code>. An empty list turns the check off.</p>
<button>Save allowlist</button></form>${log}</section>`
}

export function dashboardPage(m: DashboardModel): string {
  const notice = m.notice ? `<div class="notice ${m.notice.kind}">${escapeHtml(m.notice.text)}</div>` : ''
  // POST yanıtından sonra yenileme formu yeniden göndermesin.
  const replace = m.createdToken || m.notice ? '<script>history.replaceState(null,"","/")</script>' : ''
  return page('Lumi Relay', `<main><header><h1>Lumi Relay</h1><form class="row" method="post" action="/logout">
<span class="muted">${escapeHtml(m.username)}</span><button class="ghost">Sign out</button></form></header>
${notice}${statusSection(m.status)}${tokensSection(m)}${allowlistSection(m.allowlist, m.events)}</main>${replace}`)
}
