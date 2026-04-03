# Static Files

```@meta
CurrentModule = Inochi
```

Inochi includes two small helpers for file responses: `static` and `sendFile`.

Both helpers attach an `ETag`, and `If-None-Match` is honored when a request context is available. The `etag()` middleware applies the same behavior to ordinary response bodies.

## `static(root)`

Use `static(root)` on a wildcard route to serve files from a directory.

```julia
get(static("public"), app, "/static/*")
```

Examples:

- `GET /static/app.css` serves `public/app.css`
- `GET /static/images/logo.png` serves `public/images/logo.png`

Security behavior:

- Paths are rooted at the supplied directory.
- Requests cannot escape above that root.
- Escaping attempts return `403 Forbidden`.
- If the client sends a matching `If-None-Match`, Inochi responds with `304 Not Modified`.

## `sendFile(path)`

Use `sendFile(path)` inside a route to return one file directly.

```julia
get(app, "/about") do
    sendFile("public/about.html")
end
```

By default, `sendFile` is rooted at the executable directory. Paths outside that root return `403 Forbidden`.

If you want `If-None-Match` handling on a route-local file response, prefer the `sendFile(ctx, path)` form from inside a handler.

You can override the root explicitly:

```julia
sendFile("about.html"; root = joinpath(@__DIR__, "public"))
```

## Content Type Detection

Inochi uses `MIMEs.jl` to infer the response `Content-Type` from the file path extension.

Examples:

- `.html` -> `text/html; charset=utf-8`
- `.css` -> `text/css; charset=utf-8`
- `.json` -> `application/json; charset=utf-8`
- unknown extensions -> `application/octet-stream`

## ETag Middleware

Use `etag()` when you want ordinary handler responses to participate in the same caching flow as file helpers.

```julia
use(app, etag())
```
