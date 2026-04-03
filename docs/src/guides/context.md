# Context and Responses

```@meta
CurrentModule = Inochi
```

## The Context Object

`Context` wraps the request and the response under construction.

Common fields:

- `ctx.req`: the underlying `HTTP.Request`
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

## Request Parsing

Text body:

```julia
ctx.reqtext()
```

JSON body:

```julia
payload = ctx.reqjson()
```

Form body:

```julia
form = ctx.reqform()
```

Query parameters:

```julia
query = ctx.reqquery()
```

Multipart uploads:

```julia
parts = ctx.reqmultipart()
file = ctx.reqfile(name = "image")
```

Cookies:

```julia
cookies = ctx.reqcookies()
session = ctx.reqcookie("session", "guest")
```

`reqtext`, `reqjson`, `reqform`, and `reqmultipart` validate the request `Content-Type` and size limits. Cookie parsing is delegated to `HTTP.jl`.

## Cookies

Read request cookies:

```julia
session = ctx.cookie("session", "guest")
theme = ctx.cookie["theme"]
```

Set response cookies:

```julia
ctx.setcookie("session", "abc"; path = "/", httponly = true)
```

For signed cookies, use:

```julia
token = secure_cookie(ctx, "session")
set_secure_cookie(ctx, "session", token)
```

When a request handler throws, `on_error` can inspect `ctx.backtrace` and render it into the response. This is useful for development debugging and for custom error pages.

## Request-Local State

Use `set!` and `get` to stash request-local values.

```julia
set!(ctx, :user_id, 42)
user_id = get(ctx, :user_id, nothing)
```
