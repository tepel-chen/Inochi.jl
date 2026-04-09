# Benchmark

This directory contains a router benchmark for Inochi only.

## Setup

```bash
julia --project=benchmark -e 'using Pkg; Pkg.instantiate()'
```

## Run

```bash
julia --project=benchmark benchmark/inochi_router_benchmark.jl
```

Middleware dispatch benchmarks live in `benchmark/inochi_middleware_benchmark.jl`:

```bash
julia --project=benchmark benchmark/inochi_middleware_benchmark.jl
```

The benchmark uses the local checkout of `Inochi` via `benchmark/Project.toml`:

```toml
[sources]
Inochi = {path = ".."}
```
