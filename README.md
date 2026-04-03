# Inochi

[![Build Status](https://github.com/tepel-chen/Inochi.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/tepel-chen/Inochi.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://tepel-chen.github.io/Inochi.jl/dev/)

Inochi is a small Julia web framework built around an `App()` object, `do`-block route registration, and a lightweight `Context`. Heavily inspired by Hono. Mostly vibe-coded using Codex.

```julia
using Inochi

app = App()

get(app, "/") do ctx
    text(ctx, "Hello, Inochi!")
end

start(app)
```

## Documentation

Published docs:

- https://tepel-chen.github.io/Inochi.jl/

Documenter-compatible docs live in `docs/`.

Build locally:

```bash
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

## Example

A sample todo application is available at `/example/todo`.
