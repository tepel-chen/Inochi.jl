# Context and Responses

```@meta
CurrentModule = Inochi
```

## The Context Object

`Context` wraps the request and the response under construction.

Common fields:

- `ctx.req`: the underlying `Inochi.Request`
- `ctx.params`: route parameters
- `ctx.status`: response status
- `ctx.headers`: response headers
- `ctx.body`: response body
- `ctx.backtrace`: the captured backtrace when dispatch catches an error

You can also access request properties through `ctx`, for example `ctx.method` or `ctx.target`.

## Response Helpers

Plain text:

```julia
get(app, "/ping") do ctx
    text(ctx, "pong")
end
```

HTML:

```julia
get(app, "/page") do ctx
    html(ctx, "<h1>Hello</h1>")
end
```

JSON:

```julia
get(app, "/data") do ctx
    json(ctx, Dict("ok" => true))
end
```

Redirects:

```julia
post(app, "/login") do ctx
    redirect(ctx, "/dashboard")
end
```

Manual status, headers, and body:

```julia
get(app, "/manual") do ctx
    status!(ctx, 201)
    header!(ctx, "X-Mode", "manual")
    body!(ctx, "created")
end
```

For advanced cases, use `response!(ctx, ...)` to set a raw response on the
context:

```julia
get(app, "/raw") do ctx
    response!(ctx, Response(202, "raw"))
end
```

For a full escape hatch, return `Response(...)` directly:

```julia
get(app, "/raw") do ctx
    Response(202, "raw")
end
```

When a handler returns `Response`, Inochi sends it as-is. The usual `ctx`
helpers and default headers are skipped. `response!(ctx, ...)` is the same idea
when you want to set a raw response from inside the handler body.

## Rendering

`render(ctx, filename, data)` renders a file from `app.views`. `render_text(ctx, template, data)` renders an inline template string.

The application provides the rendering functions:

- `app.renderer(template, data)` for string templates
- `app.file_renderer(filepath, data)` for file-backed templates

If `app.file_renderer` is unset, `render(ctx, ...)` falls back to reading the file contents and passing them to `app.renderer`.

IwaiEngine uses `NamedTuple` render contexts. Pass view data as a `NamedTuple`, for example:

```julia
get(app, "/page") do ctx
    render(ctx, "pages/index.iwai", (title = "Hello", user_name = "tchen"))
end
```

## Request Parsing

Text body:

```julia
reqtext(ctx)
```

JSON body:

```julia
payload = reqjson(ctx)
```

Form body:

```julia
form = reqform(ctx)
```

Query parameters:

```julia
query = reqquery(ctx)
```

Multipart uploads:

```julia
parts = reqmultipart(ctx)
file = reqfile(ctx; name = "image")
```

Cookies:

```julia
session = cookie(ctx, "session", "guest")
theme = cookie(ctx)["theme"]
```

`reqtext`, `reqjson`, `reqform`, and `reqmultipart` validate the request `Content-Type` and size limits. Request cookies are read with `cookie(ctx, ...)` and `cookie(ctx)[...]`.

## Cookies

Read request cookies:

```julia
session = cookie(ctx, "session", "guest")
theme = cookie(ctx)["theme"]
```

Set response cookies:

```julia
setcookie(ctx, "session", "abc"; path = "/", httponly = true)
```

For signed cookies, use:

```julia
token = secure_cookie(ctx, "session")
set_secure_cookie(ctx, "session", token)
```

## Request-Local State

Use `set!` and `Base.get` to stash request-local values.

```julia
set!(ctx, :user_id, 42)
user_id = Base.get(ctx, :user_id, nothing)
```

This is separate from `ctx.params`: `ctx[key]` and `ctx.params[...]` read route parameters, while `set!` stores request-local state for middleware and handlers.
