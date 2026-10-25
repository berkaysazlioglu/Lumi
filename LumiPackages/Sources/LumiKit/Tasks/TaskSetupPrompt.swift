import Foundation

/// Lumi Tasks Protocol v1'in kanonik metni (Tasks planı, Faz 2).
///
/// Kullanıcı bunu Tasks ▸ Connect ▸ `Copy Setup Prompt` ile kopyalayıp kendi
/// sunucu projesindeki ajana yapıştırır; ajan protokolü o projenin
/// stack'inde kurar ve sonunda adres + token'ı yazdırır. Protokolün TEK
/// kaynağı bu metindir — `docs/design/06-tasks-protocol.md` tasarım
/// gerekçelerini anlatır ve buraya bakar. HTTP adapter'ı
/// (`LumiTasksHTTPProvider`) ve Verify bu metnin söylediğini bekler;
/// `TaskSetupPromptTests` uçların ve alanların burada geçtiğini kilitler.
public enum TaskSetupPrompt {
    public static let text = #"""
    # Add the Lumi Tasks API to this project

    Lumi is a macOS app that shows tasks on a board and hands them to AI coding agents. Implement the **Lumi Tasks Protocol v1** below in THIS project, using its existing language, framework and database. Lumi will connect with a base URL and a token, read tasks, move them between statuses and create/delete them.

    ## Before you start

    - If this project already has a task / issue / ticket model, **expose that model** through this API (map its states onto the four statuses below). Only create a new minimal `tasks` table if nothing like it exists.
    - Storage must be **persistent**. On Heroku, Railway, Render, Fly and similar platforms the filesystem is wiped on every deploy/restart — use the project's database (e.g. Postgres), never a JSON file or SQLite on local disk.
    - Mount everything under the path prefix `/lumi/v1`. Do not change existing routes.

    ## Authentication

    - Read the token from the environment variable `LUMI_TASKS_TOKEN`. Never commit it.
    - **Generate the token yourself** (at least 32 random bytes, e.g. `openssl rand -hex 32`), put it in the project's local env setup (e.g. a git-ignored `.env`) for development, and **print it in your final message** — the user needs to paste it into Lumi. This is expected and safe: it's their own server.
    - If `LUMI_TASKS_TOKEN` is not set, the rest of the app must still start normally. Only the `/lumi/v1` routes answer `503` with the code `not_configured` and a message saying the variable is missing.
    - Every endpoint (including `GET /lumi/v1`) requires `Authorization: Bearer <token>`. Compare in constant time. Missing or wrong token → `401` with the error envelope.
    - The app runs behind HTTPS in production (the platform provides it). Lumi only allows plain `http` for `localhost`.

    ## Conventions

    - JSON in and out, UTF-8, `Content-Type: application/json`. Field names are camelCase.
    - Timestamps are ISO 8601 in UTC (`2026-10-24T10:15:00Z`). `dueDate` is a date only (`2026-11-01`).
    - IDs are strings.
    - **Ignore unknown fields** in request bodies (do not reject them). Lumi may send fields from newer versions.
    - Errors always use this envelope and a matching HTTP status:
      ```json
      { "error": { "code": "validation_failed", "message": "status must be one of todo, in_progress, in_review, done" } }
      ```
      Codes: `unauthorized` (401), `not_found` (404), `validation_failed` (422), `conflict` (409), `rate_limited` (429, with `Retry-After`), `not_supported` (405), `internal` (500), `not_configured` (503). Messages should say exactly what was wrong — Lumi shows them to the user verbatim.

    ## The task object

    ```json
    {
      "id": "42",
      "title": "Rate limit the public endpoint",
      "status": "in_progress",
      "updatedAt": "2026-10-24T10:15:00Z",
      "createdAt": "2026-10-20T08:00:00Z",
      "body": "Markdown description",
      "project": { "key": "api", "name": "Backend API", "repo": "git@github.com:acme/api.git" },
      "priority": "high",
      "labels": ["security"],
      "assignee": { "id": "u_1", "name": "Ada Lovelace", "email": "ada@example.com" },
      "dueDate": "2026-11-01",
      "url": "https://app.example.com/tasks/42",
      "images": [
        { "url": "https://cdn.example.com/a.png", "thumbnailUrl": "https://cdn.example.com/a_thumb.png", "name": "a.png", "width": 1600, "height": 1000 }
      ],
      "lumi": { "sessionId": "…" }
    }
    ```

    - **Required:** `id`, `title`, `status`, `updatedAt`. Everything else is optional — omit what the project doesn't have and don't declare it in `fields` (see discovery).
    - `status` is exactly one of: `todo`, `in_progress`, `in_review`, `done`.
    - `priority` is one of: `none`, `low`, `medium`, `high`, `urgent`.
    - `assignee` is `null` when unassigned.
    - `images` are absolute URLs. Images on this server may require the same Bearer token; images elsewhere (S3, CDN) must be public or pre-signed. Provide `thumbnailUrl` when the original is large.
    - Lumi downloads each image once and caches it by its URL with the standard signing parameters removed (`X-Amz-*`, `X-Goog-*`, CloudFront `Expires`/`Signature`/`Key-Pair-Id`/`Policy`, Azure SAS). So a pre-signed URL may be re-signed on every request, but the rest of the URL must stay the same for the same image — and must change when the image content changes.
    - `project.repo` is the git remote of the code the task belongs to — Lumi uses it to open the right project.
    - `lumi` is an opaque object owned by Lumi. Store it as-is (a JSON column) and return it unchanged. Only needed if you declare the `lumiMetadata` capability.
    - Every write must bump `updatedAt`.

