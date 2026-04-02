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

`reqtext`, `reqjson`, and `reqform` validate the request `Content-Type`.

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

## Request-Local State

Use `set!` and `get` to stash request-local values.

```julia
set!(ctx, :user_id, 42)
user_id = get(ctx, :user_id, nothing)
```
