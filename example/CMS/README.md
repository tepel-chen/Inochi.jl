# Inochi CMS Example

Run:

```bash
cd example/CMS
docker compose up --build
```

Open `http://127.0.0.1:8080`.

Local Julia:

```bash
cd example/CMS
DB_HOST=127.0.0.1 DB_PORT=5432 DB_NAME=cms DB_USER=cms DB_PASSWORD=cms julia app.jl
```

The compose stack starts PostgreSQL and the CMS together. The image resolves `Inochi.jl` and `IwaiEngine.jl` from GitHub, installs `LibPQ` and `PostgresORM`, precompiles during build, and then starts with `CMS_SKIP_PKG_SETUP=1` so it does not reinstall on every boot.

Seeded accounts:

- `admin@example.com` / random password printed to the CMS log on startup
- `ren@example.com` / `password` (`member`)

Routes:

- `GET /` shows the public post list
- `GET|POST /login`, `GET|POST /register`, `POST /logout`
- `GET /post/:id` shows a post
- `POST /post/:id/comments` adds a comment for logged-in users
- `GET /admin/dashboard`
- `GET /admin/posts`
- `GET /admin/posts/new/edit`
- `POST /admin/posts/new`
- `POST /admin/posts/image-upload`
- `GET /admin/posts/:id/detail`
- `GET /admin/posts/:id/edit`
- `POST /admin/posts/:id/update`
- `GET /admin/users`
- `GET /admin/users/:id/detail`
- `GET /admin/files`
- `GET /admin/files/:id/detail`
- `GET /static/*` serves the CMS assets

Implementation notes:

- This sample is self-contained. `bootstrap.jl` installs `Inochi.jl` and `IwaiEngine.jl` from:
  - `https://github.com/tepel-chen/Inochi.jl`
  - `https://github.com/tepel-chen/IwaiEngine.jl`
- `app.jl` respects `HOST`, `PORT`, `CMS_SKIP_PKG_SETUP`, and `DB_*` so the same entrypoint works both locally and in Docker.
- The data layer uses `PostgresORM.jl` with schema bootstrapping and seed data in `store.jl`.
- The admin user password is generated randomly for a fresh database and printed from the app log at startup.
- Admin routes are mounted via `route(app, "/admin", admin_app)`.
- Post detail routes are mounted via `route(app, "/post", posts_app)`.
- Markdown rendering uses Julia's `Markdown` stdlib and is inserted into templates as trusted HTML.
- The Admin navigation and editor shortcuts only render for users with the `admin` role.
- The post editor accepts pasted image blobs, uploads them through `/admin/posts/image-upload`, and inserts the returned markdown image link into the textarea.
- Templates are organized by feature (`views/layouts`, `views/pages`, `views/auth`, `views/posts`, `views/admin/...`) and rendered via nested relative `extends`/`include`.
- CSRF protection is enabled through the Inochi middleware and all POST forms render a hidden `csrf_token`.
- A custom CSP middleware sets security headers while allowing the Tailwind CDN and the inline Tailwind config used by the layout.
- Styling uses Tailwind CSS via CDN; `public/` only keeps static assets such as SVGs.

Gaps noticed while building this sample:

- Flash message support is still manual; redirects do not have a built-in session flash helper.
- Request validation and form helpers are still low-level, so form-heavy pages require repetitive parsing.
- There is no built-in Markdown helper or HTML sanitization layer in the web stack yet.
