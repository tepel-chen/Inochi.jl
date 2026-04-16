# Inochi.jl

Inochi is a small Julia web framework with an API shaped around an application object and `do`-block route registration.

```@meta
CurrentModule = Inochi
```

## Quick Start

```julia
using Inochi

app = App()

get(app, "/") do ctx
    text(ctx, "Hello, Inochi!")
end

get(app, "/users/:id") do ctx
    json(ctx, Dict("id" => ctx.params["id"]))
end

start(app)
```

## Design Notes

- `App()` is the central application object.
- Routes are registered with `get`, `post`, `put`, `patch`, `delete`, `options`, `head`, `connect`, and `trace`.
- `use` registers middleware globally or on a path prefix.
- Handlers usually receive a [`Context`](@ref).
- Route matching uses a static map for exact routes and a compiled trie matcher for dynamic routes.
- TLS is served through `OpenSSL.SSLContext` with ALPN-based HTTP/2 negotiation.
- Connection handlers are spawned on Julia threads, with `max_threads` capping concurrent work.

## Next Pages

- [Routing and Middleware](guides/routing.md)
- [Context and Responses](guides/context.md)
- [Static Files](guides/static-files.md)
- [TLS with OpenSSL](guides/tls.md)
- [Todo App Example](examples/todo.md)
