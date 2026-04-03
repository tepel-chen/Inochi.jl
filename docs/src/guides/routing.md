# Routing and Middleware

```@meta
CurrentModule = Inochi
```

## Basic Routes

Routes are registered with `do` blocks.

```julia
app = App()

get(app, "/") do ctx
    text(ctx, "ok")
end

post(app, "/todos") do ctx
    form = ctx.reqform()
    text(ctx, form["title"])
end

post(app, "/upload") do ctx
    file = ctx.reqfile(name = "image")
    text(ctx, file.filename)
end
```

## Dynamic Segments

Named parameters use `:name`.

```julia
get(app, "/users/:id") do ctx
    text(ctx, ctx.params["id"])
end
```

The route `"/users/:id"` matches `"/users/42"` and exposes `"42"` as `ctx.params["id"]`.

## Optional Segments

Optional segments use a trailing `?`.

```julia
get(app, "/files/:dir?/:name?") do ctx
    json(ctx, ctx.params)
end
```

This route matches:

- `"/files"`
- `"/files/docs"`
- `"/files/docs/readme"`

## Wildcards

Use `*` at the end of a path for wildcard matching.

```julia
get(app, "/static/*") do ctx
    text(ctx, ctx.params["*"])
end
```

`"/static/app.css"` makes `ctx.params["*"] == "app.css"`.

## Middleware

Use `use` for middleware.

Global middleware:

```julia
use(app) do ctx, next
    header!(ctx, "X-Powered-By", "Inochi")
    next()
end
```

Prefix middleware:

```julia
use(app, "/admin") do ctx, next
    header!(ctx, "X-Area", "admin")
    next()
end
```

Wildcard middleware also works on method-specific routes:

```julia
get(app, "/admin/*") do ctx, next
    next()
end
```

## Middleware Rules

- Middleware receives `ctx, next`.
- Call `next()` to continue to the next middleware or final route.
- A middleware may call `next()` only once.
- If middleware does not call `next()`, its own return value becomes the response.

## Mounted Apps

Use `route(app, "/prefix", subapp)` to split larger apps into smaller route groups.

```julia
admin = App()

get(admin, "/dashboard") do ctx
    text(ctx, "admin")
end

route(app, "/admin", admin)
```
