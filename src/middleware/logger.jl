"""
    logger(; io=stdout)

Create middleware that logs the request method, path, response status, and elapsed time.
"""
function logger(; io::IO = stdout)
    return function (ctx::Context)
        started_at = time_ns()
        response = ctx.next()
        elapsed_ms = round((time_ns() - started_at) / 1_000_000; digits = 2)
        path = String(HTTP.URIs.URI(ctx.target).path)
        println(io, string(ctx.method, " ", path, " -> ", response.status, " (", elapsed_ms, " ms)"))
        return response
    end
end
