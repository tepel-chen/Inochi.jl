"""
    logger(; io=stdout)

Create middleware that logs the request method, path, response status, and elapsed time.
"""
function logger(; io::IO = stdout)
    return function (ctx::Context)
        started_at = time_ns()
        next(ctx)
        elapsed_ms = round((time_ns() - started_at) / 1_000_000; digits = 2)
        path = HTTP.URIs.URI(ctx.target).path
        println(io, string(ctx.method, " ", path, " -> ", ctx.status, " (", elapsed_ms, " ms)"))
        return ctx
    end
end
