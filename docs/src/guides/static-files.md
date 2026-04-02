# Static Files

```@meta
CurrentModule = Inochi
```

Inochi includes two small helpers for file responses: `static` and `sendFile`.

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

## `sendFile(path)`

Use `sendFile(path)` inside a route to return one file directly.

```julia
get(app, "/about") do
    sendFile("public/about.html")
end
```

By default, `sendFile` is rooted at the executable directory. Paths outside that root return `403 Forbidden`.

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