    ## Endpoints

    ### `GET /lumi/v1` — discovery
    ```json
    {
      "protocol": "lumi-tasks",
      "version": 1,
      "name": "Acme backlog",
      "me": { "id": "u_1", "name": "Ada Lovelace" },
      "capabilities": ["create", "delete", "users", "projects", "lumiMetadata"],
      "fields": { "body": "rw", "project": "rw", "priority": "rw", "labels": "r", "assignee": "rw", "dueDate": "r", "url": "r", "images": "r" }
    }
    ```
    - `me` is the user the token belongs to (optional). Lumi shows it as "You".
    - `capabilities` lists only what you implement: `create` (POST), `delete` (DELETE), `users` (GET /users), `projects` (GET /projects), `lumiMetadata` (store the `lumi` object).
    - `fields` lists every optional task field you return: `"r"` read-only, `"rw"` also writable via PATCH/POST. Lumi hides everything not listed.

    ### `GET /lumi/v1/tasks`
    Query (all optional): `status` (comma separated, e.g. `todo,in_progress`), `project` (project key), `cursor`, `limit` (Lumi sends 200).
    Response: `{ "tasks": [ …task objects… ], "nextCursor": "opaque-string-or-null", "syncToken": "opaque-string" }`. If you don't paginate, return everything with `"nextCursor": null`. Order by `updatedAt` descending.

    **Incremental sync (recommended).** Lumi refreshes every 15 seconds while the board is open. To avoid sending every task each time:
    - Include `syncToken` in the response — an opaque string marking this moment. Simplest: the highest `updatedAt` across all tasks.
    - Lumi then sends `since=<syncToken>`. Answer with only the tasks changed since then in `tasks` (with the token above: `updatedAt >= since`), plus `"ids"`: the ids of **all** tasks that currently exist (strings, same order as the full list), plus a new `syncToken`. Deleted tasks simply disappear from `ids` — no tombstones needed.
    - If you can't honor a `since` value, ignore it and return the full list without `ids`; Lumi treats a response without `ids` as a full list. A server that ignores `since` entirely still works, just less efficiently.
    - This only works if every change (including images and `lumi`) bumps `updatedAt`.

    ### `GET /lumi/v1/tasks/{id}`
    The task, or `404 not_found`.

    ### `PATCH /lumi/v1/tasks/{id}` — required
    Partial update. Body may contain any of: `status`, `title`, `body`, `priority`, `assigneeId` (string, or `null` to unassign), `projectKey`, `dueDate`, `lumi`. Only touch fields that are present. Invalid values → `422 validation_failed`. Unknown id → `404`. Returns the full updated task. Changing `status` alone must always work.

    ### `POST /lumi/v1/tasks` — capability `create`
    Body: `title` (required), optional `body`, `status` (default `todo`), `projectKey`, `priority`, `assigneeId`. Returns `201` with the created task.

    ### `DELETE /lumi/v1/tasks/{id}` — capability `delete`
    `204` with an empty body. Unknown id → `404`.

    ### `GET /lumi/v1/users` — capability `users`
    `{ "users": [ { "id": "u_1", "name": "Ada Lovelace", "email": "ada@example.com" } ] }` — the people a task can be assigned to.

    ### `GET /lumi/v1/projects` — capability `projects`
    `{ "projects": [ { "key": "api", "name": "Backend API", "repo": "git@github.com:acme/api.git" } ] }`

    ## Verify before you finish

    Run the server locally and check with curl (replace the token). Run these checks yourself; if you can't run commands in this session, give the user the exact commands instead.
    1. `GET /lumi/v1` without a token → 401 envelope; with the token → discovery JSON with `"protocol": "lumi-tasks"`, `"version": 1`.
    2. `POST /lumi/v1/tasks` with `{"title":"smoke test"}` → 201 (if you declared `create`).
    3. `PATCH /lumi/v1/tasks/<id>` with `{"status":"in_review"}` → the task with `"status": "in_review"` and a newer `updatedAt`.
    4. `PATCH` with `{"status":"blocked"}` → 422 envelope.
    5. `GET /lumi/v1/tasks` → contains the task; `DELETE` it → 204; `GET` it again → 404.
    6. `GET /lumi/v1/tasks` → note `syncToken`; `PATCH` one task; `GET /lumi/v1/tasks?since=<syncToken>` → `tasks` holds only that task, `ids` holds every task id.
    Add automated tests for these if the project has a test suite.

    ## When you're done, print

    - The **base URL** (the production origin, e.g. `https://my-app.herokuapp.com`, and the local one for development) — without `/lumi/v1`.
    - The **token**, and the exact command to set it on the platform (e.g. `heroku config:set LUMI_TASKS_TOKEN=…` or the Railway variables UI).
    - Which capabilities and fields you declared, and anything you mapped from an existing model.

    The user pastes the base URL and the token into Lumi ▸ Tasks ▸ Connect Task Source; Lumi then runs its own verification against your API.
    """#
}
