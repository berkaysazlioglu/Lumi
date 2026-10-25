import Foundation

/// Lumi Sessions Protocol v1'in kanonik metni (karar 138).
///
/// Kullanıcı bunu Agent History ▸ Import ▸ Import from Server ▸ `Copy Setup
/// Prompt` ile kopyalayıp kendi sunucu projesindeki ajana yapıştırır; ajan
/// protokolü o projenin stack'inde kurar, ilk kullanıcıyı oluşturur ve adres
/// + token'ı yazdırır. Protokolün TEK kaynağı bu metindir —
/// `docs/design/07-sessions-protocol.md` gerekçeleri anlatır ve buraya bakar.
/// `SessionShareSetupPromptTests` uçların ve alanların burada geçtiğini kilitler.
public enum SessionShareSetupPrompt {
    public static let text = #"""
    # Add the Lumi Sessions API to this project

    Lumi is a macOS app that manages Claude Code and Codex sessions. Its users want to share agent sessions (chat transcripts) with their team: one person uploads a session, teammates browse the list and import it into their own Lumi. Implement the **Lumi Sessions Protocol v1** below in THIS project, using its existing language, framework and database.

    ## Before you start

    - Storage must be **persistent**. On Heroku, Railway, Render, Fly and similar platforms the filesystem is wiped on every deploy/restart — use the project's database (e.g. Postgres), or its object storage if it already has one. Never a JSON file or SQLite on local disk.
    - Mount everything under the path prefix `/lumi/sessions/v1`. Do not change existing routes.
    - Session packages can be large: accept JSON request bodies up to **64 MB** on `POST /lumi/sessions/v1/sessions` (raise the framework's default body limit for that route only). Storing the package gzip-compressed is recommended; it is opaque to the server.

    ## Users and tokens

    Every person has their **own token**. The token decides who uploaded a session and who may delete it.

    - Create a `lumi_session_users` table (id, name, token hash, createdAt). Store only a SHA-256 hash of each token, never the token itself.
    - Add a command the operator runs on the server to create a user, e.g. `npm run lumi:add-user -- "Ada Lovelace"` (or the project's equivalent script / management command). It generates a token (at least 32 random bytes, hex), stores its hash, and **prints the token once**. Add a matching command to list users and to revoke one.
    - **Create a first user yourself** for the person you are working with (ask their name if you don't know it) and print that token in your final message — they need to paste it into Lumi. This is expected and safe: it's their own server.
    - Every endpoint (including `GET /lumi/sessions/v1`) requires `Authorization: Bearer <token>`. Hash the presented token and look it up (compare in constant time). Missing or unknown token → `401` with the error envelope.
    - If there are no users at all, the rest of the app must still start normally; the `/lumi/sessions/v1` routes answer `503` with the code `not_configured` and a message telling the operator to run the add-user command.
    - The app runs behind HTTPS in production (the platform provides it). Lumi only allows plain `http` for `localhost`.

    ## Conventions

    - JSON in and out, UTF-8, `Content-Type: application/json`. Field names are camelCase.
    - Timestamps are ISO 8601 in UTC (`2026-10-25T10:15:00Z`). IDs are strings.
    - **Ignore unknown fields** in request bodies. Lumi may send fields from newer versions.
    - Errors always use this envelope and a matching HTTP status:
      ```json
      { "error": { "code": "forbidden", "message": "Only the uploader can delete this session" } }
      ```
      Codes: `unauthorized` (401), `forbidden` (403), `not_found` (404), `payload_too_large` (413), `validation_failed` (422), `internal` (500), `not_configured` (503). Messages should say exactly what was wrong — Lumi shows them to the user verbatim.

    ## The session summary object

    ```json
    {
      "id": "s_81f2",
      "title": "Fix the login redirect loop",
      "project": "Backend API",
      "provider": "claude",
      "uploader": { "id": "u_1", "name": "Ada Lovelace" },
      "uploadedAt": "2026-10-25T10:15:00Z",
      "size": 482113
    }
    ```

    - **Required:** `id`, `title`, `project`, `uploader` (`id` + `name`), `uploadedAt`.
    - `project` is a plain display name chosen by the uploader (e.g. "Backend API") — not a path, branch or repository URL.
    - `provider` is `claude` or `codex`. `size` is the stored package size in bytes (optional).
    - `uploader` always comes from the token used for the upload, never from the request body.

    ## Endpoints

    ### `GET /lumi/sessions/v1` — discovery
    ```json
    { "protocol": "lumi-sessions", "version": 1, "name": "Acme team sessions", "me": { "id": "u_1", "name": "Ada Lovelace" }, "maxUploadBytes": 67108864 }
    ```
    - `me` (required) is the user the token belongs to. Lumi uses it to show "You" and to offer Delete only on your own uploads.
    - `name` and `maxUploadBytes` are optional.

    ### `GET /lumi/sessions/v1/sessions`
    Query (optional): `cursor`, `limit` (Lumi sends 200). Response: `{ "sessions": [ …summary objects… ], "nextCursor": "opaque-string-or-null" }`. Newest upload first. Every user sees every session. Never include the package here — the list must stay small.

    ### `GET /lumi/sessions/v1/sessions/{id}`
    The summary object plus the package exactly as uploaded: `{ …summary…, "archive": { …the uploaded archive object… } }`. Unknown id → `404 not_found`.

    ### `POST /lumi/sessions/v1/sessions`
    Body:
    ```json
    { "title": "Fix the login redirect loop", "project": "Backend API", "provider": "claude", "archive": { "format": "lumi-agent-session", "version": 1, "records": [] } }
    ```
    - `title` and `project` are required non-empty strings (trim them, max 200 characters); `provider` is `claude` or `codex`; `archive` is a JSON object whose `format` is `lumi-agent-session`. Otherwise → `422 validation_failed`.
    - Store `archive` unchanged; it is opaque to the server. Too large → `413 payload_too_large`.
    - The uploader is the token's user. Returns `201` with the summary object.

    ### `DELETE /lumi/sessions/v1/sessions/{id}`
    Only the uploader may delete: another user's token → `403 forbidden`. Success → `204` with an empty body. Unknown id → `404`.

    ## Verify before you finish

    Run the server locally and check with curl (replace the token). Run these checks yourself; if you can't run commands in this session, give the user the exact commands instead.
    1. `GET /lumi/sessions/v1` without a token → 401 envelope; with the token → discovery JSON with `"protocol": "lumi-sessions"`, `"version": 1` and `me`.
    2. `POST /lumi/sessions/v1/sessions` with `{"title":"smoke test","project":"Demo","provider":"claude","archive":{"format":"lumi-agent-session","version":1,"records":[{"type":"user"}]}}` → 201 with `uploader` = `me`.
    3. `GET /lumi/sessions/v1/sessions` → contains it, without `archive`. `GET /lumi/sessions/v1/sessions/<id>` → includes the same `archive`.
    4. Create a second user; `DELETE` the session with the second token → 403; with the first → 204; `GET` it again → 404. Revoke the second user.
    5. `POST` with `"provider": "gpt"` → 422 envelope.
    Add automated tests for these if the project has a test suite.

    ## When you're done, print

    - The **base URL** (the production origin, e.g. `https://my-app.herokuapp.com`, and the local one for development) — without `/lumi/sessions/v1`.
    - The **token** of the first user, and the exact command to create more users on the production server (e.g. `heroku run npm run lumi:add-user -- "Name"`).
    - Where the packages are stored and the upload size limit.

    The user pastes the base URL and the token into Lumi ▸ Agent History ▸ Import ▸ Import from Server. Each teammate gets their own token from the add-user command.
    """#
}
